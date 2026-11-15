# 05 — SD-card deployment

Nothing here writes to the camera flash. The patched application lives on the SD card and is
`mount --bind`-ed over `/usr/bin/anyka_ipc` at boot; removing the card and rebooting restores the stock
application.

## Card layout (FAT32)

```
/anyka_ipc_patched.bin    the patched application (3,382,008 B)
/update.nor.sh            the boot payload (LF line endings)
/TZ                       POSIX timezone, e.g. CET-1CEST,M3.5.0,M10.5.0/3
```

`prep-sd.ps1` copies and verifies all three (see [`scripts/prep-sd.ps1`](../scripts/prep-sd.ps1)).

## How the hook works

`v33.53.x` runs a script from the card as root before the vendor application starts:

```
anyka_service.sh -> update_entry -> find /mnt -maxdepth 1 -name "update.nor.sh"
                                 -> cp to /tmp/net.sh -> executed as root
```

(CVE-2025-63296). The payload therefore runs **before** `anyka_ipc`, which is exactly what the bind mount
needs.

## What `update.nor.sh` does

1. `mount --bind /mnt/anyka_ipc_patched.bin /usr/bin/anyka_ipc`
2. starts `telnetd -p 23 -l /bin/sh` for diagnostics (**remove this line for daily use**)
3. bind-mounts `/mnt/TZ` over `/etc/TZ` (the rootfs is a read-only SquashFS with `CST-8`)
4. `hwclock -s -u` to seed the clock from the RTC
5. background loop: wait for the network, `ntpd -nq -p <servers>`, `hwclock -w -u`, repeat every 6 hours
6. logs everything to `/mnt/patch-report.txt`

The timezone and NTP steps matter because the cloud is cut: without them the OSD shows 1980 and the
clock resets on every cold boot. `ntpd`/`hwclock`/`rdate` are all present in the vendor busybox, and the
camera keeps normal LAN/internet routing (only Tuya is disabled in the application), so NTP works.

## Install

1. Format the card FAT32, single partition.
2. Copy the three files to the root (not a subfolder).
3. Power the camera off, insert the card, power on.
4. Verify:

   ```sh
   md5sum /usr/bin/anyka_ipc        # 1841dcdac0db4a0815a8656e8f80461d
   netstat -ltn                     # 554, 10000, 6668, 23
   cat /mnt/patch-report.txt
   ```

5. Test video:

   ```bash
   ffprobe -v error -rtsp_transport tcp -read_intervals "%+5" -select_streams v:0 \
           -count_frames -show_entries stream=codec_name,width,height,nb_read_frames \
           -of default=noprint_wrappers=1 rtsp://admin:admin@<camera-ip>/V_ENC_001
   ```

6. Check that the cloud is really gone:

   ```sh
   cat /proc/net/tcp | grep -ci ":22B3"    # 0 (no session to Tuya 8883)
   ```

## Notes and gotchas

- The card must be FAT32; the vendor kernel does not mount exFAT/NTFS.
- Keep the card inserted: the bind mount lives only until reboot.
- Writing long files to the card **through the camera's telnet** fails (tty line limit); use a card reader.
- The `TZ` file must be LF-only.
- The payload runs as root. Keep the card physically secure; anyone with it can modify the camera.
- If the hook does not run on a newer unit (the CVE may be fixed), telnet will not open and the stock
  application stays in place. In that case the unit needs UART/SPI access first.

## Recovery

Power off, remove the SD card, power on. The stock application starts, the cloud works again, and no
configuration was lost. The camera's flash was never written by this procedure.

## Security

The payload starts a root telnet shell without a password. For permanent use, delete the `telnetd` line
from `update.nor.sh`, change the RTSP/ONVIF credentials, and keep 554/10000 on the LAN only.
