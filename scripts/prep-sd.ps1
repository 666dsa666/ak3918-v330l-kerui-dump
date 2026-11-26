# prep-sd.ps1 - write the local-only camera payload to a FAT32 SD card.
#
#   anyka_ipc_patched.bin   patched application (build it with patch_anyka_ipc.py)
#   update.nor.sh           boot payload: bind mount + telnet + TZ + NTP
#   TZ                      POSIX timezone (default Europe/Paris)
#
# Usage:
#   .\prep-sd.ps1 -Drive E
#   .\prep-sd.ps1 -Drive E -Binary .\anyka_ipc_patched.bin
#
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Drive,
    [string]$Binary = (Join-Path $PSScriptRoot 'anyka_ipc_patched.bin'),
    [string]$Payload = (Join-Path $PSScriptRoot 'update.nor.sh'),
    [string]$TzFile = (Join-Path $PSScriptRoot 'TZ'),
    [string]$ExpectedMd5 = '1841dcdac0db4a0815a8656e8f80461d'
)

$ErrorActionPreference = 'Stop'
$dst = $Drive.TrimEnd(':') + ':'
if (-not (Test-Path $dst)) { throw "Drive $dst not ready." }
foreach ($f in @($Binary, $Payload, $TzFile)) {
    if (-not (Test-Path $f)) { throw "missing file: $f" }
}

Copy-Item $Binary  (Join-Path $dst 'anyka_ipc_patched.bin') -Force
Copy-Item $Payload (Join-Path $dst 'update.nor.sh')         -Force
Copy-Item $TzFile  (Join-Path $dst 'TZ')                    -Force

$md5 = (Get-FileHash (Join-Path $dst 'anyka_ipc_patched.bin') -Algorithm MD5).Hash.ToLower()
$crSh = (Get-Content (Join-Path $dst 'update.nor.sh') -Raw) -match "`r"
$tz = (Get-Content (Join-Path $dst 'TZ') -Raw).Trim()

Write-Host ""
Write-Host "binary MD5 : $md5  (expected $ExpectedMd5)  match=$($md5 -eq $ExpectedMd5)"
Write-Host "update.nor.sh has CRLF: $crSh (must be False)"
Write-Host "TZ          : $tz"
Get-ChildItem $dst | Select-Object Name, Length | Format-Table -AutoSize

if ($md5 -eq $ExpectedMd5 -and -not $crSh) {
    Write-Host "OK - card ready. Eject and insert into the camera." -ForegroundColor Green
} else {
    Write-Host "WARNING: a check failed (see above)." -ForegroundColor Yellow
}
