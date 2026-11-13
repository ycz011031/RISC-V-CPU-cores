#!/usr/bin/env python3
"""Run the shared benchmark list on one or both cores under xsim.

    py tools/xsim/run_regress.py                 # both cores, all benchmarks
    py tools/xsim/run_regress.py --core pipeline # one core
    py tools/xsim/run_regress.py --bench fft --bench m_ext_test

Each core is compiled once. Every benchmark's commit log is kept in
<core>/xsim/logs/<bench>.commit.log. When both cores ran a benchmark, the two
commit logs are compared. They must be identical, because both cores retire
the same architectural instruction stream (PC, instruction, rd value, memory
address and data).
"""

import argparse
import filecmp
import os
import re
import shutil
import subprocess
import sys
import time

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
RUN = os.path.join(REPO, "tools", "xsim", "run_xsim.py")
OOO = "RV32IM Out-of-Order"
PIPE = "RV32I Pipeline"

BENCHES = {
    "m_ext_test":     f"{OOO}/testcode/m_ext_test.elf",
    "coremark_rv32i": f"{PIPE}/testcode/coremark_rv32i.elf",
    "coremark_im":    f"{OOO}/testcode/coremark_im.elf",
    "aes_sha":        f"{OOO}/testcode/im/aes_sha.elf",
    "compression":    f"{OOO}/testcode/im/compression.elf",
    "fft":            f"{OOO}/testcode/im/fft.elf",
    "mergesort":      f"{OOO}/testcode/im/mergesort.elf",
}
CORE_DIR = {"ooo": OOO, "pipeline": PIPE}


def run_one(core, bench, elf, compile_first, extra):
    cmd = [sys.executable, RUN, core, os.path.join(REPO, elf)] + extra
    if not compile_first:
        cmd.append("--no-compile")
    t0 = time.time()
    p = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                       errors="replace")
    dt = time.time() - t0
    out = p.stdout
    ipc = re.findall(r"Segment IPC:\s*([0-9.]+)", out) or re.findall(r"Total IPC:\s*([0-9.]+)", out)
    status = "PASS" if p.returncode == 0 else "FAIL"
    if "xvlog failed" in out or "xelab failed" in out:
        status = "BUILD FAIL"
    log_dir = os.path.join(REPO, CORE_DIR[core], "xsim", "logs")
    os.makedirs(log_dir, exist_ok=True)
    src = os.path.join(REPO, CORE_DIR[core], "xsim", "spike", "commit.log")
    dst = os.path.join(log_dir, f"{bench}.commit.log")
    if os.path.isfile(src):
        shutil.copyfile(src, dst)
    shutil.copyfile(os.path.join(REPO, CORE_DIR[core], "xsim", "run", "simulation.log"),
                    os.path.join(log_dir, f"{bench}.simulation.log"))
    if status != "PASS":
        print(out[-3000:])
    return status, (ipc[-1] if ipc else "-"), dt, dst


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--core", choices=["ooo", "pipeline", "both"], default="both")
    ap.add_argument("--bench", action="append", choices=sorted(BENCHES),
                    help="benchmark(s) to run (default: all)")
    ap.add_argument("extra", nargs=argparse.REMAINDER,
                    help="extra args passed to run_xsim.py (after --)")
    args = ap.parse_args()
    extra = [a for a in args.extra if a != "--"]

    cores = ["ooo", "pipeline"] if args.core == "both" else [args.core]
    benches = args.bench or list(BENCHES)

    results = {}
    for core in cores:
        for k, bench in enumerate(benches):
            print(f"[regress] {core:8s} {bench:15s} ...", flush=True)
            r = run_one(core, bench, BENCHES[bench], k == 0, extra)
            results[(core, bench)] = r
            print(f"[regress] {core:8s} {bench:15s} {r[0]:10s} IPC {r[1]:>9s}  {r[2]:6.1f}s",
                  flush=True)
            if r[0] == "BUILD FAIL":
                break

    print("\n%-16s" % "benchmark" + "".join(f"{c:>26s}" for c in cores) +
          ("   commit logs" if len(cores) == 2 else ""))
    all_ok = True
    for bench in benches:
        row = "%-16s" % bench
        for core in cores:
            st, ipc, dt, _ = results.get((core, bench), ("-", "-", 0, None))
            all_ok &= st == "PASS"
            row += f"{st:>10s}  IPC {ipc:>8s} {dt:5.0f}s"
        if len(cores) == 2 and all((c, bench) in results for c in cores):
            a, b = (results[(c, bench)][3] for c in cores)
            same = os.path.isfile(a) and os.path.isfile(b) and filecmp.cmp(a, b, shallow=False)
            all_ok &= same
            row += "   identical" if same else "   DIFFER"
        print(row)
    sys.exit(0 if all_ok else 1)


if __name__ == "__main__":
    main()
