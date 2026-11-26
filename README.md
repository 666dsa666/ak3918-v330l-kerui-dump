# Anyka AK3918EN080 V330L (board 5810-V7.0) — firmware dump and local-only RTSP/ONVIF

Firmware notes, dump tooling and a binary patch recipe for a Tuya camera built on the Anyka
**AK3918EN080 V330L** SoC (main board **5810-V7.0**, Tuya application `v33.53.61`).

The work started as an APP-partition dump for
[OpenIPC/firmware#1970](https://github.com/OpenIPC/firmware/issues/1970) and was extended into a
reversible way to run the camera without any Tuya cloud session while keeping RTSP, ONVIF, video,
audio, a correct clock and a steady LED.

## Scope

- One ODM build: Tuya `v33.53.61`, stock `anyka_ipc` with the MD5 given in [docs/patch.md](docs/patch.md).
  The patch refuses any other build.
- No flash writes: the patched application is bind-mounted from the SD card at boot.
- Not covered: custom firmware, OpenIPC flashing, other SoCs or other camera models.

## Status

| item | status |
|---|---|
| Patched `anyka_ipc` running, RTSP + ONVIF up, video frames, zero Tuya MQTT sessions | **HW** (units and per-check evidence: [docs/validation.md](docs/validation.md)) |
| SD boot payload `update.nor.sh` (bind mount, telnetd, timezone, NTP) | **HW** |
| `patch_anyka_ipc.py` output (patched reference MD5) running on the camera | **HW** |
| APP dump with the dump payload; full-flash read with `cat /dev/mtd0…7` over `remote-dump.ps1` | **HW** |
| SD card preparation with `prep-sd-full.ps1` (used) / `prep-sd.ps1` (minimal) | **PARTIAL** |
| ONVIF PTZ `RelativeMove` / `Stop` / `GotoHomePosition` via `onvif-ptz.ps1` | **PARTIAL** |
| Wi-Fi provisioning without the vendor app | **UNTESTED** |

Status tags and per-item evidence: [docs/validation.md](docs/validation.md).

## Safety

- The SD payload starts a **passwordless root `telnetd`** on port 23 by default. See
  [docs/deploy.md](docs/deploy.md#security).
- RTSP/ONVIF use the vendor defaults `admin`/`admin`, without TLS. Keep ports 554 and 10000 on the LAN.
- The patch removes the cloud dependency, not the local attack surface.
- Known defects in the scripts are listed in [docs/known-issues.md](docs/known-issues.md).

## Quick start

Prerequisites:

- the camera paired once with the Tuya/Smart Life app and joined to the LAN (provisioning without the
  app, [docs/wifi.md](docs/wifi.md), is **UNTESTED**);
- the camera IP address (`<camera-ip>`), for example from the router DHCP client table;
- a FAT32 microSD card and a Windows PC with PowerShell;
- Python 3 with `pip install capstone pyelftools`;
- `ffprobe`/`ffmpeg` for the checks.

1. Read the stock `/usr/bin/anyka_ipc` from the camera ([docs/dump.md](docs/dump.md)):
   1. write the dump payload to the card: `.\scripts\dump-payload\install-cve-payload.ps1 -Path E:\`;
   2. insert the card, cold-boot the camera, wait a few minutes, power off;
   3. copy `anyka_ipc_stock.bin` from the card to the PC (or use `anyka_ipc.bin` from the release zip;
      check its MD5 against [docs/patch.md](docs/patch.md#reference-hashes)).
2. `python scripts/patch_anyka_ipc.py anyka_ipc_stock.bin anyka_ipc_patched.bin` and compare the printed
   MD5 with the patched reference ([docs/patch.md](docs/patch.md#reference-hashes)).
3. Reuse the card as the deployment card. The dump card and the deployment card both rely on a file named
   `update.nor.sh`; the deployment script overwrites it.
   `.\scripts\prep-sd.ps1 -Drive E -Binary .\anyka_ipc_patched.bin` ([docs/deploy.md](docs/deploy.md)).
4. Insert the card and power the camera on.
5. `ffprobe -rtsp_transport tcp -i rtsp://admin:admin@<camera-ip>/V_ENC_001`

If ports 554 and 10000 do not listen, set the RTSP/ONVIF flags
([docs/rtsp-onvif.md](docs/rtsp-onvif.md#enabling-flags)).

Remove the card and reboot to return to the stock application.

## Documentation

| file | contents |
|---|---|
| [docs/hardware.md](docs/hardware.md) | SoC, board, flash layout, absence of UART |
| [docs/dump.md](docs/dump.md) | root access via the SD hook, how the flash was read, what is and is not published (APP dump: release [`v1`](https://github.com/666dsa666/ak3918-v330l-kerui-dump/releases/tag/v1)) |
| [docs/patch.md](docs/patch.md) | the de-cloud binary patch: problem, derivation, patch table, reference MD5s |
| [docs/deploy.md](docs/deploy.md) | SD payload, install, verification, recovery, security |
| [docs/rtsp-onvif.md](docs/rtsp-onvif.md) | stream URLs, ONVIF endpoint, PTZ, credentials |
| [docs/wifi.md](docs/wifi.md) | joining Wi-Fi without the vendor app (**UNTESTED**) |
| [docs/known-issues.md](docs/known-issues.md) | known script defects and limitations |
| [docs/validation.md](docs/validation.md) | validation status of each component (HW / PARTIAL / STATIC / UNTESTED) |

## Scripts

| file | runs on | purpose |
|---|---|---|
| [`patch_anyka_ipc.py`](scripts/patch_anyka_ipc.py) | PC (Python 3, `capstone`, `pyelftools`) | builds the patched application |
| [`update.nor.sh`](scripts/update.nor.sh) | camera (SD hook) | bind mount, telnetd, timezone, NTP |
| [`TZ`](scripts/TZ) | camera (SD card) | POSIX timezone string |
| [`prep-sd-full.ps1`](scripts/prep-sd-full.ps1) | PC (PowerShell) | writes the deployment card (version actually used; French console output) |
| [`prep-sd.ps1`](scripts/prep-sd.ps1) | PC (PowerShell) | writes the deployment card (recommended; minimal version) |
| [`onvif-ptz.ps1`](scripts/onvif-ptz.ps1) | PC (PowerShell) | minimal ONVIF PTZ client |
| [`dump-payload/update.nor.sh`](scripts/dump-payload/update.nor.sh) | camera (SD hook) | dump payload: APP partition and `anyka_ipc` to the card, telnetd |
| [`dump-payload/install-cve-payload.ps1`](scripts/dump-payload/install-cve-payload.ps1) | PC (PowerShell) | writes the dump payload to a card |
| [`remote-dump.ps1`](scripts/remote-dump.ps1) | PC (PowerShell) | raw telnet client; runs a dump script or a single command |
| [`prepare-sd.ps1`](scripts/prepare-sd.ps1) | PC (PowerShell) | writes a dump card (LSC-style root method, **UNTESTED** on this board) |
| [`dump_app.sh`](scripts/dump_app.sh) | camera | reads the APP partition and `anyka_ipc` to the card (**UNTESTED** on this board) |
| [`verify-and-pack.ps1`](scripts/verify-and-pack.ps1) | PC (PowerShell) | checks a dump and packs it for the OpenIPC issue |

## Legal

Modification of personally owned hardware for local-only operation and interoperability. The
repository tree contains no vendor binaries and no patched binary; release `v1` contains the unmodified
stock APP partition and `anyka_ipc` dumped for OpenIPC#1970. The patched application is built locally
from the user's own stock binary. Vendor firmware remains the property of its owners.
Use at your own risk.

## Credits

- [ErikBavenstrand/anyka-ak3918ev330-tuya-ipc-firmware](https://github.com/ErikBavenstrand/anyka-ak3918ev330-tuya-ipc-firmware) —
  a different build on the same SoC family; its "skip cloud wait, start RTSP locally" patches were the reference for this approach.
- [OpenIPC/firmware#1970](https://github.com/OpenIPC/firmware/issues/1970) — the dump request this started from.

## License

Scripts: MIT (see [LICENSE](LICENSE)). Documentation: CC BY 4.0.
