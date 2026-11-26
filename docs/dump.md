# Root access and flash dump

## SD update hook (CVE-2025-63296)

Firmware `v33.53.x` runs a script from the SD card as root at boot, before the vendor application:

```
/usr/sbin/anyka_service.sh -> /usr/bin/update_entry
    find /mnt -maxdepth 1 -name "update.nor.sh"
    copy to /tmp/net.sh, executed as root
```

This hook is the only root entry point used on this board (there is no UART, see
[hardware.md](hardware.md#debug-access-no-uart)). Any `update.nor.sh` at the card root runs as
`uid=0` on every boot while the card is inserted. **HW**

If a newer unit has the hook fixed, nothing runs from the card and the stock application starts
unchanged; the remaining access path is the SPI flash.

## How the dump was made

All steps only read flash.

1. **HW**. The dump payload [`scripts/dump-payload/update.nor.sh`](../scripts/dump-payload/update.nor.sh),
   placed on the card as `update.nor.sh`, logged `/proc/mtd` and the mount table, copied the APP
   partition (located by name in `/proc/mtd`, `/dev/mtd7` as fallback) and `/usr/bin/anyka_ipc` to the
   card, and started `telnetd` on ports 23 and 24 (root shell, no login).
2. **HW**. Over that telnet shell, the full flash was read to the card:

   ```sh
   cat /dev/mtd0 /dev/mtd1 /dev/mtd2 /dev/mtd3 /dev/mtd4 /dev/mtd5 /dev/mtd6 /dev/mtd7 > /mnt/full_flash.bin
   sync; md5sum /mnt/full_flash.bin
   ```

   [`scripts/remote-dump.ps1`](../scripts/remote-dump.ps1) was used as the telnet client
   (`-NoLogin -Command "..."`, since the payload's `telnetd -l /bin/sh` gives a shell without login).
3. **HW**. The APP image carved from the full read at `0x3DA000` is byte-identical to the direct
   `dd` of `/dev/mtd7` (same MD5).

The full 8 MiB read includes CONFIG (mtd6). CONFIG was extracted from it for local analysis only; it is
not part of any published file.

## Published dump files

The files below are not stored in the repository tree. They are attached to release
[`v1`](https://github.com/666dsa666/ak3918-v330l-kerui-dump/releases/tag/v1) as
`AK3918_V330L_app_dump_20261114.zip`, in the package format produced by
[`scripts/verify-and-pack.ps1`](../scripts/verify-and-pack.ps1) for OpenIPC/firmware#1970.

| file | content | size | MD5 |
|---|---|---|---|
| `backup_app.bin` | mtd7, raw APP SquashFS | 4,349,952 | `ebab68f0b4f32711de971288a0432b7b` |
| `anyka_ipc.bin` | stock `/usr/bin/anyka_ipc` | see [patch.md](patch.md#reference-hashes) | see [patch.md](patch.md#reference-hashes) |
| `dump-report.txt` | `/proc/mtd`, `/proc/cpuinfo`, mounts, hashes | — | — |
| `checksums.txt` | MD5/SHA-256 of the above | — | — |

## What is not published

- **CONFIG (mtd6)**: Wi-Fi credentials and Tuya device keys.
- **Full-flash image**: contains CONFIG.
- **Patched application**: built locally with [`scripts/patch_anyka_ipc.py`](../scripts/patch_anyka_ipc.py)
  ([patch.md](patch.md)).

## Dump payload

[`scripts/dump-payload/`](../scripts/dump-payload/) holds the payload used for the dump and its card
installer:

| file | runs on | purpose |
|---|---|---|
| `update.nor.sh` | camera (SD hook) | writes `backup_app.bin`, `anyka_ipc_stock.bin` and `update-report.txt` to the card, starts `telnetd` on 23/24 |
| `install-cve-payload.ps1` | PC (PowerShell) | writes `update.nor.sh` to the card root with LF line endings, plus `README-UPDATE-PAYLOAD.txt` |

```powershell
.\scripts\dump-payload\install-cve-payload.ps1 -Path E:\
```

The installer takes `update.nor.sh` from its own directory unless `-Source` is given. It is a separate
card from the deployment card ([deploy.md](deploy.md#card-layout)): both use the name `update.nor.sh`.

After boot, the card holds the APP image and the stock binary. The telnet shell is then used with
[`scripts/remote-dump.ps1`](../scripts/remote-dump.ps1) in `-NoLogin -Command "..."` mode for further
reads, such as the full-flash read above. Limitations, including the "already dumped" size check that
does not match this board: [known-issues.md](known-issues.md#dump-payload).

## Reproducing the dump

1. FAT32 card with an `update.nor.sh` that starts a shell: the [dump payload](#dump-payload), the
   deployment payload [`scripts/update.nor.sh`](../scripts/update.nor.sh) with the bind-mount line
   removed, or a payload containing only `telnetd -p 23 -l /bin/sh &`.
2. Boot the camera with the card and connect to port 23.
3. Read the partitions to the card (the card is mounted at `/mnt`; the dump payload already does this):

   ```sh
   dd if=/dev/mtd7 of=/mnt/backup_app.bin bs=64k
   cat /usr/bin/anyka_ipc > /mnt/anyka_ipc_stock.bin
   md5sum /mnt/backup_app.bin /mnt/anyka_ipc_stock.bin
   ```

4. Check sizes against the [flash layout](hardware.md#flash-layout) and `anyka_ipc` against
   [the reference hash](patch.md#reference-hashes).

### Helper scripts from the LSC method

[`prepare-sd.ps1`](../scripts/prepare-sd.ps1) and [`dump_app.sh`](../scripts/dump_app.sh) implement the
LSC-camera root method (`_ht_av_tuning.conf` marker plus a `shadow` file with the well-known
`root`/`telnet` password) and an automated APP dump. They were written for the LSC units of
OpenIPC#1970.

**Warning: per the card instructions written by `prepare-sd.ps1`, the `_ht_av_tuning.conf` marker makes
the camera rewrite flash at every boot. Remove the marker files after use.** The `prepare-sd.ps1` root
method is **UNTESTED** on this board.

`dump_app.sh` reads the APP partition (located by name in `/proc/mtd`) and copies `/usr/bin/anyka_ipc`
next to itself on the card, with `md5sum` output and a `dump-report.txt`. It does not read the full
flash; the full-flash image came from the `cat /dev/mtd0 … /dev/mtd7` command above. On this board the
published APP image and stock binary came from the dump payload; no run of `dump_app.sh` is recorded
(**UNTESTED**).

`dump_app.sh` must be on the card root. `install-cve-payload.ps1 -RemoveDeadFiles` deletes it from the
card. With a payload that starts `telnetd -l /bin/sh` (card mounted at `/mnt`):

```powershell
.\scripts\remote-dump.ps1 -Camera <camera-ip> -NoLogin -Command "sh /mnt/dump_app.sh"
```

In `-Command` mode `remote-dump.ps1` waits at most 120 s for the command to finish. Limitations are
listed in [known-issues.md](known-issues.md#dump-helpers).
