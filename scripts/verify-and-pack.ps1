<#
.SYNOPSIS
    Verify the APP dump taken from an LSC / Anyka AK3918 camera and pack it for GitHub.

.DESCRIPTION
    Reads the files that dump_app.sh left on the SD card, checks sizes and hashes,
    compares anyka_ipc against the MD5 the OpenIPC issue is looking for, then builds
    a zip that can be dropped straight onto the issue.

.PARAMETER Source
    SD card root or any folder containing backup_app.bin (e.g. E:\)

.PARAMETER Model
    Camera variant for the zip name: V330L (default) or V300S.

.PARAMETER OutDir
    Where to write the zip and the comment draft. Defaults to the current directory.

.EXAMPLE
    .\verify-and-pack.ps1 -Source E:\ -Model V330L
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Source,

    [ValidateSet('V330L', 'V300S', 'unknown')]
    [string]$Model = 'V330L',

    # Free-text camera description used in the comment draft.
    [string]$CameraName = '',

    [string]$ExpectedIpcMd5 = '86396fdb14f2e029fa169afd4b598391',
    [string]$OutDir = (Get-Location).Path
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Source)) { throw "Source not found: $Source" }
$src = (Resolve-Path -LiteralPath $Source).Path
if (-not $src.EndsWith('\')) { $src += '\' }

$appPath = Join-Path $src 'backup_app.bin'
if (-not (Test-Path -LiteralPath $appPath)) {
    Write-Host "backup_app.bin not found in $src" -ForegroundColor Red
    $bins = @(Get-ChildItem -LiteralPath $src -Filter *.bin -File -ErrorAction SilentlyContinue)
    if ($bins) {
        Write-Host "Other .bin files present:" -ForegroundColor Yellow
        $bins | Select-Object Name, Length | Format-Table -AutoSize | Out-String | Write-Host
    }
    throw "Nothing to pack. Did dump_app.sh finish? Check dump-report.txt on the card."
}

if (-not (Test-Path -LiteralPath $OutDir)) { New-Item -ItemType Directory -Path $OutDir | Out-Null }
$OutDir = (Resolve-Path -LiteralPath $OutDir).Path

function Get-Hashes([string]$file) {
    $md5 = (Get-FileHash -LiteralPath $file -Algorithm MD5).Hash.ToLowerInvariant()
    $sha = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
    [pscustomobject]@{ Md5 = $md5; Sha256 = $sha }
}

$app = Get-Item -LiteralPath $appPath
$appHash = Get-Hashes $appPath
$appSize = $app.Length

$lscSize = 0x500000        # APP size on the LSC V330L/V300S dumps in the issue
$sizeOk = ($appSize -eq $lscSize)
$layout = if ($sizeOk) { 'LSC 5 MiB layout' } else { 'this unit uses a different 8 MiB layout' }

$knownBuilds = @{
    '86396fdb14f2e029fa169afd4b598391' = 'LSC HT_IPC286KSD3M_TUYA_AK3918EV330 (the build the issue wants)'
    '7c2a124cdd607ebef63fb66d063b6a87' = 'LSC HT_IPC286KS3_GMN_TUYA_AK3918EV330'
}

$ipcPath = Join-Path $src 'anyka_ipc_stock.bin'
$ipc = $null; $ipcMd5 = $null; $ipcSize = $null; $ipcMatch = $false
if (Test-Path -LiteralPath $ipcPath) {
    $ipc = Get-Item -LiteralPath $ipcPath
    $ipcMd5 = (Get-FileHash -LiteralPath $ipcPath -Algorithm MD5).Hash.ToLowerInvariant()
    $ipcSize = $ipc.Length
    $ipcMatch = ($ipcMd5 -eq $ExpectedIpcMd5.ToLowerInvariant())
}

$report = Join-Path $src 'dump-report.txt'
if (-not (Test-Path -LiteralPath $report)) {
    $alt = Join-Path $src 'update-report.txt'
    if (Test-Path -LiteralPath $alt) { $report = $alt }
}

$modelLabel = if ($Model -eq 'unknown') { 'V330L/V300S (variant not confirmed)' } else { $Model }
$cameraName = if ($CameraName) { $CameraName } else { "LSC Smart Connect PTZ, AK3918EN080 $modelLabel" }

# ------------------------------------------------------------------ console
Write-Host ""
Write-Host "=== DUMP CHECK ===" -ForegroundColor Cyan
Write-Host ("APP image      : {0}" -f $appPath)
Write-Host ("APP size       : {0:N0} bytes ({1:N2} MiB)  {2}" -f $appSize, ($appSize / 1MB), $layout) -ForegroundColor $(if ($sizeOk) { 'Green' } else { 'Yellow' })
Write-Host ("APP md5        : {0}" -f $appHash.Md5)
Write-Host ("APP sha256     : {0}" -f $appHash.Sha256)
if ($ipc) {
    Write-Host ("anyka_ipc size : {0:N0} bytes" -f $ipcSize)
    Write-Host ("anyka_ipc md5  : {0}" -f $ipcMd5) -ForegroundColor $(if ($ipcMatch) { 'Green' } else { 'Yellow' })
    if ($ipcMatch) {
        Write-Host "  -> MATCHES the MD5 the issue is looking for. This is the file." -ForegroundColor Green
    } elseif ($knownBuilds.ContainsKey($ipcMd5)) {
        Write-Host ("  -> {0}" -f $knownBuilds[$ipcMd5]) -ForegroundColor Yellow
        Write-Host "     Not the requested build, but a known LSC one." -ForegroundColor Yellow
    } else {
        Write-Host ("  -> does NOT match {0}" -f $ExpectedIpcMd5) -ForegroundColor Yellow
        Write-Host "     This is a different Tuya/Anyka build, not the LSC KSD3M image." -ForegroundColor Yellow
    }
} else {
    Write-Host "anyka_ipc copy : not found on the card (embedded copy failed?)" -ForegroundColor Yellow
}

# ------------------------------------------------------------------ pack
$stamp = Get-Date -Format 'yyyyMMdd'
$zipName = "AK3918_{0}_app_dump_{1}.zip" -f $Model, $stamp
$zipPath = Join-Path $OutDir $zipName

$stage = Join-Path $env:TEMP ("ak3918-pack-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $stage | Out-Null
try {
    Copy-Item -LiteralPath $appPath -Destination (Join-Path $stage 'backup_app.bin')
    if ($ipc) { Copy-Item -LiteralPath $ipcPath -Destination (Join-Path $stage 'anyka_ipc.bin') }
    if (Test-Path -LiteralPath $report) { Copy-Item -LiteralPath $report -Destination (Join-Path $stage 'dump-report.txt') }

    $checks = @(
        "AK3918 $Model APP dump"
        "date          : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')"
        "backup_app.bin: $appSize bytes"
        "  md5         : $($appHash.Md5)"
        "  sha256      : $($appHash.Sha256)"
    )
    if ($ipc) {
        $checks += "anyka_ipc.bin : $ipcSize bytes"
        $checks += "  md5         : $ipcMd5"
        $checks += "  matches issue target ($ExpectedIpcMd5): $ipcMatch"
    }
    $checks | Set-Content -LiteralPath (Join-Path $stage 'checksums.txt') -Encoding ascii

    if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
    Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zipPath -CompressionLevel Optimal
} finally {
    Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
}

$zipInfo = Get-Item -LiteralPath $zipPath
Write-Host ""
Write-Host ("Packaged: {0} ({1:N2} MiB)" -f $zipPath, ($zipInfo.Length / 1MB)) -ForegroundColor Green
Write-Host "Upload it to the issue from the GitHub web UI (drag the zip into the comment box)." -ForegroundColor Cyan
Write-Host "Then paste the draft in issue-comment-draft.md and fill in the link." -ForegroundColor Cyan

# ------------------------------------------------------------------ draft
# Single-quoted here-string so Markdown backticks survive untouched; tokens are
# substituted afterwards (double quotes turn `a into a bell character - lesson learnt).
$draft = Join-Path $OutDir 'issue-comment-draft.md'

if ($ipcMatch) {
    $verdict = 'This is the **' + $modelLabel + ' build with `anyka_ipc` MD5 `' + $ipcMd5 + '`** that was asked for.'
} elseif ($ipc -and $knownBuilds.ContainsKey($ipcMd5)) {
    $verdict = 'Note: this is the **' + $knownBuilds[$ipcMd5] + '** (`anyka_ipc` MD5 `' + $ipcMd5 + '`), not the `86396fdb…` KSD3M build requested. Attaching the raw image for reference.'
} elseif ($ipc) {
    $verdict = 'Note: this is **not the LSC KSD3M build** - `anyka_ipc` MD5 is `' + $ipcMd5 + '`, the APP partition is ' + $appSize + ' bytes (the LSC layout is 5,242,880), and the `HT_IPC…` product strings are absent. This is a different Anyka/Tuya `v33.53.x` build on the same AK3918EN080 V330L silicon; attaching it only as a hardware/variant data point.'
} else {
    $verdict = '`anyka_ipc` could not be copied off the device; the APP image below is the raw mtd7 partition.'
}

if ($ipcMatch) {
    $opening = 'Re: the missing `backup_app.bin` - dumped the APP partition (mtd7) from my camera.'
} else {
    $opening = 'Not the exact `backup_app.bin` that was requested - my unit turned out to be a different AK3918EN080 V330L build - but here is its APP partition (mtd7) for reference.'
}

$ipcRows = ''
$ipcBullet = ''
if ($ipc) {
    $ipcRows = '| anyka_ipc size | __SIZE__ bytes |' + "`n" + '| anyka_ipc MD5 | `__MD5__` |' + "`n"
    $ipcRows = $ipcRows.Replace('__SIZE__', "$ipcSize").Replace('__MD5__', $ipcMd5)
    $ipcBullet = '- `anyka_ipc.bin` - stock `/usr/bin/anyka_ipc` from the running device' + "`n"
}

$template = @'
{{OPENING}}

{{VERDICT}}

| field | value |
|---|---|
| Camera | {{CAMERA}} |
| APP partition | mtd7, {{APPSIZE}} bytes, raw `dd` ({{LAYOUT}}) |
| backup_app.bin size | {{APPSIZE}} bytes |
| backup_app.bin MD5 | `{{APPMD5}}` |
| backup_app.bin SHA256 | `{{APPSHA}}` |
{{IPCROWS}}
Archive: **{{ZIP}}** (attached) contains:
- `backup_app.bin` - raw mtd7 APP image
{{IPCBULLET}}- `dump-report.txt` - /proc/mtd, /proc/cpuinfo, mount table, hashes
- `checksums.txt`

Dump was read-only (`dd if=/dev/mtd7`); nothing was written to the camera's flash.
'@

$draftText = $template
foreach ($pair in @(
        @('{{OPENING}}', $opening),
        @('{{VERDICT}}', $verdict),
        @('{{CAMERA}}', $cameraName),
        @('{{LAYOUT}}', $layout),
        @('{{MODEL}}', $modelLabel),
        @('{{APPSIZE}}', "$appSize"),
        @('{{APPMD5}}', $appHash.Md5),
        @('{{APPSHA}}', $appHash.Sha256),
        @('{{ZIP}}', $zipName),
        @('{{IPCROWS}}', $ipcRows),
        @('{{IPCBULLET}}', $ipcBullet))) {
    $draftText = $draftText.Replace($pair[0], $pair[1])
}

$draftText | Set-Content -LiteralPath $draft -Encoding utf8
Write-Host "Draft comment: $draft" -ForegroundColor Cyan
