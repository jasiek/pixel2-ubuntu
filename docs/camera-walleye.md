# Camera on walleye (Pixel 2) mainline: port from taimen

Status: research only. Nothing here has been booted. Target is Linux 7.2.2 plus
the Porthole patches (`build/mainline/src`). The board DTS is
`kernel/mainline/msm8998-google-walleye-ubuntu.dts`.

Bottom line: walleye's camera wiring matches taimen's almost exactly. Both
phones use the same sensors, CCI masters, I2C addresses, CSIPHY/CSID indices,
4-lane links, MCLK and reset GPIOs, PMIC enable GPIOs, the Easel bypass routing,
the laser and the flash LED channels. These are the differences that matter:

| # | Item | taimen | walleye |
|---|------|--------|---------|
| 1 | Sensor mount angle (vendor) | rear 270, front 90 | rear 90, front 270 (rotated 180 deg for both) |
| 2 | MCLK0/MCLK1 pad drive strength | 2 mA | 8 mA |
| 3 | pm8998 GPIO20 (rear DVDD enable) VIN select | 0 | 1 |
| 4 | Boot level of pm8998 GPIO15/19 and pmi8998 GPIO3/6 (`qcom,invert`) | 0 (low) | 1 (high, so those rails are on until the camera stack first powers down) |
| 5 | Front AVDD nominal | 2.7 V (label) | 2.85 V |
| 6 | Rear AVDD nominal | 2.8 V (label) | 2.85 V |
| 7 | PCIe PHY sequence | SoC default | SoC v2 default plus one extra write, `0x21c = 0x2d` (QSERDES TX_DRV_LVL) |
| 8 | Calibration EEPROM library names | `onsemi_lc898123f40xc`, `primax_g802l` | `sony_imx362`, `sony_imx179` (same I2C addresses and the same read protocol) |

## Sources and how to cite them

| Tag | File |
|-----|------|
| TDTS | `build/mainline/src/arch/arm64/boot/dts/qcom/msm8998-google-taimen.dts` (Porthole, working camera) |
| WAHOO | `build/mainline/src/arch/arm64/boot/dts/qcom/msm8998-google-wahoo.dtsi` |
| SOC | `build/mainline/src/arch/arm64/boot/dts/qcom/msm8998.dtsi` |
| WDTS | `kernel/mainline/msm8998-google-walleye-ubuntu.dts` |
| DTBO | Walleye factory `dtbo.img`, index 3, decompiled to the scratchpad as `walleye-dtbo3.dts`. Index 3 is the one the bootloader picks (`androidboot.dtbo_idx=3`, `docs/device-info.md:62`). Phandles were resolved through `__fixups__` (DTBO:5270-5408). |
| XA | `external/kernel-msm/arch/arm64/boot/dts/htc/msm8998-camera-sensor-muskie-xa.dtsi` (included by `msm8998-v2.1-htc_mw-common-overlay.dtsi:20`, which `overlay-walleye-xd_xe_a.dts:16` includes) |
| HEASEL | `external/kernel-msm/arch/arm64/boot/dts/htc/msm8998-htc-easel.dtsi` (included by the same common overlay at line 19) |
| HLASER | `external/kernel-msm/arch/arm64/boot/dts/htc/msm8998-camera-laser-muskie.dtsi` |
| TCAM | `external/kernel-msm/arch/arm64/boot/dts/lge/msm8998-taimen-camera.dtsi` |
| TEASEL | `external/kernel-msm/arch/arm64/boot/dts/lge/msm8998-taimen-easel.dtsi` |
| VEND | Walleye factory `firmware/vendor.img` (RP1A.201005.004.A1), extracted read-only with `7zz`. Offsets are file offsets inside the named library. |
| DMESG | The downstream 4.4 boot log of this walleye, `dmesg-live.txt` in the session scratchpad. The scratchpad is temporary, so the relevant lines are quoted below. |

DTBO path abbreviations: `f127/camera@0` means
`/fragment@127/__overlay__/qcom,camera@0`. Fragment 127 targets `&cci`
(DTBO:5271). Fragment 0 (DTBO:5-80) is Qualcomm's MTP reference camera from
`htc/base-msm8998-camera-sensor-mtp.dtsi`. It gives BOB for VANA, S3 for VDIG
and **tlmm 27** for VAF. Fragment 127 later overrides the same `qcom,camera@0`
properties, so **do not copy anything from fragment 0**: tlmm 27 is Easel's
READY line on this phone.

How the vendor GPIO lists were resolved: in `gpios = <PH n 0 ...>`, the byte
offsets 0 and 12 are fixed up to `tlmm`. Offsets 24, 36, 48, 60 and 72 are
fixed up to `pm8998_gpios` for camera@0 and eeprom@0. For camera@1 and
eeprom@1, offsets 24 and 36 go to `pmi8998_gpios` (DTBO:5272, 5282, 5381).

## A. Per-camera mapping

### A.1 Rear: Sony IMX362 (CameraId 0, BACK)

