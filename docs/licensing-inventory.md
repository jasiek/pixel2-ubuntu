# Licensing inventory (P10.1)

Status: inventory only, 2026-11-18. **Nothing is relicensed by this file.**
The headers and the `LICENSE` / `LICENSING.md` files come in P10.2–P10.3.
Classes and policy are the table in `PLAN.md` Phase 10.

How this was made:
- Every tracked file outside `external/` was scanned for SPDX lines,
  copyright lines and provenance words ("ported", "adapted", "copied",
  "derived", "based on", "Porthole", "libcamera", "vendor").
- Each hit was then read by hand.
- "Original" means written in this repo. Any outside code it contains is named
  in the Borrowed column.

## 1. Original material: planned MIT

None of these files has a license header today.

| Files | Borrowed / notes |
|---|---|
| `scripts/*.sh`, `scripts/*.py` (24) | None found. They invoke upstream tools; they don't copy them. `make-bootimg.sh` calls AOSP mkbootimg (Apache-2.0) as a separate program. |
| `docker/Dockerfile`, `docker/libcamera/Dockerfile`, `docker/mainline/Dockerfile`, `rootfs/Dockerfile` | Package lists and build steps only. |
| `initramfs/init`, `initramfs/probe-init`, `initramfs/probe-loop-init`, `initramfs/reboot-bootloader.c` | None found. BusyBox, bundled at build time, keeps GPL-2.0 (an image matter: P10.5). |
| `rootfs/overlay/usr/local/sbin/*`, `rootfs/overlay/usr/local/bin/*`, `rootfs/overlay/usr/local/lib/pixel2/apex-payload-offset.pl` | `pixel2-camera-tuning` re-implements the OTP lens-shading layout and reciprocal step that Porthole's `otp-to-lsc.py` uses. That's a data format and formula, written independently; no Porthole code in the file. `pixel2-audio` sets mixer values taken from Porthole's taimen UCM `HiFi.conf` (control names and values: facts, not expression). |
| `rootfs/overlay/etc/**` (systemd units and drop-ins, udev rules, NetworkManager, sshd, sudoers, fstab, modprobe, `android/props.conf`) | Settings only. `props.conf` lists Android property names and values the vendor daemons read: facts. |
| `android/stubs/peripheral_client.c` | Stub with the same function names, enum and return codes as CAF's libperipheralclient (an API, not code). No CAF code copied. |
| `tools/fbtest.c`, `tools/mod-bisect.sh` | None found. |
| `tools/pixel2-screen.c` | The renderer is original. **But** `scripts/build-screen.sh` embeds the 8×16 font from the kernel at build time; see §4. |
| `kernel/walleye-ubuntu.config`, `kernel/walleye-ubuntu-vt.config`, `kernel/debug-minimal.config`, `kernel/mainline/ubuntu.config` | Config fragments (option = value), applied on top of `wahoo_defconfig` / Porthole's config. Not copies of those files. |
| `README.md`, `PLAN.md`, `CLAUDE.md`, `docs/*.md` | Prose. `docs/camera-walleye.md` quotes short DT fragments from the vendor taimen DT (GPL-2.0, marked "copied from TDTS") as design notes; keep them marked as GPL-2.0 excerpts. |
| `.gitignore`, `.gitmodules` | Trivial configuration. |

## 2. Kernel material: GPL-2.0-only (keep)

| Files | Provenance |
|---|---|
| `kernel/mainline/msm8998-google-walleye-ubuntu.dts` | SPDX GPL-2.0-only already. Includes Porthole's `msm8998-google-walleye.dts` (GPL-2.0-only). Values copied from the vendor taimen/walleye DTs (GPL-2.0, Google/HTC/LG/Qualcomm) are marked in comments. |
| `kernel/mainline/walleye-audio.dtsi` | SPDX GPL-2.0-only already. Adapted from Porthole patch 0084 (Giuseppe Maggio, GPL-2.0-only taimen DT); credited in its header. |
| `kernel/mainline/wahoo-dtbo-sink.dtsi` | SPDX GPL-2.0-only already. Original; names the vendor DTBO's labels. |
| `kernel/mainline/patches/0001-qcom_smbx-charge-behaviour.patch` | Modifies a GPL-2.0 driver. The init sequence is described as "derived from vendor downstream driver" (GPL-2.0). |
| `kernel/mainline/patches/0002-drm-panel-samsung-s6e3fa5.patch` | New driver with SPDX GPL-2.0-only. Structure follows the linux-mdss-dsi-panel-driver-generator drivers in mainline (e.g. `panel-samsung-s6e3fa7.c`, GPL-2.0-only); command sequences from the vendor panel DT. |
| `kernel/mainline/patches/0003-iommu-arm-smmu-qcom-identity-for-msm8998-mdss.patch` | Modifies a GPL-2.0 file. |
| `kernel/mainline/patches/0004-imx362-ois-switched-rails.patch` | Modifies Porthole's `imx362.c` and `lc898123f40.c` (both SPDX GPL-2.0). |
| `kernel/patches/0001-initramfs-ignore-skip_initramfs.patch`, `kernel/debug/irqdbg.patch` | Modify GPL-2.0 files in the downstream 4.4 kernel. |

