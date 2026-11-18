#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Pack build/mainline/boot-mainline.img = mainline Image.gz + walleye DTB +
# our initramfs (P8.3). Test with `fastboot boot`, nothing flashed.
#
# Cmdline: clk/pd_ignore_unused (the bootloader's display/UFS clocks stay up),
# panic=10 + reboot=w (warm reboot back into the bootloader on a panic),
# selinux=0, fbcon=font:TER16x32 (67x60 console like 4.4's pixel2-screen).
# Burn-in: pixel2-screen keeps the panel off unless touched.
set -euo pipefail
cd "$(dirname "$0")/.."
B=build/mainline/out/arch/arm64/boot
DTB=$B/dts/qcom/msm8998-google-walleye-ubuntu.dtb
for f in $B/Image.gz $DTB build/initramfs.cpio.gz; do
    [ -f "$f" ] || { echo "missing $f"; exit 1; }
done
cat $B/Image.gz $DTB > build/mainline/Image.gz-dtb
scripts/make-bootimg.sh build/mainline/Image.gz-dtb build/initramfs.cpio.gz build/mainline/boot-mainline.img \
    "clk_ignore_unused pd_ignore_unused panic=10 reboot=w selinux=0 fbcon=font:TER16x32 quiet"
