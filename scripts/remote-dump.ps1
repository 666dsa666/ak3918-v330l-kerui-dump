<#
.SYNOPSIS
    Log into the rooted LSC/AK3918 camera over TCP, run dump_app.sh and show the output.
    Does not need the Windows "Telnet Client" optional feature.

.DESCRIPTION
    Opens a raw TCP connection (port 23 by default, 24 as fallback), answers the telnet
    IAC negotiation minimally, logs in as root, then runs:

        sh /tmp/sd/dump_app.sh

    and streams the camera's console output until the script prints DONE.
    The full transcript is saved to the log file so nothing is lost.

    The camera must already be rooted with the SD card inserted (prepare-sd.ps1) and
    reachable from this PC. Nothing is written to the camera's flash.

.PARAMETER Camera
    Camera IP or hostname.

.EXAMPLE
    .\remote-dump.ps1 -Camera 192.168.1.100
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Camera,

    [int]$Port = 23,
    [string]$User = 'root',
    [string]$Password = 'telnet',

    [string]$LogFile = (Join-Path (Get-Location).Path ("remote-dump-" + (Get-Date -Format 'yyyyMMdd-HHmmss') + ".log")),
    [int]$DumpTimeoutSec = 600,

    # Run this shell command instead of the dump script, then exit.
    [string]$Command = '',
    # The telnetd was started with -l /bin/sh: no login prompt at all.
    [switch]$NoLogin
)

$ErrorActionPreference = 'Stop'

$client = [System.Net.Sockets.TcpClient]::new()
$connect = $client.BeginConnect($Camera, $Port, $null, $null)
if (-not $connect.AsyncWaitHandle.WaitOne(6000)) {
    throw "TCP connect to $Camera`:$Port timed out. Wrong IP, or telnet is not open (did the camera boot with the SD card?)."
}
$client.EndConnect($connect)
$stream = $client.GetStream()
$stream.ReadTimeout = 500
$stream.WriteTimeout = 5000

$script:rx = ''
$script:mark = 0
$script:iacState = 0

function Convert-Telnet([byte[]]$bytes, [int]$count) {
    $sb = New-Object System.Text.StringBuilder
    for ($i = 0; $i -lt $count; $i++) {
        $v = $bytes[$i]
        switch ($script:iacState) {
            0 {
                if ($v -eq 255) { $script:iacState = 1 }
                elseif ($v -eq 13 -or $v -eq 10 -or $v -eq 8 -or $v -eq 7 -or ($v -ge 32)) { [void]$sb.Append([char]$v) }
            }
            1 {
                if ($v -eq 255) { [void]$sb.Append([char]255); $script:iacState = 0 }
                elseif ($v -ge 251 -and $v -le 254) { $script:iacState = 2 }
                else { $script:iacState = 0 }
            }
            2 { $script:iacState = 0 }
        }
    }
    $sb.ToString()
}

function Pump {
    $new = ''
    while ($stream.DataAvailable) {
        $buf = New-Object byte[] 4096
        $n = $stream.Read($buf, 0, $buf.Length)
        if ($n -le 0) { break }
        $new += Convert-Telnet $buf $n
    }
    if ($new) {
        $script:rx += $new
        Write-Host -NoNewline $new
        Add-Content -LiteralPath $LogFile -Value $new -NoNewline -Encoding utf8
    }
}

function WaitFor([string]$pattern, [int]$timeoutMs) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($sw.ElapsedMilliseconds -lt $timeoutMs) {
        Pump
        $tail = $script:rx.Substring([Math]::Min($script:mark, $script:rx.Length))
        if ($tail -match $pattern) { return $true }
        Start-Sleep -Milliseconds 120
    }
    return $false
}

function WaitForAny([string[]]$patterns, [int]$timeoutMs) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($sw.ElapsedMilliseconds -lt $timeoutMs) {
        Pump
        $tail = $script:rx.Substring([Math]::Min($script:mark, $script:rx.Length))
        foreach ($p in $patterns) {
            if ($tail -match $p) { return $p }
        }
        Start-Sleep -Milliseconds 120
    }
    return $null
}

function SendLine([string]$line) {
    $bytes = [Text.Encoding]::ASCII.GetBytes($line + "`r`n")
    $stream.Write($bytes, 0, $bytes.Length)
    $stream.Flush()
    $script:mark = $script:rx.Length
}

function Close-Session {
    try { SendLine 'exit'; Start-Sleep -Milliseconds 300; Pump } catch {}
    try { $stream.Close() } catch {}
    try { $client.Close() } catch {}
}

Set-Content -LiteralPath $LogFile -Value ("=== remote-dump $Camera`:$Port  " + (Get-Date -Format 'u') + " ===") -Encoding utf8
Write-Host "Connected to $Camera`:$Port, waiting for login prompt..." -ForegroundColor Cyan

try {
    if ($NoLogin) {
        if (-not (WaitFor '[#\$]' 12000)) { throw "No shell prompt appeared (is telnetd running with -l /bin/sh?)." }
    } else {
        if (-not (WaitFor 'login:' 20000)) {
            throw "No 'login:' prompt. Is this really the camera's telnet port? Try -Port 24."
        }
        Write-Host ""
        SendLine $User

        if (-not (WaitFor 'assword:' 8000)) {
            # Some firmwares drop straight to a shell after the user name.
            Write-Host "No password prompt - continuing." -ForegroundColor Yellow
        } else {
            SendLine $Password
        }

        if (-not (WaitFor '[#\$]' 10000)) {
            throw "Login failed (no shell prompt). Wrong password, or 'shadow' on the SD card was not picked up."
        }
    }
    Write-Host ""

    if ($Command) {
        Write-Host "Running command..." -ForegroundColor Cyan
        # The marker uses a backslash so the echoed command line cannot match it.
        SendLine ($Command + '; echo DON\E_MARK')
        if (-not (WaitFor 'DONE_MARK' 120000)) {
            throw "Command did not finish within 120 s - see $LogFile"
        }
        Write-Host ""
        Write-Host "Done. Transcript: $LogFile" -ForegroundColor Green
        return
    }

    Write-Host "Shell is up. Running the dump (up to $DumpTimeoutSec s)..." -ForegroundColor Cyan

    # Mount the card if the firmware has not done it, then run the dump script.
    SendLine 'mount /dev/mmcblk0p1 /tmp/sd 2>/dev/null; sh /tmp/sd/dump_app.sh'

    $failure = @("can't open", 'No such file or directory', 'not found')
    $hit = WaitForAny $failure 8000
    if ($null -eq $hit) {
        $hit = WaitForAny (@('DONE') + $failure) ($DumpTimeoutSec * 1000)
    }

    if ($null -eq $hit) {
        throw "The dump did not reach DONE within $DumpTimeoutSec s - see $LogFile for how far it got."
    }
    if ($hit -ne 'DONE') {
        throw "The camera shell could not run /tmp/sd/dump_app.sh ($hit). Check where the card is mounted: run 'mount' on the camera."
    }

    Write-Host ""
    Write-Host "Dump finished. Transcript: $LogFile" -ForegroundColor Green
    Write-Host "Now power the camera off, take the SD card out and run:" -ForegroundColor Cyan
    Write-Host "    .\verify-and-pack.ps1 -Source <SD-DRIVE>:\ -Model V330L" -ForegroundColor Cyan
} finally {
    Close-Session
}
