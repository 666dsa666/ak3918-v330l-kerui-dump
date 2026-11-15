# 02 — How the dump was made

## Root shell without opening the camera

Firmware `v33.53.x` ships a factory/update helper that runs a script from the SD card as root at boot:

```
/usr/sbin/anyka_service.sh  ->  /usr/bin/update_entry
    find /mnt -maxdepth 1 -name "update.nor.sh"
    cp to /tmp/net.sh ; executed as root
```

This is the SD update hook tracked as **CVE-2025-63296**. It was used **read-only**: the payload only
mounted the card, read `/dev/mtd7` (and the other `mtd` devices) into files on the card, and exited.

Nothing was written to the camera flash. The `CONFIG` partition was not copied.

## What is published

| file | size | MD5 |
|---|---|---|
| `backup_app.bin` (mtd7, raw APP/SquashFS) | 4,349,952 | `ebab68f0b4f32711de971288a0432b7b` |
| `anyka_ipc.bin` (stock `/usr/bin/anyka_ipc`) | 3,382,008 | `ab81807d9e2d9d5dc946419af43e69b6` |
| `dump-report.txt` | — | `/proc/mtd`, `/proc/cpuinfo`, mounts, hashes |
| `checksums.txt` | — | md5/sha256 |

The APP image was carved from the full-flash read at `0x3DA000` and is byte-identical to the camera's own
`dd if=/dev/mtd7` (verified by MD5).

## What is deliberately excluded

- **CONFIG (mtd6)**: Wi-Fi credentials and Tuya device keys. A sanitized full 8 MiB image with CONFIG
  zeroed can be produced on request.
- **Patched binaries**: not redistributed. Build the patched application from your own stock binary with
  [`scripts/patch_anyka_ipc.py`](../scripts/patch_anyka_ipc.py). This keeps the repository free of
  modified vendor code and makes the patch auditable.

## Reproducing the dump

1. FAT32 SD card with `update.nor.sh` (see [`05-sd-deployment.md`](05-sd-deployment.md) for the hook
   mechanics).
2. Boot the camera with the card, get a root shell over telnet (`telnetd` started by the payload), or use
   [`scripts/remote-dump.ps1`](../scripts/remote-dump.ps1).
3. Read the partitions to the card:

   ```sh
   dd if=/dev/mtd7 of=/mnt/backup_app.bin bs=64k
   dd if=/dev/mtd0 of=/mnt/backup_uboot.bin bs=64k
   # ... repeat for the other mtdN you need, then:
   md5sum /mnt/backup_*.bin
   ```

4. Verify sizes/offsets against the table in [`01-hardware.md`](01-hardware.md).

The camera keeps recording normally while the card holds the payload; remove the payload (or the card)
when done.
