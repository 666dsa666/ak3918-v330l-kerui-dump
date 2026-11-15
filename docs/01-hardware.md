# 01 — Hardware and firmware

## Camera

A Tuya/Anyka ODM camera sold under several brands (this unit is a Kerui/LSC-family V330L). It is **not**
an LSC Smart Connect `HT_IPC286KSD3M` unit, although it uses the same SoC family discussed in
[OpenIPC/firmware#1970](https://github.com/OpenIPC/firmware/issues/1970).

| field | value |
|---|---|
| SoC | Anyka **AK3918EN080 V330L** (`AK39EV330`), ARM926EJ-S rev 5, ARMv5TEJ, little-endian |
| BogoMIPS | 351.43 |
| RAM | 64 MiB DDR2 |
| Flash | 8 MiB SPI NOR (`0x800000`) |
| Sensor | SmartSens SC1346 |
| Wi-Fi | ATBM603x (USB) |
| Kernel | Linux 4.4.192V2.1 |
| Userland | Buildroot 2018.02.7, uClibc 1.0.28 (pthread/libm merged into libc) |
| Tuya application | `v33.53.61` |
| SD mount | `/mnt` (vfat) |

The stock application is `/usr/bin/anyka_ipc`:

| field | value |
|---|---|
| size | 3,382,008 bytes |
| MD5 | `ab81807d9e2d9d5dc946419af43e69b6` |
| format | ARM `ET_EXEC`, load base `0x10000`, `.dynsym` with 8,829 symbols |

`/usr` is a read-only SquashFS stored in the APP partition. The application is therefore replaced by a
`mount --bind` of a file from the SD card, not by modifying the flash.

## MTD layout

| mtd | name | offset | size |
|---|---|---|---|
| 0 | UBOOT | `0x000000` | `0x032000` |
| 1 | ENV | `0x032000` | `0x001000` |
| 2 | ENVBK | `0x033000` | `0x001000` |
| 3 | DTB | `0x034000` | `0x00B000` |
| 4 | KERNEL | `0x03F000` | `0x184000` |
| 5 | ROOTFS | `0x1C3000` | `0x1F0000` |
| 6 | CONFIG | `0x3B3000` | `0x027000` |
| 7 | **APP** | **`0x3DA000`** | **`0x426000`** |

Total: `0x800000` = 8,388,608 bytes.

- **APP** (mtd7) holds the read-only SquashFS mounted at `/usr`; it contains `anyka_ipc`.
- **CONFIG** (mtd6) is JFFS2 and contains Wi-Fi credentials and Tuya keys — it is **never published**.
- **ROOTFS** (mtd5) is a small initramfs/rootfs; the boot hook that makes this work lives in the vendor
  scripts on the APP side.

## UART / debug access — negative result

Two units of this ODM build were inspected (main board silkscreen **`5810-V7.0`**). There is **no accessible
debug UART**:

- the only unpopulated pad array on the main board belongs to the **`ULN2803L`** motor driver, not to the SoC;
- there are **no test pads near the SoC** — no `TX`/`RX`/`GND`, no `UART`/`DBG` header, no silkscreen label;
- the SPI flash is a **`25Q64`** (8 MB, SOP8), reachable only with a clip or by desoldering.

Consequence: a UART boot log (for example of the OpenIPC `ak3918ev330-nor-lite` image) **cannot be captured
on this board** without micro-soldering directly to the SoC, which is out of scope here. The board photos are
in [`images/`](../images/): [main board](../images/board-5810-v7.0-main.jpg),
[lens board](../images/board-5810-v7.0-lens.jpg).

Flashing without UART is a one-way operation on this board (no console, no Ethernet), so it was deliberately
not attempted.

## Why the APP image matters for OpenIPC

The `#1970` request wanted the APP partition of an LSC V330L (5 MiB at `0x300000`, `anyka_ipc`
`86396fdb14f2e029fa169afd4b598391`). This camera is a **different ODM build on the same silicon**:

- APP is `0x426000` (4,349,952 bytes) at `0x3DA000`;
- `anyka_ipc` MD5 is `ab81807d…`, not `86396fdb…`;
- no `HT_IPC…` product strings in the binary.

It was published as a **variant reference** for whoever picks up EV330 support, not as the LSC image.
