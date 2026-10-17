<#
  Fanatec-Stabilise.ps1
  Stops the most common causes of a Fanatec DD+ dropping out of Windows
  and tries to recover it without a full driver reinstall.

  Run from an elevated PowerShell:
    powershell -ExecutionPolicy Bypass -File .\Fanatec-Stabilise.ps1            # harden + recover
    powershell -ExecutionPolicy Bypass -File .\Fanatec-Stabilise.ps1 -Recover   # recover only
#>
param([switch]$Recover)

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "Run this script as Administrator."; exit 1
}

$FanatecVid = 'VID_0EB7'   # Fanatec USB vendor ID
$log = Join-Path $PSScriptRoot "fanatec-log.txt"
function Log($m) { $line = "$(Get-Date -f s)  $m"; Write-Host $line; Add-Content $log $line }

function Get-FanatecDevices {
    Get-PnpDevice -PresentOnly:$false | Where-Object { $_.InstanceId -match $FanatecVid }
}

function Harden {
    Log "Disabling USB selective suspend (AC + DC) in the active power plan"
    powercfg /SETACVALUEINDEX SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0
    powercfg /SETDCVALUEINDEX SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0
    powercfg /SETACTIVE SCHEME_CURRENT

    Log "Turning off 'allow the computer to turn off this device' on USB hubs and Fanatec devices"
    Get-CimInstance -Namespace root\wmi -ClassName MSPower_DeviceEnable -ErrorAction SilentlyContinue |
        Where-Object { $_.InstanceName -match 'USB|' + $FanatecVid } |
        ForEach-Object { $_.Enable = $false; Set-CimInstance -InputObject $_ -ErrorAction SilentlyContinue }

    Log "Stopping Windows Update from replacing device drivers"
    $k = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
    New-Item $k -Force | Out-Null
    Set-ItemProperty $k -Name ExcludeWUDriversInQualityUpdate -Value 1 -Type DWord

    Log "Disabling Fast Startup (leaves USB devices in a bad state after 'shutdown')"
    Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -Name HiberbootEnabled -Value 0 -Type DWord
}

function Recover-Wheel {
    $devs = Get-FanatecDevices
    if (-not $devs) { Log "No Fanatec device known to Windows. Check cable/power, then use the base's firmware recovery mode (see README)."; return }

    $devs | ForEach-Object { Log "Found: $($_.FriendlyName) [$($_.Status)] $($_.InstanceId)" }

    # Remove ghost / errored entries so Windows re-enumerates cleanly
    $devs | Where-Object { $_.Status -ne 'OK' } | ForEach-Object {
        Log "Removing stale entry $($_.InstanceId)"
        pnputil /remove-device "$($_.InstanceId)" | Out-Null
    }

    Log "Restarting Fanatec services"
    Get-Service | Where-Object { $_.DisplayName -match 'Fanatec' } | Restart-Service -Force -ErrorAction SilentlyContinue

    Log "Rescanning for hardware"
    pnputil /scan-devices | Out-Null
    Start-Sleep 5

    $ok = Get-FanatecDevices | Where-Object Status -eq 'OK'
    if ($ok) { Log "Wheel back online: $($ok.FriendlyName -join ', ')" }
    else     { Log "Still not detected. Power-cycle the base (off 10s), then rerun with -Recover." }
}

if (-not $Recover) { Harden }
Recover-Wheel
Log "Done. Reboot once after the first run so power settings take effect."
