# RTSP and ONVIF

## Enabling flags

Both servers are compiled into `anyka_ipc` and controlled by two flags in the CONFIG partition
(JFFS2, persistent):

```
/etc/config/anyka_cfg.ini        rtsp_tools        = 1
/etc/config/ipc_property.cjson   bool_onvif_enable = 1
```

On the **stock** application, setting the flags is not sufficient: RTSP and ONVIF start only after a
Tuya MQTT session is established, so the camera must be cloud-connected. The de-cloud patch
([patch.md](patch.md)) removes that dependency.

Both test units had these flags set from a root shell (**HW**). Whether the patched build also needs
them is **UNTESTED**; set them if ports 554 and 10000 do not listen.

Commands used, over the telnet shell of an SD payload (they write to the CONFIG partition in flash):

```sh
cp /etc/config/anyka_cfg.ini /mnt/bak-anyka_cfg.ini
cp /etc/config/ipc_property.cjson /mnt/bak-ipc_property.cjson
sed -i 's/^rtsp_tools = 0/rtsp_tools = 1/' /etc/config/anyka_cfg.ini
sed -i 's/"bool_onvif_enable":[[:space:]]*0/"bool_onvif_enable": 1/' /etc/config/ipc_property.cjson
grep -n rtsp_tools /etc/config/anyka_cfg.ini
grep -n bool_onvif_enable /etc/config/ipc_property.cjson
sync
reboot
```

The key and value in `ipc_property.cjson` are separated by a tab: a pattern with `" *"` (spaces only)
does not match. The two backup copies contain device configuration; keep them private. After the
reboot, `netstat -ltn` showed ports 554 and 10000 listening on the cloud-connected stock application.

## Streams

| stream | URL | content |
|---|---|---|
| main | `rtsp://admin:admin@<camera-ip>:554/V_ENC_000` | HEVC 2304×1296, PCM A-law |
| sub | `rtsp://admin:admin@<camera-ip>:554/V_ENC_001` | H.264 640×360, PCM A-law |

Frame rate: `anyka_cfg.ini` sets `main_fps = 15` and `sub_fps = 15`, but the sensor driver reports
`fps:20` and the recorded frame counts (about 120 frames in 6 s, [deploy.md](deploy.md#video-frames))
correspond to roughly 20 fps. The effective rate was not measured directly.

The binary only contains the format strings `rtsp://%s/%s` and `rtsp://%s:%d/%s`; the paths come from
ONVIF `GetStreamUri` for profiles `PROFILE_000` and `PROFILE_001`. Common guesses (`/stream0`,
`/stream1`, `/live/ch0`, `/h264`, `/onvif1`) return 404.

TCP and UDP transport both work; `-rtsp_transport tcp` is recommended for `ffprobe`/`ffmpeg`.

There is no HTTP/JPEG snapshot endpoint. Clients that require a snapshot URL show no image even when
RTSP works; use `ffmpeg -frames:v 1` instead ([deploy.md](deploy.md#video-frames)).

## ONVIF

- Endpoint: `http://<camera-ip>:10000/onvif/device_service` (non-standard port; scanners limited to
  80/8000 do not find it).
- Authentication: HTTP Digest, realm `happytimesoft`, default user `admin`, password `admin`.
- Profiles: `PROFILE_000` (main), `PROFILE_001` (sub).
- PTZ node `NODE_000`.

## PTZ

[`scripts/onvif-ptz.ps1`](../scripts/onvif-ptz.ps1) implements:

| switch | ONVIF operation |
|---|---|
| `-Info` | `GetServices`, `GetNodes` (lists node, name and advertised spaces) |
| `-Move [-Pan x] [-Tilt y]` | `RelativeMove` on `PROFILE_000` |
| `-Stop` | `Stop` |
| `-HomePos` | `GotoHomePosition` |

`ContinuousMove` and `AbsoluteMove` are not implemented in the script. Status: **PARTIAL**.
`RelativeMove` and `Stop` returned HTTP 200 according to the author's unpublished notes; `-Info` and `-HomePos` have no
raw log ([validation.md](validation.md)).

```powershell
.\scripts\onvif-ptz.ps1 -Camera <camera-ip> -Info
.\scripts\onvif-ptz.ps1 -Camera <camera-ip> -Move -Pan 0.1
```

## Credentials

Both services use the vendor defaults `admin`/`admin`. Possible ways to change them (**UNTESTED**):

- `user` and `secret` in `/etc/config/anyka_cfg.ini`;
- ONVIF `SetUser` / `CreateUsers`.

Neither the RTSP stream nor ONVIF uses TLS. Do not expose ports 554 or 10000 outside the LAN.