| Item | taimen | walleye | walleye source |
|------|--------|---------|----------------|
| Sensor part | IMX362 (TDTS:1155) | IMX362 | VEND `/etc/camera/camera_config.xml:92` |
| CCI master | 0 (TCAM:195; TDTS:1126 `&cci_i2c0`) | 0 | DTBO:4513 (`f127/camera@0 qcom,cci-master`); XA:404 |
| I2C address (7-bit) | 0x1a (TDTS:1152-1157) | 0x1a (vendor 8-bit 0x34) | VEND `lib/libmmcamera_imx362.so` @0x1080 = `0x34`; i2c_freq_mode 3 and addr_type 2 follow it |
| Chip ID | reg 0x0016 = 0x0362 | same | VEND `libmmcamera_imx362.so` @0x1090 = `16 00 62 03` |
| CSIPHY / CSID | 0 / 0 (TDTS:932-936) | 0 / 0 | DTBO:4483-4484; XA:358-359; VEND camera_config.xml:102 |
| Lanes | 4 (TDTS:934-940) | 4 (LaneMask 0x1F, LaneAssign 0x4320) | VEND camera_config.xml:103-104 |
| Link frequency | 685 MHz (op_pixel_clk 548 MHz x 10 / 8) (TDTS:1190-1194) | same op_pixel_clk, 548 MHz | VEND `libmmcamera_imx362.so` @0xa9498 = 548000000 |
| MCLK | MCLK0, gpio13 `cam_mclk`, 24 MHz, pad 2 mA (TCAM:105-108; SOC:2423-2428) | MCLK0, gpio13, 24 MHz (`0x16e3600`), **pad 8 mA** | DTBO:4268-4278 (pinctrl), DTBO:4501 (gpio 0x0d), DTBO:4515-4517 (clocks and rate); XA:142-155 |
| Reset | tlmm 24, active low (TDTS:1177) | tlmm 24, active low | DTBO:4501 (2nd entry `0x18`); DTBO:4211-4231 pinctrl `output-low`; VEND power sequence @0x1098 drives RESET low, then high after the rails |
| VIO 1.8 V | pm8998 LVS1 (TDTS:1182) | pm8998 LVS1, 1.8 V | DTBO:4490 + fixup `pm8998_lvs1` (DTBO:5275); DTBO:4494 min `0x1b7740` |
| VDIG (DVDD) | pm8998 GPIO20, 1.05 V (TDTS:1018-1027; TCAM:172) | pm8998 GPIO20, 1.05 V; **VIN select 1** | DTBO:4492 (`cam_vdig-supply = <pm8998_gpios 0x14>`), DTBO:4494 (`0x100590` = 1050000), DTBO:4605 (`gpio@d300 qcom,vin-sel = <1>`); XA:367-369, 504 |
| VANA (AVDD) | pm8998 GPIO15, 2.8 V label (TDTS:1029-1038; TCAM:173) | pm8998 GPIO15, **2.85 V**; boot level high | DTBO:4491, 4494 (`0x2b7cd0` = 2850000), DTBO:4587 (`gpio@ce00 invert = 1`); XA:366, 369, 486 |
| VANA2 (A1V8) | pm8998 GPIO19, 1.8 V (TDTS:1040-1049; TCAM:174) | pm8998 GPIO19, label "CAM1_A1V8"; boot level high | DTBO:4501 (6th entry `0x13`), DTBO:4506 (`gpio-custom1 = <5>`), DTBO:4510 (label), DTBO:4597 (`invert = 1`). Voltage is from the label only: UNCONFIRMED 1.8 V |
| VDRV (OIS driver) | pm8998 GPIO9, 2.8 V (TDTS:1051-1060; TCAM:175) | pm8998 GPIO9, label "CAM1_DRV" | DTBO:4501 (7th entry `0x09`), DTBO:4507, DTBO:4567. Voltage UNCONFIRMED (taimen label 2.8 V) |
| VAF (VCM) | pm8998 GPIO10, 2.85 V (TDTS:1062-1071; TCAM:176) | pm8998 GPIO10, label "CAM1_VAF" | DTBO:4501 (5th entry `0x0a`), DTBO:4505 (`gpio-vaf = <4>`), DTBO:4577. Voltage UNCONFIRMED (taimen label 2.85 V) |
| Vendor power-up order | drv, vaf, vdig, vio, vana, vana2, reset, MCLK, 9 ms (imx362.c:450-460) | identical | VEND `libmmcamera_imx362.so` @0x1098-0x1127: RESET low, CUSTOM2(drv), VAF, VDIG, VREG VIO, VANA, CUSTOM1(vana2), RESET high, CLK 24 MHz with delay 9 |
| Mount angle (vendor) | 270 (TCAM:155) | **90** | DTBO:4485 (`0x5a`); XA:360; VEND camera_config.xml:100 |
| VSYNC pin (vendor only) | not in TCAM | gpio80, input | DTBO:4326-4357; XA:204-231. Not used by mainline |

### A.2 Front: Sony IMX179 (CameraId 1, FRONT)

| Item | taimen | walleye | walleye source |
|------|--------|---------|----------------|
| Sensor part | IMX179 (TDTS:1244) | IMX179 | VEND camera_config.xml:118 |
| CCI master | 1 (TCAM:237) | 1 | DTBO:4548; XA:452 |
| I2C address (7-bit) | 0x10 (TDTS:1236-1246, marked "bring-up guess", proven working) | 0x10 (vendor 8-bit 0x20) | VEND `lib/libmmcamera_imx179.so` @0x7c8 = `0x20`; chip-ID reg 0x0002 = 0x0179, mask 0x0fff at @0x7d8 |
| CSIPHY / CSID | 1 / 1 (TDTS:916-917) | 1 / 1 | DTBO:4524-4525; XA:416-417; VEND camera_config.xml:125 |
| Lanes | 4 (TDTS:918-929) | 4 (LaneMask 0x1F) | VEND camera_config.xml:126-127 |
| Link frequencies | 170/270/324 MHz (TDTS:1303-1313) | same op_pixel_clk table location | VEND `libmmcamera_imx179.so` @0xa8be0 = 259200000 and @0xa8ca0 = 136000000. These sit at the same offsets the taimen comment cites (0xa8bc8), so it is very likely the same library |
| MCLK | MCLK1, gpio14, 24 MHz, pad 2 mA (TCAM:143-146; SOC:2430-2435) | MCLK1, gpio14, 24 MHz, **pad 8 mA** | DTBO:4297-4307, DTBO:4539, DTBO:4550-4552; XA:173-184 |
| Reset | tlmm 23, active low (TDTS:1293) | tlmm 23, active low | DTBO:4539 (2nd entry `0x17`); DTBO:4241-4261; VEND power sequence @0x7e0 drives RESET low first |
| VIO 1.8 V | pm8998 LVS1 (TDTS:1295) | pm8998 LVS1 | DTBO:4529 + fixup DTBO:5275 |
| VDIG (DVDD) 1.2 V | pmi8998 GPIO6 (TDTS:987-996; TCAM:223) | pmi8998 GPIO6, 1.2 V; boot level high | DTBO:4528 (`<pmi8998_gpios 0x06>`), DTBO:4532 (`0x124f80`), DTBO:4634 (`gpio@c500 invert = 1`); XA:422, 426, 528 |
| VANA (AVDD) | pmi8998 GPIO3, 2.7 V label (TDTS:998-1007; TCAM:224) | pmi8998 GPIO3, **2.85 V**; boot level high | DTBO:4530, DTBO:4532 (`0x2b7cd0`), DTBO:4624 (`gpio@c200 invert = 1`); XA:424, 426, 518 |
| Vendor power-up order | VANA, VDIG, VIO, reset release, MCLK (imx179.c:31-41) | identical | VEND `libmmcamera_imx179.so` @0x7e0-0x83f |
| Mount angle (vendor) | 90 (TCAM:209) | **270** | DTBO:4526 (`0x10e`); XA:418; VEND camera_config.xml:123 |
| VSYNC pin (vendor only) | not in TCAM | gpio63 | DTBO:4359-4390; XA:233-260 |

