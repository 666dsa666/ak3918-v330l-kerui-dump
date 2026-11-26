# Deployment and verification

Nothing in this procedure writes to the camera flash. The patched application lives on the SD card
and is bind-mounted over `/usr/bin/anyka_ipc` at boot.

## Card layout

FAT32, single partition, files at the root:

```
/anyka_ipc_patched.bin    patched application (MD5: patch.md#reference-hashes)
/update.nor.sh            boot payload, LF line endings
/TZ                       POSIX timezone string, LF line endings
```

The vendor kernel does not mount exFAT or NTFS.

Recommended: [`scripts/prep-sd.ps1`](../scripts/prep-sd.ps1) (mandatory `-Drive`, English output, an
`-ExpectedMd5` parameter). [`scripts/prep-sd-full.ps1`](../scripts/prep-sd-full.ps1) is the version
actually used for both units; it also checks `TZ` for CR characters. Both are **PARTIAL**
([validation.md](validation.md)).

```powershell
.\scripts\prep-sd.ps1 -Drive E -Binary .\anyka_ipc_patched.bin
```

Both scripts copy the three files, then report the binary MD5 and whether `update.nor.sh` (and, for
`prep-sd-full.ps1`, `TZ`) contains CR characters. `-Binary`, `-Payload` and `-TzFile` default to `anyka_ipc_patched.bin`, `update.nor.sh` and
`TZ` in the script directory. Limitations: [known-issues.md](known-issues.md#prep-sdps1).

`prep-sd-full.ps1` takes the same parameters, picks a card by itself when `-Drive` is omitted
([known-issues.md](known-issues.md#prep-sd-fullps1)) and prints French console messages.

## How the hook runs the payload

The SD update hook ([dump.md](dump.md#sd-update-hook-cve-2025-63296)) runs `update.nor.sh` as root
before `anyka_service.sh` starts `anyka_ipc`, which is the point where the bind mount must happen.

## What `update.nor.sh` does

[`scripts/update.nor.sh`](../scripts/update.nor.sh) **HW**:

1. `mount --bind /mnt/anyka_ipc_patched.bin /usr/bin/anyka_ipc` (no MD5 check before mounting);
2. starts `telnetd -p 23 -l /bin/sh` (root shell, no password);
3. if `/mnt/TZ` exists, bind-mounts it over `/etc/TZ` (read-only, `CST-8` on the stock rootfs), so the
   OSD shows local time;
4. `hwclock -s -u` seeds the system clock from the RTC;
5. in the background: pings `162.159.200.1` up to 150 times (2 s pause between attempts) until it answers, then runs
   `ntpd -nq` against public servers (`162.159.200.1`, `162.159.200.123` (Cloudflare),
   `129.6.15.28` (NIST), `pool.ntp.org`), writes the RTC with `hwclock -w -u`, and repeats every 6 h;
6. logs to `/mnt/patch-report.txt`.

The clock steps are needed because the patch skips the vendor cloud time sync: without them the OSD
starts at 1980 after every cold boot. The camera keeps normal internet routing (only the Tuya
session is disabled), so public NTP is reachable. `ntpd` and `hwclock` are part of the vendor busybox.

The shipped [`scripts/TZ`](../scripts/TZ) is Central European time (`CET-1CEST,M3.5.0,M10.5.0/3`). Edit it
before preparing the card to use another timezone (for example `UTC0`).

## Install

1. Prepare the card as above.
2. Power the camera off, insert the card, power it on.
3. Run the checks below.

The bind mount lasts until the next reboot; keep the card inserted.

## Verification

Each check carries its own status tag; evidence is listed in [validation.md](validation.md).

Shell commands run on the camera over the payload's telnet (port 23); `ffprobe`/`ffmpeg` run on a PC.

### Patched binary active

**HW**

```sh
md5sum /usr/bin/anyka_ipc     # must equal the patched reference MD5 (patch.md#reference-hashes)
cat /mnt/patch-report.txt     # stock MD5, mounted MD5, TZ, time sync result
```

### Listening services

**HW**

```sh
netstat -ltn
# 554    RTSP
# 10000  ONVIF
# 6668   vendor service
# 23     telnetd from the payload
```

### No Tuya cloud session

**HW**

```sh
grep -ci ":22B3" /proc/net/tcp    # 22B3 = port 8883 (Tuya MQTT); expected 0
```

With the `mqtt_client_start` stub, the count stays 0 for the whole uptime, including retries.

### Video frames

**HW** (the frame counts below come from the author's unpublished notes; no raw `ffprobe` log is kept)

```bash
ffprobe -v error -rtsp_transport tcp -timeout 8000000 -read_intervals "%+6" \
        -select_streams v:0 -count_frames \
        -show_entries stream=codec_name,width,height,nb_read_frames \
        -of default=noprint_wrappers=1 \
        rtsp://admin:admin@<camera-ip>/V_ENC_001
```

Recorded result: `h264`, 640×360, `nb_read_frames=119`. On `V_ENC_000`: `hevc`, 2304×1296,
`nb_read_frames=118`. About 120 frames in 6 s corresponds to roughly 20 fps, which matches the sensor
driver rate (`fps:20` in `dmesg`); the configuration file sets `main_fps`/`sub_fps` to 15
([rtsp-onvif.md](rtsp-onvif.md#streams)).

If `nb_read_frames` is `N/A` or the size is 0×0, the encoder channels are not bound: check that
`bl media_chsub_enable` at `0xB6CA0` is intact ([patch.md](patch.md#derivation)).

Single frame capture:

```bash
ffmpeg -rtsp_transport tcp -i rtsp://admin:admin@<camera-ip>/V_ENC_000 -frames:v 1 snapshot.png
```

### Audio

**PARTIAL**: both profiles carry a second stream, `pcm_alaw`. Recorded in the author's unpublished notes;
no raw `ffprobe` log.

### LED

**PARTIAL**: LED off (steady); the blink modes are redirected to the mode-5 off handler
([patch.md](patch.md#derivation)). The author's unpublished notes equate this with the stock online
state and record no continuous blink; no raw log.

### Clock

Expected: `patch-report.txt` contains `time sync OK: <local date>`.

**HW**: `ntpd` followed by `hwclock -w -u` moved the RTC from 1980 to the current date, and `/etc/TZ`
showed the bound value.

**UNTESTED**: after a cold boot without network, the clock starts from the RTC instead of 1980 (no log
of this case).

### RTSP survives a WAN loss

**PARTIAL**. With the four teardown patches (`ak_rtsp_exit`, `onvif_stop`, the `set_onvif_switch`
disable branch and the direct `bl ak_rtsp_exit`), removing the default route or poisoning the gateway ARP
entry left port 554 (and 10000) listening. This was logged on hardware with an intermediate build that
already contained these four patches, not with the final patched build; stream playback during the
outage is recorded only in the author's unpublished notes. The vendor network watchdog may restore the
route.

## Recovery

Power off, remove the card, power on. The stock application starts, the cloud connection resumes,
and the configuration is unchanged.

## Security

- The payload starts a **root shell on port 23 without a password** by default. For permanent use,
  delete the `telnetd` line from `update.nor.sh`.
- Change the RTSP/ONVIF credentials ([rtsp-onvif.md](rtsp-onvif.md#credentials)) and keep ports 554
  and 10000 on the LAN.
- Anyone with physical access to the card can run code as root on the camera at the next boot.
- Writing long files to the card through the camera's telnet fails (line-length limit); prepare the
  card in a card reader.
