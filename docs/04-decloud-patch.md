# 04 — The de-cloud patch

## The problem

On stock `v33.53.61`, `anyka_ipc` starts its RTSP and ONVIF servers **only after a Tuya MQTT session is
established**. Without the cloud:

- the application sits in a wait loop (`while (mqtt_status != 1) sleep(1);`),
- RTSP/ONVIF never start,
- and if the WAN disappears later, `ak_rtsp_exit` tears the servers down.

Blocking the cloud at the network layer is not enough: the camera re-adds its default route, re-resolves
ARP and keeps reconnecting — and on this kernel there is no netfilter to stop it.

## The approach

Patch the application itself so that it:

1. **never establishes a Tuya session** (no MQTT connect, no reconnect worker),
2. **starts RTSP/ONVIF locally** right after media init,
3. **never tears RTSP down**, even when the cloud is unreachable,
4. keeps the encoder channels bound, so video frames actually flow,
5. leaves the LED steady and the clock correct.

Deployment is a `mount --bind` of the patched file over `/usr/bin/anyka_ipc` from the SD card — no flash
write.

## How the patch was derived

The binary is an ARM `ET_EXEC` with **8,829 exported symbols** in `.dynsym`, which makes symbol-driven
reverse engineering practical (capstone + pyelftools). Key symbols:

| symbol | address |
|---|---|
| `ak_rtsp_init` | `0x0009D814` |
| `ak_rtsp_exit` | `0x0009DF6C` |
| `onvif_start` / `onvif_stop` | `0x0027AA84` / `0x0027AB60` |
| `IPC_APP_get_onvif_switch` / `IPC_APP_set_onvif_switch` | `0x000AEA40` / `0x000AE9F0` |
| `IPC_APP_WAIT_SDK_ONLINE` | `0x000B6C78` |
| `media_and_aduio_init` | `0x000097C7C` |
| `media_chsub_enable` | `0x00097D98` |
| `mqtt_connect` | `0x001FB7B4` |
| `mqtt_client_start` | `0x001526A8` |
| `IPC_APP_Init_Config` | `0x000AFD7C` |

Two findings were decisive:

- `set_onvif_switch(1)` tail-calls `ak_rtsp_init`; calling it **after** `media_and_aduio_init` (not during
  `IPC_APP_Init_Config`, which runs before media is up) starts RTSP safely.
- `IPC_APP_WAIT_SDK_ONLINE` ends with `bl media_chsub_enable` at `0xB6CA0`, and **that** call binds the
  VI→VENC channels. A previous attempt overwrote it with the RTSP call and produced a server with no
  frames. The final patch injects into the (now dead) MQTT sleep loop instead, leaving
  `media_chsub_enable` untouched.

## Final patch set

All offsets are in the stock `anyka_ipc` (3,382,008 B, MD5 `ab81807d…`). Words are little-endian ARM.

| file offset | VA | before | after | meaning |
|---|---|---|---|---|
| `0x08DF6C` | `0x09DF6C` | `e92d41f3` | `e12fff1e` | `ak_rtsp_exit` → `bx lr` (no teardown on WAN loss) |
| `0x26AB60` | `0x27AB60` | `e92d4070` | `e12fff1e` | `onvif_stop` → `bx lr` |
| `0x09EA34` | `0x0AEA34` | `eaffbd4c` | `e12fff1e` | `set_onvif_switch` disable branch → `bx lr` |
| `0x09EAE4` | `0x0AEAE4` | `ebffbd20` | `e1a00000` | direct `bl ak_rtsp_exit` → NOP |
| `0x1EB7B4` | `0x1FB7B4` | `e92d4ff0` | `e3e00000` | `mqtt_connect` → `mvn r0,#0` (return -1) |
| `0x1EB7B8` | `0x1FB7B8` | `e1a05000` | `e12fff1e` | `mqtt_connect` → `bx lr` |
| `0x0A6C8C` | `0x0B6C8C` | `0a000002` | `eaffffff` | `beq` online → `b 0xB6C90` (always skip MQTT wait) |
| `0x0A6C90` | `0x0B6C90` | `e59f0014` | `e3a00001` | `mov r0,#1` (ONVIF/RTSP switch ON) |
| `0x0A6C94` | `0x0B6C94` | `ebff2f78` | `ebffdf55` | `bl set_onvif_switch` → `ak_rtsp_init` |
| `0x0A6C98` | `0x0B6C98` | `eafffff9` | `ea000000` | `b 0xB6CA0` (skip time sync, reach `media_chsub_enable`) |
| `0x0A43B8` | `0x0B43B8` | `ea000012` | `ea00000d` | LED mode 3 (blink) → steady off |
| `0x0A43BC` | `0x0B43BC` | `ea00000f` | `ea00000c` | LED mode 4 (blink) → steady off |
| `0x0A43C4` | `0x0B43C4` | `ea00000d` | `ea00000a` | LED mode 6 (blink) → steady off |
| `0x0A43C8` | `0x0B43C8` | `ea00000e` | `ea000009` | LED mode 7 (blink) → steady off |
| `0x1426A8` | `0x1526A8` | `e3500000` | `e3a00000` | `mqtt_client_start` → `mov r0,#0` (no worker thread) |
| `0x1426AC` | `0x1526AC` | `0a000015` | `e12fff1e` | `mqtt_client_start` → `bx lr` (return 0 = success) |

Resulting flow inside `IPC_APP_WAIT_SDK_ONLINE`:

```
media_and_aduio_init            media ready
set_onvif_switch(1)             -> ak_rtsp_init    (RTSP + ONVIF up)
media_chsub_enable              -> binds VI->VENC  (video frames)
set_online_other_status         -> PTZ / LED / config
```

`media_and_aduio_init` still runs **before** the switch, so the encoder is ready when RTSP starts; the
cloud wait is never entered.

## Why the extra `mqtt_client_start` stub

Forcing `mqtt_connect` to fail already prevents any session, but the SDK still spawns a worker thread
that retries the broker forever, producing a steady trickle of failed TCP SYNs to port `8883`.
Stubbing `mqtt_client_start` to return `0` without creating the thread removes that churn:
`/proc/net/tcp` shows **zero** connections to `:8883` for the whole uptime, with video unaffected.
Both callers (`mqc_app_start`, `direct_connect_tuya_cloud`) treat `r0 == 0` as success.

## LED

`AK_TUYA_Func_Set_Indicator_Light(mode)` is a jump table: modes 0/5 → `led.sh off`, 1/2/8 → `led.sh on`,
3/4/6/7 → `blue_led_blink`. Because the cloud never reports "online", the status callback kept pushing
"connecting" modes 3/4, so the LED blinked forever. Repointing the four blink entries to the mode-5
handler forces a steady `led.sh off`, matching the stock online behaviour.

## Building it

```bash
python scripts/patch_anyka_ipc.py anyka_ipc_stock.bin anyka_ipc_patched.bin
```

The script:

- validates each original word (`expect` column) and aborts on a mismatch,
- refuses to continue if `media_chsub_enable` at `0xB6CA0` was clobbered,
- prints every offset and the disassembled new instruction,
- prints the final MD5. Expected: `1841dcdac0db4a0815a8656e8f80461d`.

If your binary's MD5 is not `ab81807d…`, the offsets will not match — the script will stop at the first
mismatch. That is intentional: this patch is for exactly this build.

## Reverting

Remove the SD card and reboot. The flash was never modified.
