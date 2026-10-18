<#
  F1-Launcher.ps1  -  Arcade home screen for F1 sim rigs
  - Boot sequence: PC connected -> wheel testing (detect, turn the wheel, press the pedals)
    -> "Wheel connected and ready to go". Auto-repairs dropouts.
  - LAN: shows "PC2 connected", "PC3 connected" ... with a green light (never IP addresses)
  - SINGLE PLAYER always; MULTIPLAYER only appears when another PC is connected
  - Attract video: loops attract.mp4 (Desktop\\F1 Arcade Media) when nobody has touched the screen for a while
  - Intro video: plays while F1 boots, hides at the menus so staff can set up the race,
    then staff press F9 after starting the session and it plays again until the car is on track
  - Hidden staff menu (press F12, enter PIN)

  Install once on EACH rig (as Administrator), after setting $CarNumber:
    powershell -ExecutionPolicy Bypass -File .\F1-Launcher.ps1 -Install
#>
param([switch]$Install)

# ================= SETTINGS =================
$CarNumber = 1                                   # UNIQUE per rig: 1, 2, 3 ...  (shown as PC1, PC2 ...)
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
# Branding folder on the desktop - staff can swap these files any time, no reinstall needed:
#   attract.mp4  idle video          intro.mp4  loading video (falls back to attract)
#   logo.png     shown in the top banner on the home screen
$MediaDir = Join-Path ([Environment]::GetFolderPath('Desktop')) 'F1 Arcade Media'
New-Item $MediaDir -ItemType Directory -Force | Out-Null
function Get-Media($name) {
    foreach ($dir in $MediaDir, $PSScriptRoot) {
        $f = Get-ChildItem $dir -Filter "$name.*" -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
        if ($f) { return $f }
    }
}
# Any video file in the folder works - names are optional.
# If files are named attract / intro those are used for idle / loading; otherwise the first video plays for both.
function Get-AnyVideo {
    Get-ChildItem $MediaDir -File -ErrorAction SilentlyContinue |
        Where-Object Extension -in '.mp4', '.wmv', '.mov', '.avi', '.m4v' |
        Sort-Object Name | Select-Object -First 1 -ExpandProperty FullName
}
function Get-AttractVideo { $v = Get-Media 'attract'; if ($v) { $v } else { Get-AnyVideo } }
function Get-IntroVideo   { $v = Get-Media 'intro';   if ($v) { $v } else { Get-AttractVideo } }
$IntroMaxSeconds = 600                           # safety: stop the intro after 10 min even if no on-track signal
$MenuDelay       = 40                            # seconds after F1's window appears before the video hides for staff
$TrackVideoKey   = 0x78                          # F9: staff press after starting a session -> video until the car is on track
$TelemetryPort   = 20777                         # F1 in-game: Settings > Telemetry > UDP Telemetry ON, IP 127.0.0.1, this port

$FanatecVid = 'VID_0EB7'
$log = Join-Path $PSScriptRoot 'fanatec-log.txt'
function Log($m) { Add-Content $log "$(Get-Date -f s)  PC$CarNumber  $m" }

