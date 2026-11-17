# Work log

Newest entries at the bottom. One dated line per event: what happened, errors, decisions.

## 2026-11-16
- Researched options (see `docs/research.md`). Ubuntu Touch supports walleye on 16.04 only (abandoned). No 20.04/24.04 port exists. Mainline work covers the Pixel 2 XL only.
- Decisions by owner:
  - phone is a **Pixel 2 (walleye)** bought from the **Google Store** (unlockable);
  - target is **plain headless Ubuntu 24.04**;
  - device role is **dedicated, job still undecided**;
  - **skip** the Ubuntu Touch 16.04 trial and go straight to porting.
- Host: M1 Pro Mac (arm64). Docker, adb and fastboot are installed.
- Phase 0 (repo setup) done. Next: P1.1, which needs the phone in hand.
- P1.1: owner factory-reset (wiped) the phone; nothing to back up.
- P1.2: confirmed build RP1A.201005.004.A1 (final Android 11) and 128 GB storage. P1.5 reflash is optional since the phone is already on the final build; the factory zip is still needed for P1.7 firmware.
- P1.3: OEM unlocking toggle enabled (not greyed out).
- P1.4: `fastboot flashing unlock` returned OKAY (9 s, confirmed on phone). Phone then left fastboot mode (likely rebooting to wipe). `unlock_critical` still to do.
- P1.4: `unlocked: yes`. `fastboot flashing unlock_critical` -> FAILED (remote: 'unknown command') on bootloader mw8998-003.0085.00. Not needed: bootloader + radio are already the final versions, so we never flash them.
- P1.5: skipped; phone already runs the final factory build.
- P1.7: factory zip `walleye-rp1a.201005.004.a1-factory-0c23f6cf.zip` SHA-256 starts with 0c23f6cf (matches Google filename suffix). Extracted boot.img (32 MiB, page 4096, kernel@0x8000, ramdisk@0x1000000), dtbo.img, vbmeta.img, vendor.img (sparse), radio img into firmware/ (gitignored).
- P1.8: `fastboot boot firmware/boot.img` works; Android booted (sys.boot_completed=1). Stock kernel 4.4.223 commit 52750b8f2138, Android clang 11.0.1 r383902. **Phase 1 complete.**
- Owner asked: reference other software as **git submodules** (in `external/`). Added `external/mkbootimg` (AOSP, d2bb0af). Kernel branch found: `android-msm-wahoo-4.4-android11` head = `52750b8f2138` = tag android-11.0.0_r0.34 = exactly the stock kernel.
- P2.1: Docker image `pixel2-build` (Ubuntu 20.04 arm64, Ubuntu clang 11.0.0, img2simg, busybox-static) builds and runs natively.
- Blocker found: Mac disk is case-insensitive APFS; the kernel tree has case-colliding files, so it cannot be checked out there. Needs a case-sensitive volume.
- Fix for case-sensitivity: created case-sensitive APFS volume `Pixel2Dev` (`diskutil apfs addVolume disk3 "Case-sensitive APFS" Pixel2Dev`, shares free space). Moved repo to `/Volumes/Pixel2Dev/ubuntu-touch-pixel2`; old path `~/github/ubuntu-touch-pixel2` is now a symlink to it.
- P2.3: kernel submodule `external/kernel-msm` @ 52750b8f2138 (2020-09-18), shallow (972 MB). `git submodule add --depth 1 -b` fetched only the empty master, so the branch was cloned with `git clone --depth 1 --single-branch -b ...` and then registered with `git submodule add`. Checkout is clean on the case-sensitive volume.
- P2.4: stock boot.img = header v0, page 4096, base 0, kernel 0x8000, ramdisk 0x1000000, tags 0x100. Found `skip_initramfs` handling in the kernel; P3.3 must neutralize it. **Phase 2 complete.**
- P3.1: stock wahoo_defconfig builds in ~1 min (full build 6 min first time) with Ubuntu clang 11.0.0 + native arm64 binutils. Needed: `device-tree-compiler` package (system dtc) and CC_WERROR disabled. Image.lz4-dtb = 14,951,785 bytes (stock 14,986,756).
- P3.2: our kernel + stock ramdisk boots Android via `fastboot boot` (26 s). Finding: `/proc/modules` empty. The `/vendor/lib/modules` .ko files (wlan, htc_battery, synaptics touch) fail to load into our kernel because CONFIG_MODVERSIONS=y and the version string differs. All of them are in-tree (`CONFIG_QCA_CLD_WLAN=m`, `CONFIG_HTC_BATTERY=m`, ...), so we build and ship our own modules.
- P3.3/P3.4: fragment `kernel/walleye-ubuntu.config` (all options applied) + patch `0001-initramfs-ignore-skip_initramfs`. SELinux disabled via BOOTPARAM + `selinux=0`. Added USB ACM serial and fbcon as debug aids. Kernel `4.4.223-walleye-ubuntu`, 15.2 MB, modules: wlan, htc_battery, synaptics touch (+ unused LG ones). Halium reference kernel (Flohack74 halium-9.0 @ 075dddda) has a near-stock defconfig and an unpatched skip_initramfs, so it was not useful. **Phase 3 complete.**
- P4.1/P4.2: rootfs built from official `ubuntu:24.04` (24.04.5) arm64 Docker image (= ubuntu-base) + `rootfs/overlay`, exported and packed with `mkfs.ext4 -d` (no loop/privileged needed). 255 MB used, 4 GiB image, 240 MB sparse. systemd 255.4. USB: NCM net + ACM serial (autologin on ttyGS0); NM `shared` gives the Mac DHCP on 172.16.42.0/24. SSH keys: owner FIDO key + a generated project key `build/ssh/pixel2_ed25519` (gitignored) so tests can run unattended. glibc needs kernel >= 3.7, OK.
- P4.3/P4.4: initramfs 0.9 MB (static busybox 1.30.1, telnetd/udhcpd/getty debug). `build/boot.img` (normal) + `build/boot-debug.img` (stops in initramfs). Cmdline adds `selinux=0 systemd.unified_cgroup_hierarchy=0 SYSTEMD_CGROUP_ENABLE_LEGACY_FORCE=1 console=tty0` (4.4 has no cgroup2). **Phase 4 complete.**
- P5 (pre-flash test): full-config `boot-debug.img` via `fastboot boot` -> phone reset back into Android (bootreason `reboot`), no USB device. Minimal variant (`kernel/debug-minimal.config`: stock + DEVTMPFS + ACM + patch) **works**: Mac sees "Pixel 2 (Ubuntu)", NCM = en9 got DHCP 172.16.42.16, ACM serial /dev/cu.usbmodempixel2_ubuntu3, telnet root shell via `scripts/initrd-sh.py`. So kernel+patch+initramfs+USB are fine; one of the fragment options kills boot. Bisecting.
- Bisect so far (all `fastboot boot`, nothing flashed):
  - full config + plain cmdline: reset to Android after 32 s, so it's a config problem, not the cmdline;
  - B (= min + no-paranoid-net + SELinux bootparam + ECM + VT/VT_CONSOLE/FBCON): reset after 32 s;
  - B2 (= B without VT/fbcon): no reset, USB gadget enumerated, but macOS created no NCM network interface and the serial port was silent. **Phone hung** (not in fastboot or Android) and needs a manual power-button restart. Unclear whether it is a kernel hang or the serial/network setup.
  - Panics reboot in 1 s (`PANIC_TIMEOUT=1`), but soft/hard lockups and hung tasks are configured not to panic. Debug images now add `softlockup_panic=1 hung_task_panic=1 nmi_watchdog=panic`. The initramfs debug mode returns to fastboot after 10 min unless `/tmp/keep` exists. A serial getty now starts first, in every mode.
  - Pre-built for the next run: `build/boot-{min,B,A}-debug.img` (B = B2 config).