### A.3 Rear module peripherals and shared parts

| Item | taimen | walleye | walleye source |
|------|--------|---------|----------------|
| AF actuator | LC898214XD, CCI0, 0x72 (vendor 0xE4) (TDTS:1126-1136) | LC898214XD, CCI0, vendor 0xE4, so 0x72 | VEND camera_config.xml:93; VEND `lib/libactuator_lc898214xd.so` @0x48c = `0xe4`. DTBO `f127/actuator@10` (DTBO:4400-4407) carries no address |
| AF supply | cam0_vaf, switched by the sensor (lc898214xd.c:147-157) | pm8998 GPIO10 | as above |
| OIS | LC898123F40, CCI0, 0x3e (vendor 0x7C) (TDTS:1138-1149) | LC898123F40, CCI0, vendor 0x7C, so 0x3e | VEND camera_config.xml:95; VEND `lib/libois_lc898123f40.so` @0x43c = `0x7c`; DTBO `f127/ois@10` (DTBO:4409-4417) status ok |
| OIS supplies | vdd = LVS1, vdrv = cam0_drv (TDTS:1147-1148) | same rails (GPIO9 = "CAM1_DRV") | DTBO:4507, 4510 |
| Rear calibration EEPROM | Inside the OIS flash: I2C 0x7C, word index written to 0xF01B, data read back from 0xF01B, starting at word 0x1A00 (lc898123f40.c:22-26). Vendor lib `onsemi_lc898123f40xc` | **Same protocol and address.** Vendor lib is named `sony_imx362` | VEND `lib/libmmcamera_sony_imx362_eeprom.so` @0x3a78 = `0x7c`, followed by reads of `0xf01b` with `0x1a00`, `0x1a01`, and so on. DTBO `f127/eeprom@0` (DTBO:4419-4450) is generic `qcom,eeprom` |
| Front calibration EEPROM | 24c32-class at 0x51, 16-bit address, 0x758 bytes, read-only (TDTS:1223-1234). Vendor lib `primax_g802l` | **0x51 (vendor 0xA2), 16-bit address, 0x758 bytes.** Vendor lib is named `sony_imx179` | VEND `lib/libmmcamera_sony_imx179_eeprom.so` @0x17b4 = `0xa2`, @0x17bc = 2 (word address), @0x17c0 = `0x758`; DTBO `f127/eeprom@1` (DTBO:4452-4477) is on CCI1 |
| Flash LED | PMI8998 flash: flash0+flash1 ganged, torch0+torch1, switch0 (TDTS:243-261; TCAM:36-44) | identical source set | DTBO:4136-4146 (`f126/qcom,camera-flash@10`), fixups DTBO:5394-5398; XA:15-22. Downstream per-channel ceilings: flash 1500 mA, torch 200 mA (`qcom/msm-pmi8998.dtsi:689`, `:728`) |
| Laser ToF | ST VL53L0 at blsp2_i2c3 (downstream i2c_9) 0x29, vdd = l19, XSHUT gpio39 (active low), INT gpio62 (TDTS:814-838) | identical | DTBO:3092-3108 (`f87/wahoo_laser@29`; pwdn `0x27`, intr `0x3e`); `power_2v8-supply` = pm8998_l19 (DTBO:5375); `CAMIO_1v8` = LVS1 (DTBO:5275); target i2c_9 (DTBO:5359); HLASER:33-46. Live: DMESG `[LASER] Laser_parse_dt: pwdn_gpio = 39`, `laser_irq_gpio = 62`, `Misc device registration name:9-0029`, `read REVISION_ID: 0x10` (cut 1.1) |
| l19 voltage | 3.008 V fixed (WAHOO:334-337) | vendor range 2.85-3.008 V | DTBO:2615-2621 (fragment@77 targets pm8998_l19: `0x2b7cd0`-`0x2de600`); `htc/msm8998-htc-regulator.dtsi:17-20` |
| CCI pins | gpio17/18 (M0), gpio19/20 (M1), `cci_i2c`, pull-up, 2 mA (SOC:2402-2414) | identical | DTBO:4150-4205; XA:25-81 |
| CSIPHY rails | vdda = l2 1.2 V, vdd_sec = l1 0.88 V (TDTS:904-912) | same SoC; no walleye override | none board-specific. These are SoC rails, shared with DSI, UFS and PCIe PHYs (WAHOO:420-421, 581-582) |

## B. Easel

**Yes. Walleye's cameras go through Easel exactly as taimen's do.** The
evidence:

1. Walleye's DTBO carries the full Easel description. pcie0 (fragment@121,
   DTBO:3875-3885) has the same `reg`/`ranges` windows downstream taimen uses.
   The BCM15602 PMIC sits on i2c_9 at 0x08 (fragment@123, DTBO:4015-4048), and
   mnh-sm and mnh-spi are present (fragments 124/125, DTBO:4050-4093). The HTC
   source for all of this is HEASEL, and it differs from TEASEL only by the
   PCIe PHY sequence (diff of the two files).
2. Easel enumerates on walleye: DMESG lines 882-883 and 962-985:
   `bcm15602 9-0008: Part: 0x5602, Rev: 2, Vendor Rev: 0x21`,
   `msm_pcie_enable: PCIe RC0 link initialized`,
   `pci 0000:01:00.0: [8086:3140]`, then BAR0 4 KB (`reg 0x10`), BAR2 8 MB
   (`reg 0x18`) and BAR4 4 MB (`reg 0x20`). These are the BAR sizes the taimen
   comment at TDTS:723 plans for. The Porthole BCM15602 driver checks part ID
   0x5602 (patch 0016, line 110), and walleye reports 0x5602.
