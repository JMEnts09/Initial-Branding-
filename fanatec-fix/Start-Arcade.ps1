<#
  Start-Arcade.ps1
  On boot: checks the Fanatec wheel, auto-recovers it if needed, shows a
  status screen, then launches F1 only when the wheel is working.

  Install once (as Administrator):
    powershell -ExecutionPolicy Bypass -File .\Start-Arcade.ps1 -Install
#>
param([switch]$Install)

# ---- SETTINGS: change these to match your machine ----
$GameLaunch  = 'steam://rungameid/3059520'   # F1 25 on Steam. F1 24 = 2488620. EA app: path to the game .exe
$BootDelay   = 20                            # seconds to let Windows + Fanatec driver settle
$MaxAttempts = 3                             # recovery attempts before showing the fault screen
# ------------------------------------------------------

$FanatecVid = 'VID_0EB7'
$log = Join-Path $PSScriptRoot 'fanatec-log.txt'
function Log($m) { Add-Content $log "$(Get-Date -f s)  $m" }

if ($Install) {
    $action  = New-ScheduledTaskAction -Execute 'powershell.exe' `
               -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`""
    $trigger = New-ScheduledTaskTrigger -AtLogOn
    $princ   = New-ScheduledTaskPrincipal -UserId $env:USERNAME -RunLevel Highest -LogonType Interactive
    Register-ScheduledTask -TaskName 'Arcade Wheel Check' -Action $action -Trigger $trigger -Principal $princ -Force | Out-Null
    Write-Host 'Installed. The wheel check will run every time this user logs in.'
    exit
}

Add-Type -AssemblyName System.Windows.Forms, System.Drawing

# Full-screen status window
$form = New-Object Windows.Forms.Form -Property @{
    FormBorderStyle = 'None'; WindowState = 'Maximized'; TopMost = $true; BackColor = 'Black' }
$label = New-Object Windows.Forms.Label -Property @{
    Dock = 'Fill'; TextAlign = 'MiddleCenter'; ForeColor = 'White'
    Font = New-Object Drawing.Font('Segoe UI', 40, [Drawing.FontStyle]::Bold) }
$form.Controls.Add($label)
$form.Show()
function Status($text, $colour) {
    $label.Text = $text; $label.ForeColor = $colour
    [Windows.Forms.Application]::DoEvents()
}

function Test-Wheel {
    # Wheel must be present, with no driver error, AND exposed as a game controller
    $devs = Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object InstanceId -match $FanatecVid
    if (-not $devs -or ($devs | Where-Object Status -ne 'OK')) { return $false }
    $joy = Get-CimInstance Win32_PnPEntity | Where-Object { $_.DeviceID -match $FanatecVid -and $_.Name -match 'game controller|HID' }
    return [bool]$joy
}

function Repair-Wheel {
    Get-PnpDevice -ErrorAction SilentlyContinue |
        Where-Object { $_.InstanceId -match $FanatecVid -and $_.Status -ne 'OK' } |
        ForEach-Object { pnputil /remove-device "$($_.InstanceId)" | Out-Null }
    Get-Service | Where-Object DisplayName -match 'Fanatec' | Restart-Service -Force -ErrorAction SilentlyContinue
    pnputil /scan-devices | Out-Null
}

Status 'Starting up…' 'White'
Start-Sleep $BootDelay

$ok = $false
for ($i = 1; $i -le $MaxAttempts -and -not $ok; $i++) {
    Status "Checking wheel… ($i/$MaxAttempts)" 'White'
    if (Test-Wheel) { $ok = $true; break }
    Log "Wheel not detected (attempt $i) - repairing"
    Status "Reconnecting wheel… ($i/$MaxAttempts)" 'Orange'
    Repair-Wheel
    Start-Sleep 10
}

if ($ok) {
    Log 'Wheel detected and working - launching game'
    Status "✔  Wheel detected and working`n`nLaunching F1…" 'LimeGreen'
    Start-Sleep 3
    Start-Process $GameLaunch
    Start-Sleep 5
    $form.Close()
} else {
    Log 'WHEEL FAULT - game not launched'
    Status "✖  WHEEL FAULT`n`nPlease call a member of staff`n`n(Staff: switch the wheel off for 10s, then press R to retry)" 'Red'
    $form.KeyPreview = $true
    $form.Add_KeyDown({ if ($_.KeyCode -eq 'R') { $form.Close(); Start-Process powershell.exe "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`"" } })
    [Windows.Forms.Application]::Run($form)
}
