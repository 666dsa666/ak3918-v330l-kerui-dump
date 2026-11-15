# 08 — Verification

These are the checks that were run on the hardware (camera at `<camera-ip>`) to prove the result. They are
reproducible on any unit with the patched application installed.

## 1. The patched binary is the one running

```sh
md5sum /usr/bin/anyka_ipc
# 1841dcdac0db4a0815a8656e8f80461d  /usr/bin/anyka_ipc
```

## 2. Services are up

```sh
netstat -ltn
# tcp  0.0.0.0:554    LISTEN   RTSP
# tcp  0.0.0.0:10000  LISTEN   ONVIF
# tcp  0.0.0.0:6668   LISTEN   vendor P2P
# tcp  0.0.0.0:23     LISTEN   telnet (payload, remove for production)
```

## 3. No Tuya cloud session

```sh
cat /proc/net/tcp | grep -ci ":22B3"     # 0
```

`22B3` = port 8883, the Tuya MQTT broker. A patched camera must show **0** established sessions and no
retry churn. (The extra `mqtt_client_start` stub exists precisely to keep the retry worker from spawning.)

## 4. Video frames actually flow

```bash
ffprobe -v error -rtsp_transport tcp -timeout 8000000 -read_intervals "%+6" \
        -select_streams v:0 -count_frames \
        -show_entries stream=codec_name,width,height,nb_read_frames \
        -of default=noprint_wrappers=1 \
        rtsp://admin:admin@<camera-ip>/V_ENC_001
```

Observed:

```
codec_name=h264
width=640
height=360
nb_read_frames=119
```

and on the main stream:

```bash
ffprobe ... rtsp://admin:admin@<camera-ip>/V_ENC_000
# hevc, 2304x1296, nb_read_frames=118
```

A snapshot can be captured with:

```bash
ffmpeg -rtsp_transport tcp -i rtsp://admin:admin@<camera-ip>/V_ENC_000 -frames:v 1 snapshot.png
```

If `nb_read_frames` is `N/A` or the dimensions are `0x0`, the encoder channels are not bound — check that
`media_chsub_enable` at `0xB6CA0` is intact (see [`04-decloud-patch.md`](04-decloud-patch.md)).

## 5. Audio

`ffprobe` reports a second stream `pcm_alaw` on both profiles.

## 6. LED

Steady (off, matching stock online behaviour). No continuous blue blink.

## 7. Clock

With the SD payload's NTP loop, the OSD timestamp matches local time and the RTC is written
(`hwclock -w -u`). On a cold boot without network the clock starts from the RTC rather than 1980.

## 8. RTSP survives a WAN cut

With `patched2` and later patch sets, removing the default route (and even poisoning the gateway ARP)
leaves 554 listening and the stream playable. This is the `ak_rtsp_exit`/`onvif_stop` neutering at work.
The camera may keep trying to restore its route — that is the vendor network watchdog and is harmless
once the application no longer depends on the cloud.

## 9. ONVIF

```bash
# GetSystemDateAndTime, GetProfiles, GetStreamUri, RelativeMove, Stop
```

PTZ node `NODE_000`, `RelativeMove`/`Stop` return `HTTP/1.1 200 OK` with Digest auth `admin`/`admin`.
