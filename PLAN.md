# Pixel 2 → Ubuntu 24.04 (headless): Plan

**Goal:** the Pixel 2 (walleye) powers on straight into Ubuntu 24.04 arm64, reachable over SSH. No Android at runtime.

## ▶ RESUME HERE: P8.4 (status LED: "phone is on" indicator). Also open: pick the phone's job

---

## How to use this file
1. Find **RESUME HERE** above and do that step.
2. Tick its box (`- [ ]` → `- [x]`) and move the RESUME HERE pointer to the next step.
3. Commit right away: `git commit -am "plan: tick P1.4"`.
4. Something went wrong or you made a decision? Add a dated line to `docs/log.md` and commit.
5. A **Gate** is a check that must pass before moving on. If it fails, stop and log it.

Background and sources: `docs/research.md`. Phone details: `docs/device-info.md` (created in P1.2).

**Get back to stock Android anytime:** bootloader mode (power off, hold **Vol-Down + Power**) → run `flash-all.sh` from the factory image.

---

## Phase 0: Repo setup (15 min)
- [x] **P0.1** `.gitignore` (build outputs + proprietary firmware never committed)
- [x] **P0.2** `docs/research.md`
- [x] **P0.3** `PLAN.md` (this file)
- [x] **P0.4** `README.md`
- [x] **P0.5** `docs/log.md`

## Phase 1: Phone prep (1 h, needs the phone, ⚠️ wipes it)
- [x] **P1.1** Back up anything you want from the phone (photos, 2FA apps, etc.). Everything is erased in P1.4.
- [x] **P1.2** Settings → About phone: write the Android version, build number and storage size into `docs/device-info.md`.
- [x] **P1.3** Tap *Build number* 7× to unlock Developer options. In Developer options, turn on **OEM unlocking** and **USB debugging**.
  - Gate: the OEM unlocking toggle is *not* greyed out. If greyed out: connect to wifi, factory reset, set up online, retry.
- [x] **P1.4** Unlock the bootloader:
  ```sh
  adb reboot bootloader
  fastboot flashing unlock           # confirm on phone with volume keys + power
  fastboot flashing unlock_critical  # confirm again; needed to flash the bootloader
  fastboot getvar unlocked
  ```
  - Gate: output says `unlocked: yes`.
- [x] **P1.5** _Skipped (2026-11-16): phone already on final build `RP1A.201005.004.A1`, bootloader `mw8998-003.0085.00`, radio `g8998-00034-2006052136`. Still download the zip for P1.7._ Download the final Android 11 factory image for walleye from https://developers.google.com/android/images#walleye (expected `RP1A.201005.004.A1`; take the newest listed). Unzip it into `firmware/` and run its `flash-all.sh` with the phone in bootloader mode.
  - Gate: phone boots Android 11.
- [x] **P1.6** In bootloader mode, record partition info into `docs/device-info.md` (delete the serial number line before committing):
  ```sh
  fastboot getvar all 2>&1 | tee firmware/getvar-all.txt
  ```
  - Note: current slot, and the sizes of boot, userdata, vendor and modem.
- [x] **P1.7** From the factory zip's inner `image-walleye-*.zip`, extract `boot.img`, `vendor.img`, `vbmeta.img` and `dtbo.img` into `firmware/`. Also keep `radio-walleye-*.img` there.
- [x] **P1.8** Test tethered boot: `fastboot boot firmware/boot.img`.
  - Gate: Android boots. This proves we can test kernels without flashing.

## Phase 2: Build environment on the Mac (1 h)
- [x] **P2.1** Write `docker/Dockerfile`: Ubuntu 20.04 **arm64** with build-essential, bc, bison, flex, libssl-dev, lz4, git, python3, cpio, android-sdk-libsparse-utils (`img2simg`), and mkbootimg tools.
- [x] **P2.2** Write `scripts/dev.sh`: runs a command inside the container with the repo mounted at `/work`.
  - Gate: `scripts/dev.sh uname -m` prints `aarch64`.
- [x] **P2.3** _Done: submodule `external/kernel-msm`, branch `android-msm-wahoo-4.4-android11` @ `52750b8f2138` (= stock kernel). Fresh clone: `git submodule update --init --depth 1`._ Clone the kernel from `https://android.googlesource.com/kernel/msm`. Use the newest `android-msm-wahoo-4.4-*` branch for Android 11 (list with `git ls-remote --heads`).
  - Record branch + commit hash in `docs/log.md`.
- [x] **P2.4** Unpack `firmware/boot.img` with `unpack_bootimg`. Record header version, kernel cmdline, base address, page size and offsets in `docs/device-info.md`.

## Phase 3: Kernel (2–6 h)
- [x] **P3.1** Build stock `wahoo_defconfig` with clang 11 (`make CC=clang LD=ld.lld`, matching the stock toolchain) → `Image.lz4-dtb`. Script it as `scripts/build-kernel.sh`.
  - Gate: it compiles. If the compiler is too new, try GCC 7/8 or Google's prebuilt toolchain; log it.