3. The RX-to-TX routing matches. Walleye's own vendor
   `lib64/libeaselcontrol.amber.so`, `EaselControlClient::startMipi` at
   0xe3c0-0xe3d4, builds `EaselMipiConfig{rx = tx = (camera != 0)}`. So rear
   (camera 0) is RX0 to TX0 and front (camera 1) is RX1 to TX1. That is exactly
   what `easel-mipi.c` assumes (patch 0015, lines 132-139; `bypass = 0x3`), and
   what the sensor drivers hardcode (`easel_mipi_set_rate(0, ...)` and
   `easel_mipi_kick(0)` in imx362.c:901/933; link index 1 in imx179.c:902/937).
   Walleye's Easel DT (`VEND /firmware/easel/mnh.dtb`) declares the same TX0,
   TX1 and RX0-2 blocks at 0x04010000-0x04014000. On the AP side, TX0 lands on
   CSIPHY0 and TX1 on CSIPHY1, consistent with the DTBO's csiphy-sd-index 0/1.

What taimen mainline does for Easel, and the walleye equivalent:

| Taimen mainline (TDTS) | What it does | Walleye value | Walleye source |
|------------------------|--------------|---------------|----------------|
| `&pcie_phy { status = "okay"; }` (711-713) | Enables the QMP PCIe PHY (l1/l2, SOC:1955-1956) | same | SoC |
| `&pcie0` reg/ranges override (747-754) | conf 0x1b010000/128K, io 0x1b030000/128K, BARs 0x1b100000/15M | identical windows | DTBO:3879-3880; HEASEL:21-29 |
| `vddpe-3v3-supply = <&easel_vddpe>` (765) | Delays the host until BCM15602 has powered Easel | same | n/a (mainline construct) |
| `pcie@0 { endpoint-powered-off-in-suspend; }` (767-778) | Avoids the second-s2idle wedge | same; Easel firmware is common | patch 0138 |
| `&blsp2_i2c3` bcm15602@8 (781-812): IRQ gpio26 falling, `pon` gpio25, `resetb` gpio91, clocks LN_BB_CLK2 + DIV_CLK3 | Easel PMIC | identical | DTBO:4020-4030 (`interrupts = <0x1a 2>`, `bcm,pon-gpio 0x19`, `bcm,intb-gpio 0x1a`, `bcm,resetb-gpio 0x5b`), DTBO:4084-4087 (mnh-sm `ref_clk`, `sleep_clk`); HEASEL:218-246, 278-280 |
| `bcm15602_default` pins (840-861): gpio25 bias-disable, gpio26 pull-up, gpio91 pull-down, 2 mA | | identical | DTBO:3890-3943; HEASEL:122-160 |
| `easel_default` (863-877): gpio27 ready (pull-down), gpio28 boot-mode. **Unreferenced** in TDTS | | identical | DTBO:3946-3976, mnh-sm `ready-gpio`/`boot-mode-gpio` DTBO:4092-4093; HEASEL:163-188, 287-288 |
| (not in TDTS) soc-pwr-good / ddr-pad-iso-n | BCM15602 GPIO0/1, driven by the bcm15602 driver | same | DTBO:4090-4091 |
| (not in TDTS) Easel console UART, mnh-spi | Not needed for bypass | blsp1 uart1 on gpio8/9; spi_10 | DTBO:4056-4063, 4071-4081 |
| **(no mainline equivalent)** `qcom,phy-sequence` | Downstream PHY init | **Walleye adds a final write `0x21c = 0x2d`.** It is absent from the SoC v2 table (`qcom/msm8998-v2.dtsi:373`) and from TEASEL. In the 0x1c06000 PHY, 0x200 is the TX block, so this is `QSERDES_V3_TX_TX_DRV_LVL` (`phy-qcom-qmp-qserdes-txrx-v3.h:13`). Mainline `msm8998_pcie_tx_tbl` (`phy-qcom-qmp-pcie.c:164-169`) does not write it | DTBO:3881 (last triple); HEASEL:106 |

## C. Proposed walleye DTS fragment

Append this to `kernel/mainline/msm8998-google-walleye-ubuntu.dts` one milestone
at a time, and RAM-boot each step (`fastboot boot`). Every label used below
already exists in this tree:

- `cci`, `cci_i2c0`, `cci_i2c1`, `camss`, `cam_mclk0_default`,
  `cam_mclk1_default`, `pcie0`, `pcie_phy`, `blsp2_i2c3`: SOC:4504, 4530, 4537,
  4365, 2423, 2430, 1866, 1933, 3717.
- `pmi8998_flash` (pmi8998.dtsi:98), `pm8998_gpios` (pm8998.dtsi:121),
  `pmi8998_gpios` (pmi8998.dtsi:49).
- `vreg_l1a_0p875`, `vreg_l2a_1p2`, `vreg_l19a_3p0`, `vreg_lvs1a_1p8`:
  WAHOO:266, 270, 334, 375.

The headers already included by WDTS and msm8998.dtsi cover `GPIO_*`, `IRQ_*`,
`LED_*`, `RPM_SMD_*` and `CAMSS_*`.

