#!/bin/sh
# dump_app.sh - dump the APP (mtd7) partition of an Anyka AK3918 Tuya/LSC camera.
#
# Run ON THE CAMERA after the SD-card root exploit:
#     sh /tmp/sd/dump_app.sh
#
# It only ever READS flash (/dev/mtdN). Nothing is written to mtd.
# Outputs, next to this script on the SD card:
#     backup_app.bin        raw APP partition (mtd7, ~5 MB)
#     anyka_ipc_stock.bin   copy of the stock /usr/bin/anyka_ipc
#     dump-report.txt       everything needed to fill in the GitHub issue
#     dd.log                dd progress/errors

SD=$(cd "$(dirname "$0")" 2>/dev/null && pwd)
[ -n "$SD" ] || SD=/tmp/sd
REPORT="$SD/dump-report.txt"

if ! : > "$REPORT" 2>/dev/null; then
    echo "ERROR: cannot write to $SD (SD card not mounted read-write?)"
    exit 1
fi

HAVE_TEE=0
command -v tee >/dev/null 2>&1 && HAVE_TEE=1

log() { printf '%s\n' "$*"; printf '%s\n' "$*" >> "$REPORT"; }
out() { if [ "$HAVE_TEE" = 1 ]; then tee -a "$REPORT"; else cat >> "$REPORT"; fi; }
run() { log "\$ $*"; "$@" 2>&1 | out; }

log "=== AK3918 APP partition dump ==="
log "date   : $(date 2>/dev/null)"
log "script : $0"
log "sd card: $SD"
log ""

log "--- uname ---"
run uname -a
log "--- /proc/cpuinfo ---"
run cat /proc/cpuinfo
log "--- /proc/mtd ---"
run cat /proc/mtd
log "--- mount ---"
run mount
log "--- free space ---"
run df -k "$SD"

# ---------------------------------------------------------------- find APP
APP_DEV=""
APP_LINE=""
APP_SIZE_HEX=""
while read -r line; do
    case "$line" in
        *'"APP"'*)
            idx=${line%%:*}
            idx=${idx#mtd}
            APP_DEV="/dev/mtd$idx"
            APP_LINE="$line"
            APP_SIZE_HEX=$(printf '%s\n' "$line" | sed 's/^[^ ]*[ ]*\([0-9a-fA-F]*\).*/\1/')
            ;;
    esac
done < /proc/mtd

log ""
if [ -z "$APP_DEV" ]; then
    log "ERROR: no partition named APP in /proc/mtd - nothing dumped."
    log "       If your layout differs, dump manually: dd if=/dev/mtd7 of=$SD/backup_app.bin bs=64k"
    exit 1
fi

APP_SIZE=""
if [ -n "$APP_SIZE_HEX" ]; then
    APP_SIZE=$((0x$APP_SIZE_HEX))
fi
log "APP partition : $APP_LINE"
log "device        : $APP_DEV"
[ -n "$APP_SIZE" ] && log "expected size : $APP_SIZE bytes"

FREE=$(df -k "$SD" 2>/dev/null | awk 'NR==2 {print $4}')
if [ -n "$FREE" ]; then
    log "free on SD    : ${FREE} KiB"
    if [ "$FREE" -lt 12288 ]; then
        log "WARNING: less than 12 MiB free - the 5 MB image may not fit."
    fi
fi

# ---------------------------------------------------------------- dump APP
OUT="$SD/backup_app.bin"
rm -f "$OUT"
log ""
log "Dumping $APP_DEV -> $OUT (bs=64k). This takes a few seconds to a minute..."
dd if="$APP_DEV" of="$OUT" bs=65536 2>"$SD/dd.log"
DD_RC=$?
cat "$SD/dd.log" 2>/dev/null | out
[ "$DD_RC" -eq 0 ] || log "WARNING: dd exited with code $DD_RC"
sync

if [ ! -s "$OUT" ]; then
    log "ERROR: $OUT is missing or empty - dump failed."
    exit 1
fi

GOT=$(wc -c < "$OUT" | tr -d ' ')
log "got size      : $GOT bytes"
if [ -n "$APP_SIZE" ] && [ "$GOT" != "$APP_SIZE" ]; then
    log "WARNING: size differs from /proc/mtd ($GOT != $APP_SIZE)."
fi

md5_of() {
    if command -v md5sum >/dev/null 2>&1; then
        md5sum "$1" 2>/dev/null | cut -d' ' -f1
    else
        echo "n/a (no md5sum on device)"
    fi
}

APP_MD5=$(md5_of "$OUT")
log "APP image md5 : $APP_MD5"

# ------------------------------------------------------------ copy anyka_ipc
IPC=""
for p in /usr/bin/anyka_ipc /usr/sbin/anyka_ipc /app/anyka_ipc /bin/anyka_ipc /usr/local/bin/anyka_ipc; do
    if [ -f "$p" ]; then IPC="$p"; break; fi
done
if [ -z "$IPC" ]; then
    IPC=$(find / -maxdepth 4 -name anyka_ipc -type f 2>/dev/null | head -n 1)
fi

IPC_MD5=""
IPC_SIZE=""
if [ -n "$IPC" ]; then
    log ""
    log "Found application binary: $IPC"
    if cat "$IPC" > "$SD/anyka_ipc_stock.bin" 2>/dev/null; then
        IPC_MD5=$(md5_of "$SD/anyka_ipc_stock.bin")
        IPC_SIZE=$(wc -c < "$SD/anyka_ipc_stock.bin" | tr -d ' ')
        log "anyka_ipc copy : $SD/anyka_ipc_stock.bin ($IPC_SIZE bytes)"
        log "anyka_ipc md5  : $IPC_MD5"
    else
        log "WARNING: could not copy $IPC to SD card."
    fi

    log ""
    log "--- product strings containing HT_IPC ---"
    tr -c '[:print:]' '\n' < "$IPC" 2>/dev/null | grep 'HT_IPC' | sort -u | head -n 20 | out
else
    log ""
    log "WARNING: anyka_ipc not found in the usual paths."
fi

# ---------------------------------------------------------------- summary
log ""
log "=== SUMMARY (copy these lines into the issue) ==="
log "APP_DEV=$APP_DEV"
log "APP_SIZE=$GOT"
log "APP_MD5=$APP_MD5"
log "IPC_PATH=$IPC"
log "IPC_SIZE=$IPC_SIZE"
log "IPC_MD5=$IPC_MD5"
log "REPORT=$REPORT"
log ""
log "DONE - power the camera off, put the SD card in your PC and run verify-and-pack.ps1"
