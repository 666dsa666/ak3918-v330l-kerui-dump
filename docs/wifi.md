# Joining Wi-Fi without the vendor app

**Status: UNTESTED** (both the SD payload and the SPI flash path). Nothing on this page was run on
the camera.

The stock firmware is provisioned by the Tuya/Smart Life app (AP or EZ mode). The SD hook
([dump.md](dump.md#sd-update-hook-cve-2025-63296)) allows a manual alternative.

## SD payload

`update.nor.sh` at the root of a FAT32 card:

```sh
#!/bin/sh
killall wpa_supplicant 2>/dev/null

cat > /etc/config/wpa_supplicant.conf <<'EOF'
ctrl_interface=/var/run/wpa_supplicant
update_config=1
ap_scan=1
network={
    ssid="YOUR_SSID"
    psk="YOUR_PASSWORD"
    key_mgmt=WPA-PSK
}
EOF

wpa_supplicant -Dnl80211 -i wlan0 -c /etc/config/wpa_supplicant.conf -B
udhcpc -i wlan0 -b -x hostname:TUYA_IPC
telnetd -p 23 -l /bin/sh &
```

Notes:

- `/etc/config` is the CONFIG partition (JFFS2): **this payload writes to flash**, unlike the
  deployment payload. Back up CONFIG first, from a root shell with the card mounted at `/mnt`:

  ```sh
  dd if=/dev/mtd6 of=/mnt/config_backup.bin bs=4k
  ```

  The backup contains Wi-Fi credentials and Tuya device keys; keep it private
  ([dump.md](dump.md#what-is-not-published)).
- The file name `wpa_supplicant.conf`, the driver `nl80211` and the persistence of this file across the
  vendor application's own Wi-Fi handling are assumptions, not verified on this firmware.
- The payload starts a passwordless root shell on port 23.
- The ATBM603x radio is 2.4 GHz only. WPA3-only networks and hidden SSIDs need `key_mgmt` /
  `scan_ssid` changes.
- To combine with the de-cloud patch, add the bind-mount and clock lines from
  [`scripts/update.nor.sh`](../scripts/update.nor.sh).

## If the SD hook is fixed

This board has no UART ([hardware.md](hardware.md#debug-access-no-uart)). The only remaining path is the
SPI flash: read it with a SOP8 clip, edit the CONFIG JFFS2 image offline, and write it back.

**Writing the flash back is irreversible without a programmer, and there is no console to diagnose a
failed boot. Keep a verified full-flash read (two reads with identical MD5) before any write.**

## Not available

- WPS: not exposed by the vendor firmware.
- Provisioning web page: the provisioning AP uses a proprietary protocol, not HTTP.

## Checks after joining

```sh
ifconfig wlan0
route -n
ping -c1 1.1.1.1
```