```dts
/* =====================================================================
 * CAMERA M1 -- CCI only. No sensors, no CAMSS.
 * Pins: msm8998.dtsi cci0/cci1_default already match walleye's
 * (gpio17/18, gpio19/20, cci_i2c, pull-up, 2 mA; DTBO:4150-4205, XA:25-81).
 * master 0 = rear, master 1 = front (DTBO:4513, :4548).
 * Do not i2cdetect: sensors are unpowered here.
 * ===================================================================== */
&cci {
	status = "okay";
};

/* =====================================================================
 * CAMERA M2 -- CAMSS, no ports yet (endpoints added in M4/M5).
 * PHY rails as taimen (TDTS:904-912): l2 1.2 V, l1 0.88 V (shared with
 * DSI/UFS/PCIe PHYs -- already on).
 * ===================================================================== */
&camss {
	status = "okay";
	vdda-supply = <&vreg_l2a_1p2>;
	vdd_sec-supply = <&vreg_l1a_0p875>;
};

/*
 * WALLEYE DIFFERENCE: MCLK pads at 8 mA, not the SoC default 2 mA
 * (DTBO:4278 mclk0, DTBO:4307 mclk1; XA:153, :184 "HTC modify 8 MA").
 */
&cam_mclk0_default {
	drive-strength = <8>;
};

&cam_mclk1_default {
	drive-strength = <8>;
};

/* =====================================================================
 * CAMERA M3 -- Easel MIPI bridge (needed for any frame; CCI chip-ID reads
 * work without it). Copied from TDTS:711-878; every walleye value
 * confirmed against DTBO:3875-4093 / HEASEL. Easel enumerates on this
 * phone under 4.4 (DMESG: 8086:3140, BAR 4K/8M/4M).
 * RAM-BOOT ONLY: a mis-sized BAR window hung taimen's fabric (TDTS:727-729).
 * ===================================================================== */
&pcie_phy {
	status = "okay";
};

&pcie0 {
	status = "okay";

	/* Same windows as walleye's DTBO fragment@121 (DTBO:3879-3880). */
	reg = <0x01c00000 0x2000>,
	      <0x1b000000 0xf1d>,
	      <0x1b000f20 0xa8>,
	      <0x1b010000 0x20000>;
	reg-names = "parf", "dbi", "elbi", "config";

	ranges = <0x01000000 0x0 0x1b030000 0x1b030000 0x0 0x20000>,
		 <0x02000000 0x0 0x1b100000 0x1b100000 0x0 0xf00000>;

	vddpe-3v3-supply = <&easel_vddpe>;

	pcie@0 {
		endpoint-powered-off-in-suspend;
	};

	/*
	 * NOT EXPRESSIBLE: walleye's vendor PHY sequence ends with an extra
	 * TX_DRV_LVL = 0x2d (DTBO:3881 last triple; HEASEL:106) that
	 * taimen and the SoC table lack. If link training is flaky on
	 * walleye, that is a driver-table change, not a DT one.
	 */
};

&blsp2_i2c3 {	/* downstream i2c_9 (DTBO fixup i2c_9, :5359) */
	status = "okay";

	bcm15602: pmic@8 {	/* DTBO:4020-4030; HEASEL:218-246 */
		compatible = "brcm,bcm15602";
		reg = <0x08>;

		interrupt-parent = <&tlmm>;
		interrupts = <26 IRQ_TYPE_EDGE_FALLING>;
		interrupt-names = "bcm15602_intb";

		pinctrl-names = "default";
		pinctrl-0 = <&bcm15602_default>;

		pon-gpios = <&tlmm 25 GPIO_ACTIVE_HIGH>;
		resetb-gpios = <&tlmm 91 GPIO_ACTIVE_HIGH>;

		/* mnh-sm ref_clk / sleep_clk (DTBO:4085-4087; HEASEL:278-280) */
		clocks = <&rpmcc RPM_SMD_LN_BB_CLK2>,
			 <&rpmcc RPM_SMD_DIV_CLK3>;
		clock-names = "ref", "sleep";

		regulators {
			easel_vddpe: easel_vddpe {
				regulator-name = "easel_vddpe";
			};
		};
	};
};

&tlmm {
	bcm15602_default: bcm15602-default-state {	/* DTBO:3890-3943 */
		pon-pins {
			pins = "gpio25";
			function = "gpio";
			drive-strength = <2>;
			bias-disable;
		};

		intb-pins {
			pins = "gpio26";
			function = "gpio";
			drive-strength = <2>;
			bias-pull-up;
		};

		resetb-pins {
			pins = "gpio91";
			function = "gpio";
			drive-strength = <2>;
			bias-pull-down;
		};
	};

	/* Unreferenced, as on taimen (TDTS:863); DTBO:3946-3976. */
	easel_default: easel-default-state {
		ready-pins {
			pins = "gpio27";
			function = "gpio";
			drive-strength = <2>;
			bias-pull-down;
		};

		boot-mode-pins {
			pins = "gpio28";
			function = "gpio";
			drive-strength = <2>;
			bias-disable;
		};
	};
};

/* =====================================================================
 * CAMERA M4 -- front sensor IMX179 + its EEPROM.
 * Rails are PMIC-GPIO-switched (1-based numbering, as TDTS:977-983).
 * Enables are active-high: the vendor lib drives them HIGH to power up
 * (VEND libmmcamera_imx179.so @0x7f0/@0x800, config 2 = GPIO_OUT_HIGH).
 * The vendor DTBO only sets their BOOT level high (invert=1, DTBO:4624,
 * :4634); here they start low -- see risks.
 * ===================================================================== */
/ {
	cam1_dvdd: regulator-cam1-dvdd {
		compatible = "regulator-fixed";
		regulator-name = "cam1_dvdd_1v2";	/* DTBO:4532 */
		regulator-min-microvolt = <1200000>;
		regulator-max-microvolt = <1200000>;
		gpio = <&pmi8998_gpios 6 GPIO_ACTIVE_HIGH>;	/* DTBO:4528 */
		enable-active-high;
		pinctrl-names = "default";
		pinctrl-0 = <&cam1_dvdd_en>;
	};

	cam1_avdd: regulator-cam1-avdd {
		compatible = "regulator-fixed";
		/* 2.85 V per walleye (DTBO:4532, XA:426); taimen said 2.7 V.
		 * Informational only: imx179.c never sets a voltage. */
		regulator-name = "cam1_avdd_2v85";
		regulator-min-microvolt = <2850000>;
		regulator-max-microvolt = <2850000>;
		gpio = <&pmi8998_gpios 3 GPIO_ACTIVE_HIGH>;	/* DTBO:4530 */
		enable-active-high;
		pinctrl-names = "default";
		pinctrl-0 = <&cam1_avdd_en>;
	};
};

&pmi8998_gpios {
	/* DTBO:4629-4636 gpio@c500: mode out, no pull, vin-sel 0 */
	cam1_dvdd_en: cam1-dvdd-en-state {
		pins = "gpio6";
		function = "normal";
		bias-disable;
		drive-push-pull;
		output-low;
		power-source = <0>;
		qcom,drive-strength = <1>;	/* UNCONFIRMED: copied from TDTS */
	};

	/* DTBO:4619-4626 gpio@c200: same */
	cam1_avdd_en: cam1-avdd-en-state {
		pins = "gpio3";
		function = "normal";
		bias-disable;
		drive-push-pull;
		output-low;
		power-source = <0>;
		qcom,drive-strength = <1>;	/* UNCONFIRMED: copied from TDTS */
	};
};

&camss {
	ports {
		/* CSIPHY1/CSID1 (DTBO:4524-4525), 4 lanes (camera_config.xml:126) */
		port@1 {
			reg = <1>;
			camss_ep_front: endpoint {
				clock-lanes = <7>;
				data-lanes = <0 1 2 3>;
				remote-endpoint = <&imx179_ep>;
			};
		};
	};
};

&cci_i2c1 {
	/* VEND libmmcamera_sony_imx179_eeprom.so @0x17b4: 0xA2 -> 0x51,
	 * 16-bit addressed, 0x758 bytes. Same as taimen (TDTS:1229). */
	eeprom@51 {
		compatible = "atmel,24c32";
		reg = <0x51>;
		vcc-supply = <&vreg_lvs1a_1p8>;
		read-only;
	};

	/* VEND libmmcamera_imx179.so @0x7c8: 0x20 -> 0x10 */
	imx179: camera@10 {
		compatible = "sony,imx179";
		reg = <0x10>;

		orientation = <0>;
		/*
		 * UNCONFIRMED. Vendor mount angle is 270 here (DTBO:4526,
		 * camera_config.xml:123) vs 90 on taimen (TCAM:209), whose
		 * owner-verified mainline value is 90 (TDTS:1250-1256). The
		 * module is turned 180 deg relative to taimen, hence 270.
		 * Verify on the live viewfinder (mind the selfie mirror).
		 */
		rotation = <270>;

		clocks = <&mmcc CAMSS_MCLK1_CLK>;	/* no assigned-clocks: TDTS:1270-1278 */
		power-domains = <&mmcc CAMSS_TOP_GDSC>;

		pinctrl-names = "default";
		pinctrl-0 = <&cam_mclk1_default>;

		reset-gpios = <&tlmm 23 GPIO_ACTIVE_LOW>;	/* DTBO:4539 */

		vio-supply = <&vreg_lvs1a_1p8>;			/* DTBO:4529 */
		vdig-supply = <&cam1_dvdd>;
		vana-supply = <&cam1_avdd>;

		port {
			imx179_ep: endpoint {
				clock-lanes = <7>;
				data-lanes = <0 1 2 3>;
				/* same op_pixel_clk table as taimen
				 * (VEND @0xa8be0 / @0xa8ca0) */
				link-frequencies = /bits/ 64 <170000000 270000000 324000000>;
				remote-endpoint = <&camss_ep_front>;
			};
		};
	};
};

/* =====================================================================
 * CAMERA M5 -- rear sensor IMX362.
 * ===================================================================== */
/ {
	cam0_dvdd: regulator-cam0-dvdd {
		compatible = "regulator-fixed";
		regulator-name = "cam0_dvdd_1v05";		/* DTBO:4494 */
		regulator-min-microvolt = <1050000>;
		regulator-max-microvolt = <1050000>;
		gpio = <&pm8998_gpios 20 GPIO_ACTIVE_HIGH>;	/* DTBO:4492 */
		enable-active-high;
		pinctrl-names = "default";
		pinctrl-0 = <&cam0_dvdd_en>;
	};

	cam0_avdd: regulator-cam0-avdd {
		compatible = "regulator-fixed";
		regulator-name = "cam0_avdd_2v85";		/* DTBO:4494, XA:369 */
		regulator-min-microvolt = <2850000>;
		regulator-max-microvolt = <2850000>;
		gpio = <&pm8998_gpios 15 GPIO_ACTIVE_HIGH>;	/* DTBO:4491 */
		enable-active-high;
		pinctrl-names = "default";
		pinctrl-0 = <&cam0_avdd_en>;
	};

	cam0_avdd2: regulator-cam0-avdd2 {
		compatible = "regulator-fixed";
		regulator-name = "cam0_avdd2_1v8";		/* "CAM1_A1V8", DTBO:4510 */
		regulator-min-microvolt = <1800000>;		/* UNCONFIRMED (name only) */
		regulator-max-microvolt = <1800000>;
		gpio = <&pm8998_gpios 19 GPIO_ACTIVE_HIGH>;	/* DTBO:4501 #6 */
		enable-active-high;
		pinctrl-names = "default";
		pinctrl-0 = <&cam0_avdd2_en>;
	};

	cam0_drv: regulator-cam0-drv {
		compatible = "regulator-fixed";
		regulator-name = "cam0_ois_drv";		/* "CAM1_DRV", DTBO:4510 */
		regulator-min-microvolt = <2800000>;		/* UNCONFIRMED (taimen label) */
		regulator-max-microvolt = <2800000>;
		gpio = <&pm8998_gpios 9 GPIO_ACTIVE_HIGH>;	/* DTBO:4501 #7 */
		enable-active-high;
		pinctrl-names = "default";
		pinctrl-0 = <&cam0_drv_en>;
	};

	cam0_vaf: regulator-cam0-vaf {
		compatible = "regulator-fixed";
		regulator-name = "cam0_vaf";			/* "CAM1_VAF", DTBO:4510 */
		regulator-min-microvolt = <2850000>;		/* UNCONFIRMED (taimen label) */
		regulator-max-microvolt = <2850000>;
		gpio = <&pm8998_gpios 10 GPIO_ACTIVE_HIGH>;	/* DTBO:4501 #5 */
		enable-active-high;
		pinctrl-names = "default";
		pinctrl-0 = <&cam0_vaf_en>;
	};
};

&pm8998_gpios {
	/* WALLEYE DIFFERENCE: vin-sel 1 (DTBO:4605 gpio@d300; XA:504).
	 * taimen uses 0 (TCAM:313, TDTS:1081). */
	cam0_dvdd_en: cam0-dvdd-en-state {
		pins = "gpio20";
		function = "normal";
		bias-disable;
		drive-push-pull;
		output-low;
		power-source = <1>;
		qcom,drive-strength = <1>;	/* UNCONFIRMED: copied from TDTS */
	};

	cam0_avdd_en: cam0-avdd-en-state {	/* DTBO:4582-4589, vin-sel 0 */
		pins = "gpio15";
		function = "normal";
		bias-disable;
		drive-push-pull;
		output-low;
		power-source = <0>;
		qcom,drive-strength = <1>;
	};

	cam0_avdd2_en: cam0-avdd2-en-state {	/* DTBO:4592-4599, vin-sel 0 */
		pins = "gpio19";
		function = "normal";
		bias-disable;
		drive-push-pull;
		output-low;
		power-source = <0>;
		qcom,drive-strength = <1>;
	};

	cam0_drv_en: cam0-drv-en-state {	/* DTBO:4562-4569, vin-sel 0 */
		pins = "gpio9";
		function = "normal";
		bias-disable;
		drive-push-pull;
		output-low;
		power-source = <0>;
		qcom,drive-strength = <1>;
	};

	cam0_vaf_en: cam0-vaf-en-state {	/* DTBO:4572-4579, vin-sel 0 */
		pins = "gpio10";
		function = "normal";
		bias-disable;
		drive-push-pull;
		output-low;
		power-source = <0>;
		qcom,drive-strength = <1>;
	};
};

&camss {
	ports {
		/* CSIPHY0/CSID0 (DTBO:4483-4484), 4 lanes (camera_config.xml:103) */
		port@0 {
			reg = <0>;
			camss_ep_rear: endpoint {
				clock-lanes = <7>;
				data-lanes = <0 1 2 3>;
				remote-endpoint = <&imx362_ep>;
			};
		};
	};
};

&cci_i2c0 {
	/* VEND libmmcamera_imx362.so @0x1080: 0x34 -> 0x1a */
	imx362: camera@1a {
		compatible = "sony,imx362";
		reg = <0x1a>;

		orientation = <1>;
		/*
		 * UNCONFIRMED. Vendor mount angle 90 (DTBO:4485,
		 * camera_config.xml:100) vs 270 on taimen (TCAM:155), where
		 * mainline uses 90 (TDTS:1168-1169). Rotated 180 deg -> 270.
		 */
		rotation = <270>;

		clocks = <&mmcc CAMSS_MCLK0_CLK>;
		power-domains = <&mmcc CAMSS_TOP_GDSC>;

		pinctrl-names = "default";
		pinctrl-0 = <&cam_mclk0_default>;

		reset-gpios = <&tlmm 24 GPIO_ACTIVE_LOW>;	/* DTBO:4501 #2 */

		vdrv-supply = <&cam0_drv>;
		vaf-supply = <&cam0_vaf>;
		vdig-supply = <&cam0_dvdd>;
		vio-supply = <&vreg_lvs1a_1p8>;			/* DTBO:4490 */
		vana-supply = <&cam0_avdd>;
		vana2-supply = <&cam0_avdd2>;

		port {
			imx362_ep: endpoint {
				clock-lanes = <7>;
				data-lanes = <0 1 2 3>;
				/* op_pixel_clk 548 MHz (VEND @0xa9498) * 10 / 8 */
				link-frequencies = /bits/ 64 <685000000>;
				remote-endpoint = <&camss_ep_rear>;
			};
		};
	};
};

/* =====================================================================
 * CAMERA M6 -- lens, OIS, flash, laser.
 * ===================================================================== */
&cci_i2c0 {
	/* VEND libactuator_lc898214xd.so @0x48c: 0xE4 -> 0x72 */
	af_lens: lens@72 {
		compatible = "onnn,lc898214xd";
		reg = <0x72>;
	};

	/* VEND libois_lc898123f40.so @0x43c: 0x7C -> 0x3e. Also holds the
	 * rear calibration (VEND libmmcamera_sony_imx362_eeprom.so @0x3a78). */
	ois@3e {
		compatible = "onnn,lc898123f40";
		reg = <0x3e>;
		vdd-supply = <&vreg_lvs1a_1p8>;
		vdrv-supply = <&cam0_drv>;
	};
};

&imx362 {
	lens-focus = <&af_lens>;
};

/* Same sources as taimen: flash0+flash1, torch0+torch1 (DTBO:4140-4142,
 * fixups :5394-5398). Currents kept at taimen's conservative caps. */
&pmi8998_flash {
	status = "okay";

	led-0 {
		function = LED_FUNCTION_FLASH;
		color = <LED_COLOR_ID_WHITE>;
		led-sources = <1>, <2>;
		led-max-microamp = <300000>;
		flash-max-microamp = <1000000>;
		flash-max-timeout-us = <1280000>;
	};
};

/* Laser ToF: DTBO:3092-3108, HLASER:33-46; live on 4.4 at 9-0029. */
&blsp2_i2c3 {
	proximity@29 {
		compatible = "st,vl53l0x";
		reg = <0x29>;
		vdd-supply = <&vreg_l19a_3p0>;		/* DTBO:5375; keep 3.008 V */
		reset-gpios = <&tlmm 39 GPIO_ACTIVE_LOW>;
		interrupt-parent = <&tlmm>;
		interrupts = <62 IRQ_TYPE_EDGE_FALLING>;
		pinctrl-names = "default";
		pinctrl-0 = <&laser_xshut_default>;
	};
};

&tlmm {
	laser_xshut_default: laser-xshut-default-state {	/* DTBO:3067-3075 */
		pins = "gpio39";
		function = "gpio";
		drive-strength = <2>;
		bias-disable;
	};
};
```

