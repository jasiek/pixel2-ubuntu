# Pixel 2 → Ubuntu 24.04 (headless): Plan

**Goal:** the Pixel 2 (walleye) powers on straight into Ubuntu 24.04 arm64, reachable over SSH. No Android at runtime.

## ▶ RESUME HERE: P8.5 camera (mainline 7.2.2 is the flashed kernel, boot_b). Waiting: P9.2 gate (someone else flashes a phone). Waiting: P9.2 gate. Also open: pick the phone's job

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
- [x] **P8.4** _Done 2026-11-17: green pulse 3–20 % (never dark) from boot, dark at shutdown; `pixel2-status-led`._ "Phone is on" indicator with the built-in notification LED (owner request, 2026-11-17; moved first by owner). The screen is off for good (OLED burn-in), so nothing shows the phone is alive.
  - Already seen: `/sys/class/leds/` has `red`, `green`, `blue` (RGB notification LED) next to `lcd-backlight`, torch and vibrator.
  - Investigate: brightness range, `trigger` options (`timer`/`heartbeat` for a slow blink), power cost. Ideas: dim slow blink = running, other colour = no wifi / low battery.
  - Gate: LED shows the state after a cold boot, without a login.
- [x] **P8.1** _Done 2026-11-17: owner tap → console (17:22:45 UTC); off 300 s later (log + webcam: dark, LED on)._ Screen: text console on the framebuffer (owner spec 2026-11-17):
  - Text console (fbcon + login on tty1) on the screen, large font.
  - Screen dark after **5 min** without touch; **touching the screen** wakes it and shows the console. Never a static image left lit (OLED burn-in).
  - Pieces: touch = Synaptics `synaptics_dsx_core_htc` module (`synaptics_dsxv26`, event2); kernel VT/fbcon (reset the phone in P5.0 with our own DTB; retest with the factory DTB, variant `kernel/walleye-ubuntu-vt.config`); a small daemon: touch → unblank, idle 5 min → panel off (the pixel2-headless sequence).
  - Gate: cold boot → dark; tap → console visible; 5 min untouched → dark again.
  - **Built (2026-11-17, see log):** `tools/pixel2-screen.c` (C, `scripts/build-screen.sh`) draws into the mmapped fb0 itself (no fbcon: mdss_fb has no fb memory until userspace mmaps). It clears the splash at boot (one black frame, then close = panel off), wakes on touch/volume, shows `pixel2-console` (status header + journal) on a pseudo-terminal through a small terminal emulator, and closes fb0 after `IDLE=300` s. Replaces pixel2-headless, whose blank-ioctl sequence broke later power-ups.
  - Verified by webcam: cold boot → dark; fake volume-key press → console; 30 s test idle → dark; wakes again. **Left for the owner:** a real finger tap, and the 5 min timeout in normal use.
  - Not done: a real tty1 login. Kernels with CONFIG_VT reset the phone very early (also without fbcon, no pstore trace); no keyboard anyway.
