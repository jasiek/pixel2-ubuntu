#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# ath10k (WCN3990) files for the mainline kernel, baked into the rootfs (P8.3):
#   build/mainline/fw/ath10k/board-2.bin     walleye's bdwlan.bin/.b09/.b80
#       from the factory vendor.img (firmware/, scripts/get-firmware.sh),
#       encoded with ath10k-bdencoder (external/qca-swiss-army-knife).
#       Walleye's QMI board_id is 0x80.
#   build/mainline/fw/ath10k/firmware-5.bin  from linux-firmware (SHA-256 checked).
# Proprietary/derived blobs: build/ only, never committed.
set -euo pipefail
FW5_URL=https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/ath10k/WCN3990/hw1.0/firmware-5.bin
FW5_SHA=fef6539e0127579536bc977be57a90d018b83f2931fedc3a8870fbe38d6c4127
OUT=build/mainline/fw/ath10k

if [ ! -f /.dockerenv ]; then
    cd "$(dirname "$0")/.."
    [ -f firmware/vendor.img ] || { echo "Missing firmware/vendor.img. Run scripts/get-firmware.sh first."; exit 1; }
    git submodule update --init external/qca-swiss-army-knife
    mkdir -p "$OUT"
    if [ "$(shasum -a 256 "$OUT/firmware-5.bin" 2>/dev/null | cut -d' ' -f1)" != "$FW5_SHA" ]; then
        curl -fsSL -o "$OUT/firmware-5.bin.part" "$FW5_URL"
        got=$(shasum -a 256 "$OUT/firmware-5.bin.part" | cut -d' ' -f1)
        [ "$got" = "$FW5_SHA" ] || { echo "firmware-5.bin: SHA-256 $got, expected $FW5_SHA"; exit 1; }
        mv "$OUT/firmware-5.bin.part" "$OUT/firmware-5.bin"
    fi
    exec scripts/dev.sh /work/scripts/build-mainline-fw.sh
fi

# ---- inside the build container ----
cd /work
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
simg2img firmware/vendor.img "$T/vendor.raw"
for f in bdwlan.bin bdwlan.b09 bdwlan.b80; do
    debugfs -R "dump /firmware/$f $T/$f" "$T/vendor.raw" 2>/dev/null
    [ -s "$T/$f" ] || { echo "vendor.img: /firmware/$f missing"; exit 1; }
done
cat > "$T/board-2.json" <<'J'
[
	{ "data": "bdwlan.bin", "names": [ "bus=snoc,qmi-board-id=ff" ] },
	{ "data": "bdwlan.b09", "names": [ "bus=snoc,qmi-board-id=9" ] },
	{ "data": "bdwlan.b80", "names": [ "bus=snoc,qmi-board-id=80" ] }
]
J
(cd "$T" && python3 /work/external/qca-swiss-army-knife/tools/scripts/ath10k/ath10k-bdencoder -c board-2.json -o board-2.bin >/dev/null)
install -m 644 "$T/board-2.bin" "$OUT/board-2.bin"
ls -l "$OUT"
