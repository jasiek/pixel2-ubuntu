# Ubuntu 24.04 on the Google Pixel 2

The Pixel 2 (walleye) boots straight into plain, headless Ubuntu 24.04 arm64, reachable over SSH (USB and wifi). It is meant as a dedicated device.

<human>

#### What works:
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

#### What doesn't work (yet)
- modem
- mouse pointer via LCD touch

#### What hasn't been tested (yet):
- sensors (pressure, accelerometer, etc)
- usb ethernet
- x/wayland

</human>

## Install

You need: an Apple Silicon Mac with Docker running, `adb` + `fastboot` (`brew install android-platform-tools`), a **case-sensitive** volume for the clone (the kernel source has files whose names differ only in case; step 1 makes one), and a Pixel 2 whose bootloader can be unlocked (not Verizon).

1. Create a case-sensitive volume. It's a new APFS volume in your existing disk's container: it shares free space, so nothing needs partitioning or resizing.
   ```sh
   diskutil info / | grep 'APFS Container'   # e.g. "APFS Container: disk3"
   diskutil apfs addVolume disk3 'Case-sensitive APFS' Pixel2Dev   # use your container
   diskutil info /Volumes/Pixel2Dev | grep Personality   # must say "Case-sensitive APFS"
   ```
   It mounts at `/Volumes/Pixel2Dev` and stays mounted across reboots. (GUI: Disk Utility → select the container → **+** → Format "APFS (Case-sensitive)".) A full build needs about 60 GB free.
2. Clone onto it:
   ```sh
   cd /Volumes/Pixel2Dev
   git clone https://github.com/jasiek/pixel2-ubuntu
   cd pixel2-ubuntu
   ```
   No `--recurse-submodules` needed: the build fetches the submodules as shallow clones.
3. Build: `scripts/build-all.sh`. It fetches the sources and Google's factory image (1.7 GB, SHA-256 checked), asks once for wifi details, and builds `build/boot.img` + `build/rootfs.simg`. The first run takes the longest (the kernel); later runs rebuild only what changed.
4. Flash: `scripts/flash.sh`. It walks you through it step by step and checks the phone before each step. It **erases the phone** and asks for `yes` first. The active slot gets the mainline 7.2.2 kernel, the other slot keeps 4.4 as a fallback (`KERNEL=4.4 scripts/flash.sh` for 4.4 on both).
5. Log in: `scripts/ssh.sh` (over USB; `PIXEL2_HOST=pixel2.local scripts/ssh.sh` over wifi). Your `~/.ssh/*.pub` keys are installed for the user `ubuntu`.

**Back to stock Android:** `scripts/flash.sh restore` (runs Google's `flash-all.sh`; erases the phone).

## Background

- **How it got here:** [`PLAN.md`](PLAN.md) is the checklist (open work under **▶ RESUME HERE**); [`docs/log.md`](docs/log.md) is the dated notebook.
- **Why this approach:** [`docs/research.md`](docs/research.md). Ubuntu Touch only supports 16.04 on this phone, so this is a custom port: Ubuntu 24.04 on the userdata partition, our own initramfs, and either mainline Linux 7.2.2 (default; Porthole's msm8998 patches + ours, `kernel/mainline/`) or Google's msm-4.4 kernel.
- **License:** MIT for this repo's own work; kernel patches and device trees are GPL-2.0-only; the details and exceptions are in [`LICENSING.md`](LICENSING.md).

Proprietary firmware and build outputs live in `firmware/` and `build/`. Both are gitignored and never committed.
