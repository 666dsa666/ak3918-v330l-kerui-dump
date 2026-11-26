# De-cloud patch for `anyka_ipc`

## Reference hashes

These are the only authoritative values; other pages link here.

| file | size | MD5 |
|---|---|---|
| stock `/usr/bin/anyka_ipc` (`v33.53.61`) | 3,382,008 B | `ab81807d9e2d9d5dc946419af43e69b6` |
| patched build (output of `patch_anyka_ipc.py`) | 3,382,008 B | `1841dcdac0db4a0815a8656e8f80461d` |

The patched build is not distributed; the MD5 above is a reference to compare a local build against.
`patch_anyka_ipc.py` produces this MD5 from the stock binary, and the binary with this MD5 is the one
run on hardware (**HW**).

## Problem

On stock `v33.53.61`, `anyka_ipc` starts its RTSP and ONVIF servers only after a Tuya MQTT session is
established, even when the RTSP/ONVIF flags are enabled in the configuration
([rtsp-onvif.md](rtsp-onvif.md#enabling-flags)). Without the cloud:

- the application waits in a loop until the MQTT status is online, so RTSP/ONVIF never start;
- if the WAN disappears later, `ak_rtsp_exit` tears the servers down.

Blocking the cloud at the network level does not help: the kernel has no netfilter, the application
uses its own resolver (so `/etc/hosts` is ignored), and the vendor network watchdog restores the
default route.

The patch removes the dependency on the Tuya session inside the application.

## Goals

1. Never establish a Tuya session (no MQTT connect, no reconnect worker).
2. Start RTSP/ONVIF locally after media initialisation.
3. Never tear RTSP/ONVIF down when the WAN is lost.
4. Keep the encoder channels bound so that video frames flow.
5. Keep the status LED steady.

## Derivation

The binary exports 8,829 symbols, which makes symbol-driven analysis with `capstone` and `pyelftools`
practical. Relevant symbols (virtual addresses):

| symbol | VA |
|---|---|
| `ak_rtsp_init` | `0x0009D814` |
| `ak_rtsp_exit` | `0x0009DF6C` |
| `onvif_start` / `onvif_stop` | `0x0027AA84` / `0x0027AB60` |
| `IPC_APP_set_onvif_switch` / `IPC_APP_get_onvif_switch` | `0x000AE9F0` / `0x000AEA40` |
| `IPC_APP_Init_Config` | `0x000AFD7C` |
| `IPC_APP_WAIT_SDK_ONLINE` | `0x000B6C78` |
| `AK_TUYA_Func_Set_Indicator_Light` | `0x000B43A0` |
| `media_and_aduio_init` (sic, vendor symbol) | `0x00097C7C` |
| `media_chsub_enable` | `0x00097D98` |
| `mqtt_client_start` | `0x001526A8` |
| `mqtt_connect` | `0x001FB7B4` |

Stock flow of `IPC_APP_WAIT_SDK_ONLINE`:

```
0xB6C7C  bl media_and_aduio_init   ; (sic, vendor symbol)
0xB6C80  bl IPC_set_default_config_for_app_before_online
0xB6C84  bl IPC_APP_Get_MqttStatus
0xB6C88  cmp r0, #1
0xB6C8C  beq 0xB6C9C              ; otherwise sleep(1) and retry until MQTT is online
0xB6C9C  bl IPC_APP_Sync_Utc_Time
0xB6CA0  bl media_chsub_enable    ; binds VI -> VENC, required for frames
0xB6CA8  b  set_online_other_status
```

Findings that shaped the patch:

- `set_onvif_switch(1)` tail-calls `ak_rtsp_init`. Calling it from `IPC_APP_Init_Config` runs before media
  is up and causes a boot loop; calling it after `media_and_aduio_init` is safe.
- The `bl media_chsub_enable` at `0xB6CA0` binds the encoder channels. An earlier attempt that
  overwrote it produced an RTSP server with no frames. The final patch places the RTSP start in the
  MQTT wait loop, which is dead code once the wait is skipped, and leaves `0xB6CA0` untouched.
- `mqtt_connect` returning `-1` prevents any session, but the SDK worker started by
  `mqtt_client_start` keeps retrying the broker (failed SYNs to port 8883). Both callers
  (`mqc_app_start`, `direct_connect_tuya_cloud`) treat `r0 == 0` as success, so the entry is stubbed to
  return 0 without creating the thread.
- `AK_TUYA_Func_Set_Indicator_Light(mode)` is a jump table: modes 0/5 → `led.sh off`, 1/2/8 →
  `led.sh on`, 3/4/6/7 → blink. Without the cloud the status callback keeps requesting modes 3/4.
  The four blink entries are redirected to the mode-5 handler (`0xB43F4`).

## Patch table

File offsets and VAs in the stock binary; 32-bit little-endian ARM words.

| file offset | VA | before | after | effect |
|---|---|---|---|---|
| `0x08DF6C` | `0x09DF6C` | `e92d41f3` | `e12fff1e` | `ak_rtsp_exit` → `bx lr` |
| `0x26AB60` | `0x27AB60` | `e92d4070` | `e12fff1e` | `onvif_stop` → `bx lr` |
| `0x09EA34` | `0x0AEA34` | `eaffbd4c` | `e12fff1e` | `set_onvif_switch` disable branch → `bx lr` |
| `0x09EAE4` | `0x0AEAE4` | `ebffbd20` | `e1a00000` | direct `bl ak_rtsp_exit` → `nop` |
| `0x1EB7B4` | `0x1FB7B4` | `e92d4ff0` | `e3e00000` | `mqtt_connect` → `mvn r0, #0` |
| `0x1EB7B8` | `0x1FB7B8` | `e1a05000` | `e12fff1e` | `mqtt_connect` → `bx lr` (returns -1) |
| `0x0A6C8C` | `0x0B6C8C` | `0a000002` | `eaffffff` | `beq` → `b 0xB6C90` (MQTT wait skipped) |
| `0x0A6C90` | `0x0B6C90` | `e59f0014` | `e3a00001` | `mov r0, #1` |
| `0x0A6C94` | `0x0B6C94` | `ebff2f78` | `ebffdf55` | `bl set_onvif_switch` (→ `ak_rtsp_init`) |
| `0x0A6C98` | `0x0B6C98` | `eafffff9` | `ea000000` | `b 0xB6CA0` (skips time sync, reaches `media_chsub_enable`) |
| `0x0A43B8` | `0x0B43B8` | `ea000012` | `ea00000d` | LED mode 3 → mode-5 handler |
| `0x0A43BC` | `0x0B43BC` | `ea00000f` | `ea00000c` | LED mode 4 → mode-5 handler |
| `0x0A43C4` | `0x0B43C4` | `ea00000d` | `ea00000a` | LED mode 6 → mode-5 handler |
| `0x0A43C8` | `0x0B43C8` | `ea00000e` | `ea000009` | LED mode 7 → mode-5 handler |
| `0x1426A8` | `0x1526A8` | `e3500000` | `e3a00000` | `mqtt_client_start` → `mov r0, #0` |
| `0x1426AC` | `0x1526AC` | `0a000015` | `e12fff1e` | `mqtt_client_start` → `bx lr` (returns 0, no worker) |

Resulting flow:

```
media_and_aduio_init      media ready
set_onvif_switch(1)       -> ak_rtsp_init (RTSP + ONVIF up)
media_chsub_enable        -> VI -> VENC bound (frames)
set_online_other_status   -> PTZ / LED / config
```

The vendor cloud time sync (`IPC_APP_Sync_Utc_Time`) is skipped; the SD payload sets the clock
instead ([deploy.md](deploy.md#what-updatenorsh-does)).

## Building

```bash
pip install capstone pyelftools
python scripts/patch_anyka_ipc.py anyka_ipc_stock.bin anyka_ipc_patched.bin
```

The script:

- refuses an input whose size or MD5 differs from the stock reference (this alone guarantees the
  offsets apply);
- checks the original word at 8 of the 16 patched locations and aborts on a mismatch;
- checks that `bl media_chsub_enable` at `0xB6CA0` is intact;
- prints each patched word with its disassembly and the MD5 of the output.

**Compare the printed MD5 with the patched reference above.** A mismatch only prints a warning and
the script still exits with status 0 ([known-issues.md](known-issues.md#patch_anyka_ipcpy)).

## Reverting

Remove the SD card and reboot. The flash is never modified.
