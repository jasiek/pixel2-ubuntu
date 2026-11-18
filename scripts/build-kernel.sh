#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Build the Pixel 2 (walleye) kernel from external/kernel-msm.
#
#   scripts/build-kernel.sh              # wahoo_defconfig + kernel/walleye-ubuntu.config
#   STOCK=1 scripts/build-kernel.sh      # plain wahoo_defconfig (P3.1 sanity build)
#   FRAGMENT=kernel/x.config OUT=build/kernel-x scripts/build-kernel.sh   # debug variants
#
# Runs inside the build container (re-execs itself through scripts/dev.sh).
# Output: build/kernel[-stock]/arch/arm64/boot/Image.lz4-dtb
#         build/kernel/modules-install/lib/modules/<release>/  (non-stock only)
# Patches in kernel/patches/*.patch are applied to the submodule (idempotent);
# .gitmodules sets ignore=dirty so the patched tree doesn't show as modified.
set -euo pipefail

if [ ! -f /.dockerenv ]; then
    DEV_CROSS=1 exec "$(dirname "$0")/dev.sh" env STOCK="${STOCK:-0}" JOBS="${JOBS:-}" FRAGMENT="${FRAGMENT:-}" OUT="${OUT:-}" /work/scripts/build-kernel.sh "$@"
fi

SRC=/work/external/kernel-msm
FRAGMENT=/work/${FRAGMENT:-kernel/walleye-ubuntu.config}
if [ -n "${OUT:-}" ]; then OUT=/work/$OUT
elif [ "${STOCK:-0}" = 1 ]; then OUT=/work/build/kernel-stock; else OUT=/work/build/kernel; fi
JOBS="${JOBS:-$(nproc)}"

if [ "${STOCK:-0}" != 1 ]; then
    for p in /work/kernel/patches/*.patch; do
        if git -C "$SRC" apply --check -R "$p" 2>/dev/null; then
            echo "patch already applied: $(basename "$p")"
        else
            git -C "$SRC" apply "$p" && echo "patch applied: $(basename "$p")"
        fi
    done
else
    # Stock build: make sure no patches are applied.
    for p in /work/kernel/patches/*.patch; do
        git -C "$SRC" apply --check -R "$p" 2>/dev/null && git -C "$SRC" apply -R "$p" && echo "patch reverted: $(basename "$p")"
    done
fi

# Same toolchain family as Google's build.config.common.clang (clang 11),
# but with native arm64 binutils instead of Android's x86 prebuilts.
MAKE=(make -C "$SRC" O="$OUT" -j"$JOBS"
      ARCH=arm64 LOCALVERSION=
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
if [ "${STOCK:-0}" != 1 ]; then
    "${MAKE[@]}" modules 2>&1 | tee -a "$OUT/build.log" | grep -E "error|Error" || true
    rm -rf "$OUT/modules-install"
    "${MAKE[@]}" INSTALL_MOD_PATH="$OUT/modules-install" INSTALL_MOD_STRIP=1 modules_install >/dev/null
    find "$OUT/modules-install" -name "*.ko" | sed "s|$OUT/modules-install/||"
fi
ls -la "$OUT/arch/arm64/boot/Image.lz4-dtb"
strings "$OUT/vmlinux" | grep -m1 "^Linux version" || true  # -m1 closes the pipe early (SIGPIPE)
