#!/usr/bin/env bash
# Guided flashing: stock Pixel 2 (walleye) -> Ubuntu 24.04.
#
#   scripts/flash.sh           # install Ubuntu (erases the phone)
#   scripts/flash.sh restore   # back to stock Android 11 (erases the phone)
#
# One step at a time; each step checks the phone's state before going on.
# Needs build/boot.img + build/rootfs.simg (scripts/build-all.sh) and
# firmware/ (scripts/get-firmware.sh). Nothing is written to the phone before
# you type "yes" in step 3.
set -euo pipefail
cd "$(dirname "$0")/.."

BUILD=walleye-rp1a.201005.004.a1
WANT_BOOTLOADER=mw8998-003.0085.00
WANT_BASEBAND=g8998-00034-2006052136
STEPS=5

say()  { printf '\n\033[1m== Step %s of %s: %s\033[0m\n' "$1" "$STEPS" "$2"; }
ok()   { printf '\033[32mOK:\033[0m %s\n' "$*"; }
warn() { printf '\033[33mWARN:\033[0m %s\n' "$*"; }
die()  { printf '\033[31mSTOP:\033[0m %s\n' "$*" >&2; exit 1; }
ask()  { local a; read -r -p "$1 [y/N] " a; [ "$a" = y ] || [ "$a" = Y ]; }
pause() { read -r -p "Press Enter when done. " _; }

[ -t 0 ] || die "Run this in a terminal: it asks questions."
for c in adb fastboot; do
    command -v "$c" >/dev/null || die "'$c' not found. Install it: brew install android-platform-tools"
done

# getvar prints to stderr as "name: value".
getvar() { fastboot getvar "$1" 2>&1 | awk -F': ' -v k="$1" '$1==k {print $2; exit}'; }

# Wait until exactly one phone is in fastboot mode.
wait_fastboot() {
    local n
    while :; do
        n=$(fastboot devices | grep -c . || true)
        [ "$n" = 1 ] && return
        [ "$n" -gt 1 ] && die "More than one phone in fastboot mode. Unplug the others."
        if [ "$(adb devices | grep -c 'device$' || true)" = 1 ]; then
            echo "Android is running with USB debugging on: rebooting it into the bootloader."
            adb reboot bootloader
        else
            echo "Waiting for the phone in bootloader mode..."
            echo "  Power it off, then hold Volume Down + Power until the bootloader screen appears."
            echo "  Plug it into this computer with a USB cable."
        fi
        sleep 5
    done
}

check_phone() {
    local product unlocked
    product=$(getvar product)
    [ "$product" = walleye ] || die "This is '$product', not a Pixel 2 (walleye). Nothing was changed."
    ok "Pixel 2 (walleye)"
    unlocked=$(getvar unlocked)
    if [ "$unlocked" != yes ]; then
        warn "The bootloader is locked."
        echo "  1. Boot Android, connect to the internet once, then Settings > About phone: tap Build number 7 times."
        echo "  2. Settings > System > Developer options: turn on OEM unlocking."
        echo "     (Greyed out = carrier-locked phone, e.g. Verizon. Those can't be unlocked.)"
        echo "  3. Return to the bootloader (Volume Down + Power) and run this script again."
        echo "  Or, if OEM unlocking is already on: unlock now. This erases the phone."
        if ask "Run 'fastboot flashing unlock' now? Confirm on the phone with the volume keys + Power."; then
            fastboot flashing unlock || true
            echo "The phone erases itself and may reboot. Bring it back to the bootloader."
            pause; wait_fastboot
            [ "$(getvar unlocked)" = yes ] || die "Still locked. Nothing else was changed."
        else
            die "Bootloader locked. Nothing was changed."
        fi
    fi
    ok "bootloader unlocked"
}

# ---------------------------------------------------------------------------
if [ "${1:-}" = restore ]; then
    STEPS=2
    [ -x "firmware/$BUILD/flash-all.sh" ] || scripts/get-firmware.sh
    say 1 "Find the phone"
    wait_fastboot; check_phone
    say 2 "Restore stock Android 11 ($BUILD)"
    echo "This flashes Google's factory image and ERASES everything on the phone, including Ubuntu."
    read -r -p 'Type "yes" to continue: ' a
    [ "$a" = yes ] || die "Not confirmed. Nothing was changed."
    (cd "firmware/$BUILD" && ./flash-all.sh)
    ok "Stock Android flashed. The phone boots Android; to lock the bootloader again: fastboot flashing lock."
    exit 0
