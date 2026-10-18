<#
  F1-Launcher.ps1  -  Arcade home screen for F1 sim rigs
  - Live Fanatec wheel status (checks every few seconds, auto-repairs dropouts)
  - LAN rig bar: shows every car on the network and whether it is Ready / Racing / Fault / Offline
  - SINGLE PLAYER: works whenever this car's wheel works (network not needed)
  - MULTIPLAYER: only lights up when this car + at least one other car on the LAN are ready
  - Attract video: loops attract.mp4 (in this folder) when nobody has touched the screen for a while
  - Intro video: plays intro.mp4 (or attract.mp4) full screen while F1 is loading, closes when the game appears
  - Hidden staff menu (press F12, enter PIN)

  Install once on EACH rig (as Administrator), after setting $CarNumber:
    powershell -ExecutionPolicy Bypass -File .\F1-Launcher.ps1 -Install
#>
param([switch]$Install)

# ================= SETTINGS =================
$CarNumber = 1                                   # UNIQUE per rig: 1, 2, 3 ...
$VenueName = 'F1 RACING EXPERIENCE'
$StaffPin  = '1234'                              # CHANGE THIS
$Games = [ordered]@{
    'F1 25' = 'steam://rungameid/3059520'
    'F1 24' = 'steam://rungameid/2488620'
}                                                # EA app: use the full path to the game .exe
$GameProcess = 'F1_2*|F1_25|F1_24'               # process names, so the launcher hides while racing
$UdpPort     = 47800                             # same on every rig
$IdleSeconds = 60                                # play the attract video after this long with no touch/mouse/keys
# ============================================

# Values saved by Install.ps1 override the defaults above
$cfgPath = Join-Path $PSScriptRoot 'settings.json'
if (Test-Path $cfgPath) {
    $cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json
    if ($cfg.CarNumber)   { $CarNumber   = [int]$cfg.CarNumber }
    if ($cfg.VenueName)   { $VenueName   = $cfg.VenueName }
    if ($cfg.StaffPin)    { $StaffPin    = $cfg.StaffPin }
    if ($cfg.IdleSeconds) { $IdleSeconds = [int]$cfg.IdleSeconds }
}
$AttractVideo = Get-ChildItem $PSScriptRoot -Filter 'attract.*' -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
# Intro video plays while F1 loads; uses intro.* if present, otherwise the attract video
$IntroVideo   = Get-ChildItem $PSScriptRoot -Filter 'intro.*' -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
if (-not $IntroVideo) { $IntroVideo = $AttractVideo }
$IntroMaxSeconds = 90                            # stop the intro after this long even if F1 hasn't appeared

$FanatecVid = 'VID_0EB7'
$log = Join-Path $PSScriptRoot 'fanatec-log.txt'
function Log($m) { Add-Content $log "$(Get-Date -f s)  CAR $CarNumber  $m" }

