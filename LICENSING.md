# Licensing

**Default:** original material in this repository is under the MIT License
(`LICENSE`). That covers the scripts, build recipes, initramfs and runtime
helpers, service and configuration files, the independent C tools, and the
documentation, except where a file or the table below says otherwise.

The MIT license does **not** cover:
- third-party code in `external/`;
- vendor firmware;
- the images this repo builds.

A file's own `SPDX-License-Identifier` line, where present, wins over this
default. The per-file record, with provenance, is
`docs/licensing-inventory.md`.

## Exceptions

| What | License | Why |
|---|---|---|
| Kernel patches (`kernel/patches/`, `kernel/debug/`, `kernel/mainline/patches/`) and device trees (`kernel/mainline/*.dts`, `*.dtsi`) | GPL-2.0-only (`LICENSES/GPL-2.0-only.txt`) | They modify or extend the Linux kernel, Porthole's drivers and vendor device trees, which are GPL-2.0. |
| `camera/tuning/imx179.yaml` | CC0-1.0 (`LICENSES/CC0-1.0.txt`) | Based on Porthole's CC0-1.0 tuning file. |
| The `cct()` function in `tools/chromatix-awb-points.py` | BSD-2-Clause (`LICENSES/BSD-2-Clause.txt`), Copyright (C) 2024 Ideas on Board Oy | Follows libcamera's `estimateCCT()` (`src/ipa/libipa/colours.cpp`). The rest of the file is MIT. |
| `pixel2-screen` as built (`tools/pixel2-screen.c` + the font `scripts/build-screen.sh` extracts) | Renderer source MIT; **the built program is treated as GPL-2.0** | The 8×16 font comes from the Linux kernel (`lib/fonts/font_8x16.c`), whose own terms are unclear. Owner decision (2026-11-18): keep this font. Give the corresponding source (`tools/pixel2-screen.c`, `scripts/build-screen.sh`, the kernel font at the pinned `external/kernel-msm` revision) with any binary. |
| `external/*` (git submodules) | Their own licenses | Linux GPL-2.0; AOSP mkbootimg Apache-2.0; qbootctl GPL-3.0; pil-squasher and qcom-diag BSD-3-Clause; qca-swiss-army-knife ISC; pmaports GPL-3.0 with per-file exceptions; libcamera LGPL-2.1-or-later (plus GPL, BSD and CC0 parts). Revisions are in `docs/licensing-inventory.md`. |

## Firmware and vendor files

Nothing proprietary is in this repository:
- `firmware/` and `build/` are git-ignored.
- `get-firmware.sh` downloads Google's factory image from Google, under
  Google's terms.
- The phone builds its own modem, wifi, audio-DSP and GPU firmware at boot
  from its own partitions (`pixel2-modem-fw`).

Converting a blob (for example squashing it with pil-squasher) doesn't
change its license or grant any right to redistribute it.

## Built images

`build/boot*.img` and `build/rootfs.simg` combine many licenses. They contain:
- the Linux kernel and BusyBox (GPL-2.0);
- Ubuntu packages, under their own licenses;
- qbootctl (GPL-3.0);
- libcamera (LGPL/GPL parts);
- `pixel2-screen` (see above);
- wifi board data taken from Google's factory `vendor.img`.

They are not MIT, and their redistribution conditions (source for
GPL/LGPL parts, firmware terms) are tracked in `PLAN.md` P10.5. Images
aren't published today.
