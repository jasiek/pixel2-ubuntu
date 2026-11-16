#!/usr/bin/env bash
# Pack build/boot.img = our kernel + our initramfs + Ubuntu cmdline additions.
#   scripts/build-bootimg.sh            # normal boot into Ubuntu
#   DEBUG=1 scripts/build-bootimg.sh    # stop in the initramfs debug shell
set -euo pipefail
cd "$(dirname "$0")/.."
# selinux=0: Ubuntu has no SELinux policy (needs SECURITY_SELINUX_BOOTPARAM).
# Kernel 4.4 has no cgroup2, so make systemd use the legacy hierarchy.
EXTRA="selinux=0 systemd.unified_cgroup_hierarchy=0 SYSTEMD_CGROUP_ENABLE_LEGACY_FORCE=1 console=tty0"
[ "${DEBUG:-0}" = 1 ] && EXTRA="$EXTRA initdebug"
OUT="${OUT:-build/boot.img}"
KDIR="${KDIR:-build/kernel}"
exec scripts/make-bootimg.sh "$KDIR/arch/arm64/boot/Image.lz4-dtb" build/initramfs.cpio.gz "$OUT" "$EXTRA"