Notes on the fragment:

- M3 must be in the DTB before the sensor **streams**. M4 and M5 can probe
  (chip-ID read over CCI) without it.
- The `easel-mipi` defaults (`bypass=0x3`, `front_rate=648`, `rear_rate=1368`,
  `front_rx=front_tx=1`; patch 0015, lines 139-165) are right for walleye too.
  The routing is confirmed in section B. The rates come from the same
  op_pixel_clk values found in walleye's sensor libraries.
- `CONFIG_EASEL_MIPI=y`, `CONFIG_REGULATOR_BCM15602_EASEL=y` and
  `CONFIG_PCIE_QCOM=y` are built in (`build/mainline/out/.config:1846, 3189,
  1626`). So M3 runs PCIe link-up, BAR assignment and the bridge probe during
  boot, not on a later modprobe.

## D. Risks

### Hang or boot-failure risks

1. **PCIe/Easel (M3).** On taimen, a wrong BAR window left the BARs at 0, and
   the first MMIO access hung the bus until the watchdog fired, three times
   (TDTS:723-729). Taimen also wedged on the second s2idle cycle without
   `endpoint-powered-off-in-suspend` (patch 0138). Walleye has hung before
   without a watchdog (WDTS:151-156; `docs/log.md:177`). Mitigations:
   - Copy the windows exactly.
   - RAM-boot only.
   - Consider building `easel-mipi` as `=m` for walleye bring-up. The
     driver's own commit message (patch 0015, lines 26-28) argues for a
     module: "a built-in driver that touches an unresponsive Easel would hang
     the boot".