Note: the patch files carry `From: pixel2 ubuntu port` and no
`Signed-off-by`. Needed only if they go upstream.

## 3. Camera data and helpers

| File | Status | Notes |
|---|---|---|
| `camera/tuning/imx179.yaml` | SPDX CC0-1.0 (kept from upstream) | Base: Porthole's `temp/libcamera/imx179.yaml` (CC0-1.0). Our change is the Awb block: numbers extracted from walleye's vendor chromatix library (measurements/facts) plus our comments. Keep CC0-1.0 for the file. Note that the AWB numbers come from a proprietary library; extracting facts doesn't make the library redistributable. |
| `tools/chromatix-awb-points.py` | MIT for our code + **BSD-2-Clause notice needed** | `cct()` copies the RGB→XYZ matrix and McCamy coefficients of libcamera `src/ipa/libipa/colours.cpp` (`estimateCCT`, BSD-2-Clause, © 2024 Ideas on Board Oy). That part needs their copyright + BSD-2-Clause text (P10.4). Also in `docs/log.md` / yaml comments by reference only (fine). |

## 4. Open provenance questions (owner / P10.4)

1. **Screen font.** `lib/fonts/font_8x16.c` from `external/kernel-msm` says
   "generated by cpi2fnt" (from a DOS code-page font) and has no license line
   in the 4.4 tree. Mainline marks the same file GPL-2.0. Until resolved,
   treat `pixel2-screen` (the binary) as GPL-2.0-covered. Options:
   - keep it, and ship the screen source and build script with any binary;
   - swap in a font with clear permissive terms (Terminus is OFL-1.1;
     Spleen is BSD-2-Clause). The fbcon console already uses Terminus 16×32
     from the kernel.
2. **Factory-image material** (`firmware/`, everything `pixel2-modem-fw`
   builds): Google's factory-image terms apply. These files aren't tracked
   and must stay out of any published image unless redistribution is
   verified (P10.5).

## 5. Submodules (upstream licenses, no relicensing)

| Path | Revision | Upstream | License |
|---|---|---|---|
| `external/linux-mainline` | `52c36105f76e` (v7.2.2) | kernel.org stable | GPL-2.0-only (with the syscall note) |
| `external/kernel-msm` | `52750b8f2138` | android.googlesource.com kernel/msm | GPL-2.0 |
| `external/porthole-pmaports` | `0d62af2af5e7` | github.com/porthole-dev/pmaports | GPL-3.0 by default, per-file overrides (kernel patches GPL-2.0, `imx179.yaml` CC0-1.0) |
| `external/libcamera` | `191e202178f0` | gitlab.freedesktop.org/camera/libcamera | LGPL-2.1-or-later core; GPL-2.0, BSD-2-Clause, CC0-1.0 parts |
| `external/mkbootimg` | `d2bb0af5ba6d` | AOSP system/tools/mkbootimg | Apache-2.0 |
| `external/qbootctl` | `39a6e6daaf02` | github.com/linux-msm/qbootctl | GPL-3.0 (LICENSE); `crc32.c` GPL-2 |
| `external/pil-squasher` | `3c9f8b8756ba` | github.com/linux-msm/pil-squasher | BSD-3-Clause |
| `external/qcom-diag` | `23c12c167e93` | github.com/linux-msm/diag | BSD-3-Clause (Linaro) |
| `external/qca-swiss-army-knife` | `6df4dae3e2f5` | github.com/qca/qca-swiss-army-knife | ISC |

## 6. What ends up in built images (for P10.5)

Not part of the tracked-file gate, but recorded here so it isn't forgotten:
- **`boot*.img`:** the Linux kernel (GPL-2.0) and the initramfs (BusyBox, GPL-2.0).
- **rootfs:**
  - Ubuntu packages, under their own licenses;
  - `qbootctl` (GPL-3.0);
  - `diag-router` (BSD-3-Clause);
  - `pil-squasher` (BSD-3-Clause);
  - libcamera (LGPL/GPL parts);
  - `pixel2-screen` (font question above);
  - the ath10k board data extracted from the factory `vendor.img` (Google
    terms).
- **Firmware built on the phone** is never in the image, so it isn't
  distributed.
