#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Dev helper (P8.3): put everything the mainline kernel needs on the running
# phone's rootfs (downstream Ubuntu is fine; nothing here runs on kernel 4.4),
# then test with `fastboot boot build/mainline/boot-mainline.img`.
#
#   PIXEL2_HOST=<ip> scripts/stage-mainline.sh
#
# Modules: build/mainline/modules-install (scripts/build-mainline.sh).
#
# Firmware is built on the phone from its own partitions by pixel2-modem-fw
# (same as at boot; never committed):
#   /lib/firmware/qcom/msm8998/wahoo/  mba.mbn, modem.mbn (squashed), modemr.jsn,
#                                      modemuw.jsn, wlanmdsp.mbn, ipa_fws.mbn (squashed)
#   /lib/firmware/ath10k/WCN3990/hw1.0/ board-2.bin (walleye bdwlan.*), firmware-5.bin
# Also: diag-router, Ubuntu's rmtfs/tqftpserv/qrtr-tools, the rootfs overlay
# (mainline-only / 4.4-only unit conditions).
# Inputs: build/modem-tools/ (scripts/build-modem-tools.sh) and
# build/mainline/fw/ath10k/{board-2.bin,firmware-5.bin}.
set -euo pipefail
cd "$(dirname "$0")/.."
FW=build/mainline/fw/ath10k
for f in build/modem-tools/pil-squasher build/modem-tools/diag-router $FW/board-2.bin $FW/firmware-5.bin; do
    [ -f "$f" ] || { echo "missing $f"; exit 1; }
done

scripts/push-overlay.sh
# Drop-ins removed from the overlay since (push-overlay only adds files).
scripts/ssh.sh 'sudo rm -rf /etc/systemd/system/pixel2-charge-limit.service.d /etc/systemd/system/pixel2-status-led.service.d /etc/systemd/system/pixel2-screen.service.d && sudo systemctl daemon-reload'

KREL=$(ls build/mainline/modules-install/lib/modules)
COPYFILE_DISABLE=1 tar --no-xattrs -cf - -C build/mainline/modules-install/lib/modules "$KREL" \
    | scripts/ssh.sh "sudo rm -rf /lib/modules/$KREL && sudo tar -C /lib/modules --no-same-owner -xf - && sudo depmod $KREL && echo modules $KREL installed"

STAGE=$(mktemp -d); trap 'rm -rf "$STAGE"' EXIT
cp build/modem-tools/pil-squasher build/modem-tools/diag-router $FW/board-2.bin $FW/firmware-5.bin "$STAGE/"
COPYFILE_DISABLE=1 tar --no-xattrs -cf - -C "$STAGE" . | scripts/ssh.sh 'sudo sh -euc "
T=\$(mktemp -d); tar -C \$T -xf -
A=/lib/firmware/ath10k/WCN3990/hw1.0
install -d \$A
install -m 644 \$T/board-2.bin \$T/firmware-5.bin \$A/
install -m 755 \$T/diag-router \$T/pil-squasher /usr/local/sbin/
rm -rf \$T
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq rmtfs tqftpserv qrtr-tools >/dev/null
systemctl daemon-reload
systemctl enable -q pixel2-modem-fw.service diag-router.service rmtfs.service tqftpserv.service pixel2-wifi-mac.service pixel2-wifi-mac-record.service
/usr/local/sbin/pixel2-modem-fw
"'
