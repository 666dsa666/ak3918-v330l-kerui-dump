#!/bin/sh
# update.nor.sh - bind-mount the patched anyka_ipc over the stock one.
# Runs from the SD hook before anyka_service.sh starts the vendor app.
# Nothing is written to flash; removing the card restores stock behaviour.

SD=/mnt
LOG="$SD/patch-report.txt"

log() { echo "$*" >> "$LOG" 2>/dev/null; }

log "=== bind patch $(date) ==="
log "stock md5: $(md5sum /usr/bin/anyka_ipc 2>&1)"

mount --bind "$SD/anyka_ipc_patched.bin" /usr/bin/anyka_ipc 2>>"$LOG"
log "mounted: $(md5sum /usr/bin/anyka_ipc 2>&1)"

telnetd -p 23 -l /bin/sh >/dev/null 2>&1 &
log "telnetd on 23"

# --- timezone: rootfs /etc/TZ is read-only squashfs (CST-8); bind Paris over it ---
# so the vendor app's OSD shows local time. Edit $SD/TZ to change zone.
if [ -f "$SD/TZ" ]; then
  mount --bind "$SD/TZ" /etc/TZ 2>>"$LOG"
  log "TZ bound: $(cat /etc/TZ)"
fi

# --- clock: cloud is cut, so sync time locally instead of showing 1980 ---
# Seed system clock from the RTC first (last-known-good, not 1980 once persisted).
hwclock -s -u 2>>"$LOG"
# Background: wait for the network, NTP-sync, persist to the RTC, then re-sync every 6h.
(
  i=0
  while [ $i -lt 150 ]; do
    ping -c1 -W2 162.159.200.1 >/dev/null 2>&1 && break
    sleep 2; i=$((i+1))
  done
  while true; do
    if ntpd -nq -p 162.159.200.1 -p 162.159.200.123 -p 129.6.15.28 -p pool.ntp.org >/dev/null 2>&1; then
      hwclock -w -u 2>/dev/null
      echo "time sync OK: $(date)" >> "$LOG"
    else
      echo "time sync FAILED (no NTP): $(date)" >> "$LOG"
    fi
    sleep 21600
  done
) &
log "time-sync backgrounded"
log "=== end ==="
exit 0
