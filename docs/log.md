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
