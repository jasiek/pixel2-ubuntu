#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Build the Ubuntu 24.04 root filesystem image for the phone.
#
#   scripts/build-rootfs.sh
#
# 1. docker build rootfs/            -> image pixel2-rootfs
# 2. docker export                   -> build/rootfs.tar
# 3. in the build container: unpack, add kernel modules + SSH keys,
#    mkfs.ext4 -d                     -> build/rootfs.img (4 GiB, grows on phone)
#    img2simg                         -> build/rootfs.simg (for fastboot)
#
# SSH keys installed for user ubuntu: every ~/.ssh/*.pub plus the project
# key build/ssh/pixel2_ed25519.pub (created if missing).
# Wifi: build/wifi.ssid + build/wifi.pass become an autoconnect NM profile.
# Mainline kernel (P8.3), if built: its modules, pil-squasher + diag-router
# (build-modem-tools.sh), ath10k board data (build-mainline-fw.sh) and
# /boot/boot-mainline.img, libcamera (scripts/build-libcamera.sh). Modem firmware is made on the phone at boot
# (pixel2-modem-fw.service).
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd -P)"
KREL=4.4.223-walleye-ubuntu
MODS="build/kernel/modules-install/lib/modules/$KREL"
SIZE="${ROOTFS_SIZE:-4G}"

if [ ! -f /.dockerenv ]; then
    cd "$REPO"
    [ -d "$MODS" ] || { echo "Missing $MODS. Run scripts/build-kernel.sh first."; exit 1; }
    [ -f build/android-stubs/libperipheral_client.so ] || scripts/build-android-stubs.sh
    [ -f build/qbootctl/qbootctl ] || scripts/build-qbootctl.sh
    scripts/build-screen.sh
    mkdir -p build/ssh
    [ -f build/ssh/pixel2_ed25519 ] || ssh-keygen -q -t ed25519 -N "" -C pixel2-port-automation -f build/ssh/pixel2_ed25519
    # A host without ~/.ssh/*.pub is fine (the project key still goes in);
    # without the `|| true`, cat's failure on the unmatched glob kills the
    # build silently under pipefail.
    { cat ~/.ssh/*.pub 2>/dev/null || true; cat build/ssh/pixel2_ed25519.pub; } | sort -u > build/ssh/authorized_keys

    docker build --platform linux/arm64 -t pixel2-rootfs rootfs/
    cid=$(docker create --platform linux/arm64 pixel2-rootfs)
    trap 'docker rm -f "$cid" >/dev/null' EXIT
    docker export "$cid" -o build/rootfs.tar
    exec "$REPO/scripts/dev.sh" env ROOTFS_SIZE="$SIZE" MAINLINE="${MAINLINE:-1}" /work/scripts/build-rootfs.sh
fi

# ---- inside the build container (as root) ----
cd /work
R=/tmp/rootfs          # container-internal FS: keeps ownership/modes exact
rm -rf "$R"; mkdir -p "$R"
tar -xpf build/rootfs.tar -C "$R" --numeric-owner

# Docker leftovers / files Docker managed at runtime.
rm -f "$R/.dockerenv"
echo pixel2 > "$R/etc/hostname"
printf '127.0.0.1\tlocalhost\n127.0.1.1\tpixel2\n::1\tlocalhost ip6-localhost ip6-loopback\n' > "$R/etc/hosts"
rm -f "$R/etc/resolv.conf"
ln -s ../run/systemd/resolve/stub-resolv.conf "$R/etc/resolv.conf"

# Kernel modules built by scripts/build-kernel.sh.
mkdir -p "$R/lib/modules"
cp -a "$MODS" "$R/lib/modules/"
# Stub libraries for the Android vendor daemons (scripts/build-android-stubs.sh).
mkdir -p "$R/usr/local/lib/pixel2/android"
install -m 644 /work/build/android-stubs/*.so "$R/usr/local/lib/pixel2/android/"
# A/B slot marking (scripts/build-qbootctl.sh, pixel2-boot-successful.service).
install -m 755 /work/build/qbootctl/qbootctl "$R/usr/local/sbin/qbootctl"
# Screen console (scripts/build-screen.sh, pixel2-screen.service).
install -m 755 /work/build/screen/pixel2-screen "$R/usr/local/sbin/pixel2-screen"
depmod -b "$R" "$KREL"

# Mainline kernel (P8.3), when scripts/build-all.sh built it.
ML=build/mainline/modules-install/lib/modules
if [ "${MAINLINE:-1}" != 0 ] && [ -d "$ML" ] && [ -f build/mainline/boot-mainline.img ]; then
    MKREL=$(ls "$ML")
    cp -a "$ML/$MKREL" "$R/lib/modules/"
    depmod -b "$R" "$MKREL"
    install -m 755 build/modem-tools/pil-squasher build/modem-tools/diag-router "$R/usr/local/sbin/"
    install -d "$R/lib/firmware/ath10k/WCN3990/hw1.0"
    install -m 644 build/mainline/fw/ath10k/board-2.bin build/mainline/fw/ath10k/firmware-5.bin \
        "$R/lib/firmware/ath10k/WCN3990/hw1.0/"
    install -m 644 build/mainline/boot-mainline.img "$R/boot/boot-mainline.img"
    # Camera (P8.5): libcamera + cam + GStreamer libcamerasrc (build-libcamera.sh).
    cp -a build/libcamera/root/usr/local/. "$R/usr/local/"
    chroot "$R" ldconfig
    echo "mainline $MKREL included"
fi

# SSH access.
install -d -m 700 -o 1000 -g 1000 "$R/home/ubuntu/.ssh"
install -m 600 -o 1000 -g 1000 build/ssh/authorized_keys "$R/home/ubuntu/.ssh/authorized_keys"

# Wifi profile from build/wifi.ssid + build/wifi.pass (gitignored; asked by
# scripts/build-all.sh). An empty or missing ssid file means no wifi profile.
# Never echo these values.
if [ -s build/wifi.ssid ] && [ -s build/wifi.pass ]; then
    ssid=$(cat build/wifi.ssid); psk=$(cat build/wifi.pass)   # $(...) drops trailing newlines
    nm="$R/etc/NetworkManager/system-connections/wifi.nmconnection"
    (umask 077
     printf '[connection]\nid=wifi\ntype=wifi\ninterface-name=wlan0\nautoconnect=true\n\n[wifi]\nmode=infrastructure\nssid=%s\n\n[wifi-security]\nkey-mgmt=wpa-psk\npsk=%s\n\n[ipv4]\nmethod=auto\n\n[ipv6]\nmethod=auto\n' "$ssid" "$psk" > "$nm")
    chown 0:0 "$nm"; chmod 600 "$nm"
    unset ssid psk
    echo "wifi profile added"
else
    echo "no wifi profile (build/wifi.ssid empty or missing)"
fi

# Build stamp.
echo "built $(date -u +%FT%TZ) kernel $KREL" > "$R/etc/pixel2-build"

rm -f build/rootfs.img build/rootfs.simg
# Features limited to what kernel 4.4 ext4 supports.
mkfs.ext4 -q -F -L ubuntu -O ^metadata_csum_seed -E root_owner=0:0,lazy_itable_init=0,lazy_journal_init=0 -d "$R" build/rootfs.img "$SIZE"
img2simg build/rootfs.img build/rootfs.simg
rm -rf "$R"
ls -la build/rootfs.img build/rootfs.simg
