<#
  Install.ps1 - installs or updates the F1 Arcade Launcher on this rig.
  Double-click Install.bat (it asks for administrator permission).
  Safe to run again to update: it keeps your settings and video.
#>
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    exit
}

$dest = 'C:\F1Arcade'
$src  = $PSScriptRoot
Write-Host "`n=== F1 Arcade Launcher installer ===`n" -ForegroundColor Red

# Stop a running launcher so its files can be replaced
Stop-ScheduledTask -TaskName 'F1 Arcade Launcher' -ErrorAction SilentlyContinue
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -match 'F1-Launcher\.ps1' } |
    ForEach-Object { Invoke-CimMethod -InputObject $_ -MethodName Terminate | Out-Null }

New-Item $dest -ItemType Directory -Force | Out-Null
Copy-Item (Join-Path $src '*.ps1'), (Join-Path $src 'README.md') $dest -Force -Exclude 'Install.ps1'

# Settings - press Enter to keep the value in [brackets]
$cfgPath = Join-Path $dest 'settings.json'
$cfg = if (Test-Path $cfgPath) { Get-Content $cfgPath -Raw | ConvertFrom-Json } else {
    [pscustomobject]@{ CarNumber = 1; VenueName = 'F1 RACING EXPERIENCE'; StaffPin = '1234'; IdleSeconds = 60 } }
function Ask($q, $cur) { $a = Read-Host "$q [$cur]"; if ($a) { $a } else { $cur } }
$cfg.CarNumber   = [int](Ask 'Car number for THIS rig (1, 2, 3...)' $cfg.CarNumber)
$cfg.VenueName   = Ask 'Venue name shown on screen' $cfg.VenueName
$cfg.StaffPin    = Ask 'Staff PIN (F12 menu)' $cfg.StaffPin
$cfg.IdleSeconds = [int](Ask 'Seconds of no use before the video plays' $cfg.IdleSeconds)
$cfg | ConvertTo-Json | Set-Content $cfgPath

# Branding folder on the desktop (videos + logo) - staff can swap files here any time
$media = Join-Path ([Environment]::GetFolderPath('Desktop')) 'F1 Arcade Media'
New-Item $media -ItemType Directory -Force | Out-Null
Get-ChildItem $dest -Include 'attract.*', 'intro.*' -File -Recurse -ErrorAction SilentlyContinue | Move-Item -Destination $media -Force
Get-ChildItem $src -Filter 'logo.*' -ErrorAction SilentlyContinue | Copy-Item -Destination $media -Force

# Attract video
$bundled = Get-ChildItem $src -Filter 'attract.*' -ErrorAction SilentlyContinue | Select-Object -First 1
$current = Get-ChildItem $media -Filter 'attract.*' -ErrorAction SilentlyContinue | Select-Object -First 1
$prompt  = if ($current) { "Video file to play when idle (drag it here, Enter to keep $($current.Name))" }
           elseif ($bundled) { "Video file to play when idle (drag it here, Enter to use $($bundled.Name))" }
           else { 'Video file to play when idle (drag it here, Enter for none)' }
$v = (Read-Host $prompt).Trim('"', ' ')
if (-not $v -and -not $current -and $bundled) { $v = $bundled.FullName }
if ($v) {
    if (Test-Path $v) {
        Get-ChildItem $media -Filter 'attract.*' | Remove-Item -Force
        Copy-Item $v (Join-Path $media ('attract' + [IO.Path]::GetExtension($v))) -Force
        Write-Host 'Video installed.' -ForegroundColor Green
    } else { Write-Warning "Video not found: $v" }
}

# Intro video (plays while F1 loads). Enter = use the idle video for this too
$curIntro = Get-ChildItem $media -Filter 'intro.*' -ErrorAction SilentlyContinue | Select-Object -First 1
$iv = (Read-Host ("Video to play while F1 loads (drag it here, Enter to " + $(if ($curIntro) { "keep $($curIntro.Name)" } else { 'use the idle video' }) + ")")).Trim('"', ' ')
if ($iv) {
    if (Test-Path $iv) {
        Get-ChildItem $media -Filter 'intro.*' | Remove-Item -Force
        Copy-Item $iv (Join-Path $media ('intro' + [IO.Path]::GetExtension($iv))) -Force
        Write-Host 'Intro video installed.' -ForegroundColor Green
    } else { Write-Warning "Video not found: $iv" }
}

Write-Host "`nApplying Fanatec stability fixes..." -ForegroundColor Yellow
& (Join-Path $dest 'Fanatec-Stabilise.ps1')

Write-Host "`nRegistering launcher to start at login..." -ForegroundColor Yellow
& (Join-Path $dest 'F1-Launcher.ps1') -Install

Write-Host "`nDONE - installed to $dest as CAR $($cfg.CarNumber)." -ForegroundColor Green
Write-Host "Branding folder: $media  (attract.mp4, intro.mp4, logo.png)"
Start-Process explorer.exe $media
Write-Host 'Make sure Windows logs in automatically (run "netplwiz"), then restart the PC.'
Read-Host "`nPress Enter to close"