- [ ] **P8.2** Modem / SMS (ModemManager + qrtr) if needed. _Parked 2026-11-17: owner has no SIM card (SMS, data and calls need one)._ Found so far: modem subsystem `ONLINE` (it also runs the wifi firmware, so it stays on); the kernel has the downstream IPC router (`CONFIG_IPC_ROUTER`), not upstream QRTR, so ModemManager/libqmi can't use their QRTR path; `qmicli --device-open-qmi` on `/dev/smdcntl8` got no reply (hung). Next if picked up: QMI over the IPC router (AF_MSM_IPC sockets) or a backported QRTR.
- [x] **P8.3** Mainline kernel (owner go 2026-11-17). Research: `docs/mainline.md` (nobody has booted mainline on walleye; start from Porthole 7.2.2 + patches).
  - [x] P8.3.1 _Done: walleye uses dtbo_idx 3 = id 444 rev 3 (dtbo.img is shared: idx 0–5 id 444 rev 0–4/0x80, idx 6–12 ids 400–2704 incl. taimen 2704)._ Read walleye's dtbo ids: `/proc/cmdline` dtbo_idx + parse `firmware/dtbo.img` entries (no flashing).
  - [x] P8.3.2 _Done: linux-stable v7.2.2 (52c36105) + porthole-pmaports taimen-bringup, shallow._ Sources as submodules: Porthole pmaports (patches) + linux-stable v7.2.2 (shallow).
  - [x] P8.3.3 _Done: `scripts/build-mainline.sh`, docker/mainline (clang 18), 10 min._ Build container with a modern toolchain + `scripts/build-mainline.sh` → Image.gz + walleye DTB (fix panel/touch nodes: drop taimen's; no bootargs).
  - [x] P8.3.4 _Done 2026-11-17: mainline 7.2.2 boots to our initramfs, USB serial works. Needed: `wahoo-dtbo-sink.dtsi` (stock overlay applies into dummy nodes), factory msm-id, no `earlycon`._ `fastboot boot` test with the **stock dtbo** (nothing flashed). Gate: USB serial/network from our initramfs.
  - [x] P8.3.5 _Not needed: the sink DTS avoids flashing dtbo._ Only if P8.3.4 fails on the overlay: crafted stub dtbo, flashed to the **inactive slot only** (owner OK first; current Ubuntu needs the stock dtbo for its panel).
  - [x] P8.3.6 Bring-up order (each step: `fastboot boot`, nothing flashed):
    - [x] UFS + USB gadget + rootfs: _Ubuntu 24.04 runs on 7.2.2 (2026-11-17): running, 0 failed, cgroup2, cpufreq present._
    - [x] Charger + fuel gauge + RGB LED: _work (battery %, voltage, charging; rgb:status lights)._
    - [x] _Done 2026-11-17 (tests 10, 12)._ Mainline variants of pixel2-charge-limit (input suspend via charger `status`) and pixel2-status-led (rgb:status pattern trigger).
    - [x] Wifi: modem (MSS) + ath10k with the wahoo carveouts; firmware paths for mainline (qcom/msm8998/wahoo/*). Works 2026-11-17: `scripts/stage-mainline-wifi.sh` (firmware from the phone's own partitions), rmtfs + tqftpserv + diag-router, `ath regd_override=0x67`.
    - [x] Stable MAC: _done (4.4 records it to /var/lib/pixel2/wlan0.mac, mainline applies it before NetworkManager; same IP .44 on both kernels)._
    - [ ] Wifi follow-ups: bake firmware + tools into build-rootfs.sh (now staged by hand); IPA/rmnet (mobile data, needs SIM: parked with P8.2).
    - [x] Display (S6E3FA5 panel driver) + touch (rmi4): _done 2026-11-17. Panel: patch 0002 + SMMU identity patch 0003. Touch: Synaptics S3708AR, l28 at 3.008 V (3.3 V froze boots, tests 25-30). pixel2-screen mainline mode: dark from boot, touch wakes the fbcon console on tty1 (TER16x32, 67x60), off after 5 min (test 34)._
    - [x] Baked into `scripts/build-all.sh` (MAINLINE=0 skips): modules, modem tools, ath10k board data from the factory vendor.img, boot-mainline.img; modem firmware built on the phone at boot (`pixel2-modem-fw`).
    - [x] _Flashed 2026-11-17 (owner: "flash it"): `boot_b` (active slot) = build/mainline/boot-mainline.img; boot_a still 4.4. Boots on its own and after `sudo reboot`: running in ~19 s, wifi .44. Back to 4.4: bootloader, `fastboot flash boot_b build/boot.img`._ Flash mainline as the default kernel.

- [ ] **P8.5** Camera: take pictures and record video (owner request 2026-11-17).
  - Downstream 4.4 is a dead end: its camera stack (msm camera v2) only works with Android's proprietary camera HAL.
  - Path: mainline (P8.3) CAMSS (Porthole carries msm8998 CAMSS patches) + sensor drivers + libcamera (`cam` / `libcamera-still`-style CLI, GStreamer `libcamerasrc` for video).
  - First steps: identify walleye's sensors from the downstream DT (rear/front sensor models, CSI ports, I2C addresses, regulators, MCLK); check mainline/Porthole drivers for them; check Porthole's taimen camera status.
  - Gate: a photo (JPEG) and a short video (MP4) taken from the shell, copied to the Mac.

## Phase 9: One-command build + guided flashing (2–4 h; owner request 2026-11-17)
Goal: on a fresh clone, one script builds everything and then walks the user through flashing a stock Pixel 2, step by step, with checks.
- [x] **P9.1** _Done 2026-11-17: fresh clone → both images, no manual steps, 11.5 min (kernel 6.5 min); rerun = all steps "up to date"; plus `scripts/get-firmware.sh`._ `scripts/build-all.sh`: one entry point that runs, in order and only when outdated:
  - `git submodule update --init` (kernel-msm, qbootctl);
  - build container (`docker/`), `build-kernel.sh`, `build-initramfs.sh`, `build-android-stubs.sh`, `build-qbootctl.sh`;
  - `build-bootimg.sh` (factory DTB) and `build-rootfs.sh` → `build/boot.img`, `build/rootfs.simg`.
  - Prerequisites checked up front with clear messages: Docker running, case-sensitive volume, `adb`/`fastboot`, the factory image in `firmware/` (or download it, checking the SHA-256 from developers.google.com), and the user's SSH key.
  - Wifi credentials asked once (or read from a gitignored file) and baked into the rootfs as an NM profile (mode 0600), so the phone is reachable without USB.
  - Gate: on a fresh clone it produces both images with no manual steps.
- [ ] **P9.2** `scripts/flash.sh`: an interactive guide, one step per screen, each confirmed by checking the phone's state (adb, fastboot getvar, USB IDs) before going on:
  1. Check the phone: walleye, bootloader unlocked (or explain OEM unlocking + `fastboot flashing unlock`), on the final Android 11 firmware (else offer the factory `flash-all.sh`).
  2. Show what will be erased (userdata) and ask for an explicit "yes".
  3. Flash vbmeta_a/b (verification off), boot_a/b, userdata; handle the bootloader going quiet on USB after the userdata write (tell the user to pick **Start**).
  4. Wait for the phone on USB/wifi, print the SSH command, check the LED pulse + screen off by asking the user.
  - Also a restore path: back to stock Android (`flash-all.sh`, vbmeta with verification).
  - _2026-11-17: flashes mainline to the active slot and 4.4 to the other (KERNEL=4.4 for 4.4 on both). A mainline-only install never records the real wifi MAC (that needs 4.4), so pixel2-wifi-mac makes up one stable locally administered MAC on first boot._
  - Gate: someone else flashes a phone using only README + `scripts/flash.sh`.
- [x] **P9.3** _Done 2026-11-17._ README: replace the dev-notes flow with "build-all → flash", and keep PLAN.md/log.md as the history.
