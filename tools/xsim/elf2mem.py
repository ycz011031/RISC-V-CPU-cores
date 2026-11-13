#!/usr/bin/env python3
"""Convert a 32-bit little-endian RISC-V ELF into a $readmemh-style memory image.

Output format (readable by $readmemh and by the portable loader in the
testbench memory models):

    @<word index in hex>
    <word in hex>
    <word in hex>
    ...

A "word" is --word-bytes bytes wide (4 for the pipeline's 32-bit memory,
32 for the OoO core's 256-bit DRAM bursts). The word index is
byte_address / word_bytes. Every PT_LOAD segment is loaded. The .bss part
(p_memsz > p_filesz) is zero-filled. Bytes in a partly covered word are zero.

No third-party packages are needed.
"""

import argparse
import struct
import sys


def load_elf_bytes(path):
    data = open(path, "rb").read()
    if data[:4] != b"\x7fELF":
        sys.exit(f"elf2mem: {path} is not an ELF file")
    if data[4] != 1 or data[5] != 1:
        sys.exit(f"elf2mem: {path} must be ELF32 little-endian")
    e_phoff = struct.unpack_from("<I", data, 28)[0]
    e_phentsize, e_phnum = struct.unpack_from("<HH", data, 42)
    mem = {}
    for i in range(e_phnum):
        p_type, p_offset, p_vaddr, p_paddr, p_filesz, p_memsz, _flags, _align = \
            struct.unpack_from("<8I", data, e_phoff + i * e_phentsize)
        if p_type != 1 or p_memsz == 0:          # PT_LOAD only
            continue
        seg = data[p_offset:p_offset + p_filesz]
        for j, byte in enumerate(seg):
            mem[p_paddr + j] = byte
        for j in range(p_filesz, p_memsz):       # .bss
            mem[p_paddr + j] = 0
    return mem


def write_image(mem, out_path, word_bytes):
    words = {}
    for addr, byte in mem.items():
        idx, off = divmod(addr, word_bytes)
        words.setdefault(idx, bytearray(word_bytes))[off] = byte
    digits = word_bytes * 2
    with open(out_path, "w", newline="\n") as f:
        prev = None
        for idx in sorted(words):
            if prev is None or idx != prev + 1:
                f.write(f"@{idx:x}\n")
            # little-endian: byte 0 is the least significant
            f.write(words[idx][::-1].hex().rjust(digits, "0") + "\n")
            prev = idx
    return len(words)


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("elf")
    ap.add_argument("out")
    ap.add_argument("--word-bytes", type=int, default=4,
                    help="bytes per memory word (power of 2, default 4)")
    args = ap.parse_args()
    if args.word_bytes <= 0 or args.word_bytes & (args.word_bytes - 1):
        sys.exit("elf2mem: --word-bytes must be a power of two")
    mem = load_elf_bytes(args.elf)
    n = write_image(mem, args.out, args.word_bytes)
    print(f"elf2mem: {args.elf} -> {args.out} ({n} x {args.word_bytes * 8}-bit words)")


if __name__ == "__main__":
    main()
