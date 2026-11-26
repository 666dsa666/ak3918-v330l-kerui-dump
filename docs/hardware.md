# Hardware and firmware

## Camera

A Tuya/Anyka ODM pan/tilt camera. It is **not** the LSC Smart Connect `HT_IPC286KSD3M` build discussed
in [OpenIPC/firmware#1970](https://github.com/OpenIPC/firmware/issues/1970), although it uses the same
SoC.

The units were sold under the Kerui brand. The firmware itself carries no brand: `anyka_ipc` contains
no `Kerui`, `LSC` or `HT_IPC…` string (**STATIC**), so the same board may ship under other names.
Identify a matching unit by its firmware: the
Tuya/Smart Life app shows the firmware version on the device page (expected application `v33.53.61`),
and the stock `anyka_ipc` must match the MD5 in [patch.md](patch.md#reference-hashes). The board
silkscreen `5810-V7.0` is visible only with the case open.

| field | value |
|---|---|
| SoC | Anyka AK3918EN080 V330L (kernel reports `AK39EV330`), ARM926EJ-S rev 5, ARMv5TEJ, little-endian |
| Main board | silkscreen `5810-V7.0` |
| RAM | 64 MiB DDR2 |
| Flash | 8 MiB SPI NOR `25Q64` (SOP8) |
| Sensor | SmartSens SC1346 |
| Wi-Fi | ATBM603x (USB, 2.4 GHz) |
| Motor driver | `ULN2803L` |
| Kernel | Linux 4.4.192V2.1 |
| Userland | Buildroot 2018.02.7, uClibc 1.0.28 (pthread/libm merged into libc) |
| Tuya application | `v33.53.61`, `/usr/bin/anyka_ipc` (size and MD5: [patch.md](patch.md#reference-hashes)) |
| SD card mount point | `/mnt` (vfat) |

`anyka_ipc` is an ARM `ET_EXEC` ELF, load base `0x10000`, with 8,829 symbols in `.dynsym`.

Board photos: [SoC side](../images/board-5810-v7.0-main.jpg) (silkscreen `5810-V7.0`, Anyka SoC,
microSD slot, `ULN2803L`), [lens side](../images/board-5810-v7.0-lens.jpg) (sensor, microphone, IR-cut
connector, reset button, several SOP8 packages). No SOP8 package is visible on the SoC side; the `25Q64`
flash is therefore expected among the SOP8 packages on the lens side; check the marking before clipping.

## Flash layout

| mtd | name | offset | size | content |
|---|---|---|---|---|
| 0 | UBOOT | `0x000000` | `0x032000` | bootloader |
| 1 | ENV | `0x032000` | `0x001000` | U-Boot environment |
| 2 | ENVBK | `0x033000` | `0x001000` | environment backup |
| 3 | DTB | `0x034000` | `0x00B000` | device tree |
| 4 | KERNEL | `0x03F000` | `0x184000` | kernel |
| 5 | ROOTFS | `0x1C3000` | `0x1F0000` | SquashFS root, mounted read-only at `/` |
| 6 | CONFIG | `0x3B3000` | `0x027000` | JFFS2, mounted read-write at `/etc/config` |
| 7 | APP | `0x3DA000` | `0x426000` | SquashFS, mounted read-only at `/usr` |

Total: `0x800000` (8,388,608 bytes).

- APP holds `anyka_ipc` and the vendor service scripts. Because `/usr` is read-only, the application is
  replaced at runtime with `mount --bind` from the SD card ([deploy.md](deploy.md)).
- CONFIG holds the Wi-Fi credentials, Tuya device keys and the RTSP/ONVIF flags. It is never published
  ([dump.md](dump.md#what-is-not-published)).
- `/etc/TZ` on ROOTFS is `CST-8` and read-only; the SD payload binds a replacement over it.

## Debug access: no UART

Two units with main board `5810-V7.0` were inspected. There is no accessible debug UART:

- the only unpopulated pad array on the SoC side belongs to the `ULN2803L` motor driver;
- there are no test pads near the SoC (no `TX`/`RX`/`GND`, no `UART`/`DBG` label);
- the only low-level access is the SPI NOR flash, with a SOP8 clip or by desoldering.

A UART boot log (for example of the OpenIPC `ak3918ev330-nor-lite` image) cannot be captured on this
board without soldering to the SoC. Flashing a different firmware without a console is therefore a
one-way operation on this board and was not attempted. Root access is obtained through the SD hook
instead ([dump.md](dump.md)).

## Difference from the LSC build in OpenIPC#1970

| item | LSC build requested in #1970 | this board |
|---|---|---|
| APP partition | 5 MiB at `0x300000` | `0x426000` (4,349,952 B) at `0x3DA000` |
| `anyka_ipc` MD5 | `86396fdb14f2e029fa169afd4b598391` | see [patch.md](patch.md#reference-hashes) |
| `HT_IPC…` product strings | present | absent |

The APP image of this board is a variant reference for EV330 support, not the LSC image.
