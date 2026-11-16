# Pixel 2 → Ubuntu 24.04 (headless): Plan

**Goal:** the Pixel 2 (walleye) powers on straight into Ubuntu 24.04 arm64, reachable over SSH. No Android at runtime.

## ▶ RESUME HERE: P1.4

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
- [ ] **P1.4** Unlock the bootloader:
  ```sh
  adb reboot bootloader
  fastboot flashing unlock           # confirm on phone with volume keys + power
  fastboot flashing unlock_critical  # confirm again; needed to flash the bootloader
  fastboot getvar unlocked
  ```
  - Gate: output says `unlocked: yes`.
- [ ] **P1.5** Download the final Android 11 factory image for walleye from https://developers.google.com/android/images#walleye (expected `RP1A.201005.004.A1`; take the newest listed). Unzip it into `firmware/` and run its `flash-all.sh` with the phone in bootloader mode.
  - Gate: phone boots Android 11.
- [ ] **P1.6** In bootloader mode, record partition info into `docs/device-info.md` (delete the serial number line before committing):
  ```sh
  fastboot getvar all 2>&1 | tee firmware/getvar-all.txt
  ```
  - Note: current slot, and the sizes of boot, userdata, vendor and modem.
- [ ] **P1.7** From the factory zip's inner `image-walleye-*.zip`, extract `boot.img`, `vendor.img`, `vbmeta.img` and `dtbo.img` into `firmware/`. Also keep `radio-walleye-*.img` there.
- [ ] **P1.8** Test tethered boot: `fastboot boot firmware/boot.img`.
  - Gate: Android boots. This proves we can test kernels without flashing.

## Phase 2: Build environment on the Mac (1 h)
- [ ] **P2.1** Write `docker/Dockerfile`: Ubuntu 20.04 **arm64** with build-essential, bc, bison, flex, libssl-dev, lz4, git, python3, cpio, android-sdk-libsparse-utils (`img2simg`), and mkbootimg tools.
- [ ] **P2.2** Write `scripts/dev.sh`: runs a command inside the container with the repo mounted at `/work`.
  - Gate: `scripts/dev.sh uname -m` prints `aarch64`.
- [ ] **P2.3** Clone the kernel into `src/kernel` (gitignored) from `https://android.googlesource.com/kernel/msm`. Use the newest `android-msm-wahoo-4.4-*` branch for Android 11 (list with `git ls-remote --heads`).
  - Record branch + commit hash in `docs/log.md`.
- [ ] **P2.4** Unpack `firmware/boot.img` with `unpack_bootimg`. Record header version, kernel cmdline, base address, page size and offsets in `docs/device-info.md`.

## Phase 3: Kernel (2–6 h)
- [ ] **P3.1** Build stock `wahoo_defconfig` → `Image.lz4-dtb`. Script it as `scripts/build-kernel.sh`.
  - Gate: it compiles. If the compiler is too new, try GCC 7/8 or Google's prebuilt toolchain; log it.
- [ ] **P3.2** Repack our kernel with the **stock** ramdisk into `build/boot-stockramdisk.img`, then `fastboot boot` it.
  - Gate: Android boots. Proves our kernel build works on the phone.
- [ ] **P3.3** Write `kernel/walleye-ubuntu.config` (config fragment). Cross-check against Flohack74's Halium tree (github.com/Flohack74/android_device_google_wahoo).
  - systemd: `DEVTMPFS`, `DEVTMPFS_MOUNT`, `CGROUPS` + controllers, `FHANDLE`, `AUTOFS4_FS`, `NAMESPACES` (UTS/IPC/PID/NET/USER), `SECCOMP`, `TMPFS_POSIX_ACL`, `TMPFS_XATTR`, `INOTIFY_USER`, `SIGNALFD`, `TIMERFD`, `EPOLL`
  - USB gadget networking: `USB_CONFIGFS_ECM`, `USB_CONFIGFS_NCM`
  - `# CONFIG_ANDROID_PARANOID_NETWORK is not set` (otherwise only special Android groups get network access)
  - SELinux off (`selinux=0` on cmdline or disable in config)
- [ ] **P3.4** Rebuild with the fragment merged.
  - Gate: it compiles.

