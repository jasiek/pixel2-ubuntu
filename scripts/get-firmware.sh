#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Get the Pixel 2 factory image that the build and flashing need -> firmware/
#
#   scripts/get-firmware.sh
#
# - firmware/<build>-factory-<sha8>.zip  downloaded if missing, SHA-256 checked
# - firmware/<build>/                    unpacked: flash-all.sh, bootloader, radio,
#                                        image zip (restoring stock Android)
# - firmware/boot.img                    factory DTB for build-bootimg.sh
# - firmware/vbmeta.img                  flashed with verification off
# - firmware/vendor.img                  wifi board files for build-mainline-fw.sh
# Proprietary Google files: firmware/ is gitignored, never commit it.
set -euo pipefail
cd "$(dirname "$0")/.."

# Final walleye release (Android 11, Dec 2020), see docs/research.md.
# Google's file name carries the first 8 hex digits of the SHA-256.
BUILD=walleye-rp1a.201005.004.a1
ZIP=firmware/$BUILD-factory-0c23f6cf.zip
URL=https://dl.google.com/dl/android/aosp/$BUILD-factory-0c23f6cf.zip
SHA256=0c23f6cf9e2194a3e72b1288f65c5a7f2f6c020080af49c8a494ee99ab3eb543

if [ -f firmware/boot.img ] && [ -f firmware/vbmeta.img ] && [ -f firmware/vendor.img ] \
    && [ -f "firmware/$BUILD/flash-all.sh" ]; then
    echo "firmware: up to date ($BUILD)"
    exit 0
fi

mkdir -p firmware
if [ ! -f "$ZIP" ]; then
    echo "Downloading the Pixel 2 factory image $BUILD (1.7 GB)."
    echo "Google's terms apply: https://developers.google.com/android/images#walleye"
    curl -fL --progress-bar -C - -o "$ZIP.part" "$URL"
    mv "$ZIP.part" "$ZIP"
fi

echo "Checking SHA-256 of $ZIP"
got=$(shasum -a 256 "$ZIP" | cut -d' ' -f1)
if [ "$got" != "$SHA256" ]; then
    echo "ERROR: SHA-256 mismatch: got $got, expected $SHA256." >&2
    echo "Delete $ZIP and run this again." >&2
    exit 1
fi

unzip -o -q "$ZIP" -d firmware/
unzip -o -q -j "firmware/$BUILD/image-$BUILD.zip" boot.img vbmeta.img vendor.img -d firmware/
ls -la firmware/boot.img firmware/vbmeta.img firmware/vendor.img "firmware/$BUILD/flash-all.sh"