if ($Install) {
    $a = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`""
    $p = New-ScheduledTaskPrincipal -UserId $env:USERNAME -RunLevel Highest -LogonType Interactive
    Register-ScheduledTask -TaskName 'F1 Arcade Launcher' -Action $a -Trigger (New-ScheduledTaskTrigger -AtLogOn) -Principal $p -Force | Out-Null
    Unregister-ScheduledTask -TaskName 'Arcade Wheel Check' -Confirm:$false -ErrorAction SilentlyContinue
    Remove-NetFirewallRule -DisplayName 'F1 Arcade Launcher LAN' -ErrorAction SilentlyContinue
    New-NetFirewallRule -DisplayName 'F1 Arcade Launcher LAN' -Direction Inbound -Protocol UDP -LocalPort $UdpPort -Action Allow -Profile Any | Out-Null
    Write-Host "Installed as CAR $CarNumber. The launcher will open every time this user logs in."; exit
}

Add-Type -AssemblyName System.Windows.Forms, System.Drawing, PresentationFramework, PresentationCore, WindowsBase
[Windows.Forms.Application]::EnableVisualStyles()
Add-Type @'
using System; using System.Runtime.InteropServices;
public static class IdleTime {
    [StructLayout(LayoutKind.Sequential)] struct LASTINPUTINFO { public uint cbSize; public uint dwTime; }
    [DllImport("user32.dll")] static extern bool GetLastInputInfo(ref LASTINPUTINFO p);
    public static uint Seconds() {
        var l = new LASTINPUTINFO(); l.cbSize = (uint)Marshal.SizeOf(l); GetLastInputInfo(ref l);
        return ((uint)Environment.TickCount - l.dwTime) / 1000;
    }
}
'@

# ---------- videos ----------
# attract: loops when idle, any touch/click/key returns to the home screen
# intro:   loops while F1 is loading, closes itself when the game window appears
$script:attract = $null
$script:intro   = $null
function New-VideoWindow($path, $caption) {
    $w = New-Object System.Windows.Window
    $w.WindowStyle = 'None'; $w.WindowState = 'Maximized'; $w.ResizeMode = 'NoResize'; $w.Topmost = $true
    $w.Background = [System.Windows.Media.Brushes]::Black
    $grid = New-Object System.Windows.Controls.Grid
    $m = New-Object System.Windows.Controls.MediaElement
    $m.Source = [Uri]$path; $m.LoadedBehavior = 'Manual'; $m.Stretch = 'UniformToFill'
    $m.Add_MediaEnded({ $this.Position = [TimeSpan]::Zero; $this.Play() })
    $tb = New-Object System.Windows.Controls.TextBlock
    $tb.Text = $caption; $tb.FontSize = 54; $tb.FontWeight = [System.Windows.FontWeights]::Bold
    $tb.Foreground = [System.Windows.Media.Brushes]::White; $tb.HorizontalAlignment = 'Center'; $tb.VerticalAlignment = 'Bottom'
    $tb.Margin = New-Object System.Windows.Thickness(0, 0, 0, 60)
    [void]$grid.Children.Add($m); [void]$grid.Children.Add($tb)
    $w.Content = $grid
    $w.Tag = $m
    $w.Add_Loaded({ $this.Tag.Play() })
    $w
}
function Close-Video($w) { if ($w) { $w.Tag.Stop(); $w.Close() } }

function Show-Attract {
    if (-not $AttractVideo -or $script:attract) { return }
    $script:attract = New-VideoWindow $AttractVideo 'TOUCH ANYWHERE TO PLAY'
    $close = { if ($script:attract) { Close-Video $script:attract; $script:attract = $null; $form.Activate() } }
    $script:attract.Add_PreviewMouseDown($close); $script:attract.Add_PreviewKeyDown($close); $script:attract.Add_PreviewTouchDown($close)
    $script:attract.Show()
}

function Show-Intro($game) {
    if (-not $IntroVideo) { return }
    $script:intro = New-VideoWindow $IntroVideo "Loading $game…"
    $script:introStart = Get-Date
    $script:intro.Show()
}
function Update-Intro {
    if (-not $script:intro) { return }
    $elapsed = ((Get-Date) - $script:introStart).TotalSeconds
    $gameUp  = Get-Process | Where-Object { $_.Name -match $GameProcess -and $_.MainWindowHandle -ne 0 }
    if (($gameUp -and $elapsed -ge 8) -or $elapsed -ge $IntroMaxSeconds) {
        Close-Video $script:intro; $script:intro = $null
    }
}

# ---------- LAN: every rig broadcasts "F1RIG|car|state" and listens for the others ----------
$udp = New-Object Net.Sockets.UdpClient
$udp.Client.SetSocketOption('Socket', 'ReuseAddress', $true)
$udp.Client.Bind((New-Object Net.IPEndPoint([Net.IPAddress]::Any, $UdpPort)))
$udp.EnableBroadcast = $true
$bcast = New-Object Net.IPEndPoint([Net.IPAddress]::Broadcast, $UdpPort)
$peers = @{}                                     # car number -> @{ State; Seen }

function Test-Network { [Net.NetworkInformation.NetworkInterface]::GetIsNetworkAvailable() }
function Send-Beacon {
    $b = [Text.Encoding]::ASCII.GetBytes("F1RIG|$CarNumber|$script:state")
    try { [void]$udp.Send($b, $b.Length, $bcast) } catch {}
}
function Read-Beacons {
    $ep = New-Object Net.IPEndPoint([Net.IPAddress]::Any, 0)
    while ($udp.Available -gt 0) {
        try { $parts = [Text.Encoding]::ASCII.GetString($udp.Receive([ref]$ep)).Split('|') } catch { break }
        if ($parts.Count -eq 3 -and $parts[0] -eq 'F1RIG' -and [int]$parts[1] -ne $CarNumber) {
            $peers[[int]$parts[1]] = @{ State = $parts[2]; Seen = Get-Date }
        }
    }
}
function Get-PeerState($car) {
    $p = $peers[$car]
    if (-not $p -or ((Get-Date) - $p.Seen).TotalSeconds -gt 15) { 'offline' } else { $p.State }
}

# ---------- UI ----------
$red   = [Drawing.Color]::FromArgb(225, 6, 0)
$dark  = [Drawing.Color]::FromArgb(15, 15, 20)
$panel = [Drawing.Color]::FromArgb(30, 30, 38)
function F($size, $bold = $true) { New-Object Drawing.Font('Segoe UI', $size, $(if ($bold) { 'Bold' } else { 'Regular' })) }

$form = New-Object Windows.Forms.Form -Property @{
    FormBorderStyle = 'None'; WindowState = 'Maximized'; TopMost = $true; BackColor = $dark; KeyPreview = $true }

$top = New-Object Windows.Forms.Panel -Property @{ Dock = 'Top'; Height = 130; BackColor = $red }
$top.Controls.Add((New-Object Windows.Forms.Label -Property @{
    Text = "$VenueName   ·   CAR $CarNumber"; Dock = 'Fill'; TextAlign = 'MiddleCenter'; ForeColor = 'White'; Font = (F 44) }))

$layout = New-Object Windows.Forms.TableLayoutPanel -Property @{ Dock = 'Fill'; ColumnCount = 1; RowCount = 4; Padding = '60,30,60,30' }
foreach ($pct in 22, 13, 20, 45) { [void]$layout.RowStyles.Add((New-Object Windows.Forms.RowStyle('Percent', $pct))) }

# Wheel status card
$status = New-Object Windows.Forms.Label -Property @{
    Dock = 'Fill'; TextAlign = 'MiddleCenter'; Font = (F 34); BackColor = $panel; ForeColor = 'White'
    Text = 'Checking wheel…'; Margin = '200,10,200,10' }
$layout.Controls.Add($status, 0, 0)

# LAN rig bar
$rigBar = New-Object Windows.Forms.FlowLayoutPanel -Property @{ AutoSize = $true; WrapContents = $false }
$rigHost = New-Object Windows.Forms.Panel -Property @{ Dock = 'Fill' }
$rigHost.Controls.Add($rigBar)
$centreRigs = { $rigBar.Left = [int](($rigHost.Width - $rigBar.Width) / 2); $rigBar.Top = [int](($rigHost.Height - $rigBar.Height) / 2) }
$rigHost.Add_Resize($centreRigs); $rigBar.Add_SizeChanged($centreRigs)
$layout.Controls.Add($rigHost, 0, 1)

function Update-RigBar {
    $rigBar.SuspendLayout(); $rigBar.Controls.Clear()
    $cars = @($CarNumber) + @($peers.Keys) | Sort-Object -Unique
    foreach ($c in $cars) {
        $s = if ($c -eq $CarNumber) { $script:state } else { Get-PeerState $c }
        $txt, $col = switch ($s) {
            'ready'  { '✔ Ready',   'LimeGreen' }
            'racing' { '🏁 Racing', 'DeepSkyBlue' }
            'repair' { '… Fixing',  'Orange' }
            'fault'  { '✖ Fault',   $red }
            default  { '● Offline', 'Gray' }
        }
        $name = if ($c -eq $CarNumber) { "CAR $c (this car)" } else { "CAR $c" }
        $rigBar.Controls.Add((New-Object Windows.Forms.Label -Property @{
            Text = "$name`n$txt"; ForeColor = $col; BackColor = $panel; Font = (F 16); TextAlign = 'MiddleCenter'
            Width = 230; Height = 80; Margin = '10,0,10,0' }))
    }
    $rigBar.ResumeLayout()
}

