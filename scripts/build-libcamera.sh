#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# libcamera for the phone (P8.5): external/libcamera (v0.7.2) + the patches
# Porthole carries for msm8998 (IMX179/IMX362 sensor properties, soft-ISP
# AGC/AWB/CCM/LSC/focus) and its tuning files for both sensors.
#
#   scripts/build-libcamera.sh  ->  build/libcamera/root (installed under /usr/local)
#
# Pipelines: simple (CAMSS + CPU soft-ISP; walleye's GPU is off, so no
# softisp-gpu) and virtual. Tools: cam, the GStreamer libcamerasrc element,
# and the v4l2 compatibility layer.
set -euo pipefail
if [ ! -f /.dockerenv ]; then
    cd "$(dirname "$0")/.."
    git submodule update --init external/libcamera external/porthole-pmaports
    docker build -q --platform linux/arm64 -t pixel2-libcamera-build docker/libcamera >/dev/null
    exec env DEV_IMAGE=pixel2-libcamera-build DEV_DOCKERDIR=docker/libcamera scripts/dev.sh /work/scripts/build-libcamera.sh
fi

# ---- inside the build container ----
P=/work/external/porthole-pmaports/temp/libcamera
SRC=/tmp/libcamera; OUT=/work/build/libcamera
rm -rf "$SRC" "$OUT/root"; mkdir -p "$SRC" "$OUT"
cp -a /work/external/libcamera/. "$SRC/"; rm -rf "$SRC/.git"
n=0
for f in $(sed -n '/^source=/,/"$/p' "$P/APKBUILD" | grep -o '[0-9]\{4\}-[^ ]*\.patch'); do
    patch -d "$SRC" -p1 -s --no-backup-if-mismatch -i "$P/$f"
    n=$((n + 1))
done
echo "applied $n Porthole patches"
# A git-less tree: give meson the version instead of running git describe.
echo 0.7.2 > "$SRC/.tarball-version"

meson setup /tmp/lc-build "$SRC" --prefix=/usr/local --buildtype=release \
    -Dpipelines=simple,virtual -Dipas=simple -Dsoftisp-gpu=disabled \
    -Dcam=enabled -Dgstreamer=enabled -Dv4l2=enabled \
    -Dqcam=disabled -Dlc-compliance=disabled -Dtest=false -Dpycamera=disabled \
    -Ddocumentation=disabled -Dwerror=false >/tmp/meson.log || { tail -40 /tmp/meson.log; exit 1; }
meson compile -C /tmp/lc-build
DESTDIR="$OUT/root" meson install --no-rebuild -C /tmp/lc-build >/dev/null
# Tuning: Porthole's taimen files, unless camera/tuning/ has a walleye one
# (imx179: Bayes AWB on walleye's vendor locus). pixel2-camera-tuning puts
# each phone's own lens shading on top at boot.
for t in imx179 imx362; do
    src="$P/$t.yaml"; [ -f "/work/camera/tuning/$t.yaml" ] && src="/work/camera/tuning/$t.yaml"
    install -Dm644 "$src" "$OUT/root/usr/local/share/libcamera/ipa/simple/$t.yaml"
done
ls "$OUT/root/usr/local/bin" "$OUT/root/usr/local/lib/aarch64-linux-gnu" 2>/dev/null | head -20
