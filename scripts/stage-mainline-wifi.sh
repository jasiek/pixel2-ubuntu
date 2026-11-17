#!/usr/bin/env bash
# Dev helper (P8.3 wifi): put the mainline wifi/modem pieces on the running
# phone (downstream Ubuntu is fine; nothing here runs on kernel 4.4).
#
#   PIXEL2_HOST=<ip> scripts/stage-mainline-wifi.sh
#
# Firmware is built on the phone from its own partitions (never committed):
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

STAGE=$(mktemp -d); trap 'rm -rf "$STAGE"' EXIT
cp build/modem-tools/pil-squasher build/modem-tools/diag-router $FW/board-2.bin $FW/firmware-5.bin "$STAGE/"
COPYFILE_DISABLE=1 tar --no-xattrs -cf - -C "$STAGE" . | scripts/ssh.sh 'sudo sh -euc "
T=\$(mktemp -d); tar -C \$T -xf -
W=/lib/firmware/qcom/msm8998/wahoo; A=/lib/firmware/ath10k/WCN3990/hw1.0
install -d \$W \$A
install -m 644 /firmware/image/mba.mbn /firmware/image/modemr.jsn \$W/
install -m 644 /vendor/firmware/modemuw.jsn /vendor/firmware/wlanmdsp.mbn \$W/
\$T/pil-squasher \$W/modem.mbn /firmware/image/modem.mdt
\$T/pil-squasher \$W/ipa_fws.mbn /vendor/firmware/ipa_fws.mdt
chmod 644 \$W/*.mbn
install -m 644 \$T/board-2.bin \$T/firmware-5.bin \$A/
install -m 755 \$T/diag-router /usr/local/sbin/diag-router
rm -rf \$T
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq rmtfs tqftpserv qrtr-tools >/dev/null
systemctl daemon-reload
systemctl enable -q diag-router.service rmtfs.service tqftpserv.service
ls -la \$W \$A
"'
