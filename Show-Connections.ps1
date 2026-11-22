<#
.SYNOPSIS
  Shows established TCP connections and the program behind each one. Read-only.

.EXAMPLE
  .\Show-Connections.ps1                 # all established connections
  .\Show-Connections.ps1 -Resolve        # also look up remote hostnames
  .\Show-Connections.ps1 -Name chrome    # only processes matching "chrome"
  .\Show-Connections.ps1 -Watch 5        # refresh every 5 seconds (Ctrl+C to stop)
  .\Show-Connections.ps1 -IncludeLocal   # include loopback / LAN connections
  .\Show-Connections.ps1 -Csv conns.csv  # also save to CSV
#>
[CmdletBinding()]
param(
    [switch]$Resolve,
    [string]$Name,
    [int]$Watch = 0,
    [switch]$IncludeLocal,
    [string]$Csv
)

$dnsCache = @{}

function Get-RemoteName([string]$ip) {
    if (-not $Resolve) { return '' }
    if ($dnsCache.ContainsKey($ip)) { return $dnsCache[$ip] }
    $n = ''
    try {
        $r = Resolve-DnsName -Name $ip -Type PTR -QuickTimeout -DnsOnly -ErrorAction Stop |
             Where-Object { $_.NameHost } | Select-Object -First 1
        if ($r) { $n = $r.NameHost }
    } catch {}
    $dnsCache[$ip] = $n
    return $n
}

function Test-LocalAddress([string]$ip) {
    return ($ip -match '^(127\.|::1$|0\.0\.0\.0|::$|10\.|192\.168\.|169\.254\.|fe80:)' -or
            $ip -match '^172\.(1[6-9]|2[0-9]|3[01])\.')
}

function Get-Connections {
    # PID -> process info
    $procs = @{}
    Get-Process -ErrorAction SilentlyContinue | ForEach-Object {
        $path = ''
        try { $path = $_.Path } catch {}
        $procs[$_.Id] = [pscustomobject]@{ Name = $_.ProcessName; Path = $path }
    }

    # PID -> service names (so svchost lines say which service)
    $svc = @{}
    Get-CimInstance Win32_Service -Filter "State='Running'" -ErrorAction SilentlyContinue | ForEach-Object {
        $id = [int]$_.ProcessId
        if ($svc.ContainsKey($id)) { $svc[$id] += ",$($_.Name)" } else { $svc[$id] = $_.Name }
    }

    Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue | ForEach-Object {
        $c = $_
        if (-not $IncludeLocal -and (Test-LocalAddress $c.RemoteAddress)) { return }

        $p = $procs[[int]$c.OwningProcess]
        $pname = if ($p) { $p.Name } else { '?' }
        $ppath = if ($p) { $p.Path } else { '' }

        if ($Name -and $pname -notlike "*$Name*") { return }

        [pscustomobject]@{
            Process  = $pname
            PID      = $c.OwningProcess
            Service  = $svc[[int]$c.OwningProcess]
            Local    = "$($c.LocalAddress):$($c.LocalPort)"
            Remote   = "$($c.RemoteAddress):$($c.RemotePort)"
            Host     = Get-RemoteName $c.RemoteAddress
            Path     = $ppath
        }
    } | Sort-Object Process, Remote
}

function Show-Once {
    $rows = @(Get-Connections)

    Write-Host ""
    Write-Host ("=== Established connections: {0}  ({1}) ===" -f $rows.Count, (Get-Date -Format 'HH:mm:ss')) -ForegroundColor Cyan

    Write-Host "`n-- Per program --" -ForegroundColor DarkCyan
    $rows | Group-Object Process | Sort-Object Count -Descending |
        Select-Object @{n='Connections';e={$_.Count}}, @{n='Program';e={$_.Name}},
                      @{n='Path';e={($_.Group | Select-Object -First 1).Path}} |
        Format-Table -AutoSize | Out-Host

    Write-Host "-- Details --" -ForegroundColor DarkCyan
    $cols = 'Process','PID','Remote'
    if ($Resolve) { $cols += 'Host' }
    $cols += 'Service','Local'
    $rows | Select-Object $cols | Format-Table -AutoSize | Out-Host

    # flag anything running from a temp / user-writable location
    $sus = $rows | Where-Object { $_.Path -match '\\(Temp|AppData\\Local\\Temp|Downloads|Users\\Public)\\' }
    if ($sus) {
        Write-Host "!! Programs connecting from Temp/Downloads/Public folders:" -ForegroundColor Yellow
        $sus | Select-Object Process, PID, Remote, Path | Format-Table -AutoSize | Out-Host
    }

    if ($Csv) { $rows | Export-Csv -Path $Csv -NoTypeInformation; Write-Host "Saved to $Csv" -ForegroundColor DarkGray }
}

if ($Watch -gt 0) {
    while ($true) { Clear-Host; Show-Once; Start-Sleep -Seconds $Watch }
} else {
    Show-Once
}
