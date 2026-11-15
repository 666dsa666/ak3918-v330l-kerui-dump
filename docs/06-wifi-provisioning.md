# 06 — Joining Wi-Fi without the official app

Stock Tuya firmware has no documented manual provisioning: the Smart Life / Tuya app puts the camera in
AP/EZ mode and writes the Wi-Fi credentials itself. Without the app you have two options.

## Option A — SD payload (this camera family)

The same boot hook used for the patched application can provision Wi-Fi directly. Put this
`update.nor.sh` on a FAT32 card:

```sh
#!/bin/sh
# join Wi-Fi without any cloud/app involvement
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

On boot the camera joins the network before the vendor application starts. Combine it with the bind
mount of the patched binary and the camera never needs the cloud at all.

**Caveats**

- This relies on the SD hook (`CVE-2025-63296`). A newer unit may have it fixed — test with a harmless
  payload (`telnetd` only) and see whether port 23 opens.
- If the Wi-Fi is WPA3-only or uses a hidden SSID, adjust `key_mgmt`/`scan_ssid` accordingly.
- 5 GHz-only networks are not supported (ATBM603x is 2.4 GHz).

## Option B — get root first

If the hook is fixed, Wi-Fi provisioning requires code execution on the device:

- **Same SoC family**: UART console / SPI flash access, then write `/etc/config/wpa_supplicant.conf` or
  use `wpa_cli`.
- **Xiaomi MJSXJ02CM**: Mi Home performs the initial provisioning; without the app you must flash the
  hacked rootfs first (see the separate
  [Xiaomi MJSXJ02CM notes](https://github.com/666dsa666/xiaomi-mjsxj02cm-hacks)).

## What does not work

- **WPS button**: not exposed by the vendor firmware.
- **AP-mode web page**: the camera's provisioning AP uses a proprietary protocol, not HTTP.
- **Cloning router settings**: only helps if you can already write the camera's credentials.

## Result

Once on the network, verify with:

```sh
ifconfig wlan0
route -n
ping -c1 1.1.1.1
```

Then install the patched application ([`05-sd-deployment.md`](05-sd-deployment.md)) if you want it
local-only.
