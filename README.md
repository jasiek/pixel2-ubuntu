# Ubuntu 24.04 on the Google Pixel 2

The Pixel 2 (walleye) boots straight into plain, headless Ubuntu 24.04 arm64, reachable over SSH (USB and wifi). It is meant as a dedicated device.

What works: SSH over USB (172.16.42.1) and wifi (`pixel2.local`), the modem firmware, a charge limit (70–80 %), a green status LED that pulses while the phone runs, and a text console on the screen (tap to wake; dark after 5 min).

## Install

You need: an Apple Silicon Mac with Docker running, `adb` + `fastboot` (`brew install android-platform-tools`), a **case-sensitive** volume for the clone (the kernel needs one; Disk Utility → APFS (Case-sensitive)), and a Pixel 2 whose bootloader can be unlocked (not Verizon).

1. Build: `scripts/build-all.sh`. It fetches the sources and Google's factory image (1.7 GB, SHA-256 checked), asks once for wifi details, and builds `build/boot.img` + `build/rootfs.simg`. The first run takes the longest (the kernel); later runs rebuild only what changed.
2. Flash: `scripts/flash.sh`. It walks you through it step by step and checks the phone before each step. It **erases the phone** and asks for `yes` first.
3. Log in: `scripts/ssh.sh` (over USB; `PIXEL2_HOST=pixel2.local scripts/ssh.sh` over wifi). Your `~/.ssh/*.pub` keys are installed for the user `ubuntu`.

**Back to stock Android:** `scripts/flash.sh restore` (runs Google's `flash-all.sh`; erases the phone).

## Background

- **How it got here:** [`PLAN.md`](PLAN.md) is the checklist (open work under **▶ RESUME HERE**); [`docs/log.md`](docs/log.md) is the dated notebook.
- **Why this approach:** [`docs/research.md`](docs/research.md). Ubuntu Touch only supports 16.04 on this phone, so this is a custom port: Google's msm-4.4 kernel, our own initramfs, Ubuntu 24.04 on the userdata partition.
- **Location:** the main working copy lives on the case-sensitive APFS volume `/Volumes/Pixel2Dev`; `~/github/ubuntu-touch-pixel2` is a symlink to it.

Proprietary firmware and build outputs live in `firmware/` and `build/`. Both are gitignored and never committed.