- [x] **P3.2** Repack our kernel with the **stock** ramdisk into `build/boot-stockramdisk.img`, then `fastboot boot` it.
  - Gate: Android boots. Proves our kernel build works on the phone.
- [x] **P3.3** Write `kernel/walleye-ubuntu.config` (config fragment). Cross-check against Flohack74's Halium tree (github.com/Flohack74/android_device_google_wahoo).
  - systemd: `DEVTMPFS`, `DEVTMPFS_MOUNT`, `CGROUPS` + controllers, `FHANDLE`, `AUTOFS4_FS`, `NAMESPACES` (UTS/IPC/PID/NET/USER), `SECCOMP`, `TMPFS_POSIX_ACL`, `TMPFS_XATTR`, `INOTIFY_USER`, `SIGNALFD`, `TIMERFD`, `EPOLL`
  - USB gadget networking: `USB_CONFIGFS_ECM`, `USB_CONFIGFS_NCM`
  - `# CONFIG_ANDROID_PARANOID_NETWORK is not set` (otherwise only special Android groups get network access)
  - SELinux off (`selinux=0` on cmdline or disable in config)
  - **Ignore `skip_initramfs`** (patch `init/initramfs.c`): the bootloader adds it on normal boots, and it would bypass our initramfs. Found in P2.4.
  - Already set in `wahoo_defconfig`: `USB_CONFIGFS_NCM=y` (macOS supports NCM), `BUILD_ARM64_APPENDED_DTB_IMAGE=y`. Missing: `DEVTMPFS`, `FHANDLE`.
- [x] **P3.4** Rebuild with the fragment merged.
  - Gate: it compiles.

## Phase 4: Initramfs + rootfs (2–4 h)
- [x] **P4.1** Write `scripts/build-rootfs.sh`, which runs inside the arm64 container:
  - Start from `ubuntu-base-24.04.x-base-arm64.tar.gz`.
  - Install systemd, systemd-sysv, udev, openssh-server, sudo, network-manager, iproute2, e2fsprogs, avahi-daemon, nano, less.
  - Set hostname `pixel2`, create user `ubuntu`, and install your SSH public key.
  - Add a systemd unit that brings up the USB-ECM gadget at `172.16.42.1/24`.
  - Install our kernel modules (`make modules_install`) into `/lib/modules/<ver>/`: wifi (`wlan.ko`), battery (`htc_battery.ko`) and touchscreen are modules. Google's prebuilt ones in `/vendor` won't load into our kernel (found in P3.2).
- [x] **P4.2** Pack into a 4 GB ext4 `build/rootfs.img`, then `img2simg` → `build/rootfs.simg`.
- [x] **P4.3** Write `scripts/build-initramfs.sh`: a static-busybox `/init` that:
  - mounts proc, sys and dev;
  - starts the USB-ECM gadget;
  - mounts the userdata partition and runs `resize2fs` once to fill it;
  - runs `switch_root` → `/sbin/init`.
  - On failure: start `telnetd` on `172.16.42.1` and keep running, so we can log in and debug.
- [x] **P4.4** Write `scripts/make-bootimg.sh`: kernel + initramfs + cmdline/offsets from P2.4 → `build/boot.img`.

