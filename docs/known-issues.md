# Known issues

Documented, not fixed. The scripts are published as used.

## patch_anyka_ipc.py

- The input size and MD5 are verified against the stock reference. This is what guarantees that the
  offsets apply.
- Only 8 of the 16 patched words have their original value checked individually (`ak_rtsp_exit`,
  the `set_onvif_switch` disable branch, the `beq` at `0xB6C8C`, the four LED entries and the first
  `mqtt_client_start` word). The docstring and comments say "every" word; that is inaccurate.
- If the output MD5 differs from the patched reference, the script prints `WARNING` and still exits
  with status 0 and leaves the output file in place. The output MD5 printed at the end is the real
  check: compare it with [patch.md](patch.md#reference-hashes).
- On a match the script prints `matches the published patched build`. No patched binary is published;
  the message refers to the reference MD5 only.

## update.nor.sh

- Starts `telnetd -p 23 -l /bin/sh` by default: a root shell without password on the LAN.
- Bind-mounts `/mnt/anyka_ipc_patched.bin` without checking its MD5. A truncated or wrong file on the
  card is executed as the vendor application. Verify the file before inserting the card.
- The network wait pings a fixed public address (`162.159.200.1`). On a network that blocks it, the
  NTP loop starts only after the wait gives up (150 attempts).
- Writes its log to the card on every boot (`/mnt/patch-report.txt`, appended).

## prep-sd.ps1

- Copies the files to the card first and verifies afterwards; on a failed check the card already holds
  the copied files and the script only prints a warning.
- Does not refuse a system drive: `-Drive C` writes to the root of `C:`.
- Checks `update.nor.sh` for CR characters, but not `TZ`. A CRLF `TZ` file must be avoided.
- A wrong binary MD5 is reported as a warning, not an error.

## prep-sd-full.ps1

- Without `-Drive`, selects the first volume labelled `CAMPAYLOAD` **or any FAT volume**
  (`Select-Object -First 1`): another FAT drive (USB stick, second card) can be chosen. Pass `-Drive`.
- Copies the files to the card first and verifies afterwards; on a failed check the card already holds
  the copied files and the script only prints a warning (`ATTENTION: ...`) with exit status 0.
- Does not refuse a system drive.
- Console messages are in French.

## Dump payload

[`scripts/dump-payload/update.nor.sh`](../scripts/dump-payload/update.nor.sh):

- The "already dumped" check compares the size of `backup_app.bin` with `5242880` bytes (5 MiB). The
  APP partition on this board is `0x426000` (4,349,952) bytes, so the check never matches and the
  partition is read again on every boot while the card is inserted.
- Starts two root shells without password, `telnetd` on ports 23 and 24.
- Copies `/usr/bin/anyka_ipc` and appends to `/mnt/update-report.txt` on every boot.

[`scripts/dump-payload/install-cve-payload.ps1`](../scripts/dump-payload/install-cve-payload.ps1):

- The `README-UPDATE-PAYLOAD.txt` it writes describes the APP partition as 5 MiB and refers to a
  `HARDWARE-FALLBACK.md` that is not part of this repository.
- `-RemoveDeadFiles` deletes `_ht_av_tuning.conf`, `shadow`, `dump_app.sh` and `README-FIRST.txt`
  from the card root.

## remote-dump.ps1

- The default mode mounts `/dev/mmcblk0p1` on `/tmp/sd` and runs `/tmp/sd/dump_app.sh` (LSC layout).
  On this board the card is already mounted at `/mnt`; use `-NoLogin -Command "<shell command>"`.
- The default login (`root` / `telnet`) matches the `shadow` file written by `prepare-sd.ps1`, not the
  deployment payload, which needs `-NoLogin`.
- Writes a transcript `remote-dump-<timestamp>.log` in the current directory.

## Dump helpers

`prepare-sd.ps1`, `dump_app.sh` and `verify-and-pack.ps1` were written for the LSC units of
OpenIPC#1970. On this board:

- `prepare-sd.ps1`: the `_ht_av_tuning.conf` + `shadow` root method is **UNTESTED**. It writes a root
  password hash for the public password `telnet`. Flash-write warning for the marker files:
  [dump.md](dump.md#helper-scripts-from-the-lsc-method).
- `dump_app.sh`: expects to be run from the card directory; size messages assume a ~5 MB APP partition
  (this board: 4,349,952 B). No run on this board is recorded (**UNTESTED**).
- `verify-and-pack.ps1`: defaults target the LSC build (`-ExpectedIpcMd5 86396fdb…`, camera name
  "LSC Smart Connect PTZ"); pass `-CameraName` for this board. The generated issue-comment draft is
  written in the first person and should be reviewed before posting.

## Hardware and firmware limits

- No UART on board `5810-V7.0`; recovery from a bad flash write needs an SPI programmer.
- The SD hook may be fixed on newer units; in that case no payload runs and the camera boots stock.
- The patch applies to one exact `anyka_ipc` build only.