## 2026-11-17
- Owner restarted the phone (power button); it came back in Android.
- Bisect results:
  - min: UP after 22 s.
  - B2: UP, but the first telnet session closed at once, telnetd died, and serial was silent. ~3 min later `hung_task_panic` rebooted it to Android. Cause: **the B2 fragment lacked `CONFIG_DEVTMPFS=y`**, a bug in the test, not the options. `/dev` had no `ptmx` (telnet) and no `ttyGS0` (serial). Last night's "hang" was the same thing.
  - Raw reads of `boot_a` (sda9) and `userdata` (sda45) work fine on the min kernel. userdata currently holds Android's ext4 `/data`.
  - Partition map: userdata = `/dev/sda45`, system_a/b = sda22/sda43, vendor_a/b = sda20/sda41, boot_a/b = sda9/sda30. LUNs sdb–sdf hold xbl, misc, persist, modemst, etc.
- Conclusion: **only VT/VT_CONSOLE/FRAMEBUFFER_CONSOLE break boot.** Removed from `kernel/walleye-ubuntu.config` and dropped `console=tty0`.
- Full kernel rebuilt without VT, `boot-debug.img` via `fastboot boot`: UP after 21 s, telnet + serial shells both work, `selinux=0` effective (no /sys/fs/selinux), `/dev/ptmx` + `/dev/ttyGS0` present. **P5.0 done.**