if ($Install) {
    $a = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`""
    $p = New-ScheduledTaskPrincipal -UserId $env:USERNAME -RunLevel Highest -LogonType Interactive
    Register-ScheduledTask -TaskName 'F1 Arcade Launcher' -Action $a -Trigger (New-ScheduledTaskTrigger -AtLogOn) -Principal $p -Force | Out-Null
    Unregister-ScheduledTask -TaskName 'Arcade Wheel Check' -Confirm:$false -ErrorAction SilentlyContinue
    Remove-NetFirewallRule -DisplayName 'F1 Arcade Launcher LAN' -ErrorAction SilentlyContinue
    New-NetFirewallRule -DisplayName 'F1 Arcade Launcher LAN' -Direction Inbound -Protocol UDP -LocalPort $UdpPort -Action Allow -Profile Any | Out-Null
    Write-Host "Installed as PC$CarNumber. The launcher will open every time this user logs in."; exit
}

Add-Type -AssemblyName System.Windows.Forms, System.Drawing, PresentationFramework, PresentationCore, WindowsBase
[Windows.Forms.Application]::EnableVisualStyles()
Add-Type @'
using System; using System.Runtime.InteropServices;
// Reads every game controller's axes through winmm (no extra drivers). Fanatec devices only, if any are found.
public static class Joy {
    [StructLayout(LayoutKind.Sequential)] struct JOYINFOEX {
        public int dwSize, dwFlags, X, Y, Z, R, U, V, dwButtons, dwButtonNumber, dwPOV, r1, r2; }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)] struct JOYCAPS {
        public ushort wMid, wPid;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string szPname;
        public int wXmin, wXmax, wYmin, wYmax, wZmin, wZmax, wNumButtons, wPeriodMin, wPeriodMax,
                   wRmin, wRmax, wUmin, wUmax, wVmin, wVmax, wCaps, wMaxAxes, wNumAxes, wMaxButtons;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string szRegKey;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)] public string szOEMVxD; }
    [DllImport("winmm.dll")] static extern int joyGetPosEx(int id, ref JOYINFOEX ji);
    [DllImport("winmm.dll", CharSet = CharSet.Unicode)] static extern int joyGetDevCapsW(IntPtr id, ref JOYCAPS jc, int size);
    public static int[][] Read(ushort vid) {
        var fan = new System.Collections.Generic.List<int[]>(); var all = new System.Collections.Generic.List<int[]>();
        for (int id = 0; id < 16; id++) {
            var c = new JOYCAPS();
            if (joyGetDevCapsW((IntPtr)id, ref c, Marshal.SizeOf(c)) != 0) continue;
            var j = new JOYINFOEX(); j.dwSize = Marshal.SizeOf(j); j.dwFlags = 0xFF;
            if (joyGetPosEx(id, ref j) != 0) continue;
            var axes = new int[] { j.X, j.Y, j.Z, j.R, j.U, j.V };
            all.Add(axes); if (c.wMid == vid) fan.Add(axes);
        }
        return (fan.Count > 0 ? fan : all).ToArray();
    }
}
public static class StaffKey {
    [DllImport("user32.dll")] static extern short GetAsyncKeyState(int vKey);
    public static bool Pressed(int vKey) { return (GetAsyncKeyState(vKey) & 0x8001) != 0; }
}
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
    if (-not $caption) { $tb.Visibility = 'Collapsed' }
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
    $video = Get-AttractVideo
    if (-not $video -or $script:attract) { return }
    $script:attract = New-VideoWindow $video 'TOUCH ANYWHERE TO PLAY'
    $close = { if ($script:attract) { Close-Video $script:attract; $script:attract = $null; $form.Activate() } }
    $script:attract.Add_PreviewMouseDown($close); $script:attract.Add_PreviewKeyDown($close); $script:attract.Add_PreviewTouchDown($close)
    $script:attract.Show()
}

# F1's own UDP telemetry tells us when the car is actually at the track.
# Header byte 6 = packet id. Motion (0) is only sent while a car is in a session;
# Event (3) carries a 4-letter code at byte 29: SSTA session start, STLG start lights, LGOT lights out.
$tele = $null
try {
    $tele = New-Object Net.Sockets.UdpClient
    $tele.Client.SetSocketOption('Socket', 'ReuseAddress', $true)
    $tele.Client.Bind((New-Object Net.IPEndPoint([Net.IPAddress]::Any, $TelemetryPort)))
} catch { Log "Telemetry port $TelemetryPort unavailable: $_"; $tele = $null }

function Test-OnTrack {
    if (-not $tele) { return $false }
    $ep = New-Object Net.IPEndPoint([Net.IPAddress]::Any, 0); $hit = $false
    while ($tele.Available -gt 0) {
        try { $b = $tele.Receive([ref]$ep) } catch { break }
        if ($b.Length -lt 33) { continue }
        if ($b[6] -eq 0) { $hit = $true }
        elseif ($b[6] -eq 3 -and [Text.Encoding]::ASCII.GetString($b, 29, 4) -in 'SSTA', 'STLG', 'LGOT') { $hit = $true }
    }
    $hit
}

$LoadingTips = @(
    'F1 is loading in the background – your race starts automatically',
    'Use the paddles behind the wheel to change gear',
    'Brake in a straight line, then turn in',
    'Smooth on the throttle out of corners – the wheel will fight back!',
    'Keep both hands on the wheel at all times'
)

# Two phases, because staff set up the race in F1's menus:
#   boot  - from PLAY until F1 reaches its menus (video hides so staff can see them)
#   track - staff press F9 after starting the session; video until the car is on track
function Show-Intro($game, $mode = 'boot') {
    try { Show-IntroWindow $game $mode }
    catch { Log "Intro video failed: $_"; $script:intro = $null }
}
function Show-IntroWindow($game, $mode) {
    $video = Get-IntroVideo
    if ($script:intro) { return }
    if (-not $video) { Log "Intro: no video found in $MediaDir"; return }
    Log "Intro ($mode): playing $video"
    $script:introMode = $mode
    [void](Test-OnTrack)                          # throw away anything left over from the last race
    $script:intro = New-VideoWindow $video ''
    $script:intro.ShowActivated = $false          # keep keyboard/wheel focus on the game, not the video
    $grid = $script:intro.Content

    # Loading panel over the video: stage, tip, skip hint
    $bg = New-Object System.Windows.Controls.Border
    $bg.Background = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(190, 0, 0, 0))
    $bg.VerticalAlignment = 'Bottom'; $bg.Padding = New-Object System.Windows.Thickness(40, 30, 40, 30)
    $stack = New-Object System.Windows.Controls.StackPanel
    $mk = { param($size, $bold, $colour)
        $t = New-Object System.Windows.Controls.TextBlock
        $t.FontSize = $size; $t.HorizontalAlignment = 'Center'; $t.TextWrapping = 'Wrap'; $t.TextAlignment = 'Center'
        $t.Foreground = $colour
        if ($bold) { $t.FontWeight = [System.Windows.FontWeights]::Bold }
        [void]$stack.Children.Add($t); $t }
    $script:introStage = & $mk 50 $true  ([System.Windows.Media.Brushes]::White)
    $bar = New-Object System.Windows.Controls.ProgressBar
    $bar.IsIndeterminate = $true; $bar.Height = 10; $bar.Width = 700; $bar.Margin = New-Object System.Windows.Thickness(0, 18, 0, 18)
    $bar.Foreground = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb(225, 6, 0))
    [void]$stack.Children.Add($bar)
    $script:introTip   = & $mk 30 $false ([System.Windows.Media.Brushes]::Gainsboro)
    $skip = & $mk 22 $false ([System.Windows.Media.Brushes]::Gray)
    $skip.Text = 'Tap the screen to skip the video'
    $skip.Margin = New-Object System.Windows.Thickness(0, 20, 0, 0)
    $bg.Child = $stack
    [void]$grid.Children.Add($bg)

    $script:intro.Add_PreviewMouseDown({ Log 'Intro skipped'; Close-Video $script:intro; $script:intro = $null })
    $script:intro.Add_PreviewTouchDown({ Log 'Intro skipped'; Close-Video $script:intro; $script:intro = $null })

    $script:introGame  = $game
    $script:introStart = Get-Date
    Set-IntroText
    $script:intro.Show()
}

function Set-IntroText {
    $elapsed = ((Get-Date) - $script:introStart).TotalSeconds
    $running = Get-Process | Where-Object Name -match $GameProcess
    $script:introStage.Text = if ($script:introMode -eq 'track') { 'Heading to the track…' }
                              elseif (-not $running) { "Starting $($script:introGame)…" }
                              else { "Loading $($script:introGame)…" }
    $script:introTip.Text = $LoadingTips[[int]($elapsed / 6) % $LoadingTips.Count]
}

function Update-Intro {
    if (-not $script:intro) { return }
    # F1 grabs the top of the screen when its window opens - push the video back on top
    $script:intro.Topmost = $false; $script:intro.Topmost = $true
    $elapsed = ((Get-Date) - $script:introStart).TotalSeconds
    $window = Get-Process | Where-Object { $_.Name -match $GameProcess -and $_.MainWindowHandle -ne 0 }
    if ($window -and -not $script:windowSeen) { $script:windowSeen = Get-Date }
    if ($script:introMode -eq 'boot') {
        $done = $script:windowSeen -and ((Get-Date) - $script:windowSeen).TotalSeconds -ge $MenuDelay
    } else {
        # No telemetry socket: fall back to a short fixed video
        $done = (Test-OnTrack) -or (-not $tele -and $elapsed -ge 30)
    }
    if ($done -or $elapsed -ge $IntroMaxSeconds) {
        if ($elapsed -ge $IntroMaxSeconds) { Log 'Intro video timed out - no on-track signal from F1' }
        Close-Video $script:intro; $script:intro = $null
        if ($script:introMode -eq 'boot') { [void][StaffKey]::Pressed($TrackVideoKey) }   # clear any earlier F9 press
        return
    }
    Set-IntroText
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
    Text = "$VenueName   ·   PC$CarNumber"; Dock = 'Fill'; TextAlign = 'MiddleCenter'; ForeColor = 'White'; Font = (F 44) }))
$logo = Get-Media 'logo'
if ($logo -and $logo -match '\.(png|jpg|jpeg|bmp|gif)$') {
    $top.Controls.Add((New-Object Windows.Forms.PictureBox -Property @{
        Dock = 'Left'; Width = 320; SizeMode = 'Zoom'; Padding = '20,10,20,10'; Image = [Drawing.Image]::FromFile($logo) }))
}

$layout = New-Object Windows.Forms.TableLayoutPanel -Property @{ Dock = 'Fill'; ColumnCount = 1; RowCount = 4; Padding = '60,30,60,30' }
foreach ($pct in 22, 13, 20, 45) { [void]$layout.RowStyles.Add((New-Object Windows.Forms.RowStyle('Percent', $pct))) }

# Wheel status card
$status = New-Object Windows.Forms.Label -Property @{
    Dock = 'Fill'; TextAlign = 'MiddleCenter'; Font = (F 30); BackColor = $panel; ForeColor = 'White'
    Text = 'Starting…'; Margin = '150,10,150,10' }
$status.Add_Click({ if ($script:phase -eq 'fault') { Log 'Wheel test restarted from screen'; Start-WheelTest } })
$layout.Controls.Add($status, 0, 0)

# LAN rig bar
$rigBar = New-Object Windows.Forms.FlowLayoutPanel -Property @{ AutoSize = $true; WrapContents = $false }
$rigHost = New-Object Windows.Forms.Panel -Property @{ Dock = 'Fill' }
$rigHost.Controls.Add($rigBar)
$centreRigs = { $rigBar.Left = [int](($rigHost.Width - $rigBar.Width) / 2); $rigBar.Top = [int](($rigHost.Height - $rigBar.Height) / 2) }
$rigHost.Add_Resize($centreRigs); $rigBar.Add_SizeChanged($centreRigs)
$layout.Controls.Add($rigHost, 0, 1)

function Get-ConnectedPeers { @($peers.Keys | Where-Object { (Get-PeerState $_) -ne 'offline' } | Sort-Object) }

function Update-RigBar {
    $rigBar.SuspendLayout(); $rigBar.Controls.Clear()
    $connected = Get-ConnectedPeers
    if (-not (Test-Network) -or $connected.Count -eq 0) {
        $rigBar.Controls.Add((New-Object Windows.Forms.Label -Property @{
            Text = 'No other PCs connected – single player'; ForeColor = 'Gray'; Font = (F 18 $false)
            AutoSize = $true; Margin = '10,25,10,0' }))
    } else {
        foreach ($c in $connected) {
            $detail = switch (Get-PeerState $c) {
                'ready'   { 'ready to go' } 'racing' { 'racing' } 'testing' { 'wheel testing' } 'fault' { 'wheel fault' } default { '' } }
            $rigBar.Controls.Add((New-Object Windows.Forms.Label -Property @{
                Text = "●  PC$c connected`n$detail"; ForeColor = 'LimeGreen'; BackColor = $panel; Font = (F 18)
                TextAlign = 'MiddleCenter'; Width = 280; Height = 85; Margin = '10,0,10,0' }))
        }
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
$multi.Visible = $false
$modes.ColumnStyles[0].Width = 100; $modes.ColumnStyles[1].Width = 0
$modes.Controls.Add($single, 0, 0); $modes.Controls.Add($multi, 1, 0)
$layout.Controls.Add($modes, 0, 3)

