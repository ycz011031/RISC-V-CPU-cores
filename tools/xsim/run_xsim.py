#!/usr/bin/env python3
"""Compile, elaborate and run either core on Vivado xsim.

Examples (from the repository root):

    py tools/xsim/run_xsim.py ooo      "RV32IM Out-of-Order/testcode/coremark_im.elf"
    py tools/xsim/run_xsim.py pipeline "RV32IM Out-of-Order/testcode/im/fft.elf"
    py tools/xsim/run_xsim.py pipeline prog.elf --wave      # write a .wdb waveform
    py tools/xsim/run_xsim.py ooo prog.elf --no-compile     # reuse the last build

Use `python3` instead of `py` on Linux.

The flow is vendor-neutral RTL only: USE_SYNOPSYS_DW is NOT defined, so the
mul/div units use ip/gen_*_seq.sv. The Spike DPI co-simulation (a Linux-only
.so) is disabled. Correctness is checked by the riscv-formal RVFI monitor
(hvl/common/rvfimon.v), which checks every committed instruction's ISA
semantics (RV32IMC), plus the X checks in hvl/common/monitor.sv.

The commit log is written to <core>/xsim/spike/commit.log, in the Spike
--log-commits format. On a machine with Spike it can be diffed against a
golden Spike log.
"""

import argparse
import glob
import os
import platform
import re
import shutil
import subprocess
import sys
import time

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
TOOLS = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, TOOLS)
import elf2mem  # noqa: E402

CORES = {
    "ooo": {
        "root": "RV32IM Out-of-Order",
        "word_bytes": 32,           # DRAM model: 4 x 64-bit bursts per access
        "clock_ps": 1400,           # options.json "clock"
        "src_globs": [
            "pkg/types.sv",
            "@ip/*.sv",
            "hdl/*.sv",
            "sram/output/*/*.v",
            "hvl/common/*.sv",
            "hvl/common/*.v",
            "hvl/xsim/*.sv",
        ],
    },
    "pipeline": {
        "root": "RV32I Pipeline",
        "word_bytes": 32,           # same banked DRAM model as the OoO core
        "clock_ps": 2000,
        "src_globs": [
            "pkg/types.sv",
            "@ip/*.sv",
            "hdl/*.sv",
            "sram/output/*/*.v",
            "hvl/common/*.sv",
            "hvl/common/*.v",
            "hvl/xsim/*.sv",
        ],
    },
}

DEFINES = ["ECE411_XSIM", "ECE411_NO_FLOAT", "ECE411_NO_SPIKE_DPI", "ECE411_PERF"]


def find_vivado_bin(user_path):
    exe = "xvlog.bat" if platform.system() == "Windows" else "xvlog"
    if user_path:
        cands = [user_path, os.path.join(user_path, "bin")]
    else:
        cands = []
        if os.environ.get("XILINX_VIVADO"):
            cands.append(os.path.join(os.environ["XILINX_VIVADO"], "bin"))
        found = shutil.which(exe)
        if found:
            cands.append(os.path.dirname(found))
        roots = ["C:/Xilinx", "C:/AMD", "D:/Xilinx", "/tools/Xilinx", "/opt/Xilinx"]
        vers = []
        for r in roots:
            vers += glob.glob(os.path.join(r, "*", "Vivado", "bin"))      # 2025.1+ layout
            vers += glob.glob(os.path.join(r, "Vivado", "*", "bin"))      # classic layout
        cands += sorted(vers, key=lambda p: re.findall(r"20\d\d\.\d", p) or [""], reverse=True)
    for c in cands:
        if os.path.isfile(os.path.join(c, exe)):
            return c
    sys.exit("run_xsim: could not find Vivado (xvlog). Use --vivado <Vivado install or bin dir>"
             " or set XILINX_VIVADO.")


def tool(bindir, name):
    return os.path.join(bindir, name + (".bat" if platform.system() == "Windows" else ""))


