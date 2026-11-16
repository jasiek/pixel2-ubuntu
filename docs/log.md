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
