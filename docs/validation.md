# Validation status

Scope: Tuya camera on Anyka AK3918EN080 V330L (board 5810-V7.0), application `v33.53.61`. Other
documents use the same tags; this table is the reference.

Legend:

- **HW**: proven on the camera from logs.
- **PARTIAL**: indirect evidence, or documented as working without a raw capture.
- **STATIC**: verified offline on the binary.
- **UNTESTED**: no evidence.

Two units with the same board and the same `anyka_ipc` build were used. Raw logs were kept mainly for
one unit; the author's unpublished notes record the final patched build working on both.

| Item | Status | Evidence |
|---|---|---|
| `patch_anyka_ipc.py` output (patched `anyka_ipc`) | HW | patched reference MD5 read from the running camera |
| RTSP and ONVIF listening, no Tuya MQTT session ([deploy.md](deploy.md#verification)) | HW | `netstat -ltn` (554, 10000) and `/proc/net/tcp` port 8883 count 0, with the patched MD5 running |
| Video frames ([deploy.md](deploy.md#video-frames)) | HW | frames reported by `ffprobe`; the frame counts come from the author's unpublished notes, no raw log kept |
| Audio stream `pcm_alaw` ([deploy.md](deploy.md#audio)) | PARTIAL | author's unpublished notes; no raw `ffprobe` log |
| LED steady off ([deploy.md](deploy.md#led)) | PARTIAL | author's unpublished notes; patch derivation in [patch.md](patch.md#derivation) |
| RTSP/ONVIF survive a WAN loss ([deploy.md](deploy.md#rtsp-survives-a-wan-loss)) | PARTIAL | 554/10000 still listening after the default route was removed and the gateway ARP entry poisoned, logged with an intermediate build carrying the same teardown patches; not re-logged with the final build |
| RTSP/ONVIF flags set from a root shell ([rtsp-onvif.md](rtsp-onvif.md#enabling-flags)) | HW | `sed` edits and `grep` of both files logged; 554 and 10000 listening after reboot (stock application, cloud connected) |
| `update.nor.sh` at boot (bind mount, `telnetd` on port 23) | HW | start and end markers logged, port 23 active |
| NTP and timezone in `update.nor.sh` | HW | `ntpd` and `hwclock -w -u` OK, RTC moved from 1980 to the current date, `TZ` bound |
| Clock from the RTC after a cold boot without network | UNTESTED | no log of this case |
| Full-flash read (`cat /dev/mtd0…7`) through `remote-dump.ps1 -NoLogin -Command` | HW | transcript with file size 8,388,608 and `md5sum` output |
| `dump-payload/update.nor.sh` (APP dump at boot, `telnetd` 23/24) | HW | its `update-report.txt` read back: APP size and MD5, `anyka_ipc` MD5, `telnetd started (23/24)` |
| `dump-payload/install-cve-payload.ps1` | PARTIAL | the `README-UPDATE-PAYLOAD.txt` it writes was present on the card; script output not kept |
| `dump_app.sh` on this board | UNTESTED | present on the card, no run recorded |
| `prep-sd-full.ps1` (version used for both units) | PARTIAL | use recorded in the author's unpublished notes, console output not kept |
| `prep-sd.ps1` (recommended, minimal version) | PARTIAL | card files present, script output not kept |
| `onvif-ptz.ps1` `-Move` (`RelativeMove`) and `-Stop` | PARTIAL | HTTP 200 recorded in the author's unpublished notes |
| `onvif-ptz.ps1` `-Info` and `-HomePos` | PARTIAL | documented, no raw log |
| `prepare-sd.ps1` (LSC root method) | UNTESTED | no evidence on this board |
| Wi-Fi provisioning, option A (SD payload, [wifi.md](wifi.md#sd-payload)) | UNTESTED | no evidence |
| Wi-Fi provisioning, option B (SPI CONFIG edit, [wifi.md](wifi.md#if-the-sd-hook-is-fixed)) | UNTESTED | no evidence |
