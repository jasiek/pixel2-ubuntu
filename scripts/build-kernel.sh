#!/usr/bin/env bash
# Build the Pixel 2 (walleye) kernel from external/kernel-msm.
#
#   scripts/build-kernel.sh              # wahoo_defconfig + kernel/walleye-ubuntu.config
#   STOCK=1 scripts/build-kernel.sh      # plain wahoo_defconfig (P3.1 sanity build)
#
# Runs inside the build container (re-execs itself through scripts/dev.sh).
# Output: build/kernel[-stock]/arch/arm64/boot/Image.lz4-dtb
set -euo pipefail

if [ ! -f /.dockerenv ]; then
    exec "$(dirname "$0")/dev.sh" env STOCK="${STOCK:-0}" JOBS="${JOBS:-}" /work/scripts/build-kernel.sh "$@"
fi

SRC=/work/external/kernel-msm
FRAGMENT=/work/kernel/walleye-ubuntu.config
if [ "${STOCK:-0}" = 1 ]; then OUT=/work/build/kernel-stock; else OUT=/work/build/kernel; fi
JOBS="${JOBS:-$(nproc)}"

# Same toolchain family as Google's build.config.common.clang (clang 11),
# but with native arm64 binutils instead of Android's x86 prebuilts.
MAKE=(make -C "$SRC" O="$OUT" -j"$JOBS"
      ARCH=arm64
      CC=clang CLANG_TRIPLE=aarch64-linux-gnu-
      CROSS_COMPILE=aarch64-linux-gnu-
      CROSS_COMPILE_ARM32=arm-linux-gnueabi-)

mkdir -p "$OUT"
"${MAKE[@]}" wahoo_defconfig

# Ubuntu's clang 11 warns about a few things Android's clang didn't; don't fail on them.
"$SRC/scripts/config" --file "$OUT/.config" -d CC_WERROR

if [ "${STOCK:-0}" != 1 ]; then
    "$SRC/scripts/kconfig/merge_config.sh" -m -O "$OUT" "$OUT/.config" "$FRAGMENT"
fi
"${MAKE[@]}" olddefconfig

if [ "${STOCK:-0}" != 1 ]; then
    # Report fragment options that Kconfig dropped (missing deps, typos).
    missing=0
    while IFS= read -r line; do
        case "$line" in
            CONFIG_*=*) grep -qxF "$line" "$OUT/.config" || { echo "WARN not applied: $line"; missing=1; } ;;
            "# CONFIG_"*" is not set") grep -qxF "$line" "$OUT/.config" || { echo "WARN not applied: $line"; missing=1; } ;;
        esac
    done < "$FRAGMENT"
    [ "$missing" = 0 ] && echo "All fragment options applied."
fi

"${MAKE[@]}" Image.lz4-dtb 2>&1 | tee "$OUT/build.log" | grep -E "error|Error|warning: .*(implicit|incompatible)|Image" || true
test -f "$OUT/arch/arm64/boot/Image.lz4-dtb"
ls -la "$OUT/arch/arm64/boot/Image.lz4-dtb"
strings "$OUT/vmlinux" | grep -m1 "^Linux version"
