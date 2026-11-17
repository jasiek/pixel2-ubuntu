#!/usr/bin/env bash
# Pack build/boot.img = our kernel + our initramfs + Ubuntu cmdline additions.
#   scripts/build-bootimg.sh            # normal boot into Ubuntu
#   DEBUG=1 scripts/build-bootimg.sh    # stop in the initramfs debug shell
#   DTB=own scripts/build-bootimg.sh    # use our kernel build's DTB instead of the factory one
set -euo pipefail
cd "$(dirname "$0")/.."
# selinux=0: Ubuntu has no SELinux policy (needs SECURITY_SELINUX_BOOTPARAM).
# Kernel 4.4 has no cgroup2, so make systemd use the legacy hierarchy.
EXTRA="selinux=0 systemd.unified_cgroup_hierarchy=0 SYSTEMD_CGROUP_ENABLE_LEGACY_FORCE=1"
# Debug images: stop in the initramfs, and turn any hang into a panic so the
# phone reboots (PANIC_TIMEOUT=1) instead of needing the power button.
DEBUG_HANG="softlockup_panic=1 hung_task_panic=1 nmi_watchdog=panic"
[ "${DEBUG:-0}" = 1 ] && EXTRA="$EXTRA initdebug $DEBUG_HANG"
OUT="${OUT:-build/boot.img}"
KDIR="${KDIR:-build/kernel}"
# Device tree: the factory one by default (DTB=own: the one our kernel build
# appended). Only the factory DTB takes the bootloader's dtbo overlays, which
# hold the walleye panel; without the panel node the bootloader splash stays
# lit forever (OLED burn-in). See docs/log.md 2026-11-17.
KIMG="$KDIR/arch/arm64/boot/Image.lz4-dtb"
if [ "${DTB:-factory}" = factory ]; then
    [ -f firmware/boot.img ] || { echo "Missing firmware/boot.img (factory image, see PLAN P1.7)."; exit 1; }
    python3 -I scripts/extract-dtb.py firmware/boot.img build/factory.dtb
    cat "$KDIR/arch/arm64/boot/Image.lz4" build/factory.dtb > build/Image.lz4-factorydtb
    KIMG=build/Image.lz4-factorydtb
fi
exec scripts/make-bootimg.sh "$KIMG" build/initramfs.cpio.gz "$OUT" "$EXTRA"
