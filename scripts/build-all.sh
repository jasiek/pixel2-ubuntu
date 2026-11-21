#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Build everything the phone needs, from a fresh clone:
#   build/boot.img      kernel + initramfs (flash to boot_a/boot_b)
#   build/rootfs.simg   Ubuntu 24.04 (flash to userdata)
#
#   scripts/build-all.sh          # only the steps whose inputs changed
#   FORCE=1 scripts/build-all.sh  # every step again
#   MAINLINE=0 scripts/build-all.sh  # skip the mainline kernel (P8.3; on by default)
#
# With mainline, the rootfs also carries kernel 7.2.2's modules + firmware
# helpers and build/mainline/boot-mainline.img (`fastboot boot` it).
#
# Each step stores a hash of its inputs in build/.stamps/<step> and runs again
# when that hash changes or its output is missing. Hashes rather than mtimes:
# a fresh clone gives every file a new mtime, and the kernel tree is too big
# to scan (its submodule commit stands in for it; local patches are inputs).
set -euo pipefail
cd "$(dirname "$0")/.."
REPO=$(pwd -P)
KREL=4.4.223-walleye-ubuntu

say()  { printf '\n\033[1m== %s\033[0m\n' "$*"; }
warn() { printf '\033[33mWARN:\033[0m %s\n' "$*"; }
die()  { printf '\033[31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

# ---- 1. Prerequisites ------------------------------------------------------
say "1/5 Prerequisites"
# All host checks live in check-prereqs.sh (it reports every gap at once).
# Flash/login tools are only warnings there; run it without --build to see them.
scripts/check-prereqs.sh --build || die "Prerequisites missing (see FAIL lines above)."

# On an x86 Docker the kernels cross-compile (scripts/dev.sh, DEV_CROSS), but
# the initramfs, tools and rootfs are arm64 images: register qemu for them.
# Privileged, and only until the host reboots, so it is checked every run.
BINFMT=tonistiigi/binfmt:qemu-v10.2.3-68@sha256:400a4873b838d1b89194d982c45e5fb3cda4593fbfd7e08a02e76b03b21166f0
arm64_runs() { docker run --rm --platform linux/arm64 ubuntu:24.04 true >/dev/null 2>&1; }
case "$(docker info --format '{{.Architecture}}')" in
    aarch64|arm64) ;;
    *) if ! arm64_runs; then
           echo "Registering qemu for arm64 containers ($BINFMT)"
           docker run --privileged --rm "$BINFMT" --install arm64 >/dev/null
           arm64_runs || die "arm64 containers still don't run after installing qemu binfmt."
       fi
       echo "arm64 containers: emulated (kernels cross-compile natively)" ;;
esac
mkdir -p build/.stamps

# ---- 2. Sources and firmware -----------------------------------------------
say "2/5 Sources and firmware"
# Only what this build uses.
MAINLINE=${MAINLINE:-1}
SUBS=(external/kernel-msm external/mkbootimg external/qbootctl)
[ "$MAINLINE" = 0 ] || SUBS+=(external/linux-mainline external/porthole-pmaports \
    external/pil-squasher external/qcom-diag external/qca-swiss-army-knife external/libcamera)
# grep without -q: -q exits at the first match, git then dies of SIGPIPE and
# pipefail makes the test false exactly when a submodule is missing.
if git submodule status "${SUBS[@]}" | grep '^-' >/dev/null; then
    echo "Fetching submodules (the kernel is a shallow clone, a few hundred MB)."
    git submodule update --init "${SUBS[@]}"
fi
{ git submodule status "${SUBS[@]}" | grep '^+' || true; } | while read -r line; do
    warn "submodule not at the committed version: $line"
done
scripts/get-firmware.sh

# ---- 3. Wifi ---------------------------------------------------------------
# build/wifi.ssid + build/wifi.pass (gitignored, mode 600) become a wifi
# profile in the rootfs. An empty build/wifi.ssid means "no wifi, don't ask".
say "3/5 Wifi"
if [ ! -e build/wifi.ssid ]; then
    if [ -t 0 ]; then
        read -r -p "Wifi network name for the phone (empty = no wifi, USB only): " ssid
        ( umask 077; printf '%s' "$ssid" > build/wifi.ssid )
        if [ -n "$ssid" ]; then
            read -r -s -p "Wifi password: " pass; echo
            ( umask 077; printf '%s' "$pass" > build/wifi.pass )
        fi
        unset ssid pass
    else
        warn "No build/wifi.ssid and no terminal to ask: the phone gets no wifi profile."
    fi
fi
if [ -s build/wifi.ssid ] && [ -s build/wifi.pass ]; then
    echo "wifi: profile from build/wifi.ssid + build/wifi.pass (delete both to be asked again)"
else
    if [ -e build/wifi.ssid ]; then
        echo "wifi: none (delete build/wifi.ssid to be asked again)"
    else
        echo "wifi: none (run this in a terminal to be asked)"
    fi
fi

# ---- 4. Build container ----------------------------------------------------
say "4/5 Build container"
docker build -q --platform linux/arm64 -t pixel2-build docker/ >/dev/null
echo "ok"

# ---- 5. Build steps --------------------------------------------------------
# hash_of <path|@text>...: one SHA-256 over the contents of every file under
# the given paths (missing paths are skipped) plus any @text values.
hash_of() {
    local a paths=()
    {
        for a in "$@"; do
            case "$a" in
                @*) printf '%s\n' "$a" ;;
                *)  [ -e "$a" ] && paths+=("$a") ;;
            esac
        done
        if [ ${#paths[@]} -gt 0 ]; then
            find "${paths[@]}" -type f ! -name '*~' ! -name .DS_Store -print0 \
                | LC_ALL=C sort -z | xargs -0 shasum -a 256
        fi
    } | shasum -a 256 | cut -d' ' -f1
}