## Phase 4: Initramfs + rootfs (2–4 h)
- [ ] **P4.1** Write `scripts/build-rootfs.sh`, which runs inside the arm64 container:
  - Start from `ubuntu-base-24.04.x-base-arm64.tar.gz`.
  - Install systemd, systemd-sysv, udev, openssh-server, sudo, network-manager, iproute2, e2fsprogs, avahi-daemon, nano, less.
  - Set hostname `pixel2`, create user `ubuntu`, and install your SSH public key.
  - Add a systemd unit that brings up the USB-ECM gadget at `172.16.42.1/24`.
- [ ] **P4.2** Pack into a 4 GB ext4 `build/rootfs.img`, then `img2simg` → `build/rootfs.simg`.
- [ ] **P4.3** Write `scripts/build-initramfs.sh`: a static-busybox `/init` that:
  - mounts proc, sys and dev;
  - starts the USB-ECM gadget;
  - mounts the userdata partition and runs `resize2fs` once to fill it;
  - runs `switch_root` → `/sbin/init`.
  - On failure: start `telnetd` on `172.16.42.1` and keep running, so we can log in and debug.
- [ ] **P4.4** Write `scripts/make-bootimg.sh`: kernel + initramfs + cmdline/offsets from P2.4 → `build/boot.img`.

## Phase 5: First boot, tethered (1–3 h; most debugging lands here)
- [ ] **P5.1** ⚠️ Overwrites Android's data partition: `fastboot flash userdata build/rootfs.simg`
- [ ] **P5.2** `fastboot boot build/boot.img`
- [ ] **P5.3** On the Mac, a new USB network interface appears (check `ifconfig`). Give it `172.16.42.2/24`, then `ssh ubuntu@172.16.42.1`.
  - Gate: you get a shell. 🎉 **Milestone 1: Ubuntu 24.04 is running on the Pixel 2.**
- [ ] **P5.4** If P5.3 failed:
  - Try `telnet 172.16.42.1` (initramfs debug shell).
  - No network at all? Check `/sys/fs/pstore` on the next boot.
  - systemd refuses kernel 4.4? Switch to Ubuntu 22.04 and log the decision.
- [ ] **P5.5** Save `uname -a`, `systemctl --failed` and notable `dmesg` errors in `docs/log.md`.

## Phase 6: Wifi (2 h to 2 days)
- [ ] **P6.1** Mount `vendor_a` → `/vendor` and the modem partition → `/firmware`, both read-only, via systemd mount units. The kernel loads wifi firmware from there.
- [ ] **P6.2** Check `ip link`.
  - Gate: `wlan0` exists.
- [ ] **P6.3** No `wlan0`? Read `dmesg` for cnss / qrtr / rmt_storage / pd-mapper errors. Try the Linux packages `qrtr-tools`, `rmtfs`, `pd-mapper`.
- [ ] **P6.4** Still nothing? Fall back to running Android vendor services in an LXC container (the Halium approach). Log the decision.
- [ ] **P6.5** Connect: `sudo nmcli dev wifi connect "<SSID>" password "<pw>"`.
  - Gate: `ssh ubuntu@pixel2.local` works with the USB cable unplugged.

## Phase 7: Make it permanent (1 h)
- [ ] **P7.1** `fastboot --disable-verity --disable-verification flash vbmeta firmware/vbmeta.img`
- [ ] **P7.2** `fastboot flash boot_a build/boot.img && fastboot flash boot_b build/boot.img`
- [ ] **P7.3** Power off, then press the power button.
  - Gate: SSH over wifi works without the Mac. 🎉 **Milestone 2: the phone boots into Linux.**
- [ ] **P7.4** Headless tuning:
  - Turn the screen backlight off.
  - Enable `unattended-upgrades`.
  - Check charging under `/sys/class/power_supply/`. If it lives on a charger 24/7, look for a charge limit (battery swelling risk).
- [ ] **P7.5** Reboot 5 times.
  - Gate: SSH works after every reboot.

## Phase 8: Optional stretch (decide later)
- [ ] **P8.1** Screen: text console on the framebuffer, then a kiosk if the device's job needs a screen.
- [ ] **P8.2** Modem / SMS (ModemManager + qrtr) if needed.
- [ ] **P8.3** Revisit a mainline kernel (msm8998 work done for the Pixel 2 XL).
