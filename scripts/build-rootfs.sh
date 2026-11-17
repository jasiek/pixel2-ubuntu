#!/usr/bin/env bash
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
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd -P)"
KREL=4.4.223-walleye-ubuntu
MODS="build/kernel/modules-install/lib/modules/$KREL"
SIZE="${ROOTFS_SIZE:-4G}"

if [ ! -f /.dockerenv ]; then
    cd "$REPO"
    [ -d "$MODS" ] || { echo "Missing $MODS. Run scripts/build-kernel.sh first."; exit 1; }
    [ -f build/android-stubs/libperipheral_client.so ] || scripts/build-android-stubs.sh
    mkdir -p build/ssh
    [ -f build/ssh/pixel2_ed25519 ] || ssh-keygen -q -t ed25519 -N "" -C pixel2-port-automation -f build/ssh/pixel2_ed25519
    cat ~/.ssh/*.pub build/ssh/pixel2_ed25519.pub 2>/dev/null | sort -u > build/ssh/authorized_keys

    docker build --platform linux/arm64 -t pixel2-rootfs rootfs/
    cid=$(docker create --platform linux/arm64 pixel2-rootfs)
    trap 'docker rm -f "$cid" >/dev/null' EXIT
    docker export "$cid" -o build/rootfs.tar
    exec "$REPO/scripts/dev.sh" env ROOTFS_SIZE="$SIZE" /work/scripts/build-rootfs.sh
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
depmod -b "$R" "$KREL"

# SSH access.
install -d -m 700 -o 1000 -g 1000 "$R/home/ubuntu/.ssh"
install -m 600 -o 1000 -g 1000 build/ssh/authorized_keys "$R/home/ubuntu/.ssh/authorized_keys"

# Build stamp.
echo "built $(date -u +%FT%TZ) kernel $KREL" > "$R/etc/pixel2-build"

rm -f build/rootfs.img build/rootfs.simg
# Features limited to what kernel 4.4 ext4 supports.
mkfs.ext4 -q -F -L ubuntu -O ^metadata_csum_seed -E root_owner=0:0,lazy_itable_init=0,lazy_journal_init=0 -d "$R" build/rootfs.img "$SIZE"
img2simg build/rootfs.img build/rootfs.simg
rm -rf "$R"
ls -la build/rootfs.img build/rootfs.simg