2. **Walleye-only PCIe PHY TX drive level** (`0x21c = 0x2d`, DTBO:3881) is
   not applied by mainline. Expected symptom is marginal link training or AER
   errors, not damage. The fix would be a board quirk in
   `phy-qcom-qmp-pcie.c`, not a DT property.
3. **Reset/MCLK ordering for the front sensor.** imx179.c enables MCLK before
   releasing reset, which is the opposite of the vendor (imx179.c:31-45). It is
   proven on taimen, and walleye's vendor sequence is byte-for-byte the same
   shape, so the risk is no worse than on taimen.

### Rails

4. **None of the camera rails is on l28, l22 or l14.**
   - Sensors, actuator and OIS use PMIC-GPIO-switched board rails plus LVS1
     (DTBO:4490-4492, 4528-4530; fixups 5275, 5282, 5381).
   - l22 and l14 are display only on walleye (DTBO:5382-5383; WDTS:117-140).
   - l28 is touch only (DTBO:5405, fragment@139 at DTBO:4907-4917, 3.3 V
     always-on in the vendor build; WDTS:151-156 keeps 3.008 V).
   - **BOB:** only indirectly. The laser's l19 hangs off BOB
     (`vdd_l13_l19_l21-supply = <&vreg_bob>`, WAHOO:242), as do l28 (touch),
     l20 (UFS) and l24 (USB PHY), the rails implicated in the 3.3 V freeze.
     Keep l19 at WAHOO's 3.008 V, which is the top of the vendor range
     (DTBO:2619-2620). Never raise BOB-fed LDOs as part of camera work. BOB as
     direct VANA is only in fragment 0, the MTP reference (DTBO:5276), which is
     overridden on production walleye. Do not copy it.
   - The **upstream source of the GPIO-switched rails** (whatever the enable
     pins switch) is UNCONFIRMED. If those are BOB-fed load switches, the rear
     module (OIS coil + VCM + sensor) adds BOB load. Bring the rear module up
     with nothing else new enabled.