# step <name> <output> <hash> <command...>
step() {
    local name=$1 out=$2 hash=$3; shift 3
    local stamp=build/.stamps/$name start=$SECONDS
    if [ "${FORCE:-0}" != 1 ] && [ -e "$out" ] && [ "$(cat "$stamp" 2>/dev/null)" = "$hash" ]; then
        echo "$name: up to date"
        return
    fi
    echo "$name: building..."
    rm -f "$stamp"
    "$@" > "build/$name.log" 2>&1 || {
        tail -n 30 "build/$name.log"
        die "$name failed. Full log: build/$name.log"
    }
    [ -e "$out" ] || die "$name finished but $out is missing. Log: build/$name.log"
    echo "$hash" > "$stamp"
    echo "$name: done in $(( (SECONDS - start) / 60 )) min $(( (SECONDS - start) % 60 )) s (log: build/$name.log)"
}

say "5/5 Build (first run: the kernel takes longest)"
H_DOCKER=$(hash_of docker scripts/dev.sh)
K_HEAD=$(git -C external/kernel-msm rev-parse HEAD)

H_KERNEL=$(hash_of kernel/walleye-ubuntu.config kernel/patches scripts/build-kernel.sh "@$K_HEAD" "@$H_DOCKER")
step kernel "build/kernel/modules-install/lib/modules/$KREL" "$H_KERNEL" scripts/build-kernel.sh

H_INITRAMFS=$(hash_of initramfs scripts/build-initramfs.sh "@$H_DOCKER")
step initramfs build/initramfs.cpio.gz "$H_INITRAMFS" scripts/build-initramfs.sh

H_STUBS=$(hash_of android/stubs scripts/build-android-stubs.sh "@$H_DOCKER")
step android-stubs build/android-stubs/libperipheral_client.so "$H_STUBS" scripts/build-android-stubs.sh

H_QBOOTCTL=$(hash_of scripts/build-qbootctl.sh "@$(git -C external/qbootctl rev-parse HEAD)" "@$H_DOCKER")
step qbootctl build/qbootctl/qbootctl "$H_QBOOTCTL" scripts/build-qbootctl.sh

H_SCREEN=$(hash_of tools/pixel2-screen.c scripts/build-screen.sh "@$K_HEAD" "@$H_DOCKER")
step screen build/screen/pixel2-screen "$H_SCREEN" scripts/build-screen.sh

H_BOOTIMG=$(hash_of firmware/boot.img scripts/build-bootimg.sh scripts/make-bootimg.sh scripts/extract-dtb.py \
    "@$(git -C external/mkbootimg rev-parse HEAD)" "@$H_KERNEL" "@$H_INITRAMFS")
step bootimg build/boot.img "$H_BOOTIMG" scripts/build-bootimg.sh

H_ML=@no-mainline
if [ "$MAINLINE" != 0 ]; then
    H_MTOOLS=$(hash_of scripts/build-modem-tools.sh "@$(git -C external/pil-squasher rev-parse HEAD)" \
        "@$(git -C external/qcom-diag rev-parse HEAD)" "@$H_DOCKER")
    step modem-tools build/modem-tools/diag-router "$H_MTOOLS" scripts/build-modem-tools.sh

    H_MFW=$(hash_of firmware/vendor.img scripts/build-mainline-fw.sh \
        "@$(git -C external/qca-swiss-army-knife rev-parse HEAD)" "@$H_DOCKER")
    step mainline-fw build/mainline/fw/ath10k/board-2.bin "$H_MFW" scripts/build-mainline-fw.sh

    H_MKERNEL=$(hash_of kernel/mainline scripts/build-mainline.sh \
        "@$(git -C external/linux-mainline rev-parse HEAD)" \
        "@$(git -C external/porthole-pmaports rev-parse HEAD)" "@$H_DOCKER")
    step mainline build/mainline/out/arch/arm64/boot/Image.gz "$H_MKERNEL" scripts/build-mainline.sh

    H_MBOOT=$(hash_of scripts/build-mainline-bootimg.sh scripts/make-bootimg.sh "@$H_MKERNEL" "@$H_INITRAMFS")
    step mainline-bootimg build/mainline/boot-mainline.img "$H_MBOOT" scripts/build-mainline-bootimg.sh
    H_LIBCAMERA=$(hash_of scripts/build-libcamera.sh docker/libcamera libcamera/patches "@$(git -C external/libcamera rev-parse HEAD)" \
        "@$(git -C external/porthole-pmaports rev-parse HEAD)")
    step libcamera build/libcamera/root/usr/local/bin/cam "$H_LIBCAMERA" scripts/build-libcamera.sh
    H_ML="@$H_MTOOLS $H_MFW $H_MKERNEL $H_MBOOT $H_LIBCAMERA"
fi

H_ROOTFS=$(hash_of rootfs scripts/build-rootfs.sh camera/tuning build/wifi.ssid build/wifi.pass build/ssh/pixel2_ed25519.pub \
    "@$(cat ~/.ssh/*.pub 2>/dev/null | sort -u)" \
    "@$H_KERNEL" "@$H_STUBS" "@$H_QBOOTCTL" "@$H_SCREEN" "$H_ML")
step rootfs build/rootfs.simg "$H_ROOTFS" env MAINLINE="$MAINLINE" scripts/build-rootfs.sh

say "Done"
ls -lh build/boot.img build/rootfs.simg | awk '{print $5, $9}'
[ "$MAINLINE" = 0 ] || ls -lh build/mainline/boot-mainline.img | awk '{print $5, $9, "(fastboot boot)"}'
echo "Next: flash the phone (PLAN.md P9.2, scripts/flash.sh)."
