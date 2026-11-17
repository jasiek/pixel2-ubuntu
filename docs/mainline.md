# Mainline kernel for walleye: research (2026-11-17, P8.3)

Two web research passes (kernel trees + boot method; per-subsystem driver support). Summary with sources; "unconfirmed" = not verified.

## Bottom line
- **Nobody has publicly booted mainline on walleye.** No upstream `msm8998-google-*` DTS (torvalds 7.4-rc3). No Nura (ex-postmarketOS, renamed Sep 2026) walleye page or package; the old msm8998 pmOS kernel (6.0) was archived 2026-06-22.
- Best starting point: **Porthole** `porthole-dev/pmaports`, branch `taimen-bringup`, package `device/testing/linux-postmarketos-qcom-msm8998-7.2` = kernel.org **v7.2.2 + ~180 patches** (last push 2026-10-14). Patch 0029 adds `msm8998-google-walleye.dts`, "nobody has run this branch on an actual walleye device yet"; it inherits taimen's panel (`lg,sw43402`, wrong for walleye) and touch (ftm4, wrong).
  - https://github.com/porthole-dev/pmaports/tree/taimen-bringup
- Taimen itself (Nura wiki, 5.10): boots, USB networking yes, screen no, battery no.

## Boot method (taimen evidence)
- Boot image header v0, same offsets as ours; kernel with appended DTB.
- DTB: `qcom,msm-id = <0x124 0x20001>` (same as our factory DTB), no board-id; **no `bootargs` in /chosen** (the bootloader appends to it).
- **dtbo is the hard part:** the bootloader applies an overlay from the `dtbo` partition to the kernel DTB. Erasing dtbo hangs the bootloader; it also refuses to boot without an overlay with the expected id. Taimen fix: flash a crafted dtbo.img with an empty stub overlay carrying that id (taimen 2704). Unconfirmed whether `fastboot boot` of a mainline kernel works with the **stock** dtbo still flashed (stock overlay targets downstream nodes; likely fails).
  - https://gitlab.com/kcxt/dtbo-google-wahoo-mainline
- Cmdline (Porthole): `clk_ignore_unused earlycon=msm_serial_dm,0xc1b0000 panic=10 reboot=w`. SoC notes: remove CoreSight nodes; USB needs `CONFIG_NVMEM_QCOM_QFPROM`.
- No lk2nd needed (none used on taimen).

## Subsystems in mainline (msm8998)
| Part | Status | Notes |
|---|---|---|
| USB gadget | works | dwc3-qcom + qusb2 (5.1); wahoo USB2 only |
| UFS | works | 5.1 |
| Charger | works | pmi8998 SMB2 (6.5); charge-disable for limits 7.1 |
| RGB LED | works | leds-qcom-lpg (5.19/6.0) |
| Buttons, tsens | works | |
| Wifi (WCN3990) | partial, **main risk** | needs working modem (MSS); taimen needed a 120 MiB modem carveout, fixed MSA carveout, 5 GHz capped (ch 169/173 crash fw), 10+ ath10k fixes; a bad MSS/MSA setup bootlooped / hung boots |
| Modem / QRTR | partial | q6v5-mss 5.5; no IPA node in msm8998.dtsi (no data path) |
| Display | partial | DPU ok; **no S6E3FA5 panel driver** upstream (old out-of-tree one for OnePlus 5); simplefb might work (walleye has no DSC) |
| Touch | likely | Synaptics at i2c5 0x20 → rmi4 (unconfirmed) |
| Fuel gauge | out of tree | `qcom_fg` (Porthole) |
| cpufreq | **missing upstream** | CPUs stay at bootloader clock; Porthole carries CPRh/OSM |

## Risks for this phone
1. Wifi depends on Pixel-specific modem memory setup; found on taimen, untested on walleye.
2. Walleye DTS untested; panel/touch/battery nodes wrong (inherited from taimen).
3. Testing needs a crafted dtbo flashed, which the current downstream Ubuntu also depends on (its panel overlay).