$foot = New-Object Windows.Forms.Label -Property @{
    Dock = 'Bottom'; Height = 40; ForeColor = 'Gray'; Font = (F 12 $false); TextAlign = 'MiddleCenter'
    Text = "Multiplayer: start on every PC, then join the same lobby in F1's Multiplayer menu   ·   Staff: F12" }

$form.Controls.AddRange(@($layout, $foot, $top))

# ---------- state + boot wheel test ----------
# phase: network -> detect -> steer -> pedal -> ready   (or fault)
$script:fails  = 0
$script:racing = $false
$script:phase  = 'network'
$script:state  = 'testing'                        # what other PCs see: testing | ready | fault | racing
$TestTimeout   = 120                              # seconds to wait for the wheel to be turned / pedals pressed
$MoveThreshold = 6000                             # axis change (of 0-65535) that counts as movement

function Start-WheelTest { $script:phase = 'network'; $script:phaseStart = Get-Date; $script:fails = 0; $script:steerDev = $null }
function Set-Phase($p) { $script:phase = $p; $script:phaseStart = Get-Date; $script:base = [Joy]::Read(0x0EB7) }
function Get-Moved($skipX) {
    # returns the index of a device whose axis moved past the threshold, or $null
    $now = [Joy]::Read(0x0EB7)
    for ($d = 0; $d -lt [Math]::Min($now.Count, $script:base.Count); $d++) {
        for ($a = 0; $a -lt 6; $a++) {
            if ($a -eq 0 -and $skipX -contains $d) { continue }
            if ($a -ne 0 -and $skipX -eq 'onlyX') { continue }
            if ([Math]::Abs($now[$d][$a] - $script:base[$d][$a]) -gt $MoveThreshold) { return $d }
        }
    }
    $null
}
function Show-Test($line, $colour) {
    $tick = { param($done, $name) if ($done) { "✔ $name" } else { "○ $name" } }
    $p = $script:phase
    $checks = '{0}     {1}     {2}' -f (& $tick ($p -ne 'network') 'PC connected'),
                                      (& $tick ($p -in 'pedal', 'ready') 'Steering'),
                                      (& $tick ($p -eq 'ready') 'Pedals')
    $status.Text = "$line`n`n$checks"; $status.ForeColor = $colour
}

