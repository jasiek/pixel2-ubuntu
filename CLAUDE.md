# Working on this repo

Pixel 2 (walleye) running plain headless Ubuntu 24.04. Mainline kernel 7.2.2
(Porthole's msm8998 patches + ours) is the default on `boot_b`; the downstream
4.4 kernel stays on `boot_a` as the fallback.

## Where things are

- `PLAN.md`: the checklist. Start at **▶ RESUME HERE**. After a step, tick its
  box and move the pointer.
- `docs/log.md`: dated notes. Every phone test gets a number (`Test 50: ...`):
  what was run, what was measured, what it means.
- `docs/camera-walleye.md`, `docs/research.md`, `docs/device-info.md`:
  subsystem notes.
- `external/`: third-party code as pinned git submodules.
  - `linux-mainline`, `porthole-pmaports` (patches + taimen work), `libcamera`.
  - `kernel-msm` (downstream 4.4; its DTs are the hardware reference).
- `kernel/mainline/`: our DTS (`msm8998-google-walleye-ubuntu.dts`), extra
  `*.dtsi` and `patches/`.
- `rootfs/`: `Dockerfile` (packages, enabled units) + `overlay/` (files
  copied as-is).
- `scripts/`: builds, flashing, phone access.

## Commits

- Commit after every change: each file, each ticked box, each log entry.
- Message style: `P8.6: what changed` or `plan/log: ...`. The body says why.
- End with `Co-Authored-By: Claude ...` only. **Never** include Claude session
  references (no `Claude-Session:` line, no session URLs or IDs).
- Don't push unless asked.
- Third-party software goes in a pinned submodule under `external/`. Never an
  ad-hoc clone or a `git clone` in a Dockerfile.

## Never commit or print

- **The phone's serial number.** It shows up in:
  - `fastboot devices`;
  - `/dev/cu.usbmodem*` names;
  - `androidboot.serialno` in `/proc/cmdline`.

  Grep single keys out of `/proc/cmdline`, never the whole line. Don't list
  `/dev/cu.usbmodem*` broadly.
- Firmware or images: `firmware/` and `build/` are gitignored. Vendor blobs
  never leave the phone. `pixel2-modem-fw` assembles them at boot from the
  phone's own modem/vendor partitions (modem, wifi, ADSP, GPU, TAS2557).
- Wifi credentials (`build/wifi.ssid`, `build/wifi.pass`, mode 600) and the
  wifi MAC (`/var/lib/pixel2/wlan0.mac` on the phone only).

## Phone safety

- **Never boot stock Android**: it formats userdata (our rootfs).
- Confirm with the owner before any `fastboot flash`. Flashing `userdata`
  wipes the phone.
- Test kernels tethered first: `scripts/try-boot.sh <img> 150`
  (`fastboot boot`, nothing flashed; a reboot returns to `boot_b`). Flash
  `boot_b` only after a clean tethered boot. Way back:
  `fastboot flash boot_b build/boot.img` (4.4).
- `reboot bootloader` from Ubuntu occasionally boots Ubuntu again;
  `try-boot.sh` retries 3x. Mainline reboots are cold resets: pstore and IMEM
  don't survive them.
- **OLED burn-in**: never leave a static image lit. After any screen test:
  `echo 1 | sudo tee /sys/class/graphics/fb0/blank`.
- Don't scan an I2C/CCI bus whose devices are unpowered. It proves nothing
  and can wedge the bus.

## Talking to the phone

- `PIXEL2_HOST=172.16.42.1 scripts/ssh.sh '<cmd>'` over USB, or the wifi IP.
  Pipe files in with `cat f | scripts/ssh.sh 'sudo install -m755 /dev/stdin /path'`.
- Kernel lines before journald starts are only in `dmesg` of that boot; the
  journal doesn't keep them. Never `dmesg -C`.
- PMIC registers: `/sys/kernel/debug/regmap/0-00/registers`.
- Python that reads anything copied off the phone runs as `python3 -I`.

## Building

- `scripts/build-all.sh` rebuilds only the steps whose input hash changed.
  When a build step gains a new input directory, add it to that step's
  `hash_of` list. Otherwise changes there never trigger a rebuild.
- A changed patch text forces a full kernel tree recopy;
  `kernel/mainline/*.dtsi` are copied into the tree on every build.
- Check a built rootfs without flashing: run `debugfs` on `build/rootfs.img`
  inside the `pixel2-build` container and compare files with the repo.
- The clone must be on a case-sensitive volume. Builds run in arm64 Docker
  natively.
- The Mac shell is zsh with BSD tools:
  - `sed -i ''`, and `-E` instead of `\|`;
  - quote globs like `--include='*.dts'`;
  - no ffmpeg (Swift/AVFoundation works for media checks).

## How to work

- Carry on until the owner is really needed. Owner actions should be small and
  concrete ("point the back camera at printed text, say go").
- Hardware questions:
  1. Read walleye's downstream DT first (HTC "muskie":
     `external/kernel-msm/arch/arm64/boot/dts/htc/*muskie*`; `lge/*taimen*`
     is the XL).
  2. Which part is fitted is decided by `status = "ok"` vs `"disabled"`
     there.
  3. Then check Porthole's taimen work (same SoC, often the same parts).
- Device tree changes need a reboot. Firmware files and userspace packages
  don't: stage those on the running phone first.
- Measure before claiming, and compare within one boot. Power: A/B on
  `/sys/class/power_supply/pmi8998-charger/current_now` (USB input). Single
  readings swing ±30 mA. When a cause is unproven, say so in the log.
- When something can't be reproduced on demand, make the tooling tolerate it
  (retry) and log the failure pattern, rather than guessing a fix.
- Keep one change per test image (e.g. `boot-gpu.img`, then
  `boot-audio.img`), so a failure points at one thing.
