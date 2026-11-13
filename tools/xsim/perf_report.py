#!/usr/bin/env python3
"""Collect the perf-probe counters of a regression into one table.

    py tools/xsim/run_regress.py            # DRAM model   -> <core>/xsim/logs/*.perf.json
    py tools/xsim/run_regress.py --magic    # magic memory -> <core>/xsim_magic/logs/*.perf.json
    py tools/xsim/perf_report.py [out.json]

Writes {rows, meta}: one row per (core, memory model, benchmark) with every raw
counter plus derived rates. Every *_pct column is a percentage of the cycles in
the measured window (the same window as the monitor's segment IPC), or of the
instructions where the name says so. Also prints a short text summary.
"""

import glob
import json
import os
import sys

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CORES = {"ooo": "RV32IM Out-of-Order", "pipeline": "RV32I Pipeline"}
MEMS = {"dram": "xsim", "magic": "xsim_magic"}
BENCH_ORDER = ["coremark_rv32i", "coremark_im", "aes_sha", "compression", "fft", "mergesort", "m_ext_test"]


def pct(n, d):
    return round(100.0 * n / d, 2) if d else 0.0


def derive(c):
    cyc = c["CYCLES"]
    r = {}
    if c["core"] == "ooo":
        insts = c["COMMIT_LANE1"] + c["COMMIT_LANE2"]
        r["insts"] = insts
        r["ipc"] = round(insts / cyc, 4)
        for k in ["COMMIT_0", "COMMIT_1", "COMMIT_2",
                  "C0_MISPREDICT_RECOVERY", "C0_ROB_EMPTY", "C0_HEAD_LOAD", "C0_HEAD_STORE",
                  "C0_HEAD_MULDIV", "C0_HEAD_BRANCH", "C0_HEAD_ALU",
                  "C1_ONLY_ONE_IN_ROB", "C1_SECOND_NOT_DONE", "C1_SECOND_NOT_SIMPLE", "C1_MISPREDICT", "C1_OTHER",
                  "FETCH_LANE1", "FETCH_LANE2", "DECODE_LANE1", "DECODE_LANE2",
                  "DISPATCH_LANE1", "DISPATCH_LANE2", "ISSUE_ALU1", "ISSUE_ALU2",
                  "CDB1_VALID", "CDB2_VALID", "COMMIT_LANE1", "COMMIT_LANE2",
                  "ISSUE_MUL", "ISSUE_DIV", "ISSUE_LUI", "ISSUE_MEM", "ISSUE_BR",
                  "DISPATCH_0", "DISPATCH_1", "DISPATCH_2",
                  "DISP0_NO_INST", "DISP0_ROB_FULL", "DISP0_PRF_FULL", "DISP0_RS_FULL",
                  "DISP0_DECODE_STALL", "DISP0_OTHER",
                  "FETCH_0", "FETCH_1", "FETCH_2", "FETCH_STALL_ICACHE", "FETCH_STALL_QUEUE_FULL",
                  "FETCH_STALL_FLUSH", "FETCH_STALL_FTQ", "ICACHE_DFP_BUSY", "DCACHE_DFP_BUSY"]:
            r[k.lower() + "_pct"] = pct(c[k], cyc)
        # reservation station holds work but issues nothing this cycle
        for u in ["ALU1", "ALU2", "MUL", "DIV", "LUI", "MEM", "BR"]:
            r[f"rs_wait_{u.lower()}_pct"] = pct(max(c[f"RSOCC_{u}"] - c[f"ISSUE_{u}"], 0), cyc)
        branches = c["COMMIT_BRANCH"] + c["COMMIT_JAL"] + c["COMMIT_JALR"]
        mispred = c["MISPRED_BRANCH"] + c["MISPRED_JAL"] + c["MISPRED_JALR"]
        # zero-commit cycles spent recovering, per mispredict flush
        r["cycles_per_mispredict"] = round(c["C0_MISPREDICT_RECOVERY"] / c["FLUSHES"], 2) if c["FLUSHES"] else 0.0
        r["branch_mispred_pct_of_branches"] = pct(c["MISPRED_BRANCH"], c["COMMIT_BRANCH"])
        r["jalr_mispred_pct_of_jalr"] = pct(c["MISPRED_JALR"], c["COMMIT_JALR"])
        r["c0_head_other_pct"] = pct(c["C0_HEAD_STORE"] + c["C0_HEAD_MULDIV"] + c["C0_HEAD_BRANCH"], cyc)
    else:
        insts = c["COMMITS"]
        r["insts"] = insts
        r["ipc"] = round(insts / cyc, 4)
        for k in ["COMMITS", "LOST_FLUSH_BRANCH", "LOST_FLUSH_JALR", "LOST_ICACHE_MISS",
                  "LOST_PORT_CONFLICT", "LOST_FETCH_RESTART", "LOST_LOAD_USE", "LOST_MEM_DCACHE",
                  "LOST_MEM_MULDIV", "LOST_OTHER", "VALID_IF_ID", "VALID_ID_EX", "VALID_EX_MEM",
                  "VALID_MEM_WB", "MEM_STALL_CYCLES", "LOAD_USE_CYCLES", "CACHE_BUSY_FILL",
                  "PORT_BOTH_REQUEST"]:
            r[k.lower() + "_pct"] = pct(c[k], cyc)
        r["cache_miss_i_pct_of_access"] = pct(c["CACHE_MISS_I"], c["CACHE_ACCESS_I"])
        r["cache_miss_d_pct_of_access"] = pct(c["CACHE_MISS_D"], c["CACHE_ACCESS_D"])
        branches = c["COMMIT_BRANCH"] + c["COMMIT_JAL"] + c["COMMIT_JALR"]
        mispred = c["REDIRECT_BRANCH"] + c["REDIRECT_JALR"]
        # lost (bubble) cycles charged to redirects, per redirect
        r["cycles_per_mispredict"] = round((c["LOST_FLUSH_BRANCH"] + c["LOST_FLUSH_JALR"]) / mispred, 2) if mispred else 0.0
        r["branch_mispred_pct_of_branches"] = pct(c["REDIRECT_BRANCH"], c["COMMIT_BRANCH"])
        r["jalr_mispred_pct_of_jalr"] = pct(c["REDIRECT_JALR"], c["COMMIT_JALR"])
        r["lost_control_pct"] = pct(c["LOST_FLUSH_BRANCH"] + c["LOST_FLUSH_JALR"], cyc)
        r["lost_misc_pct"] = pct(c["LOST_LOAD_USE"] + c["LOST_FETCH_RESTART"] + c["LOST_OTHER"], cyc)
    r["control_pct_of_insts"] = pct(branches, insts)
    r["load_pct_of_insts"] = pct(c["COMMIT_LOAD"], insts)
    r["store_pct_of_insts"] = pct(c["COMMIT_STORE"], insts)
    r["muldiv_pct_of_insts"] = pct(c["COMMIT_MULDIV"], insts)
    r["redirects_per_kinst"] = round(1000.0 * mispred / insts, 2) if insts else 0.0
    return r


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(REPO, "tools", "xsim", "perf_rows.json")
    rows = []
    for core, cdir in CORES.items():
        for mem, bdir in MEMS.items():
            for f in sorted(glob.glob(os.path.join(REPO, cdir, bdir, "logs", "*.perf.json"))):
                bench = os.path.basename(f)[:-len(".perf.json")]
                c = json.load(open(f))
                row = {"core": core, "mem": mem, "bench": bench}
                row.update({k: v for k, v in c.items() if k != "core"})
                row.update(derive(c))
                rows.append(row)
    rows.sort(key=lambda r: (r["core"], r["mem"],
                             BENCH_ORDER.index(r["bench"]) if r["bench"] in BENCH_ORDER else 99))
    code = open(os.path.abspath(__file__)).read()
    meta = [
        {"label": "perf_report.py", "value": code, "type": "code", "lang": "python"},
        {"label": "Input", "value": "<core>/xsim{,_magic}/logs/<bench>.perf.json from "
                                    "hvl/common/perf_probe.sv (Vivado xsim 2025.1)"},
    ]
    with open(out, "w") as fh:
        json.dump({"rows": rows, "meta": meta}, fh, indent=1)
    print(f"perf_report: {len(rows)} rows -> {out}")
    for r in rows:
        print(f"{r['core']:9s} {r['mem']:6s} {r['bench']:15s} IPC {r['ipc']:.3f}  cycles {r['CYCLES']}")


if __name__ == "__main__":
    main()
