<#
  prep-sd-full.ps1 - write the complete local-camera payload to an SD card:
    anyka_ipc_patched.bin  (patched app: local RTSP+video, MQTT off, LED steady)
    update.nor.sh          (bind-mount + telnet + TZ bind + NTP/RTC time sync)
    TZ                     (POSIX timezone, Europe/Paris by default)
  Verifies MD5 of the binary and the presence of the other two.
  Usage:  .\prep-sd-full.ps1 -Drive E
          .\prep-sd-full.ps1            # auto-detect the CAMPAYLOAD card
#>
[CmdletBinding()]
param(
    [string]$Drive,
    [string]$Binary = (Join-Path $PSScriptRoot 'anyka_ipc_patched.bin'),
    [string]$Payload = (Join-Path $PSScriptRoot 'update.nor.sh'),
    [string]$TzFile = (Join-Path $PSScriptRoot 'TZ')
)

$ErrorActionPreference = 'Stop'
$bin    = $Binary
$script = $Payload
$tz     = $TzFile
$binMd5 = '1841dcdac0db4a0815a8656e8f80461d'

if (-not $Drive) {
    $v = Get-Volume | Where-Object { $_.FileSystemLabel -eq 'CAMPAYLOAD' -or $_.FileSystem -like 'FAT*' } | Select-Object -First 1
    if (-not $v -or -not $v.DriveLetter) { throw "No FAT/CAMPAYLOAD card found. Insert the SD and pass -Drive <letter>." }
    $Drive = [string]$v.DriveLetter
}
$Drive = $Drive.TrimEnd(':')
$dst = "${Drive}:"
if (-not (Test-Path $dst)) { throw "Drive $dst not ready." }

Write-Host "Target SD: $dst" -ForegroundColor Cyan
Copy-Item $bin    "$dst\anyka_ipc_patched.bin" -Force
Copy-Item $script "$dst\update.nor.sh"         -Force
Copy-Item $tz     "$dst\TZ"                     -Force

$m = (Get-FileHash "$dst\anyka_ipc_patched.bin" -Algorithm MD5).Hash.ToLower()
$crU = [bool]([IO.File]::ReadAllBytes("$dst\update.nor.sh") -contains 13)
$crT = [bool]([IO.File]::ReadAllBytes("$dst\TZ") -contains 13)

Write-Host ""
Write-Host "binaire MD5 : $m  (attendu $binMd5)  match=$($m -eq $binMd5)"
Write-Host "update.nor.sh CR present: $crU  (doit etre False = LF)"
Write-Host "TZ            : $([IO.File]::ReadAllText("$dst\TZ").Trim())  CR=$crT"
Write-Host ""
Get-ChildItem $dst | Select-Object Name, Length | Format-Table -AutoSize
if ($m -eq $binMd5 -and -not $crU -and -not $crT) {
    Write-Host "OK - carte prete. Ejecter et inserer dans la camera." -ForegroundColor Green
} else {
    Write-Host "ATTENTION: une verification a echoue (voir ci-dessus)." -ForegroundColor Yellow
}
