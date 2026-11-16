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


## From stock `boot.img` header (P2.4)
_TODO_