fi

for f in build/boot.img build/rootfs.simg; do
    [ -f "$f" ] || die "Missing $f. Run scripts/build-all.sh first."
done
[ -f firmware/vbmeta.img ] || scripts/get-firmware.sh

say 1 "Find the phone"
wait_fastboot
check_phone

say 2 "Check the phone's firmware"
bl=$(getvar version-bootloader); bb=$(getvar version-baseband)
if [ "$bl" = "$WANT_BOOTLOADER" ] && [ "$bb" = "$WANT_BASEBAND" ]; then
    ok "final Android 11 firmware (bootloader $bl, radio $bb)"
else
    warn "Bootloader '$bl' / radio '$bb' are not the final versions ($WANT_BOOTLOADER / $WANT_BASEBAND)."
    echo "  Ubuntu was only tested on the final firmware. Flashing Google's factory image fixes this"
    echo "  (it erases the phone and boots Android once; come back to the bootloader afterwards)."
    if ask "Flash the factory image now?"; then
        [ -x "firmware/$BUILD/flash-all.sh" ] || scripts/get-firmware.sh
        (cd "firmware/$BUILD" && ./flash-all.sh)
        echo "Let Android start, then power off and hold Volume Down + Power for the bootloader."
        pause; wait_fastboot
    else
        warn "Going on with the current firmware."
    fi
fi

say 3 "Confirm"
echo "About to write:"
echo "  vbmeta_a, vbmeta_b  firmware/vbmeta.img with verification turned off"
echo "  boot_a, boot_b      build/boot.img (kernel + initramfs)"
echo "  userdata            build/rootfs.simg (Ubuntu 24.04)"
printf '\033[31mThis ERASES all data on the phone (userdata).\033[0m Android stays installed but won'"'"'t start.\n'
echo "Undo later with: scripts/flash.sh restore"
read -r -p 'Type "yes" to flash: ' a
[ "$a" = yes ] || die "Not confirmed. Nothing was changed."

say 4 "Flash"
fastboot --disable-verity --disable-verification flash vbmeta_a firmware/vbmeta.img
fastboot --disable-verity --disable-verification flash vbmeta_b firmware/vbmeta.img
fastboot flash boot_a build/boot.img
fastboot flash boot_b build/boot.img
# Reset the retry counter of the active slot (an earlier failed boot may have
# marked it unbootable); Ubuntu marks it successful once it's up (qbootctl).
slot=$(getvar current-slot)
[ -n "$slot" ] && fastboot set_active "$slot"
# userdata last: after this write the bootloader stops answering on USB.
fastboot flash userdata build/rootfs.simg || true
ok "written"
echo
echo "On the phone: if the bootloader screen still shows, press Volume Up/Down until it says START,"
echo "then press Power. (The bootloader often stops answering on USB after this write; that's normal.)"

say 5 "Wait for Ubuntu"
echo "Waiting up to 10 min for SSH (USB 172.16.42.1 or wifi pixel2.local)..."
KEY=build/ssh/pixel2_ed25519
up=""
for _ in $(seq 120); do
    for h in 172.16.42.1 pixel2.local; do
        if nc -z -G 2 "$h" 22 >/dev/null 2>&1; then up=$h; break 2; fi
    done
    sleep 5
done
if [ -z "$up" ]; then
    warn "No SSH after 10 min."
    echo "  USB: the Mac sometimes creates no network interface; unplug and replug the cable."
    echo "  Serial console: scripts/serial-sh.py. Notes: docs/log.md."
    exit 1
fi
ok "Ubuntu is up at $up"
echo "  Log in: ssh -i $KEY ubuntu@$up   (or scripts/ssh.sh)"
ask "Is the green LED pulsing slowly?" && ok "status LED" || warn "LED: see PLAN.md P8.4"
ask "Is the screen dark, and does touching it show a text console?" && ok "screen" || warn "screen: see PLAN.md P8.1"
echo "Done."
