#!/usr/bin/env python3
import argparse
import shutil
import subprocess
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser(description="Convert an ELF to byte-per-line hex for the XDMA xsim host model.")
    parser.add_argument("elf", type=Path)
    parser.add_argument("hex", type=Path)
    parser.add_argument("--bin", type=Path, default=None)
    parser.add_argument("--objcopy", default=None)
    args = parser.parse_args()

    objcopy = args.objcopy or shutil.which("riscv64-unknown-elf-objcopy") or shutil.which("llvm-objcopy") or shutil.which("objcopy")
    if objcopy is None:
        raise SystemExit("objcopy not found; set --objcopy or install riscv64-unknown-elf-objcopy/llvm-objcopy")

    bin_path = args.bin or args.hex.with_suffix(".bin")
    args.hex.parent.mkdir(parents=True, exist_ok=True)
    bin_path.parent.mkdir(parents=True, exist_ok=True)

    subprocess.run([objcopy, "-O", "binary", str(args.elf), str(bin_path)], check=True)
    data = bin_path.read_bytes()
    with args.hex.open("w", encoding="ascii") as f:
        for byte in data:
            f.write(f"{byte:02x}\n")

    print(len(data))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
