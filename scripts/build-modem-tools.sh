#!/usr/bin/env bash
# Build the modem/wifi helper tools for the mainline kernel (P8.3 wifi):
#   build/modem-tools/pil-squasher   merges split .mdt/.bNN firmware into one .mbn
#   build/modem-tools/diag-router    drains the modem's DIAG channel (without it
#                                    the modem kills the WLAN PD every ~19 s)
# Built in docker/mainline (Ubuntu 24.04 = the phone's release, so the
# dynamically linked diag-router runs there; needs libqrtr1 + libudev1).
set -euo pipefail
if [ ! -f /.dockerenv ]; then
    cd "$(dirname "$0")/.."
    git submodule update --init external/pil-squasher external/qcom-diag
    docker build -q --platform linux/arm64 -t pixel2-mainline-build docker/mainline >/dev/null
    exec env DEV_IMAGE=pixel2-mainline-build DEV_DOCKERDIR=docker/mainline scripts/dev.sh /work/scripts/build-modem-tools.sh
fi
OUT=/work/build/modem-tools
mkdir -p "$OUT" /tmp/b
cp -r /work/external/pil-squasher /work/external/qcom-diag /tmp/b/
make -s -C /tmp/b/pil-squasher pil-squasher
make -s -C /tmp/b/qcom-diag diag-router
install -m 755 /tmp/b/pil-squasher/pil-squasher /tmp/b/qcom-diag/diag-router "$OUT/"
file "$OUT"/*