def run(cmd, cwd, log_name=None, echo=True):
    if echo:
        print("  $ " + " ".join(f'"{c}"' if " " in c else c for c in cmd), flush=True)
    t0 = time.time()
    if platform.system() == "Windows":
        # The Vivado .bat wrappers split unquoted arguments at '=' and ';',
        # so quote every argument explicitly.
        cmd = " ".join('"' + c.replace('"', '\\"') + '"' for c in cmd)
    proc = subprocess.run(cmd, cwd=cwd, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                          text=True, errors="replace")
    out = proc.stdout
    if log_name:
        with open(os.path.join(cwd, log_name), "w") as f:
            f.write(out)
    return proc.returncode, out, time.time() - t0


def collect_sources(core_dir, globs):
    files = []
    for g in globs:
        base = REPO if g.startswith("@") else core_dir
        hits = sorted(glob.glob(os.path.join(base, g.lstrip("@"))))
        files += [h for h in hits if h not in files]
    # the package must come first
    files.sort(key=lambda p: 0 if p.replace("\\", "/").endswith("pkg/types.sv") else 1)
    return files


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("core", choices=sorted(CORES))
    ap.add_argument("prog", help="RISC-V ELF to run")
    ap.add_argument("--timeout", type=int, default=50_000_000, help="timeout in cycles")
    ap.add_argument("--clock", type=int, help="clock period in ps")
    ap.add_argument("--wave", action="store_true", help="record all signals to a .wdb")
    ap.add_argument("--magic", action="store_true",
                    help="magic memory (no DRAM timing) instead of the DRAM model; "
                         "builds in <core>/xsim_magic")
    ap.add_argument("--no-compile", action="store_true", help="reuse the existing snapshot")
    ap.add_argument("--debug", action="store_true",
                    help="elaborate with signal visibility (implied by --wave / --tcl)")
    ap.add_argument("--tcl", help="custom xsim Tcl batch script to run instead of 'run all'")
    ap.add_argument("--define", "-D", action="append", default=[],
                    help="extra `define (e.g. -D USE_SYNOPSYS_DW with DW sim models added)")
    ap.add_argument("--extra-src", action="append", default=[],
                    help="extra source file (e.g. DesignWare simulation models)")
    ap.add_argument("--vivado", help="Vivado install dir or its bin dir")
    ap.add_argument("--build-dir", help="default: <core>/xsim")
    args = ap.parse_args()

    cfg = CORES[args.core]
    core_dir = os.path.join(REPO, cfg["root"])
    if args.magic:
        args.define.append("ECE411_MAGIC_MEM")
    build = os.path.abspath(args.build_dir or
                            os.path.join(core_dir, "xsim_magic" if args.magic else "xsim"))
    run_dir = os.path.join(build, "run")
    os.makedirs(run_dir, exist_ok=True)
    os.makedirs(os.path.join(build, "spike"), exist_ok=True)   # monitor writes ../spike/commit.log
    os.makedirs(os.path.join(build, "gen"), exist_ok=True)

    prog = os.path.abspath(args.prog)
    if not os.path.isfile(prog):
        sys.exit(f"run_xsim: program not found: {prog}")
    bindir = find_vivado_bin(args.vivado)
    print(f"[run_xsim] core={args.core}  prog={prog}")
    print(f"[run_xsim] vivado={bindir}")

    # ---- program image --------------------------------------------------------
    memfile = os.path.join(build, "gen", "memory.lst")
    mem = elf2mem.load_elf_bytes(prog)
    elf2mem.write_image(mem, memfile, cfg["word_bytes"])

    snapshot = "top_tb_snap"
    if not args.no_compile:
        # ---- rvfi_reference.svh ------------------------------------------------
        subprocess.check_call([sys.executable, os.path.join(TOOLS, "gen_rvfi_ref.py"),
                               os.path.join(core_dir, "hvl", "common", "rvfi_reference.json"),
                               os.path.join(build, "gen", "rvfi_reference.svh")])

        srcs = collect_sources(core_dir, cfg["src_globs"]) + [os.path.abspath(s) for s in args.extra_src]
        cmd = [tool(bindir, "xvlog"), "--sv", "--nolog",
               "-i", os.path.join(core_dir, "hvl", "common"),
               "-i", os.path.join(build, "gen")]
        for d in DEFINES + args.define:
            cmd += ["-d", d]
        cmd += srcs
        print("[run_xsim] compiling ...")
        rc, out, dt = run(cmd, run_dir, "compile.log", echo=False)
        if rc != 0 or re.search(r"^ERROR:", out, re.M):
            print(out)
            sys.exit(f"[run_xsim] xvlog failed (see {run_dir}/compile.log)")
        print(f"[run_xsim] compiled {len(srcs)} files in {dt:.1f}s")

        cmd = [tool(bindir, "xelab"), "top_tb", "-s", snapshot, "--nolog",
               "-timescale", "1ps/1ps", "-override_timeunit", "-override_timeprecision",
               "-debug", "typical" if (args.wave or args.debug or args.tcl) else "off",
               "--relax"]
        print("[run_xsim] elaborating ...")
        rc, out, dt = run(cmd, run_dir, "elaborate.log", echo=False)
        if rc != 0 or re.search(r"^ERROR:", out, re.M):
            print(out)
            sys.exit(f"[run_xsim] xelab failed (see {run_dir}/elaborate.log)")
        print(f"[run_xsim] elaborated in {dt:.1f}s")

    plusargs = {
        "TIMEOUT_ECE411": str(args.timeout),
        "CLOCK_PERIOD_PS_ECE411": str(args.clock or cfg["clock_ps"]),
        "BRAM_0_ON_X_ECE411": "1",
        # relative to the sim cwd (<build>/run): xsim re-parses its command
        # line through Tcl, so absolute paths containing spaces would break
        "MEMLST_ECE411": "../gen/memory.lst",
    }
    tcl = os.path.join(build, "gen", "run.tcl")
    with open(tcl, "w") as f:
        if args.wave:
            f.write("log_wave -recursive *\n")
        if args.tcl:
            with open(args.tcl) as user_tcl:
                # catch errors so a broken probe script cannot drop xsim into
                # an interactive prompt
                f.write("if {[catch {\n" + user_tcl.read() +
                        "\n} err]} { puts \"TCL ERROR: $err\" }\n")
        else:
            f.write("run all\n")
        f.write("quit\n")
    cmd = [tool(bindir, "xsim"), snapshot, "--nolog", "-tclbatch", "../gen/run.tcl"]
    if args.wave:
        cmd += ["-wdb", "dump.wdb"]
    for k, v in plusargs.items():
        cmd += ["-testplusarg", f"{k}={v}"]
    # Everything runs in <build>/run (xsim looks for ./xsim.dir there). The
    # monitor writes ./time.txt and ../spike/commit.log relative to that cwd.
    print("[run_xsim] simulating ...", flush=True)
    rc, out, dt = run(cmd, run_dir, "simulation.log", echo=False)

    # ---- report -----------------------------------------------------------------
    keep = re.compile(r"Monitor:|Magic memory:|Perf:|Error|ERROR|Fatal|FATAL|TB Error|Spike|RVFI|Memory Error|"
                      r"\$finish|mismatch|Timed out")
    lines = [l for l in out.splitlines() if keep.search(l)]
    print("\n".join(lines[-40:]))
    failed = bool(re.search(r"Fatal|FATAL|^Error|Error:|Timed out", out, re.M))
    finished = "$finish called" in out
    status = "PASS" if finished and not failed else "FAIL"
    print(f"[run_xsim] {status}  ({dt:.1f}s wall, log: {run_dir}/simulation.log)")
    if args.wave:
        print(f"[run_xsim] waveform: {run_dir}/dump.wdb   (open with: xsim --gui dump.wdb, from that dir)")
    sys.exit(0 if status == "PASS" else 1)


if __name__ == "__main__":
    main()