function Step-WheelTest {
    $elapsed = ((Get-Date) - $script:phaseStart).TotalSeconds
    switch ($script:phase) {
        'network' {
            $script:state = 'testing'
            if (Test-Network) { Show-Test '✔  PC connected' 'LimeGreen' } else { Show-Test 'PC ready – no network, single player only' 'Orange' }
            if ($elapsed -ge 3) { Set-Phase 'detect' }
        }
        'detect' {
            Show-Test 'Wheel testing…  looking for the wheel' 'White'
            if ((Test-Wheel) -and [Joy]::Read(0x0EB7).Count -gt 0) { Log 'Wheel detected - testing steering'; Set-Phase 'steer' }
            elseif ($elapsed -ge 8) {
                $script:fails++
                if ($script:fails -gt 3) { Set-Fault 'Wheel not detected' }
                else { Show-Test "Reconnecting wheel…  ($($script:fails)/3)" 'Orange'; [Windows.Forms.Application]::DoEvents(); Repair-Wheel; Set-Phase 'detect' }
            }
        }
        'steer' {
            Show-Test 'Wheel testing…  turn the steering wheel left and right' 'Orange'
            $d = Get-Moved 'onlyX'
            if ($null -ne $d) { $script:steerDev = $d; Log 'Steering OK - testing pedals'; Set-Phase 'pedal' }
            elseif ($elapsed -ge $TestTimeout) { Set-Fault 'Steering not responding' }
        }
        'pedal' {
            Show-Test 'Wheel testing…  press the throttle and brake pedals' 'Orange'
            if ($null -ne (Get-Moved @($script:steerDev))) { Log 'Pedals OK - ready'; Set-Phase 'ready' }
            elseif ($elapsed -ge $TestTimeout) { Set-Fault 'Pedals not detected' }
        }
        'ready' {
            $script:state = 'ready'
            Show-Test '✔  Wheel connected and ready to go' 'LimeGreen'
            if ($script:tick % 5 -eq 0 -and -not (Test-Wheel)) { Log 'Wheel lost - retesting'; $script:state = 'testing'; Set-Phase 'detect' }
        }
        'fault' { }
    }
}
function Set-Fault($why) {
    Log "WHEEL FAULT: $why"
    $script:phase = 'fault'; $script:state = 'fault'
    $status.Text = "✖  $why`n`nPlease call staff  –  tap here to test again"; $status.ForeColor = $red
}

