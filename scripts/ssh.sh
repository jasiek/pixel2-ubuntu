#!/usr/bin/env bash
# SSH into the phone's Ubuntu over USB (or pass another host via PIXEL2_HOST).
#   scripts/ssh.sh                 # interactive shell
#   scripts/ssh.sh 'uptime'        # run a command
cd "$(dirname "$0")/.."
exec ssh -i build/ssh/pixel2_ed25519 -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -o LogLevel=ERROR \
    "ubuntu@${PIXEL2_HOST:-172.16.42.1}" "$@"
