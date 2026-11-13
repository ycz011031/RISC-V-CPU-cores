#!/usr/bin/env python3
"""Generate a directed RV32M test program as a bare ELF (no toolchain needed).

    py tools/xsim/gen_m_test.py <out.elf> [--seed N] [--random N]

The program exercises every RV32M instruction on corner-case operands
(0, +-1, INT_MIN, INT_MAX, divide by zero, INT_MIN / -1, ...) plus random
operands. It also exercises the pipeline hazards that matter for a multi-cycle
unit:
  M -> M (back to back, dependent), load -> M, M -> store, M -> branch,
  M -> load address, M inside a counted loop, M result through x0.
The program has no self-check. Every committed result is checked by the RVFI
monitor (hvl/common/rvfimon.v implements real RV32M semantics). It ends with
the ECE 411 halt instruction (slti x0, x0, -256).

Link address 0xaaaaa000 (same as the course benchmarks), data at 0xaaac0000.
"""

import argparse
import random
import struct

BASE = 0xAAAAA000
DATA = 0xAAAC0000   # well past the ~22 KB of code


# ---------------------------------------------------------------- encoders --
def _r(f7, rs2, rs1, f3, rd, op):
    return (f7 << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | op


def _i(imm, rs1, f3, rd, op):
    return ((imm & 0xFFF) << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | op


def _s(imm, rs2, rs1, f3, op):
    return (((imm >> 5) & 0x7F) << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | ((imm & 0x1F) << 7) | op


def _b(imm, rs2, rs1, f3, op=0x63):
    return (((imm >> 12) & 1) << 31) | (((imm >> 5) & 0x3F) << 25) | (rs2 << 20) | (rs1 << 15) | \
           (f3 << 12) | (((imm >> 1) & 0xF) << 8) | (((imm >> 11) & 1) << 7) | op


def _j(imm, rd, op=0x6F):
    return (((imm >> 20) & 1) << 31) | (((imm >> 1) & 0x3FF) << 21) | (((imm >> 11) & 1) << 20) | \
           (((imm >> 12) & 0xFF) << 12) | (rd << 7) | op


M_OPS = {"mul": 0, "mulh": 1, "mulhsu": 2, "mulhu": 3, "div": 4, "divu": 5, "rem": 6, "remu": 7}


class Asm:
    def __init__(self):
        self.words = []
        self.labels = {}
        self.fixups = []          # (index, kind, label, args)

    @property
    def pc(self):
        return BASE + 4 * len(self.words)

    def label(self, name):
        self.labels[name] = self.pc

    def emit(self, w):
        self.words.append(w & 0xFFFFFFFF)

    # base ISA
    def lui(self, rd, imm20):        self.emit((imm20 << 12) | (rd << 7) | 0x37)
    def addi(self, rd, rs1, imm):    self.emit(_i(imm, rs1, 0, rd, 0x13))
    def add(self, rd, rs1, rs2):     self.emit(_r(0, rs2, rs1, 0, rd, 0x33))
    def xor(self, rd, rs1, rs2):     self.emit(_r(0, rs2, rs1, 4, rd, 0x33))
    def sw(self, rs2, off, rs1):     self.emit(_s(off, rs2, rs1, 2, 0x23))
    def lw(self, rd, off, rs1):      self.emit(_i(off, rs1, 2, rd, 0x03))
    def halt(self):                  self.emit(0xF0002013)      # slti x0, x0, -256

    def m(self, op, rd, rs1, rs2):   self.emit(_r(1, rs2, rs1, M_OPS[op], rd, 0x33))

    def li(self, rd, value):
        value &= 0xFFFFFFFF
        lo = value & 0xFFF
        if lo >= 0x800:
            lo -= 0x1000
        hi = ((value - lo) >> 12) & 0xFFFFF
        if hi:
            self.lui(rd, hi)
            if lo:
                self.addi(rd, rd, lo)
        else:
            self.addi(rd, 0, lo)

    def branch(self, f3, rs1, rs2, label):
        self.fixups.append((len(self.words), "b", label, (f3, rs1, rs2)))
        self.emit(0)

    def bne(self, rs1, rs2, label): self.branch(1, rs1, rs2, label)
    def beq(self, rs1, rs2, label): self.branch(0, rs1, rs2, label)

    def jal(self, rd, label):
        self.fixups.append((len(self.words), "j", label, (rd,)))
        self.emit(0)

    def finish(self):
        for idx, kind, label, args in self.fixups:
            off = self.labels[label] - (BASE + 4 * idx)
            self.words[idx] = _b(off, args[2], args[1], args[0]) if kind == "b" else _j(off, args[0])
        return b"".join(struct.pack("<I", w) for w in self.words)


def write_elf(path, code):
    ehsize, phentsize = 52, 32
    off = ehsize + phentsize
    hdr = b"\x7fELF" + bytes([1, 1, 1, 0]) + bytes(8)
    hdr += struct.pack("<HHIIIIIHHHHHH", 2, 0xF3, 1, BASE, ehsize, 0, 0,
                       ehsize, phentsize, 1, 40, 0, 0)
    ph = struct.pack("<8I", 1, off, BASE, BASE, len(code), len(code), 7, 4)
    with open(path, "wb") as f:
        f.write(hdr + ph + code)


# ---------------------------------------------------------------- program --
CORNERS = [0, 1, 0xFFFFFFFF, 2, 0xFFFFFFFE, 7, 0xFFFFFFF9, 0x7FFFFFFF, 0x80000000,
           0x80000001, 0x12345678, 0xDEADBEEF, 0x0000FFFF, 0xFFFF0000]


def build(seed, n_random):
    rng = random.Random(seed)
    a = Asm()
    a.li(31, DATA)                      # x31 = data pointer
    a.addi(30, 0, 0)                    # x30 = running checksum

    # 1. every op on every corner pair; result folded into a checksum and
    #    stored (M -> xor dependency, M -> store data dependency)
    for x in CORNERS:
        for y in CORNERS:
            a.li(1, x)
            a.li(2, y)
            for k, op in enumerate(M_OPS):
                rd = 5 + k
                a.m(op, rd, 1, 2)
            for k in range(8):
                a.xor(30, 30, 5 + k)
            a.sw(30, 0, 31)

    # 2. random operands, mixed ops
    for _ in range(n_random):
        a.li(1, rng.getrandbits(32))
        a.li(2, rng.choice([rng.getrandbits(32), rng.getrandbits(8), 0]))
        a.m(rng.choice(list(M_OPS)), 3, 1, 2)
        a.add(30, 30, 3)

    # 3. hazard patterns
    a.li(1, 0x9E3779B9)
    a.li(2, 0x00010003)
    a.m("mul", 5, 1, 2)                 # M -> M -> M dependent chain
    a.m("mulh", 6, 5, 5)
    a.m("divu", 7, 6, 2)
    a.m("rem", 8, 7, 1)
    a.add(9, 8, 5)                      # M -> ALU
    a.sw(9, 4, 31)                      # -> store
    a.lw(10, 4, 31)                     # store -> load
    a.m("mul", 11, 10, 10)              # load -> M (load-use on an M op)
    a.m("div", 12, 11, 0)               # divide by x0
    a.m("rem", 13, 11, 0)
    a.m("mul", 0, 1, 2)                 # M writing x0
    a.add(14, 0, 0)
    a.m("mulhu", 15, 1, 1)
    a.bne(15, 0, "m_br_taken")          # M -> branch (taken)
    a.addi(16, 0, 1)                    # skipped
    a.label("m_br_taken")
    a.m("mul", 17, 0, 1)                # = 0
    a.beq(17, 0, "m_br_taken2")         # M -> branch (taken)
    a.addi(16, 0, 2)                    # skipped
    a.label("m_br_taken2")
    a.li(18, 4)
    a.m("mul", 19, 18, 18)              # 16
    a.add(19, 19, 31)                   # M -> load address
    a.sw(1, 0, 19)
    a.lw(20, 0, 19)

    # 4. counted loop with M ops and a loop-carried dependence
    a.li(21, 20)                        # counter
    a.li(22, 1)                         # accumulator
    a.li(23, 3)
    a.label("loop")
    a.m("mul", 22, 22, 23)
    a.m("remu", 24, 22, 21)
    a.add(22, 22, 24)
    a.m("divu", 25, 22, 23)
    a.xor(30, 30, 25)
    a.addi(21, 21, -1)
    a.bne(21, 0, "loop")
    a.sw(30, 8, 31)

    a.halt()
    return a.finish()


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("out")
    ap.add_argument("--seed", type=int, default=411)
    ap.add_argument("--random", type=int, default=300, help="number of random M ops")
    args = ap.parse_args()
    code = build(args.seed, args.random)
    write_elf(args.out, code)
    print(f"gen_m_test: wrote {args.out} ({len(code) // 4} instructions)")


if __name__ == "__main__":
    main()
