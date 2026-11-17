#!/usr/bin/env bash
# Tethered-boot an image and report whether our system came up over USB.
#
#   scripts/try-boot.sh build/boot-debug.img [timeout_s]
#
# Gets the phone into fastboot from wherever it is (Android via adb, our
# initramfs via telnet, Ubuntu via ssh, either via USB serial), runs
# `fastboot boot`, then waits for
# 172.16.42.1 to answer. Exit 0 = up, 1 = Android came back, 2 = timeout.
# Nothing is flashed.
set -uo pipefail
cd "$(dirname "$0")/.."
IMG="$1"; TIMEOUT="${2:-120}"
PHONE=172.16.42.1
KEY=build/ssh/pixel2_ed25519
SSH=(ssh -i "$KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=3 -o LogLevel=ERROR)

in_fastboot() { [ -n "$(fastboot devices 2>/dev/null)" ]; }
in_android()  { adb get-state 2>/dev/null | grep -q device; }
ours_up()     { ping -c1 -t1 "$PHONE" >/dev/null 2>&1; }

to_fastboot() {
    in_fastboot && return 0
    if in_android; then
        adb reboot bootloader
    elif ours_up && nc -z -G 2 "$PHONE" 22 2>/dev/null; then
        "${SSH[@]}" ubuntu@$PHONE 'sudo systemctl reboot --reboot-argument=bootloader' || true
    elif ours_up && nc -z -G 2 "$PHONE" 23 2>/dev/null; then
        scripts/initrd-sh.py 'reboot-bootloader || echo b > /proc/sysrq-trigger' >/dev/null 2>&1 || true
    elif ls /dev/cu.usbmodempixel2* >/dev/null 2>&1; then
        # Ubuntu (autologin user with sudo) or the initramfs serial shell.
        TIMEOUT=10 scripts/serial-sh.py 'sudo -n systemctl reboot --reboot-argument=bootloader 2>/dev/null || reboot-bootloader' >/dev/null 2>&1 || true
    else
        echo "phone not reachable (adb/fastboot/usb net). Hold Vol-Down + Power."
    fi
    for i in $(seq 1 90); do in_fastboot && return 0; sleep 1; done
    # Fallback: we may have landed in Android.
    in_android && { adb reboot bootloader; for i in $(seq 1 60); do in_fastboot && return 0; sleep 1; done; }
    return 1
}

to_fastboot || { echo "FAIL: could not reach fastboot"; exit 3; }
sleep 1
fastboot boot "$IMG" >/dev/null 2>&1 || { echo "FAIL: fastboot boot"; exit 3; }
start=$(date +%s)
sleep 3
while [ $(( $(date +%s) - start )) -lt "$TIMEOUT" ]; do
    if ours_up; then echo "UP after $(( $(date +%s) - start ))s: $IMG"; exit 0; fi
    if in_android; then echo "DOWN: Android came back after $(( $(date +%s) - start ))s (image crashed/reset)"; exit 1; fi
    sleep 2
done
echo "TIMEOUT after ${TIMEOUT}s: no USB network, no Android"
exit 2
