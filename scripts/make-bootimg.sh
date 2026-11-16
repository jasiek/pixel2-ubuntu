#!/usr/bin/env bash
# Pack a Pixel 2 boot.img (header v0) with the same layout as the stock one.
# Values come from docs/device-info.md (P2.4).
#
#   scripts/make-bootimg.sh <kernel Image.lz4-dtb> <ramdisk> <out.img> [extra cmdline]
set -euo pipefail

if [ ! -f /.dockerenv ]; then
    exec "$(dirname "$0")/dev.sh" /work/scripts/make-bootimg.sh "$@"
fi

KERNEL="$1"; RAMDISK="$2"; OUT="$3"; EXTRA="${4:-}"

STOCK_CMDLINE="androidboot.hardware=walleye androidboot.console=ttyMSM0 lpm_levels.sleep_disabled=1 user_debug=31 msm_rtb.filter=0x37 ehci-hcd.park=3 service_locator.enable=1 swiotlb=2048 firmware_class.path=/vendor/firmware loop.max_part=7 raid=noautodetect usbcore.autosuspend=7 androidboot.dtbo_idx=3 buildvariant=user"
CMDLINE="${CMDLINE:-$STOCK_CMDLINE}${EXTRA:+ $EXTRA}"

mkdir -p "$(dirname "$OUT")"
python3 /work/external/mkbootimg/mkbootimg.py \
    --header_version 0 --pagesize 4096 --base 0x00000000 \
    --kernel_offset 0x00008000 --ramdisk_offset 0x01000000 --tags_offset 0x00000100 \
    --os_version 11.0.0 --os_patch_level 2020-10 \
    --kernel "$KERNEL" --ramdisk "$RAMDISK" \
    --cmdline "$CMDLINE" \
    --output "$OUT"

size=$(stat -c %s "$OUT")
max=$((32 * 1024 * 1024))   # boot_a/boot_b partition size
echo "$OUT: $size bytes (partition limit $max)"
[ "$size" -le "$max" ] || { echo "ERROR: boot image larger than boot partition"; exit 1; }