# Game picker
$pick = New-Object Windows.Forms.FlowLayoutPanel -Property @{ Dock = 'Fill'; FlowDirection = 'LeftToRight'; WrapContents = $false }
$script:selected = @($Games.Keys)[0]
$gameButtons = @()
foreach ($name in $Games.Keys) {
    $b = New-Object Windows.Forms.Button -Property @{
        Text = $name; Width = 300; Height = 95; Font = (F 26); FlatStyle = 'Flat'; ForeColor = 'White'; Tag = $name; Margin = '20,10,20,10' }
    $b.FlatAppearance.BorderSize = 3
    $b.Add_Click({ $script:selected = $this.Tag; Update-Picker })
    $pick.Controls.Add($b); $gameButtons += $b
}
$pickHost = New-Object Windows.Forms.Panel -Property @{ Dock = 'Fill' }
$pickHost.Controls.Add($pick)
$pickHost.Add_Resize({ $pick.Width = $pick.PreferredSize.Width; $pick.Height = 120; $pick.Left = [int](($pickHost.Width - $pick.Width) / 2) })
$layout.Controls.Add($pickHost, 0, 2)
function Update-Picker { foreach ($b in $gameButtons) {
    $b.BackColor = if ($b.Tag -eq $script:selected) { $red } else { $panel }
    $b.FlatAppearance.BorderColor = if ($b.Tag -eq $script:selected) { 'White' } else { $panel } } }
