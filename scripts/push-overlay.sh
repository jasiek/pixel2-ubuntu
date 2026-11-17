#!/usr/bin/env bash
# Copy rootfs/overlay onto the running phone (no reflash) and reload systemd.
# For quick iteration; the next scripts/build-rootfs.sh bakes it in properly.
# Also sets the phone's clock from the Mac (it has no RTC sync until wifi/NTP).
set -euo pipefail
cd "$(dirname "$0")/.."
COPYFILE_DISABLE=1 tar --no-xattrs -C rootfs/overlay -cf - . \
    | scripts/ssh.sh "sudo date -s @$(date +%s) >/dev/null && sudo tar -C / -m --no-same-owner --no-overwrite-dir -xf - && sudo systemctl daemon-reload && echo 'overlay pushed'"
