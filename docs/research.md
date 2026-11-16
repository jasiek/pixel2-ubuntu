# Research: Linux on the Pixel 2 (walleye)

Researched 2026-11-16. Re-check anything marked *verify* before acting on it.

## Device

| | |
|---|---|
| Model | Google Pixel 2 (made by HTC), codename **walleye** |
| Sibling | Pixel 2 XL (LG), codename **taimen**. Same SoC, shares kernel/device tree ("wahoo") |
| SoC | Qualcomm Snapdragon 835 (**MSM8998**), arm64 |
| Partitions | A/B slots (`boot_a`/`boot_b`, `system_a`/`system_b`, `vendor_a`/`vendor_b`, …) |
| Bootloader | Google Store units: unlockable. Verizon units: locked, no official unlock |
| Final Android | Android 11. Final factory image expected to be `RP1A.201005.004.A1` (*verify* on Google's factory image page) |

## Options surveyed

### 1. Ubuntu Touch (UBports): only 16.04, abandoned
- The device page says: *"The Google Pixel 2 is not supported by the current Ubuntu Touch release."*
  - Only **16.04 xenial** is offered (stable OTA-25, 2023-04-17).
  - Marked unmaintained; last commit 2022-09-06; maintainer Flohack74.
- Installer config `v2/devices/walleye.yml`:
  - requires a downgrade to Android 9 `PQ3A.190801.002`;
  - flashes `boot`, `dtbo`, `vbmeta` with `--disable-verity --disable-verification`;
  - then installs via system-image in recovery.
- Feature matrix on 16.04:
  - Works: calls, SMS, data, wifi, camera, fingerprint, GPS.
  - Partial: Bluetooth, microphone.
  - Not working: VoLTE, hotspot.
- Forum: no one is porting it to 20.04 focal or 24.04 noble. A Focal port "depends on someone putting in the work to do so."
- **Useful to us:** the Halium device tree (github.com/Flohack74/android_device_google_wahoo) proves this kernel can boot Ubuntu userspace. Its kernel config is a reference for systemd-required options.

### 2. postmarketOS / mainline kernel: taimen only
- Pixel 2 XL (taimen) wiki status: "Boots but no display output". Mainline with basic DTS reaches a shell over USB networking.
  - Display needs Display Stream Compression support.
- MSM8998 page: USB was flagged as not working on mainline at one point; CPU frequency scaling is partial.
- The postmarketOS msm8998 maintainer stepped down (Sept 2025); ports are looking for maintainers.
- Unofficial fork `porthole-dev/pmaports` (2026):
  - mainline 7.2 kernel for **taimen only**;
  - single author; claims are self-reported; redistributes firmware blobs; treat as unvetted.
- No walleye port found. Porting mainline to walleye = research project (weeks+).

### 3. Droidian / Sailfish / Mobian
- No walleye support found in any of them.

### 4. Chosen: custom port, plain Ubuntu 24.04 on the downstream kernel
- Google's Android kernel (`android.googlesource.com/kernel/msm`, branch `android-msm-wahoo-4.4-*`; *verify* exact name).
- Plus our own busybox initramfs.
- Plus an Ubuntu 24.04 arm64 rootfs (`ubuntu-base`) flashed onto `userdata`.
- Why: it is the only route to a *recent* Ubuntu that has a realistic chance of working within days.

## Known risks
1. **systemd 255 (Ubuntu 24.04) on Linux 4.4.**
   - Halium-based distros run modern systemd on old kernels, but it is unverified on this kernel.
   - Fallback: Ubuntu 22.04 (systemd 249).
2. **Wifi (WCN3990)** may depend on Android vendor daemons (cnss-daemon, rmt_storage, qrtr, pd-mapper).
   - Fallback: Linux equivalents (`qrtr`, `rmtfs`, `pd-mapper`), or vendor services in an LXC Android container (Halium approach).
3. **Old kernel and new GCC.** The 4.4 kernel may not compile with GCC ≥ 10. Use an older container or Google's prebuilt toolchain.
4. **Battery.** A phone kept on a charger 24/7 can swell. Check charge-limit support in the kernel.

## Handy facts
- `fastboot boot <img>` boots an image from RAM without flashing it. A reboot returns to the flashed image.
- macOS supports USB **CDC-ECM** (and NCM) gadgets natively, but not RNDIS. Use ECM for SSH over USB.
- Restoring Android at any point: bootloader mode → factory image `flash-all.sh`.

## Sources
- UBports device page, walleye: https://devices.ubuntu-touch.io/device/walleye/
- UBports walleye xenial page (feature matrix): https://devices.ubuntu-touch.io/device/walleye/release/xenial/
- UBports installer config: https://github.com/ubports/installer-configs/blob/master/v2/devices/walleye.yml
- UBports forum, Pixel 2 installer thread: https://forums.ubports.com/topic/6251/beta-pixel-2-installer-config
- UBports forum, Focal for Pixel 2: https://forums.ubports.com/topic/9438/will-there-be-an-update-for-google-pixel-2-to-ubuntu-touch-ota-2-focal-release
- Liliputing (2021) on Pixel 2 UT port: https://liliputing.com/new-software-for-old-phones-pixel-2-gets-android-12-and-ubuntu-touch-ports/
- postmarketOS wiki, Pixel 2 XL: https://wiki.postmarketos.org/wiki/Google_Pixel_2_XL_(google-taimen)
- postmarketOS wiki, MSM8998: https://wiki.postmarketos.org/wiki/Qualcomm_Snapdragon_835_(MSM8998)
- postmarketOS 2025-09 update (maintainer change): https://postmarketos.org/blog/2025/10/12/pmOS-update-2025-09/
- Pixel 2 XL mainline DTS patch (2021): https://lore.kernel.org/phone-devel/20210305213235.398252-1-caleb@connolly.tech/T/
- Unofficial taimen fork: https://github.com/porthole-dev/pmaports
- Pixel 2 bootloader unlock issues (2017): https://9to5google.com/2017/11/22/google-fix-pixel-2-locked-bootloader-how-to-enable/
- CalyxOS on Verizon Pixels: https://calyxos.org/install/verizon/
- Google factory images: https://developers.google.com/android/images#walleye
