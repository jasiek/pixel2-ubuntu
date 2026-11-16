#!/bin/sh
# Mount the active slot's Android vendor partition read-only at /vendor.
# The kernel loads firmware from /vendor/firmware (firmware_class.path).
set -e
suffix=$(sed -n 's/.*androidboot.slot_suffix=\(_[ab]\).*/\1/p' /proc/cmdline)
[ -n "$suffix" ] || suffix=_a
dev=/dev/disk/by-partlabel/vendor$suffix
for i in $(seq 1 20); do [ -e "$dev" ] && break; sleep 0.5; done
mkdir -p /vendor
mountpoint -q /vendor || mount -o ro "$dev" /vendor
echo "mounted vendor$suffix at /vendor"