function Update-Buttons {
    $wheelOk   = $script:phase -eq 'ready'
    $connected = if (Test-Network) { Get-ConnectedPeers } else { @() }
    $others    = @($connected | Where-Object { (Get-PeerState $_) -eq 'ready' }).Count

    $single.Enabled   = $wheelOk
    $single.Text      = if ($wheelOk) { 'SINGLE PLAYER' } else { "SINGLE PLAYER`nWaiting for wheel test" }
    $single.BackColor = if ($wheelOk) { $red } else { $panel }

    # Multiplayer is removed from the screen entirely unless another PC is connected
    $showMulti = $connected.Count -gt 0
    if ($multi.Visible -ne $showMulti) {
        $multi.Visible = $showMulti
        $modes.ColumnStyles[0].Width = if ($showMulti) { 50 } else { 100 }
        $modes.ColumnStyles[1].Width = if ($showMulti) { 50 } else { 0 }
    }
    $multi.Enabled = $wheelOk -and $others -ge 1
    $multi.Text = if (-not $wheelOk) { "MULTIPLAYER`nWaiting for wheel test" }
                  elseif ($others -lt 1) { "MULTIPLAYER`nWaiting for other PCs" }
                  else { "MULTIPLAYER`n$($others + 1) PCs ready" }
    $multi.BackColor = if ($multi.Enabled) { $red } else { $panel }
}

