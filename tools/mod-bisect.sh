#!/bin/sh
# SPDX-License-Identifier: MIT
# Find which kernel module hangs a boot (P8.3 dev tool). Run from the
# initramfs debug shell (cmdline "initdebug"), as root:
#   sh /newroot/var/lib/pixel2/mod-bisect.sh        (after mounting userdata)
# or let it mount userdata itself:  sh <path>/mod-bisect.sh
# Loads the modules in /var/lib/pixel2/mod-bisect.list one at a time via the
# rootfs's modprobe, logging each name to /mainline-probe/modload.txt and
# syncing BEFORE loading it. After a hang, the last line names the culprit.
R=/newroot
if ! mountpoint -q $R 2>/dev/null; then
    mkdir -p $R
    for u in /sys/class/block/*/uevent; do
        grep -q '^PARTNAME=userdata$' "$u" && root="/dev/$(sed -n 's/^DEVNAME=//p' "$u")"
    done
    mount -t ext4 -o rw,noatime "$root" $R || exit 1
fi
for d in proc sys dev; do mountpoint -q $R/$d || mount --bind /$d $R/$d; done
L=$R/mainline-probe/modload.txt
mkdir -p $R/mainline-probe
echo "== start $(cut -d' ' -f1 /proc/uptime)" >> $L; sync
for m in $(cat $R/var/lib/pixel2/mod-bisect.list); do
    echo "$m" >> $L; sync
    chroot $R /sbin/modprobe "$m" 2>> $L
    sleep "${STEP:-2}"
done
echo "== all loaded, no hang $(cut -d' ' -f1 /proc/uptime)" >> $L; sync
