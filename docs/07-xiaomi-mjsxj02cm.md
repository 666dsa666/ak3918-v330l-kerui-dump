# 07 — Xiaomi MJSXJ02CM notes

This page is about a **different camera** from the Anyka one: the Xiaomi Mi 360° 1080p **MJSXJ02CM**
(model type IPC009). It is documented here because the same questions came up.

## Hardware

| field | value |
|---|---|
| SoC | SigmaStar/MStar (ARM926EJ-S class, SSC325/SSC335 family) |
| RAM | 64 MB |
| Flash | 16 MB SPI NOR (Winbond) |
| UART | 115200 8N1, pads labelled `TXO` / `RX0` / `TP` / `TM` |
| U-Boot prompt | `SigmaStar #` |
| Stock OS | Buildroot 2017.08, `CHUANGMI_VERSION=4.3.7_0417` (built Nov 2023) |

The firmware version can be read from the card's own log: `log/diagnosis.txt` on the camera's SD card
contains `/etc/os-release`, the service list, mounts and a device diagnosis.

## The old SD-card hack does not work on this firmware

[j0se/xiaomi-360-1080p-hacks](https://github.com/j0se/xiaomi-360-1080p-hacks) (and the original
telmomarques repo) targets firmware **3.4.2_0062** and requires downgrading via `tf_recovery.img` on the
SD card.

Xiaomi changed U-Boot and RSA signing in **4.0.9_0409**; from that version on the camera refuses old
firmware (no downgrade). A unit on `4.3.7_0417` cannot use the SD-card downgrade, so that path is closed.

## What does work: the 2024 UART/U-Boot mod

[tsunglung/xiaomi-360-hacks](https://github.com/tsunglung/xiaomi-360-hacks) supports **MJSXJ02CM
(IPC009)** and provides telnet + ONVIF + RTSP + a web configuration server. It does not downgrade
anything: it stops U-Boot over UART and flashes a prebuilt hacked rootfs from the SD card.

```
fatload mmc 0:1 0x21000000 rootfs_new.bin
sf probe
sf erase 0x260000 0x674000
sf write 0x21000000 0x260000 0x674000
reset
```

### Verified payload details

The repository's `mjsxj02cm/rootfs_new.bin`:

| field | value |
|---|---|
| size | 6,856,704 B (`0x68A000`) |
| MD5 | `b150897a77f716cb577cf51a82baeb3f` |
| format | SquashFS 4.0, xz, 128 KiB blocks |
| `bytes_used` | 6,854,408 B (`0x689708`) |

### Warning: the erase length in the README is too short for the current file

The command erases **`0x674000`** (6,766,592 B) but the rootfs needs **`0x689708`** (6,854,408 B) — about
**88 KB more**. Writing past the erased area on NOR corrupts the last blocks.

Before flashing, get the real partition map from U-Boot (`printenv`, `mtdparts=…` in `bootargs`) or from a
full SPI dump, then erase at least `0x260000` for the correct length without touching the data partition.
A full flash backup first is strongly recommended.

## Recommended order

1. **Full SPI dump with CH341A** (SOIC8 clip) — 16 MB, keep two copies, verify by reading twice.
2. Parse the dump: confirm the rootfs partition offset/size and the data partition start.
3. Either:
   - splice `rootfs_new.bin` into the dump at `0x260000` and flash the complete image, or
   - use U-Boot `sf erase`/`sf write` with the corrected length.
4. Boot, telnet in, set Wi-Fi (`/etc/wpa_supplicant.conf` or the web config), verify RTSP/ONVIF.
5. Keep the original dump to restore.

## UART wiring

- adapter `TXD` → camera `RX0`
- adapter `RXI` → camera `TXO`
- `GND` ↔ `GND`
- **do not** connect 3V3/5V; power the camera from its own supply.

Hold **Enter** while powering on to stop at `SigmaStar #`.

## Status

Not yet performed on the unit in question — the camera is still on stock `4.3.7_0417`. The plan above is
the safe sequence once the flash dump exists.
