# AK3918EN080 V330L — Tuya/Anyka `v33.53.61` firmware dump

Hardware/variant reference for [OpenIPC/firmware#1970](https://github.com/OpenIPC/firmware/issues/1970).
This is **not** an LSC Smart Connect unit and **not** the `HT_IPC286KSD3M` build discussed there —
it is a different Tuya/Anyka ODM build on the same `AK3918EN080 V330L` silicon
(`Hardware: AK39EV330`, ARM926EJ-S rev 5, BogoMIPS 351.43).

## Camera

| field | value |
|---|---|
| SoC | Anyka AK3918EN080 **V330L** (`AK39EV330`) |
| Kernel | Linux 4.4.192V2.1, Buildroot 2018.02.7, built Jan 2023 |
| Firmware (Tuya app) | v33.53.61 |
| Flash | 8 MiB SPI NOR, single MTD layout below |
| SD mount | `/mnt` (vfat) |

## Partition layout

| mtd | name | offset | size |
|---|---|---|---|
| 0 | UBOOT | 0x000000 | 0x032000 |
| 1 | ENV | 0x032000 | 0x001000 |
| 2 | ENVBK | 0x033000 | 0x001000 |
| 3 | DTB | 0x034000 | 0x00B000 |
| 4 | KERNEL | 0x03F000 | 0x184000 |
| 5 | ROOTFS | 0x1C3000 | 0x1F0000 |
| 6 | CONFIG | 0x3B3000 | 0x027000 |
| 7 | **APP** | **0x3DA000** | **0x426000** |

Total `0x800000` = 8,388,608 bytes.

## Files in the release

| file | size | md5 |
|---|---|---|
| `backup_app.bin` (mtd7, squashfs `/usr`) | 4,349,952 | `ebab68f0b4f32711de971288a0432b7b` |
| `anyka_ipc.bin` (`/usr/bin/anyka_ipc`) | 3,382,008 | `ab81807d9e2d9d5dc946419af43e69b6` |
| `dump-report.txt` | — | `/proc/mtd`, `/proc/cpuinfo`, mount table, hashes |
| `checksums.txt` | — | md5/sha256 of the above |

The APP image was carved from a full-flash read at `0x3DA000` and is byte-identical to the
camera's own `dd if=/dev/mtd7` (verified by MD5).

## How it was dumped

Root shell through the `v33.53.x` SD update hook (`update.nor.sh`, CVE-2025-63296:
`/usr/sbin/anyka_service.sh` → `/usr/bin/update_entry` → `/tmp/net.sh`), then a read-only
`dd if=/dev/mtd7` and `cat /dev/mtd0..7` to the SD card. **Nothing was written to the flash.**

## Deliberately not published

The **CONFIG** partition (mtd6, jffs2, `0x3B3000..0x3DA000`) contains the device's Wi-Fi
credentials and Tuya keys, so it is excluded. A sanitized full 8 MiB image (CONFIG zeroed)
can be provided on request.

## Why it is not the image #1970 asked for

* APP is 4,349,952 bytes; the LSC layout uses 5,242,880 at `0x300000`.
* `anyka_ipc` MD5 is `ab81807d…`, not `86396fdb14f2e029fa169afd4b598391`.
* No `HT_IPC…` product strings in the binary.
