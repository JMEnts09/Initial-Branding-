<#
  F1-Launcher.ps1  -  Arcade home screen for F1 sim rigs
  - Live Fanatec wheel status on the home screen (checks every 5s)
  - Auto-repairs the wheel if it drops out
  - PLAY button only works when the wheel is detected and working
  - Hidden staff menu (press F12, enter PIN)

  Install once (as Administrator):
    powershell -ExecutionPolicy Bypass -File .\F1-Launcher.ps1 -Install
#>
param([switch]$Install)

# ================= SETTINGS =================
$VenueName = 'F1 RACING EXPERIENCE'
$StaffPin  = '1234'                              # CHANGE THIS
$Games = [ordered]@{
    'F1 25' = 'steam://rungameid/3059520'
    'F1 24' = 'steam://rungameid/2488620'
}                                                # EA app: use the full path to the game .exe
$GameProcess = 'F1_2*|F1_25|F1_24'               # process names, so the launcher hides while racing
# ============================================

$FanatecVid = 'VID_0EB7'
$log = Join-Path $PSScriptRoot 'fanatec-log.txt'
function Log($m) { Add-Content $log "$(Get-Date -f s)  $m" }

if ($Install) {
    $a = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`""
    $p = New-ScheduledTaskPrincipal -UserId $env:USERNAME -RunLevel Highest -LogonType Interactive
    Register-ScheduledTask -TaskName 'F1 Arcade Launcher' -Action $a -Trigger (New-ScheduledTaskTrigger -AtLogOn) -Principal $p -Force | Out-Null
    Unregister-ScheduledTask -TaskName 'Arcade Wheel Check' -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host 'Installed. The launcher will open every time this user logs in.'; exit
}

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()

# ---------- wheel logic ----------
function Test-Wheel {
    $d = Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object InstanceId -match $FanatecVid
    if (-not $d -or ($d | Where-Object Status -ne 'OK')) { return $false }
    [bool](Get-CimInstance Win32_PnPEntity | Where-Object { $_.DeviceID -match $FanatecVid -and $_.Name -match 'game controller|HID' })
}
function Repair-Wheel {
    Log 'Wheel missing - repairing'
    Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -match $FanatecVid -and $_.Status -ne 'OK' } |
        ForEach-Object { pnputil /remove-device "$($_.InstanceId)" | Out-Null }
    Get-Service | Where-Object DisplayName -match 'Fanatec' | Restart-Service -Force -ErrorAction SilentlyContinue
    pnputil /scan-devices | Out-Null
}

# ---------- UI ----------
$red   = [Drawing.Color]::FromArgb(225, 6, 0)
$dark  = [Drawing.Color]::FromArgb(15, 15, 20)
$panel = [Drawing.Color]::FromArgb(30, 30, 38)
function F($size, $bold = $true) { New-Object Drawing.Font('Segoe UI', $size, $(if ($bold) { 'Bold' } else { 'Regular' })) }

$form = New-Object Windows.Forms.Form -Property @{
    FormBorderStyle = 'None'; WindowState = 'Maximized'; TopMost = $true; BackColor = $dark; KeyPreview = $true }

$top = New-Object Windows.Forms.Panel -Property @{ Dock = 'Top'; Height = 140; BackColor = $red }
$title = New-Object Windows.Forms.Label -Property @{
    Text = $VenueName; Dock = 'Fill'; TextAlign = 'MiddleCenter'; ForeColor = 'White'; Font = (F 48) }
$top.Controls.Add($title)

$layout = New-Object Windows.Forms.TableLayoutPanel -Property @{ Dock = 'Fill'; ColumnCount = 1; RowCount = 3; Padding = '60,40,60,40' }
[void]$layout.RowStyles.Add((New-Object Windows.Forms.RowStyle('Percent', 30)))
[void]$layout.RowStyles.Add((New-Object Windows.Forms.RowStyle('Percent', 20)))
[void]$layout.RowStyles.Add((New-Object Windows.Forms.RowStyle('Percent', 50)))

# Wheel status card
$status = New-Object Windows.Forms.Label -Property @{
    Dock = 'Fill'; TextAlign = 'MiddleCenter'; Font = (F 36); BackColor = $panel; ForeColor = 'White'
    Text = 'Checking wheel…'; Margin = '200,10,200,10' }
$layout.Controls.Add($status, 0, 0)

# Game picker
$pick = New-Object Windows.Forms.FlowLayoutPanel -Property @{ Dock = 'Fill'; FlowDirection = 'LeftToRight'; WrapContents = $false }
$script:selected = @($Games.Keys)[0]
$gameButtons = @()
foreach ($name in $Games.Keys) {
    $b = New-Object Windows.Forms.Button -Property @{
        Text = $name; Width = 300; Height = 100; Font = (F 28); FlatStyle = 'Flat'; ForeColor = 'White'; Tag = $name; Margin = '20,10,20,10' }
    $b.FlatAppearance.BorderSize = 3
    $b.Add_Click({ $script:selected = $this.Tag; Update-Picker })
    $pick.Controls.Add($b); $gameButtons += $b
}
$pickHost = New-Object Windows.Forms.Panel -Property @{ Dock = 'Fill' }
$pickHost.Controls.Add($pick)
$pickHost.Add_Resize({ $pick.Width = $pick.PreferredSize.Width; $pick.Height = 130; $pick.Left = [int](($pickHost.Width - $pick.Width) / 2) })
$layout.Controls.Add($pickHost, 0, 1)
function Update-Picker { foreach ($b in $gameButtons) {
    $b.BackColor = if ($b.Tag -eq $script:selected) { $red } else { $panel }
    $b.FlatAppearance.BorderColor = if ($b.Tag -eq $script:selected) { 'White' } else { $panel } } }
Update-Picker

# PLAY button
$play = New-Object Windows.Forms.Button -Property @{
    Text = 'PLAY'; Font = (F 72); Dock = 'Fill'; FlatStyle = 'Flat'; ForeColor = 'White'; Margin = '300,20,300,20'; Enabled = $false }
$play.FlatAppearance.BorderSize = 0
$layout.Controls.Add($play, 0, 2)

$foot = New-Object Windows.Forms.Label -Property @{
    Dock = 'Bottom'; Height = 40; ForeColor = 'Gray'; Font = (F 12 $false); TextAlign = 'MiddleCenter'; Text = 'Staff: F12' }

$form.Controls.AddRange(@($layout, $foot, $top))

# ---------- state ----------
$script:fails = 0
$script:racing = $false

function Set-Status {
    if ($script:racing) { return }
    if (Test-Wheel) {
        if ($script:fails -gt 0) { Log 'Wheel detected and working' }
        $script:fails = 0
        $status.Text = '✔  Wheel detected and working'; $status.ForeColor = 'LimeGreen'
        $play.Enabled = $true; $play.BackColor = $red; $play.Text = 'PLAY'
    } else {
        $script:fails++
        $play.Enabled = $false; $play.BackColor = $panel
        if ($script:fails -le 3) {
            $status.Text = "Reconnecting wheel…  ($($script:fails)/3)"; $status.ForeColor = 'Orange'
            [Windows.Forms.Application]::DoEvents(); Repair-Wheel
        } else {
            if ($script:fails -eq 4) { Log 'WHEEL FAULT shown' }
            $status.Text = "✖  WHEEL FAULT – please call staff"; $status.ForeColor = $red
            $play.Text = 'UNAVAILABLE'
        }
    }
}

$play.Add_Click({
    if (-not (Test-Wheel)) { Set-Status; return }
    Log "Launching $script:selected"
    $script:racing = $true
    $status.Text = "Launching $script:selected…"; $status.ForeColor = 'White'
    [Windows.Forms.Application]::DoEvents()
    Start-Process $Games[$script:selected]
    Start-Sleep 3
    $form.TopMost = $false; $form.WindowState = 'Minimized'
})

# Poll: wheel status on the home screen, and bring launcher back when the game closes
$timer = New-Object Windows.Forms.Timer -Property @{ Interval = 5000 }
$timer.Add_Tick({
    if ($script:racing) {
        if (-not (Get-Process | Where-Object Name -match $GameProcess)) {
            if ($script:launchSeen) {
                $script:racing = $false; $script:launchSeen = $false
                $form.WindowState = 'Maximized'; $form.TopMost = $true; $form.Activate(); Set-Status
            }
        } else { $script:launchSeen = $true }
        return
    }
    Set-Status
})

# Staff menu
$form.Add_KeyDown({
    if ($_.KeyCode -ne 'F12') { return }
    $pin = New-Object Windows.Forms.Form -Property @{ Text = 'Staff'; Width = 380; Height = 330; StartPosition = 'CenterScreen'; TopMost = $true; FormBorderStyle = 'FixedDialog' }
    $box = New-Object Windows.Forms.TextBox -Property @{ UseSystemPasswordChar = $true; Left = 20; Top = 20; Width = 320; Font = (F 16 $false) }
    $mk = { param($t, $y) New-Object Windows.Forms.Button -Property @{ Text = $t; Left = 20; Top = $y; Width = 320; Height = 45 } }
    $bRetry = & $mk 'Re-check / repair wheel' 70
    $bLog   = & $mk 'Open log' 120
    $bExit  = & $mk 'Exit launcher to Windows' 170
    $bOff   = & $mk 'Shut down PC' 220
    $guard = { if ($box.Text -ne $StaffPin) { [Windows.Forms.MessageBox]::Show('Wrong PIN'); return $false }; $true }
    $bRetry.Add_Click({ if (& $guard) { $script:fails = 0; Repair-Wheel; $pin.Close(); Set-Status } })
    $bLog.Add_Click({   if (& $guard) { $form.TopMost = $false; Start-Process notepad $log; $pin.Close() } })
    $bExit.Add_Click({  if (& $guard) { Log 'Staff exit'; $pin.Close(); $form.Close() } })
    $bOff.Add_Click({   if (& $guard) { Log 'Staff shutdown'; Stop-Computer -Force } })
    $pin.Controls.AddRange(@($box, $bRetry, $bLog, $bExit, $bOff))
    [void]$pin.ShowDialog($form)
})

$form.Add_Shown({ Set-Status; $timer.Start() })
[Windows.Forms.Application]::Run($form)
