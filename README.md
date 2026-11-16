# Ubuntu 24.04 on the Google Pixel 2

Goal: the Pixel 2 (walleye) boots straight into plain, headless Ubuntu 24.04 arm64, reachable over SSH. It is meant as a dedicated device.

- **Continue the work:** open [`PLAN.md`](PLAN.md) and do the step under **▶ RESUME HERE**.
- **Why this approach:** see [`docs/research.md`](docs/research.md). Ubuntu Touch only supports 16.04 on this phone, so this is a custom port.
- **What happened so far:** see [`docs/log.md`](docs/log.md).
- **Restore stock Android:** power off, hold Vol-Down + Power for bootloader mode, then run `flash-all.sh` from Google's factory image (https://developers.google.com/android/images#walleye).

**Location:** the repo lives on the case-sensitive APFS volume `/Volumes/Pixel2Dev` (the Linux kernel needs case-sensitive filenames); `~/github/ubuntu-touch-pixel2` is a symlink to it.

Proprietary firmware and build outputs live in `firmware/` and `build/`. Both are gitignored and never committed.
