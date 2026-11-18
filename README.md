# Ubuntu 24.04 on the Google Pixel 2

The Pixel 2 (walleye) boots straight into plain, headless Ubuntu 24.04 arm64, reachable over SSH (USB and wifi). It is meant as a dedicated device.

<human>
What works:
- ssh over USB
- ssh over WiFi
- modem firmware
- charge limit
- pulsating green status led to indicate that it is working
- text console on screen
- screen blanking
- camera
- microphone and speakers
- GPU

What doesn't work (yet)
- modem
- mouse pointer via LCD touch

What hasn't been tested (yet):
- sensors (pressure, accelerometer, etc)
- usb ethernet
- x/wayland
</human>

## Install

You need: an Apple Silicon Mac with Docker running, `adb` + `fastboot` (`brew install android-platform-tools`), a **case-sensitive** volume for the clone (the kernel needs one; Disk Utility → APFS (Case-sensitive)), and a Pixel 2 whose bootloader can be unlocked (not Verizon).

1. Build: `scripts/build-all.sh`. It fetches the sources and Google's factory image (1.7 GB, SHA-256 checked), asks once for wifi details, and builds `build/boot.img` + `build/rootfs.simg`. The first run takes the longest (the kernel); later runs rebuild only what changed.
2. Flash: `scripts/flash.sh`. It walks you through it step by step and checks the phone before each step. It **erases the phone** and asks for `yes` first. The active slot gets the mainline 7.2.2 kernel, the other slot keeps 4.4 as a fallback (`KERNEL=4.4 scripts/flash.sh` for 4.4 on both).
3. Log in: `scripts/ssh.sh` (over USB; `PIXEL2_HOST=pixel2.local scripts/ssh.sh` over wifi). Your `~/.ssh/*.pub` keys are installed for the user `ubuntu`.

**Back to stock Android:** `scripts/flash.sh restore` (runs Google's `flash-all.sh`; erases the phone).

## Background

- **How it got here:** [`PLAN.md`](PLAN.md) is the checklist (open work under **▶ RESUME HERE**); [`docs/log.md`](docs/log.md) is the dated notebook.
- **Why this approach:** [`docs/research.md`](docs/research.md). Ubuntu Touch only supports 16.04 on this phone, so this is a custom port: Ubuntu 24.04 on the userdata partition, our own initramfs, and either mainline Linux 7.2.2 (default; Porthole's msm8998 patches + ours, `kernel/mainline/`) or Google's msm-4.4 kernel.
- **Location:** the main working copy lives on the case-sensitive APFS volume `/Volumes/Pixel2Dev`; `~/github/ubuntu-touch-pixel2` is a symlink to it.

Proprietary firmware and build outputs live in `firmware/` and `build/`. Both are gitignored and never committed.
