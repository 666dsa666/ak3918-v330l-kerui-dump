<#
.SYNOPSIS
    Prepare a FAT32 SD card so an Anyka AK3918 / LSC Tuya camera opens a root telnet shell.

.DESCRIPTION
    Writes only three small files to the card root (no vendor binaries, nothing downloaded):
        _ht_av_tuning.conf   empty marker file required by the stock firmware
        shadow               root password hash  (root / telnet)
        dump_app.sh          the partition dump script you run once you are in

    This is the documented LSC / Merkury SD-card root method for these Tuya cameras
    (guino/LSCOutdoor1080P) and it is confirmed working on SDK V1.02.04 by the
    reporter in OpenIPC/firmware#1970.

.PARAMETER Path
    SD card root, e.g. E:\  or  E:

.EXAMPLE
    .\prepare-sd.ps1 -Path E:\
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Path,

    # Allow a non-FAT32 volume or a plain folder (advanced / testing).
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

# --- resolve the target ------------------------------------------------------
if ($Path -match '^[A-Za-z]:$') { $Path = $Path + '\' }
if (-not (Test-Path -LiteralPath $Path)) { throw "Path not found: $Path" }
$root = (Resolve-Path -LiteralPath $Path).Path
if (-not $root.EndsWith('\')) { $root += '\' }

$dir = Get-Item -LiteralPath $root
if (-not $dir.PSIsContainer) { throw "$root is not a directory" }

# --- filesystem check --------------------------------------------------------
$fs = $null
try {
    $drive = Split-Path -Qualifier $root          # "E:"
    $letter = $drive.TrimEnd(':')
    $vol = Get-Volume -DriveLetter $letter -ErrorAction Stop
    $fs = $vol.FileSystem
    $label = $vol.FileSystemLabel
    Write-Host ("Volume {0}  label='{1}'  fs={2}  free={3:N1} GB" -f $drive, $label, $fs, ($vol.SizeRemaining / 1GB))
} catch {
    Write-Host "Could not query the volume (that is fine for a plain folder)." -ForegroundColor DarkGray
}

if ($fs -and $fs -ne 'FAT32') {
    if (-not $Force) {
        throw "The card is $fs. The camera kernel only mounts FAT32 - reformat it as FAT32 (MBR, <= 32 GB works best), then re-run. Use -Force only if you know the camera accepts this filesystem."
    }
    Write-Warning "Card is $fs, not FAT32 - continuing because -Force was given."
}

# --- refuse to scribble on a non-empty non-card directory --------------------
$existing = @(Get-ChildItem -LiteralPath $root -Force -ErrorAction SilentlyContinue)
if ($existing.Count -gt 0 -and -not $existing.Name.Contains('_ht_av_tuning.conf') -and -not $Force) {
    Write-Warning "$root is not empty. If this is really your SD card, re-run with -Force."
    throw "Refusing to write into a non-empty directory without -Force."
}

# --- payload -----------------------------------------------------------------
$shadowLine = 'root:$1$M2qq8yA.$oasb2xrzUG0EVpDuaCBNW1:18943:0:99999:7:::'

# LF-only, no BOM, no trailing newline: the camera reads this file raw.
[System.IO.File]::WriteAllText((Join-Path $root 'shadow'), $shadowLine, (New-Object System.Text.ASCIIEncoding))

# Empty marker file (must be 0 bytes).
$marker = Join-Path $root '_ht_av_tuning.conf'
if (Test-Path -LiteralPath $marker) { Remove-Item -LiteralPath $marker -Force }
[System.IO.File]::WriteAllBytes($marker, [byte[]]@())

$script = Join-Path $PSScriptRoot 'dump_app.sh'
if (-not (Test-Path -LiteralPath $script)) { throw "dump_app.sh not found next to this script ($PSScriptRoot)" }
$text = [System.IO.File]::ReadAllText($script) -replace "`r`n", "`n"
[System.IO.File]::WriteAllText((Join-Path $root 'dump_app.sh'), $text, (New-Object System.Text.UTF8Encoding($false)))

$readme = @'
LSC / AK3918 camera - APP partition dump
========================================

1. Power the camera OFF, insert this card, power it ON.
2. Wait 2-3 minutes (the camera boots and joins Wi-Fi as usual).
3. Find its IP (router DHCP table, Tuya app, or "arp -a" on the PC).
4. telnet <CAMERA-IP> 23      login: root   password: telnet
   (if 23 is closed, try port 24)
5. In the shell run:

       sh /tmp/sd/dump_app.sh

   If /tmp/sd does not exist, first run:

       mount /dev/mmcblk0p1 /tmp/sd
       sh /tmp/sd/dump_app.sh

6. When it prints DONE, power the camera off, take the card out.
7. On the PC:  .\verify-and-pack.ps1 -Source E:\
8. Delete "shadow" and "_ht_av_tuning.conf" from the card when you are finished
   (otherwise the camera re-writes flash on every boot).

Nothing here modifies the camera firmware: the script only reads /dev/mtdN.
'@
[System.IO.File]::WriteAllText((Join-Path $root 'README-FIRST.txt'), ($readme -replace "`r`n", "`n"), (New-Object System.Text.UTF8Encoding($false)))

# --- report ------------------------------------------------------------------
Write-Host ""
Write-Host "Done. Files on $root :" -ForegroundColor Green
Get-ChildItem -LiteralPath $root -Force | Select-Object Name, Length | Format-Table -AutoSize | Out-String | Write-Host
Write-Host "Next: eject safely, then follow README-FIRST.txt on the card." -ForegroundColor Cyan