Update-Picker

# SINGLE PLAYER / MULTIPLAYER buttons
$modes = New-Object Windows.Forms.TableLayoutPanel -Property @{ Dock = 'Fill'; ColumnCount = 2; RowCount = 1; Margin = '120,10,120,10' }
[void]$modes.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent', 50)))
[void]$modes.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent', 50)))
$mkMode = { param($t) $b = New-Object Windows.Forms.Button -Property @{
    Text = $t; Font = (F 30); Dock = 'Fill'; FlatStyle = 'Flat'; ForeColor = 'White'; Margin = '25,10,25,10'; Enabled = $false }
    $b.FlatAppearance.BorderSize = 0; $b }
$single = & $mkMode 'SINGLE PLAYER'
$multi  = & $mkMode 'MULTIPLAYER'
$modes.Controls.Add($single, 0, 0); $modes.Controls.Add($multi, 1, 0)
$layout.Controls.Add($modes, 0, 3)

$foot = New-Object Windows.Forms.Label -Property @{
    Dock = 'Bottom'; Height = 40; ForeColor = 'Gray'; Font = (F 12 $false); TextAlign = 'MiddleCenter'
    Text = 'Multiplayer: start on every car, then join the same lobby in F1's Multiplayer menu   ·   Staff: F12' }

$form.Controls.AddRange(@($layout, $foot, $top))

# ---------- state ----------
$script:fails  = 0
$script:racing = $false
$script:state  = 'repair'                         # ready | repair | fault | racing

function Set-Status {
    if ($script:racing) { return }
    if (Test-Wheel) {
        if ($script:fails -gt 0) { Log 'Wheel detected and working' }
        $script:fails = 0; $script:state = 'ready'
        $status.Text = '✔  Wheel detected and working'; $status.ForeColor = 'LimeGreen'
    } else {
        $script:fails++
        if ($script:fails -le 3) {
            $script:state = 'repair'
            $status.Text = "Reconnecting wheel…  ($($script:fails)/3)"; $status.ForeColor = 'Orange'
            Update-Buttons; [Windows.Forms.Application]::DoEvents(); Repair-Wheel
        } else {
            if ($script:fails -eq 4) { Log 'WHEEL FAULT shown' }
            $script:state = 'fault'
            $status.Text = '✖  WHEEL FAULT – please call staff'; $status.ForeColor = $red
        }
    }
}

function Update-Buttons {
    $wheelOk = $script:state -eq 'ready'
    $netOk   = Test-Network
    $others  = @($peers.Keys | Where-Object { (Get-PeerState $_) -eq 'ready' }).Count

    $single.Enabled = $wheelOk
    $single.Text    = if ($wheelOk) { 'SINGLE PLAYER' } else { "SINGLE PLAYER`nUnavailable" }
    $single.BackColor = if ($wheelOk) { $red } else { $panel }

    $multi.Enabled = $wheelOk -and $netOk -and $others -ge 1
    $multi.Text = if (-not $wheelOk) { "MULTIPLAYER`nUnavailable" }
                  elseif (-not $netOk) { "MULTIPLAYER`nNetwork not connected" }
                  elseif ($others -lt 1) { "MULTIPLAYER`nWaiting for other cars" }
                  else { "MULTIPLAYER`n$($others + 1) cars ready" }
    $multi.BackColor = if ($multi.Enabled) { $red } else { $panel }
}

function Start-Race($mode) {
    if (-not (Test-Wheel)) { Set-Status; Update-Buttons; return }
    Log "Launching $script:selected ($mode)"
    $script:racing = $true; $script:state = 'racing'; Send-Beacon
    $status.Text = "Launching $script:selected – $mode…"; $status.ForeColor = 'White'
    $single.Enabled = $false; $multi.Enabled = $false
    [Windows.Forms.Application]::DoEvents()
    Close-Video $script:attract; $script:attract = $null
    Show-Intro $script:selected
    Start-Process $Games[$script:selected]
    Start-Sleep 3
    $form.TopMost = $false; $form.WindowState = 'Minimized'
}
$single.Add_Click({ Start-Race 'Single Player' })
$multi.Add_Click({ Start-Race 'Multiplayer' })

# Every 3s: check wheel, talk to the other rigs, refresh screen, bring launcher back after a race
$script:tick = 0
$timer = New-Object Windows.Forms.Timer -Property @{ Interval = 2000 }
$timer.Add_Tick({
    $script:tick++
    if ($script:racing) {
        Update-Intro
        if (-not (Get-Process | Where-Object Name -match $GameProcess)) {
            if ($script:launchSeen) {
                $script:racing = $false; $script:launchSeen = $false
                $form.WindowState = 'Maximized'; $form.TopMost = $true; $form.Activate(); Set-Status
            }
        } else { $script:launchSeen = $true }
    } elseif ($script:tick % 2 -eq 0) { Set-Status }
    Send-Beacon; Read-Beacons
    if (-not $script:racing) {
        Update-RigBar; Update-Buttons
        if ([IdleTime]::Seconds() -ge $IdleSeconds) { Show-Attract }
    }
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
    $bRetry.Add_Click({ if (& $guard) { $script:fails = 0; Repair-Wheel; $pin.Close(); Set-Status; Update-Buttons } })
    $bLog.Add_Click({   if (& $guard) { $form.TopMost = $false; Start-Process notepad $log; $pin.Close() } })
    $bExit.Add_Click({  if (& $guard) { Log 'Staff exit'; $pin.Close(); $form.Close() } })
    $bOff.Add_Click({   if (& $guard) { Log 'Staff shutdown'; Stop-Computer -Force } })
    $pin.Controls.AddRange(@($box, $bRetry, $bLog, $bExit, $bOff))
    [void]$pin.ShowDialog($form)
})

$form.Add_Shown({ Set-Status; Send-Beacon; Update-RigBar; Update-Buttons; $timer.Start() })
$form.Add_FormClosed({ $timer.Stop(); $udp.Close() })
[Windows.Forms.Application]::Run($form)
