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
- P5.1: `fastboot flash userdata build/rootfs.simg` (sparse, 229 MB, one chunk; max-download-size 512 MiB) OKAY. Verified from the debug shell: sda45 mounts, build stamp 06:43Z, /sbin/init -> systemd, 3.9G fs (not grown yet).
- P5.2 first real boot (`fastboot boot build/boot.img`): **Ubuntu 24.04.5 + systemd 255 runs on kernel 4.4.223.** Serial autologin on ttyGS0 works (`/dev/cu.usbmodempixel2_ubuntu3`). State `degraded`, no USB network. Problems and fixes:
  1. `usb0` unmanaged: NM's `85-nm-unmanaged.rules` sets NM_UNMANAGED=1 for DEVTYPE=gadget. Fix: `/etc/udev/rules.d/86-pixel2-usb-gadget-nm.rules`.
  2. ssh: "no hostkeys available". Ubuntu's `ExecStartPre=sshd -t` runs before our `ssh-keygen -A`. Fix: reset the ExecStartPre list in the drop-in.
  3. Modules: "htc_battery: disagrees about version of symbol module_layout". The CRCs are identical on disk, but this 4.4 tree stores `__kcrctab = &__crc_sym` (an address), and KASLR (RANDOMIZE_BASE=y) relocates it. Fix: `# CONFIG_MODVERSIONS is not set`.
  4. growfs failed: "There are errors in the filesystem". The ext4 error is `ext4_has_uninit_itable: Inode table for bg 0 marked as needing zeroing`, because mke2fs lazy itable init leaves bg 0 without INODE_ZEROED. Fix: `mkfs -E lazy_itable_init=0,lazy_journal_init=0`. Checked first: img2simg encodes zeros as FILL chunks (19 RAW + 19 FILL, no DONT_CARE), so the flashed itables really are zero.
  5. PIDs at 1.9 M after 6 min: the initramfs getty loop survived switch_root and spun because its binaries were gone. Fix: kill it before switch_root.
  - Clock starts at 2026-10-12 (systemd build-time floor; no RTC sync yet). timesyncd should fix it once networking works.
- Rebuilt with the five fixes, reflashed userdata, `fastboot boot build/boot.img`. SSH port open ~18 s after boot. 🎉 **Milestone 1: `ssh ubuntu@172.16.42.1` works.** (`scripts/ssh.sh` helper.) P5.2–P5.5 done.
  - `Linux pixel2 4.4.223-walleye-ubuntu #3 SMP PREEMPT`, Ubuntu 24.04.5, `systemctl is-system-running` = **running**, no failed units.
  - htc_battery loads (battery 99% Charging). Root grew to 111 G (271 M used). /vendor = sda41 (vendor_b) ro. 3.6 GB RAM, 8 CPUs.
  - Mac got 172.16.42.106 from NM's shared-mode DHCP on en9. PIDs stable (fork storm fixed).
  - Clock = 2026-10-12, NTP unsynced (no internet yet).
  - dmesg: 394 err-level lines, all Android-hardware noise. Top ones: `ufshcd_ioctl: User buffer is NULL` x82 (something probes the UFS ioctl), ASoC tavil platform not registered (audio), camera/msm_bus/i2c probe failures, `[LASER]` sensor.
  - Oddity: `fastboot boot` took 302 s to return (normally a few seconds), but the boot itself was fine.
- **P6 wifi works (2026-11-17).** `wlan0` (factory MAC 40:4e:36:…) scans 10 networks on 2.4 and 5 GHz. It comes up by itself on a cold boot. Chain, all Android vendor binaries run directly on Ubuntu, no container:
  - **Kernel IPC is the old IPC Router (`CONFIG_IPC_ROUTER`), not QRTR**, so Linux rmtfs/pd-mapper/qrtr can't work. Use the vendor's.
  - `android-env.service`:
    - mounts `system$slot` → /android/system (bind /system);
    - loop-mounts `com.android.runtime` and `com.android.vndk.current` APEX payloads (stored uncompressed in the zip; offset via perl) at /apex/…;
    - mounts `modem$slot` (vfat) at /firmware;
    - **/persist = overlayfs**: real partition read-only at /android/persist, writes go to /var/lib/pixel2/persist-overlay;
    - /dev/block/bootdevice/by-name links, firmware path /run/pixel2-fw (vendor + modem images), modem restart_level=RELATED;
    - `irsc_util /vendor/etc/sec_config` (without it the kernel IPC router blocks: "wait_for_irsc_completion").
  - `android-props`: bionic reads a **legacy single-file property area** when /dev/__properties__ is a regular file. Built from androidboot.* and /etc/android/props.conf. rmt_storage needs ro.baseband=msm ("not supported on undefined target" otherwise).
  - `android-logd`: liblog socket → journal (tag `android`). Essential for debugging.
  - Daemons: rmt_storage (EFS in modemst1/2, fsg, fsc), tftp_server (modem pulls wlanmdsp.mbn etc.), pd-mapper (servloc; without it a kworker hangs in pd_locator_work), `modem.service` (holds /dev/subsys_modem open, which boots the modem).
  - **cnss-daemon** downloads the BDF (bdwlan.b80, board_id 0x80) and the MAC to the WLAN firmware. Only then does icnss get FW_READY and wlan.ko probe. It links libperipheral_client.so (binder to pm-service), so we ship a **stub** (android/stubs/peripheral_client.c, freestanding clang build) that reports the modem online.
  - Backups before any daemon wrote to them: modemst1/2, fsg, fsc, persist, ssd → firmware/backup/ (gitignored).
  - Tools: scripts/ssh.sh, scripts/push-overlay.sh (live overlay update + clock set), scripts/build-android-stubs.sh, try-boot serial fallback.
- Problems still open:
  - **The Mac's NCM interface stopped coming up.** usb0 NO-CARRIER; macOS made an IOEthernetInterface with no BSD name. Serial still works. Committed fixed NCM MACs (02:50:49:58:32:01/02) in the initramfs; untested.
  - **The next boot.img boot never showed USB serial, and the phone fell back to stock Android.** It came up as 18d1:4ee1 (MTP, adb off). Android most likely reformatted userdata (fstab: `formattable`) because it found our ext4. That wipes the Ubuntu rootfs. Needs the buttons to recover (PLAN P6.R). Rebuilt `build/rootfs.simg` (08:00Z) with all P6 work, ready to reflash.
  - Lesson: until our boot.img is flashed (Phase 7), any failed tethered boot falls back to Android, and Android destroys userdata.
- Recovery attempt (owner pressed the buttons): `boot-debug.img` also reset into Android (18d1:4ee1). **Cause: the fixed-MAC change.** In this kernel `f_ncm` creates its net device only in `ncm_bind()`, so writing `ncm.usb0/dev_addr` before bind dereferences NULL. PID 1 dies, the kernel panics, the phone reboots into Android. After bind the write returns EBUSY. Reverted, with a warning comment in both scripts. Rebuilt the initramfs, boot images and rootfs (all match the repo now).
- The phone is in Android again (adb off), so it needs the buttons once more.
