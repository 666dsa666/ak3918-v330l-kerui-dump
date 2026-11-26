<#
.SYNOPSIS
    Minimal ONVIF PTZ client for the AK3918/Tuya camera (Digest auth, admin/admin).

.DESCRIPTION
    -Info   : lists services, PTZ nodes and configurations
    -Move   : relative pan/tilt move (default +0.1 pan, +0.0 tilt)
    -Stop   : stops any continuous move
    -HomePos: GotoHomePosition (if the node supports it)

.EXAMPLE
    .\onvif-ptz.ps1 -Camera <camera-ip> -Info
.EXAMPLE
    .\onvif-ptz.ps1 -Camera <camera-ip> -Move -Pan 0.1
#>
[CmdletBinding()]
param(
    [string]$Camera = '192.168.1.100',
    [int]$Port = 10000,
    [string]$User = 'admin',
    [string]$Password = 'admin',
    [switch]$Info,
    [switch]$Move,
    [switch]$Stop,
    [switch]$HomePos,
    [double]$Pan = 0.1,
    [double]$Tilt = 0.0
)

$ErrorActionPreference = 'Stop'

function Md5Hex([string]$s) {
    $h = [Security.Cryptography.MD5]::Create()
    (($h.ComputeHash([Text.Encoding]::ASCII.GetBytes($s))) | ForEach-Object { $_.ToString('x2') }) -join ''
}

function Soap([string]$uri, [string]$body) {
    $xml = "<?xml version=`"1.0`"?><s:Envelope xmlns:s=`"http://www.w3.org/2003/05/soap-envelope`"><s:Body>$body</s:Body></s:Envelope>"
    $c = [System.Net.Sockets.TcpClient]::new()
    try { $c.Connect($Camera, $Port) } catch { throw "cannot connect to $Camera`:$Port" }
    $s = $c.GetStream(); $s.ReadTimeout = 5000
    $req = "POST $uri HTTP/1.1`r`nHost: $Camera`:$Port`r`nContent-Type: application/soap+xml; charset=utf-8`r`nContent-Length: $($xml.Length)`r`nConnection: close`r`n`r`n$xml"
    $b = [Text.Encoding]::ASCII.GetBytes($req); $s.Write($b, 0, $b.Length); $s.Flush()
    Start-Sleep -Milliseconds 350
    $buf = New-Object byte[] 16384
    $n = $s.Read($buf, 0, $buf.Length)
    $ch = if ($n -gt 0) { [Text.Encoding]::ASCII.GetString($buf, 0, $n) } else { '' }
    $s.Close(); $c.Close()
    if ($ch -notmatch 'nonce="([^"]+)"') { return $ch }
    $nonce = $Matches[1]; $realm = 'happytimesoft'; $qop = 'auth'; $nc = '00000001'
    $cn = [guid]::NewGuid().ToString('N').Substring(0, 8)
    $ha1 = Md5Hex("$User`:$realm`:$Password"); $ha2 = Md5Hex("POST`:$uri")
    $resp = Md5Hex("$ha1`:$nonce`:$nc`:$cn`:$qop`:$ha2")
    $auth = "Digest username=`"$User`", realm=`"$realm`", nonce=`"$nonce`", uri=`"$uri`", qop=$qop, nc=$nc, cnonce=`"$cn`", response=`"$resp`""
    $c2 = [System.Net.Sockets.TcpClient]::new(); $c2.Connect($Camera, $Port)
    $s2 = $c2.GetStream(); $s2.ReadTimeout = 5000
    $req2 = "POST $uri HTTP/1.1`r`nHost: $Camera`:$Port`r`nContent-Type: application/soap+xml; charset=utf-8`r`nContent-Length: $($xml.Length)`r`nConnection: close`r`nAuthorization: $auth`r`n`r`n$xml"
    $b2 = [Text.Encoding]::ASCII.GetBytes($req2); $s2.Write($b2, 0, $b2.Length); $s2.Flush()
    Start-Sleep -Milliseconds 500
    $out = ''
    for ($i = 0; $i -lt 10; $i++) {
        try { $m = $s2.Read($buf, 0, $buf.Length) } catch { break }
        if ($m -le 0) { break }
        $out += [Text.Encoding]::ASCII.GetString($buf, 0, $m)
    }
    $s2.Close(); $c2.Close()
    return $out
}

if ($Info) {
    $svc = Soap '/onvif/device_service' '<GetServices xmlns="http://www.onvif.org/ver10/device/wsdl"><IncludeCapability>false</IncludeCapability></GetServices>'
    Write-Host '=== services ==='
    [regex]::Matches($svc, '<tds:Service>.*?<tds:Namespace>([^<]+)</tds:Namespace>.*?<tds:XAddr>([^<]+)</tds:XAddr>', 'Singleline') | ForEach-Object {
        "{0}  {1}" -f $_.Groups[1].Value, $_.Groups[2].Value
    }
    $ptzUri = '/onvif/ptz_service'
    if ($svc -match '<tds:Namespace>http://www.onvif.org/ver20/ptz/wsdl</tds:Namespace>.*?<tds:XAddr>([^<]+)</tds:XAddr>') {
        $full = $Matches[1]
        if ($full -match '^https?://[^/]+(/.*)$') { $ptzUri = $Matches[1] }
    }
    Write-Host "=== using PTZ endpoint $ptzUri ==="
    $nodes = Soap $ptzUri '<GetNodes xmlns="http://www.onvif.org/ver20/ptz/wsdl"/>'
    if ($nodes -match 'NotAuthorized|ActionNotSupported|ter:') {
        Write-Host 'PTZ service rejected GetNodes:' -ForegroundColor Yellow
        ($nodes -split "`r`n" | Select-Object -Last 3) -join "`n"
        return
    }
    [regex]::Matches($nodes, '<tptz:PTZNode[^>]*token="([^"]+)"[^>]*>') | ForEach-Object { "node: $($_.Groups[1].Value)" }
    [regex]::Matches($nodes, '<tt:Name>([^<]+)</tt:Name>') | ForEach-Object { "name: $($_.Groups[1].Value)" }
    [regex]::Matches($nodes, 'ContinuousPanTiltVelocitySpace|RelativePanTiltTranslationSpace|AbsolutePanTiltPositionSpace') | ForEach-Object { $_.Value } | Sort-Object -Unique | ForEach-Object { "space: $_" }
    return
}

$ptz = '/onvif/ptz_service'
if ($Move) {
    $body = "<RelativeMove xmlns=`"http://www.onvif.org/ver20/ptz/wsdl`"><ProfileToken>PROFILE_000</ProfileToken><Translation><PanTilt xmlns=`"http://www.onvif.org/ver10/schema`" x=`"$Pan`" y=`"$Tilt`"/></Translation></RelativeMove>"
    $r = Soap $ptz $body
    ($r -split "`r`n")[0]
    if ($r -match '<s:Text[^>]*>([^<]+)') { "detail: $($Matches[1])" }
}
if ($Stop) {
    $body = '<Stop xmlns="http://www.onvif.org/ver20/ptz/wsdl"><ProfileToken>PROFILE_000</ProfileToken><PanTilt>true</PanTilt><Zoom>false</Zoom></Stop>'
    $r = Soap $ptz $body
    ($r -split "`r`n")[0]
}
if ($HomePos) {
    $body = '<GotoHomePosition xmlns="http://www.onvif.org/ver20/ptz/wsdl"><ProfileToken>PROFILE_000</ProfileToken></GotoHomePosition>'
    $r = Soap $ptz $body
    ($r -split "`r`n")[0]
}
