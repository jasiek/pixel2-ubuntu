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
