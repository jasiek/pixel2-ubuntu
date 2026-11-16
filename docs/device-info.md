# Device info: Pixel 2 (walleye)

Facts about this specific phone. Never commit the serial number.

## From Settings → About phone (P1.2)
| Field | Value |
|---|---|
| Model | Pixel 2 (walleye), Google Store |
| Android version | 11 (implied by `RP1A` build prefix) |
| Build number | `RP1A.201005.004.A1` (Google's final walleye build, Android 11) |
| Storage size | 128 GB (userdata will be ~110 GB → Ubuntu rootfs) |

## From `fastboot getvar all` (P1.6)
Captured 2026-11-16 after the bootloader unlock. Full output is in `firmware/getvar-all.txt` (gitignored, contains the serial).

| Field | Value |
|---|---|
| Bootloader | `mw8998-003.0085.00` (final) |
| Baseband / radio | `g8998-00034-2006052136` (final) |
| Unlocked | yes (`unlock_critical` not supported by this bootloader; not needed) |
| Secure / AVB | `secure: yes`, `avb_version: 1.0.0` |
| Slots | A/B, **current slot: b**, both marked successful |
| Max fastboot download | 512 MiB (fastboot splits larger sparse images automatically) |

| Partition | Size | Type |
|---|---|---|
| `boot_a` / `boot_b` | 32 MiB each | raw (our kernel + initramfs must fit) |
| `system_a` / `system_b` | 2.5 GiB each | ext4 |
| `vendor_a` / `vendor_b` | 500 MiB each | ext4 (Android firmware/blobs, keep) |
| `userdata` | **112.7 GiB** | ext4 → Ubuntu rootfs |
| `dtbo`, `vbmeta`, `modem`, `radio` | slotted (`_a`/`_b`) | |


## Stock kernel (seen in P1.8)
- `Linux version 4.4.223-g52750b8f2138-ab6846512`, built Fri Sep 18 2020.
- Kernel git commit: **`52750b8f2138`**. Check out exactly this commit in P2.3.
- Toolchain: **Android clang 11.0.1 (r383902)**. Use this clang version in P3.1, rather than GCC.
- Stock cmdline: `androidboot.hardware=walleye androidboot.console=ttyMSM0 lpm_levels.sleep_disabled=1 user_debug=31 msm_rtb.filter=0x37 ehci-hcd`
- boot.img: page size 4096, kernel offset 0x8000, ramdisk offset 0x1000000.

## From stock `boot.img` header (P2.4)
Unpacked with `external/mkbootimg/unpack_bootimg.py` into `build/stock-boot/` (gitignored).

| Field | Value |
|---|---|
| Header version | 0 |
| Page size | 4096 |
| Kernel | LZ4-compressed `Image.lz4-dtb` (DTB appended), 14.3 MiB, load addr `0x00008000` |
| Ramdisk | gzip cpio, 10.9 MiB (21.4 MiB unpacked), load addr `0x01000000` |
| Tags | `0x00000100` |
| OS version / patch | 11.0.0 / 2020-10 |

**mkbootimg arguments to reproduce:**
```
--header_version 0 --pagesize 4096 --base 0x00000000 \
--kernel_offset 0x00008000 --ramdisk_offset 0x01000000 --tags_offset 0x00000100 \
--os_version 11.0.0 --os_patch_level 2020-10
```

**Full stock cmdline:**
```
androidboot.hardware=walleye androidboot.console=ttyMSM0 lpm_levels.sleep_disabled=1 user_debug=31 msm_rtb.filter=0x37 ehci-hcd.park=3 service_locator.enable=1 swiotlb=2048 firmware_class.path=/vendor/firmware loop.max_part=7 raid=noautodetect usbcore.autosuspend=7 androidboot.dtbo_idx=3 buildvariant=user
```

Notes:
- `firmware_class.path=/vendor/firmware`: the kernel loads firmware from there, so mount `vendor_a/b` at `/vendor` (P6.1).
- ⚠️ The bootloader adds **`skip_initramfs`** to the cmdline on normal boots. The kernel (`init/initramfs.c:618`) then ignores our ramdisk and mounts the system partition as root. Our kernel must ignore that flag (P3.3).
