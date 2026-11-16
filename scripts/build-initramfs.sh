#!/usr/bin/env bash
# Build the initramfs: static busybox + initramfs/init -> build/initramfs.cpio.gz
set -euo pipefail

if [ ! -f /.dockerenv ]; then
    exec "$(dirname "$0")/dev.sh" /work/scripts/build-initramfs.sh "$@"
fi

T=/tmp/initramfs
rm -rf "$T"; mkdir -p "$T"/{bin,dev,proc,sys,tmp,run,newroot}
cp /bin/busybox "$T/bin/busybox"
install -m 755 /work/initramfs/init "$T/init"
# The kernel needs /dev/console before devtmpfs is mounted.
mknod -m 600 "$T/dev/console" c 5 1
mknod -m 666 "$T/dev/null" c 1 3

mkdir -p /work/build
(cd "$T" && find . | sort | cpio -o -H newc --quiet | gzip -9) > /work/build/initramfs.cpio.gz
rm -rf "$T"
ls -la /work/build/initramfs.cpio.gz
