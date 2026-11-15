# 03 — RTSP and ONVIF

Both servers are compiled into `anyka_ipc` but disabled by two config flags. They can be enabled on the
**stock** firmware without patching, as long as you can edit the JFFS2 config once:

```
/etc/config/anyka_cfg.ini        rtsp_tools        = 1
/etc/config/ipc_property.cjson   bool_onvif_enable = 1
```

The values persist in JFFS2, so the services start on every boot afterwards — no SD card, root shell or
cloud connection needed.

## Streams

| stream | URL | codec |
|---|---|---|
| main | `rtsp://admin:admin@<ip>:554/V_ENC_000` | HEVC 2304×1296 @ 15 fps + PCM A-law |
| sub | `rtsp://admin:admin@<ip>:554/V_ENC_001` | H.264 640×360 @ 15 fps + PCM A-law |

The path is **not** guessable from the binary: `anyka_ipc` only contains the format strings
`rtsp://%s/%s` and `rtsp://%s:%d/%s`. The actual paths are returned by ONVIF `GetStreamUri` for the two
profiles `PROFILE_000` and `PROFILE_001`:

- `/stream0`, `/stream1`, `/live/ch0`, `/h264`, `/onvif1` all return **404** on this firmware;
- only `V_ENC_000` and `V_ENC_001` exist.

Transport: both TCP and UDP work (`ffprobe -rtsp_transport tcp` is recommended).

## ONVIF

- Endpoint: `http://<ip>:10000/onvif/device_service` (non-standard port — scanners that only look at
  port 80/8000 will not find it).
- Authentication: HTTP Digest, realm `happytimesoft`, user `admin`, password `admin` by default.
- Profiles: `PROFILE_000` (main), `PROFILE_001` (sub).
- PTZ node `NODE_000`, spaces `Absolute`, `Relative`, `Continuous`.
  `RelativeMove` and `Stop` return `HTTP/1.1 200 OK`.
- There is **no HTTP/JPEG snapshot server** on this firmware; tools that require a snapshot URL will show
  no image even when RTSP works.

## Credentials

Both services use the vendor defaults (`admin`/`admin`). Change them:

- ONVIF/RTSP: `/etc/config/anyka_cfg.ini` (`user`, `secret`);
- or via ONVIF `SetUser` / `CreateUsers`.

Do not expose 554/10000 to the internet; these cameras have no TLS on the stream and a weak default
password.
