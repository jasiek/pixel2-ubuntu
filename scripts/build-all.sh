#!/usr/bin/env bash
# Build everything the phone needs, from a fresh clone:
#   build/boot.img      kernel + initramfs (flash to boot_a/boot_b)
#   build/rootfs.simg   Ubuntu 24.04 (flash to userdata)
#
#   scripts/build-all.sh          # only the steps whose inputs changed
#   FORCE=1 scripts/build-all.sh  # every step again
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
for c in docker git curl unzip shasum python3; do
    command -v "$c" >/dev/null || die "'$c' not found. Install it and run this again."
done
docker info >/dev/null 2>&1 || die "Docker is not running. Start Docker Desktop and run this again."
mkdir -p build/.stamps
touch build/.stamps/CaseTest
if [ -e build/.stamps/casetest ]; then
    rm -f build/.stamps/CaseTest
    die "This folder is on a case-insensitive filesystem; the kernel needs case-sensitive names.
       Create a case-sensitive APFS volume (Disk Utility: APFS (Case-sensitive)) and clone there."
fi
rm -f build/.stamps/CaseTest
for c in adb fastboot; do
    command -v "$c" >/dev/null || warn "'$c' not found: not needed to build, but needed to flash (brew install android-platform-tools)."
done
ls ~/.ssh/*.pub >/dev/null 2>&1 \
    || warn "No ~/.ssh/*.pub: only the project key build/ssh/pixel2_ed25519 will be able to log in (scripts/ssh.sh uses it)."
echo "ok"

# ---- 2. Sources and firmware -----------------------------------------------
say "2/5 Sources and firmware"
if git submodule status | grep -q '^-'; then
    echo "Fetching submodules (the kernel is a shallow clone, a few hundred MB)."
    git submodule update --init
fi
{ git submodule status | grep '^+' || true; } | while read -r line; do
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
    echo "wifi: none (delete build/wifi.ssid to be asked again)"
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

H_ROOTFS=$(hash_of rootfs scripts/build-rootfs.sh build/wifi.ssid build/wifi.pass build/ssh/pixel2_ed25519.pub \
    "@$(cat ~/.ssh/*.pub 2>/dev/null | sort -u)" \
    "@$H_KERNEL" "@$H_STUBS" "@$H_QBOOTCTL" "@$H_SCREEN")
step rootfs build/rootfs.simg "$H_ROOTFS" scripts/build-rootfs.sh

say "Done"
ls -lh build/boot.img build/rootfs.simg | awk '{print $5, $9}'
echo "Next: flash the phone (PLAN.md P9.2, scripts/flash.sh)."
