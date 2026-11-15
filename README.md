# AK3918EV330 Tuya camera — local RTSP/ONVIF and Tuya-cloud-free operation

Documentation, tooling and patch recipes for a **Tuya/Anyka `AK3918EN080 V330L` (`AK39EV330`)** camera running
firmware **`v33.53.61`**. It started as a firmware dump for
[OpenIPC/firmware#1970](https://github.com/OpenIPC/firmware/issues/1970) and grew into a complete,
reversible way to run the camera **without any Tuya cloud connection** while keeping RTSP, ONVIF, PTZ,
video, audio, a correct clock and a steady LED.

> **Status: working and verified on hardware.** RTSP + ONVIF + full video frames with **zero Tuya MQTT
> sessions**, no router rules, no flash writes — the patched application is bind-mounted from the SD card
> at boot and the camera reverts to stock when the card is removed.
>
> Validated on **two units**: the cloud-linked production camera and a spare that had never been linked
> to a Tuya account. Both run the identical `anyka_ipc` build, and the same patched binary works on both.

## What is in this repository

| path | contents |
|---|---|
| [`docs/01-hardware.md`](docs/01-hardware.md) | SoC, flash, sensor, Wi-Fi, firmware, partition table, hashes |
| [`docs/02-dump.md`](docs/02-dump.md) | how the flash/APP dump was made, what is published, what is deliberately excluded |
| [`docs/03-rtsp-onvif.md`](docs/03-rtsp-onvif.md) | enabling and using RTSP/ONVIF, stream URLs, PTZ, credentials |
| [`docs/04-decloud-patch.md`](docs/04-decloud-patch.md) | the binary patch set: cloud off, RTSP on, video frames, LED, why each patch exists |
| [`docs/05-sd-deployment.md`](docs/05-sd-deployment.md) | SD payload, boot hook, timezone/NTP, install and recovery |
| [`docs/06-wifi-provisioning.md`](docs/06-wifi-provisioning.md) | joining Wi-Fi without the official app |
| [Xiaomi MJSXJ02CM notes](https://github.com/666dsa666/xiaomi-mjsxj02cm-hacks) | **separate repository**: different SoC, downgrade-blocked firmware, UART/SPI mod plan |
| [`docs/07-verification.md`](docs/07-verification.md) | the exact checks used to prove the result |
| [`scripts/`](scripts/) | patch builder, SD preparation, payload, telnet/ONVIF tools |

## Quick start

1. **Get your own stock `anyka_ipc`.** Read `/usr/bin/anyka_ipc` from the camera (root shell via the SD hook,
   `dd`, or extract it from your own APP partition dump). The stock binary is 3,382,008 bytes,
   MD5 `ab81807d9e2d9d5dc946419af43e69b6`.
2. **Build the patched binary** (needs Python 3 + `capstone` + `pyelftools`):

   ```bash
   python scripts/patch_anyka_ipc.py anyka_ipc_stock.bin anyka_ipc_patched.bin
   ```

   The script checks every original instruction word before patching and refuses to continue if the
   binary is not the expected build. Expected result: 3,382,008 bytes, MD5 `1841dcdac0db4a0815a8656e8f80461d`.
3. **Prepare the SD card** (FAT32) with exactly three files:
   `anyka_ipc_patched.bin`, `update.nor.sh`, `TZ` — see [`docs/05-sd-deployment.md`](docs/05-sd-deployment.md).
4. Insert the card, power on, and verify:

   ```bash
   ffprobe -rtsp_transport tcp -i rtsp://admin:admin@<camera-ip>/V_ENC_001
   ```

Nothing is written to flash. Remove the card and reboot to return to the stock application.

## Result at a glance

| item | value |
|---|---|
| RTSP | `rtsp://admin:admin@<ip>:554/V_ENC_000` (HEVC 2304×1296 + PCM A-law) |
| RTSP | `rtsp://admin:admin@<ip>:554/V_ENC_001` (H.264 640×360 + PCM A-law) |
| ONVIF | `http://<ip>:10000/onvif/device_service`, Digest `admin`/`admin` |
| Tuya cloud | no MQTT session, no reconnect churn, `8883` sockets = 0 |
| LED | steady (stock "online" behaviour) |
| Clock | NTP-synced through the local router, RTC persisted, OSD in local time |
| PTZ | ONVIF `RelativeMove` / `ContinuousMove` / `Stop` |

## Important security notes

- The RTSP/ONVIF credentials are the vendor defaults (`admin`/`admin`). **Change them** and never expose
  ports 554/10000 to the internet.
- The SD payload starts `telnetd` as root for diagnostics. Remove that line for day-to-day use.
- The patch disables the cloud, not the local attack surface: treat the camera as an untrusted LAN device.

## Legal / intent

This documents modification of **personally owned hardware** for local-only operation and interoperability.
No vendor firmware is redistributed here beyond the dump that the OpenIPC issue explicitly requested; the
patched binary is **not** published — you build it from your own dump with the provided script.
Vendor firmware and components remain the property of their respective owners. Use at your own risk.

## Credits

- [ErikBavenstrand/anyka-ak3918ev330-tuya-ipc-firmware](https://github.com/ErikBavenstrand/anyka-ak3918ev330-tuya-ipc-firmware) —
  sibling build on the same SoC; its patches and decompiled source were the reference that made the
  "skip cloud wait, start RTSP locally" approach obvious.
- [OpenIPC/firmware#1970](https://github.com/OpenIPC/firmware/issues/1970) — the dump request this started from.

## License

Scripts: MIT (see [`LICENSE`](LICENSE)). Documentation: CC BY 4.0.
