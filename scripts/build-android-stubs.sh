#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Build stub libraries for Android (bionic) vendor daemons -> build/android-stubs/
# Freestanding (no libc), so no NDK is needed: clang targets aarch64 Android
# and lld links a plain shared object.
set -euo pipefail
if [ ! -f /.dockerenv ]; then
    exec "$(dirname "$0")/dev.sh" /work/scripts/build-android-stubs.sh "$@"
fi
OUT=/work/build/android-stubs
mkdir -p "$OUT"
clang --target=aarch64-linux-android29 -O2 -fPIC -shared -nostdlib -fuse-ld=lld \
    -Wl,-soname,libperipheral_client.so -Wl,--hash-style=both \
    -o "$OUT/libperipheral_client.so" /work/android/stubs/peripheral_client.c
readelf --dyn-syms "$OUT/libperipheral_client.so" | grep pm_client
