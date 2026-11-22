# Show-Connections

PowerShell script that shows every established network connection on Windows and the program behind it - name, PID, .exe path, svchost service, and optional remote hostnames. Flags programs connecting from Temp/Downloads. Read-only.

## Usage
```powershell
powershell -ExecutionPolicy Bypass -File .\Show-Connections.ps1
.\Show-Connections.ps1 -Resolve        # remote hostnames
.\Show-Connections.ps1 -Watch 5        # live refresh
.\Show-Connections.ps1 -Name chrome    # filter by program
.\Show-Connections.ps1 -IncludeLocal   # include LAN/loopback
.\Show-Connections.ps1 -Csv out.csv    # export
```
Run as admin to see paths for system processes.

## Found a suspicious connection? What to do

**1. Cut it off.** Unplug Ethernet / turn off Wi-Fi so it can't send more data.

**2. Identify the program.** Note the process name, PID and path from the script, then check it:
```powershell
Get-Process -Id <PID> | Select-Object Name, Path, StartTime
Get-AuthenticodeSignature "<path to exe>" | Select-Object Status, SignerCertificate
```
Unsigned, or running from `Temp`, `Downloads`, `AppData\Roaming` or `Users\Public` = red flag.
Upload the file to https://www.virustotal.com to see if antivirus engines flag it.

**3. Kill it and block it** (admin PowerShell):
```powershell
Stop-Process -Id <PID> -Force
New-NetFirewallRule -DisplayName "Block suspicious" -Direction Outbound -Program "<path to exe>" -Action Block
New-NetFirewallRule -DisplayName "Block suspicious IP" -Direction Outbound -RemoteAddress <IP> -Action Block
```

**4. Find how it starts itself** (malware comes back after reboot if you skip this):
```powershell
Get-CimInstance Win32_StartupCommand | Select-Object Name, Command, Location
Get-ScheduledTask | Where-Object { $_.Actions.Execute -match 'Temp|AppData|Public|Downloads' } | Select-Object TaskName, TaskPath
Get-CimInstance Win32_Service | Where-Object { $_.PathName -match 'Temp|AppData|Public|Downloads' } | Select-Object Name, PathName
```
For a full view, use Microsoft **Autoruns** (Sysinternals) and uncheck anything suspicious.

**5. Scan everything.**
```powershell
Start-MpScan -ScanType FullScan
Start-MpWDOScan   # Defender Offline scan - reboots and scans before Windows loads
```
Get a second opinion with Malwarebytes.

**6. Lock your accounts - from a different, clean device.** Change passwords for email first, then banking, then everything else. Turn on 2FA. Sign out all sessions (Google, Microsoft, Discord, Steam all have "sign out everywhere").

**7. When in doubt, reinstall.** If it was a remote-access tool (RAT), ransomware, or you can't find how it got in, back up your personal files (not programs) and do a clean Windows reinstall. It's the only way to be 100% sure.

> Not every unknown connection is a hacker - Windows, drivers, game launchers and updaters connect out constantly. Check the path and signature before deleting anything.

## License
AGPL-3.0
