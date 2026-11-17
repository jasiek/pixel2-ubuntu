#!/usr/bin/env python3
"""Copy the device tree appended to a boot.img's kernel into its own file.

    scripts/extract-dtb.py firmware/boot.img build/factory.dtb

Takes the first flattened device tree (magic d00dfeed) with a sane header.
Why: our kernel tree's own walleye base DTB doesn't take the bootloader's
dtbo overlays (no panel node -> the bootloader splash stays lit forever on
the OLED). The factory DTB does (androidboot.dtbo_idx=3).
"""
import struct
import sys

src, dst = sys.argv[1], sys.argv[2]
data = open(src, "rb").read()
i = 0
while True:
    i = data.find(b"\xd0\x0d\xfe\xed", i)
    if i < 0:
        sys.exit(f"{src}: no device tree found")
    total, off_struct, off_strings = struct.unpack(">III", data[i + 4:i + 16])
    if 0x1000 < total < 0x400000 and off_struct < total and off_strings < total:
        break
    i += 4
open(dst, "wb").write(data[i:i + total])
print(f"{dst}: {total} bytes from {src} @ {i}")
