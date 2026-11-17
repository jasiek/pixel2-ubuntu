#!/usr/bin/env bash
# Build the mainline kernel experiment for walleye (P8.3).
#
#   scripts/build-mainline.sh
#
# Sources: external/linux-mainline (kernel.org v7.2.2) + Porthole's patch
# series (external/porthole-pmaports, applied in APKBUILD order) + ours in
# kernel/mainline/ (DTS, config fragment, patches/*.patch applied last). The patched tree is an
# APFS clone in build/mainline/src, so the submodule stays pristine.
# Toolchain: clang 18 (LLVM=-18) in docker/mainline, like Porthole's LLVM=1.
#
# Output: build/mainline/out/arch/arm64/boot/Image.gz
#         build/mainline/out/arch/arm64/boot/dts/qcom/msm8998-google-walleye-ubuntu.dtb
#         build/mainline/modules-install/lib/modules/<release>/
set -euo pipefail
PKG=external/porthole-pmaports/device/testing/linux-postmarketos-qcom-msm8998-7.2
DTS=msm8998-google-walleye-ubuntu

if [ ! -f /.dockerenv ]; then
    cd "$(dirname "$0")/.."
    export DEV_IMAGE=pixel2-mainline-build DEV_DOCKERDIR=docker/mainline
    if [ ! -f external/linux-mainline/Makefile ] || [ ! -f "$PKG/APKBUILD" ]; then
        git submodule update --init external/linux-mainline external/porthole-pmaports
    fi
    want="$(cat "$PKG/APKBUILD" "$PKG"/*.patch | shasum -a 256 | cut -c1-16) $(git -C external/linux-mainline rev-parse HEAD)"
    ours="$(cat kernel/mainline/patches/*.patch 2>/dev/null | shasum -a 256 | cut -c1-16)"
    have_ours="$(cat build/mainline/src/.ours 2>/dev/null || true)"
    if [ "$(cat build/mainline/src/.porthole 2>/dev/null)" != "$want" ] \
        || { [ -n "$have_ours" ] && [ "$have_ours" != "$ours" ]; }; then
        echo "Copying the kernel tree to build/mainline/src"
        rm -rf build/mainline/src build/mainline/out
        mkdir -p build/mainline
        cp -c -R external/linux-mainline build/mainline/src   # APFS clone: fast, no extra space
        rm -f build/mainline/src/.git
        scripts/dev.sh /work/scripts/build-mainline.sh patch
        echo "$want" > build/mainline/src/.porthole
        have_ours=""
    fi
    # Our own patches (kernel/mainline/patches) go on top. Applied in place when
    # the tree has none yet, so adding the first one doesn't force a full rebuild.
    if [ -z "$have_ours" ]; then
        scripts/dev.sh /work/scripts/build-mainline.sh ours
        echo "$ours" > build/mainline/src/.ours
    fi
    exec scripts/dev.sh /work/scripts/build-mainline.sh build
fi

# ---- inside the container ----
SRC=/work/build/mainline/src
OUT=/work/build/mainline/out
P=/work/$PKG

if [ "${1:-}" = patch ]; then
    n=0
    for f in $(sed -n '/^source="/,/"$/p' "$P/APKBUILD" | grep -o '[^[:space:]"]*\.patch'); do
        patch -d "$SRC" -p1 -s --no-backup-if-mismatch -i "$P/$f" || { echo "FAILED: $f"; exit 1; }
        n=$((n + 1))
    done
    echo "applied $n Porthole patches"
    exit 0
fi
if [ "${1:-}" = ours ]; then
    for f in /work/kernel/mainline/patches/*.patch; do
        [ -e "$f" ] || continue
        patch -d "$SRC" -p1 -s --no-backup-if-mismatch -i "$f" || { echo "FAILED: $f"; exit 1; }
        echo "applied $(basename "$f")"
    done
    exit 0
fi

MAKE=(make -C "$SRC" O="$OUT" ARCH=arm64 LLVM=-18 -j"$(nproc)"
      KBUILD_BUILD_USER=pixel2 KBUILD_BUILD_HOST=ubuntu-port)

# Our first-boot DTS next to Porthole's walleye.dts.
cp /work/kernel/mainline/$DTS.dts /work/kernel/mainline/wahoo-dtbo-sink.dtsi "$SRC/arch/arm64/boot/dts/qcom/"
grep -q "$DTS.dtb" "$SRC/arch/arm64/boot/dts/qcom/Makefile" \
    || echo "dtb-\$(CONFIG_ARCH_QCOM) += $DTS.dtb" >> "$SRC/arch/arm64/boot/dts/qcom/Makefile"

mkdir -p "$OUT"
cp "$P/config-postmarketos-qcom-msm8998-7.2.aarch64" "$OUT/.config"
# merge_config.sh writes temp files into the current directory.
(cd "$OUT" && "$SRC/scripts/kconfig/merge_config.sh" -m -O "$OUT" "$OUT/.config" /work/kernel/mainline/ubuntu.config >/dev/null)
"${MAKE[@]}" olddefconfig >/dev/null

missing=0
while IFS= read -r line; do
    case "$line" in
        CONFIG_*=*|"# CONFIG_"*" is not set")
            grep -qxF "$line" "$OUT/.config" || { echo "WARN not applied: $line"; missing=1; } ;;
    esac
done < /work/kernel/mainline/ubuntu.config
[ "$missing" = 0 ] && echo "All fragment options applied."

"${MAKE[@]}" Image.gz dtbs modules 2>&1 | tee "$OUT/build.log" | grep -E "error|Error|warning: unused" || true
test -f "$OUT/arch/arm64/boot/Image.gz"
test -f "$OUT/arch/arm64/boot/dts/qcom/$DTS.dtb"
rm -rf /work/build/mainline/modules-install
"${MAKE[@]}" INSTALL_MOD_PATH=/work/build/mainline/modules-install INSTALL_MOD_STRIP=1 modules_install >/dev/null
ls -la "$OUT/arch/arm64/boot/Image.gz" "$OUT/arch/arm64/boot/dts/qcom/$DTS.dtb"
cat "$OUT/include/config/kernel.release"