## Phase 5: First boot, tethered (1–3 h; most debugging lands here)
- [x] **P5.0** Pre-flash bisect: the full config kernel resets or hangs; the minimal one (`kernel/debug-minimal.config`) reaches the initramfs shell. Find the bad option(s):
  ```sh
  scripts/try-boot.sh build/boot-min-debug.img   # baseline, expect UP
  scripts/try-boot.sh build/boot-B-debug.img     # +no-paranoid-net, selinux bootparam, ECM (hung once)
  scripts/try-boot.sh build/boot-A-debug.img     # +systemd/cgroup/namespace options
  ```
  - Already known: VT + VT_CONSOLE + FRAMEBUFFER_CONSOLE together reset the phone; drop them from `kernel/walleye-ubuntu.config`.
  - Result: VT/fbcon was the only culprit (B2's 'hang' was a test bug: no DEVTMPFS). Full kernel without VT boots to the debug shell.
  - Debug images now turn hangs into panics (auto-reboot) and return to fastboot after 10 min, so unattended runs can't get stuck again.
  - When the shell is up: `scripts/initrd-sh.py '<cmd>'` (telnet) or `scripts/serial-sh.py '<cmd>'` (USB serial).
- [x] **P5.1** ⚠️ Overwrites Android's data partition: `fastboot flash userdata build/rootfs.simg`
- [x] **P5.2** `fastboot boot build/boot.img`
- [x] **P5.3** On the Mac, a new USB network interface appears (check `ifconfig`). Give it `172.16.42.2/24`, then `ssh ubuntu@172.16.42.1`.
  - Gate: you get a shell. 🎉 **Milestone 1: Ubuntu 24.04 is running on the Pixel 2.**
- [x] **P5.4** If P5.3 failed:
  - Try `telnet 172.16.42.1` (initramfs debug shell).
  - No network at all? Check `/sys/fs/pstore` on the next boot.
  - systemd refuses kernel 4.4? Switch to Ubuntu 22.04 and log the decision.
- [x] **P5.5** Save `uname -a`, `systemctl --failed` and notable `dmesg` errors in `docs/log.md`.

## Phase 6: Wifi (2 h to 2 days)
- [x] **P6.1** Mount `vendor_a` → `/vendor` and the modem partition → `/firmware`, both read-only, via systemd mount units. The kernel loads wifi firmware from there.
- [x] **P6.2** Check `ip link`.
  - Gate: `wlan0` exists.
- [x] **P6.3** No `wlan0`? Read `dmesg` for cnss / qrtr / rmt_storage / pd-mapper errors. Try the Linux packages `qrtr-tools`, `rmtfs`, `pd-mapper`.
- [x] **P6.4** ~~Skipped: not needed.~~ The vendor daemons run directly on Ubuntu (no container), see docs/log.md. Still nothing? Fall back to running Android vendor services in an LXC container (the Halium approach). Log the decision.
- [x] **P6.R** _Done 2026-11-17: reflashed userdata, booted, SSH + wifi scan (13 networks) work with no manual steps. Step 2 skipped: reflashed directly._ Recover after the fallback to Android (2026-11-17):
  1. On the phone: hold **Power + Volume Down** until the bootloader screen appears.
  2. `scripts/try-boot.sh build/boot-debug.img`, then `scripts/initrd-sh.py 'dd if=/dev/sda45 bs=1024 skip=1 count=1 | hexdump -C | head -12'`. Check whether Android reformatted userdata (label at 0x478: `ubuntu` = intact).
  3. `scripts/initrd-sh.py reboot-bootloader`, then `fastboot flash userdata build/rootfs.simg`. The rebuilt image already contains all the wifi work.
  4. `scripts/try-boot.sh build/boot.img 180`. If there's no USB network, use `scripts/serial-sh.py`.
  5. Find out why the last `boot.img` boot never brought up USB serial; pstore was lost to the Android boot.
  6. Then do Phase 7 soon: with our boot.img flashed, a failed boot can't drop into Android and wipe userdata again.
- [x] **P6.5** _Done 2026-11-17: profile `home`, autoconnect on; SSH over wifi + pixel2.local work._ Connect: `sudo nmcli dev wifi connect "<SSID>" password "<pw>"`.
  - Gate: `ssh ubuntu@pixel2.local` works with the USB cable unplugged.

## Phase 7: Make it permanent (1 h)
- [x] **P7.1** _Done 2026-11-17 on vbmeta_a + vbmeta_b._ `fastboot --disable-verity --disable-verification flash vbmeta firmware/vbmeta.img`
- [x] **P7.2** _Done 2026-11-17; Start in the bootloader now boots Ubuntu (SSH in ~15 s)._ `fastboot flash boot_a build/boot.img && fastboot flash boot_b build/boot.img`
- [x] **P7.3** _Done 2026-11-17: cable unplugged, power button → SSH over wifi (pixel2.local) within ~60 s of power-on, slot marked successful, NTP synced._ Power off, then press the power button.
  - Gate: SSH over wifi works without the Mac. 🎉 **Milestone 2: the phone boots into Linux.**
- [x] **P7.4** _Done 2026-11-17 (pixel2-headless, pixel2-charge-limit 70–80%, unattended-upgrades). Charge limit still to verify on a charger._ Headless tuning:
  - Turn the screen backlight off.
  - Enable `unattended-upgrades`.
  - Check charging under `/sys/class/power_supply/`. If it lives on a charger 24/7, look for a charge limit (battery swelling risk).
- [x] **P7.5** _Done 2026-11-17: 5/5 reboots over wifi, SSH after ~34 s each, slot stays successful, backlight 0._ Reboot 5 times.
  - Gate: SSH works after every reboot.

## Phase 8: Optional stretch (decide later)
- [ ] **P8.4** "Phone is on" indicator with the built-in notification LED (owner request, 2026-11-17; moved first by owner). The screen is off for good (OLED burn-in), so nothing shows the phone is alive.
  - Already seen: `/sys/class/leds/` has `red`, `green`, `blue` (RGB notification LED) next to `lcd-backlight`, torch and vibrator.
  - Investigate: brightness range, `trigger` options (`timer`/`heartbeat` for a slow blink), power cost. Ideas: dim slow blink = running, other colour = no wifi / low battery.
  - Gate: LED shows the state after a cold boot, without a login.
- [ ] **P8.1** Screen: text console on the framebuffer, then a kiosk if the device's job needs a screen.
- [ ] **P8.2** Modem / SMS (ModemManager + qrtr) if needed.
- [ ] **P8.3** Revisit a mainline kernel (msm8998 work done for the Pixel 2 XL).