5. **Voltages differing from taimen** (front AVDD 2.85 vs 2.7 V, rear AVDD
   2.85 vs 2.8 V) are fixed by board hardware, not software. `regulator-fixed`
   values are labels, and the camera drivers never call
   `regulator_set_voltage` (grep of imx179.c, imx362.c, lc898*.c). No damage
   path.
6. **GPIO20 VIN select.** Walleye uses VIN1 (DTBO:4605). If taimen's
   `power-source = <0>` is copied, the DVDD enable may never reach a valid
   high level. Expected symptom: the IMX362 chip ID reads zero, which looks
   like a dead sensor. Use `<1>` as proposed. The actual VIN1 voltage was not
   established.
7. **Boot level of the walleye enables** (`invert = 1` on pm8998 GPIO15/19 and
   pmi8998 GPIO3/6; DTBO:4587, 4597, 4624, 4634). On stock these rails come up
   on at boot until the camera stack first powers the module down. The
   downstream `__qpnp_pin_set` writes the INVERT bit, so `invert` is just the
   initial output level (`drivers/gpio/qpnp-pin.c:884-895`). The enables
   are still active-high (the vendor library drives them high to power up).
   The proposal starts them low, which is the state stock reaches after the
   first camera close. No known consumer depends on them being high, but this
   is UNCONFIRMED.
8. **Shared SoC rails.** CAMSS l1/l2 are shared with DSI, UFS and the PCIe
   PHY. They are already on for the display, as on taimen (TDTS:908-909 notes
   captures only worked because DSI held l2). LVS1 is shared by the sensors,
   EEPROMs, OIS and the laser IO.

### Driver assumptions (Porthole drivers are taimen-tuned)

9. **easel-mipi / sensors:** the link indices (rear 0, front 1), 4 lanes
   (patch 0015, lines 574 and 703) and rates are hardcoded. All match walleye
   (section B). The bypass registers persist across module reloads (patch
   0015, lines 755-762).
10. **lc898214xd:** the focus code range `CODE_FAR -257 / CODE_NEAR 1112` was
    measured on a taimen module (lc898214xd.c:126-127). Walleye's module
    vendor (KT or Largan, which the vendor reads from OIS word 0x1A03) is
    unknown, so AF range or calibration may be off. The servo is closed-loop,
    so this is not a damage risk. The driver deliberately does not burn the
    actuator EEPROM.
11. **lc898123f40:** this driver enables stabilisation at probe and
    permanently enables `vdrv` (`devm_regulator_bulk_get_enable`,
    lc898123f40.c:172-174). It does not reflash firmware. The vendor kernel
    reflashes anything below 0x19, and its tables include HTC module variants
    (`camera_v2/sensor/fw_update/FromCode_0[49]_05_0[68].h`: "LGIT HTC for
    google", "SHARP HTC for google"). A walleye module on older OIS firmware
    is possible. The driver only logs the version.
12. **EEPROM content:** the addresses and protocols are identical, but the
    library names differ (`sony_imx362` / `sony_imx179` vs taimen's
    `onsemi_lc898123f40xc` / `primax_g802l`). Any calibration parsing ported
    from taimen (field offsets, the AWB "PM" header check TDTS:1227) may not
    apply.
13. **Rotation:** both values are UNCONFIRMED (see M4/M5 comments). This is
    cosmetic.
14. **gpio62:** WAHOO:510-515 defines `disp_en_default` on gpio62 (taimen's
    panel). WDTS overrides the panel pinctrl, so the pin is free for the laser
    IRQ on walleye. Do not re-add `disp_en_default` to the walleye panel.

### UNCONFIRMED summary

- Rear VANA2, VDRV and VAF voltages (taken from labels or taimen).
- The supply that feeds the GPIO-switched camera rails.
- `qcom,drive-strength` for the PMIC enable pins (copied from TDTS; the vendor
  does not specify it).
- Rotation values.
- The VIN1 voltage on pm8998 GPIO20.
- Whether anything on walleye relies on the camera rails being high at boot.
- AF range for walleye's module.
- Walleye OIS firmware version.