function Start-Race($mode) {
    if (-not (Test-Wheel)) { Log 'Wheel lost at PLAY - retesting'; Set-Phase 'detect'; Update-Buttons; return }
    Log "Launching $script:selected ($mode)"
    $script:racing = $true; $script:state = 'racing'; Send-Beacon
    $status.Text = "Launching $script:selected – $mode…"; $status.ForeColor = 'White'
    $single.Enabled = $false; $multi.Enabled = $false
    [Windows.Forms.Application]::DoEvents()
    Close-Video $script:attract; $script:attract = $null
    $script:windowSeen = $null
    Show-Intro $script:selected 'boot'
    Start-Process $Games[$script:selected]
    Start-Sleep 3
    $form.TopMost = $false; $form.WindowState = 'Minimized'
}
$single.Add_Click({ Start-Race 'Single Player' })
$multi.Add_Click({ Start-Race 'Multiplayer' })

# Every 1s: wheel test step; every 3s: talk to the other PCs, refresh screen, bring launcher back after a race
$script:tick = 0
$timer = New-Object Windows.Forms.Timer -Property @{ Interval = 1000 }
$timer.Add_Tick({
    $script:tick++
    if ($script:racing) {
        if (-not $script:intro -and [StaffKey]::Pressed($TrackVideoKey)) { Show-Intro $script:selected 'track' }
        Update-Intro
        if (-not (Get-Process | Where-Object Name -match $GameProcess)) {
            if ($script:launchSeen) {
                $script:racing = $false; $script:launchSeen = $false
                $form.WindowState = 'Maximized'; $form.TopMost = $true; $form.Activate()
                $script:state = 'testing'; Set-Phase 'ready'
            }
        } else { $script:launchSeen = $true }
    } else { Step-WheelTest; Update-Buttons }
    if ($script:tick % 3 -ne 0) { return }
    Send-Beacon; Read-Beacons
    if (-not $script:racing) {
        Update-RigBar
        if ([IdleTime]::Seconds() -ge $IdleSeconds) { Show-Attract }
    }
})

# Staff menu
$form.Add_KeyDown({
    if ($_.KeyCode -ne 'F12') { return }
    $pin = New-Object Windows.Forms.Form -Property @{ Text = 'Staff'; Width = 380; Height = 330; StartPosition = 'CenterScreen'; TopMost = $true; FormBorderStyle = 'FixedDialog' }
    $box = New-Object Windows.Forms.TextBox -Property @{ UseSystemPasswordChar = $true; Left = 20; Top = 20; Width = 320; Font = (F 16 $false) }
    $mk = { param($t, $y) New-Object Windows.Forms.Button -Property @{ Text = $t; Left = 20; Top = $y; Width = 320; Height = 45 } }
    $bRetry = & $mk 'Run wheel test again' 70
    $bLog   = & $mk 'Open log' 120
    $bExit  = & $mk 'Exit launcher to Windows' 170
    $bOff   = & $mk 'Shut down PC' 220
    $guard = { if ($box.Text -ne $StaffPin) { [Windows.Forms.MessageBox]::Show('Wrong PIN'); return $false }; $true }
    $bRetry.Add_Click({ if (& $guard) { Log 'Staff restarted wheel test'; $pin.Close(); Repair-Wheel; Start-WheelTest } })
    $bLog.Add_Click({   if (& $guard) { $form.TopMost = $false; Start-Process notepad $log; $pin.Close() } })
    $bExit.Add_Click({  if (& $guard) { Log 'Staff exit'; $pin.Close(); $form.Close() } })
    $bOff.Add_Click({   if (& $guard) { Log 'Staff shutdown'; Stop-Computer -Force } })
    $pin.Controls.AddRange(@($box, $bRetry, $bLog, $bExit, $bOff))
    [void]$pin.ShowDialog($form)
})

$form.Add_Shown({ Start-WheelTest; Step-WheelTest; Send-Beacon; Update-RigBar; Update-Buttons; $timer.Start() })
$form.Add_FormClosed({ $timer.Stop(); $udp.Close(); if ($tele) { $tele.Close() } })
[Windows.Forms.Application]::Run($form)
