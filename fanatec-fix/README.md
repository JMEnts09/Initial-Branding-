# Fanatec DD+ – stop dropouts & firmware corruption

## ⚡ Quick install / update (do this on each rig)
1. Download this folder (GitHub → Code → Download ZIP → Extract All → open `fanatec-fix`).
3. Double-click **`Install.bat`**, click **Yes** on the admin prompt, answer the questions (car number, venue name, PIN, video, idle time).
4. Restart the PC.

Installs to `C:\F1Arcade`, and creates a **`F1 Arcade Media`** folder on the desktop for your branding:

| File | What it's for |
|---|---|
| `attract.mp4` | idle video when nobody is playing |
| `intro.mp4` | loading video (uses `attract.mp4` if missing) |
| `logo.png` | your logo in the top banner of the home screen |

Swap these files any time – videos change on the next play, the logo on the next restart. Keep the exact names.

 Run `Install.bat` again any time to update – your settings and video are kept.
The video plays full screen after the idle time; touching the screen, clicking or pressing a key returns to the home screen.
When PLAY is pressed, an intro video (`intro.mp4`, or the idle video if there isn't one) plays full screen in two parts: (1) while F1 boots – it hides when F1 reaches its menus so staff can set up the race; (2) staff press **F9** after starting the session and it plays again until the car is at the track, then the race screen appears. A loading panel over the video shows what's happening (Starting → Loading → Heading to the track), driving tips, and a progress bar. Tapping the screen skips the video so players can watch F1 load.

**Required once in F1 on each rig:** Settings → Telemetry Settings → **UDP Telemetry: On**, **UDP Broadcast: Off**, **UDP IP: 127.0.0.1**, **UDP Port: 20777**. (If SimHub also uses 20777, set SimHub to forward to another port, or change `$TelemetryPort`.)

## 1. Run the script (once, as Administrator)
```
powershell -ExecutionPolicy Bypass -File .\Fanatec-Stabilise.ps1
```
Then reboot. If the wheel disappears again later, run with `-Recover` instead of reinstalling the app.

What it does:
- Turns off USB selective suspend and USB power-saving (main cause of the base vanishing)
- Stops Windows Update swapping the Fanatec driver
- Disables Fast Startup (leaves USB in a half-asleep state)
- Clears stale/errored device entries, restarts Fanatec services and rescans

## 2. Hardware habits that prevent firmware corruption
- Plug the base **directly into a rear motherboard USB port** – no hubs, front-panel ports or extensions.
- Power on the base **after** Windows has fully booted; power it off before shutting the PC down.
- When updating firmware: close all games/SimHub/etc., don't touch the wheel, never unplug mid-update. Update the **driver first**, then base, then wheel/rim firmware.
- Use a ferrite-cored, short USB cable; keep it away from the power brick cable (EMI can corrupt flashes).
- Plug the base PSU into a surge-protected socket.

## 3. If the base is already corrupted (not seen at all)
Use Fanatec's **firmware recovery/bootloader mode** (hold the specified button while powering on – see your base's manual), then run *Fanatec Firmware Manager* to reflash. No app reinstall needed.

If corruption keeps recurring after all of this, the base or rim's USB/QR board is likely faulty – contact Fanatec support with `fanatec-log.txt` from the script folder.

## 4. Arcade startup check (Start-Arcade.ps1)
Checks the wheel every boot, auto-repairs it, and only launches F1 when the wheel works.

1. Open `Start-Arcade.ps1` in Notepad and set `$GameLaunch` (F1 25 Steam = `steam://rungameid/3059520`, F1 24 = `2488620`).
2. Run once as Administrator: `powershell -ExecutionPolicy Bypass -File .\Start-Arcade.ps1 -Install`
3. Set Windows to log in automatically, and turn the wheel on before / at the same time as the PC.

On screen players see: **"Wheel detected and working – Launching F1"** (green), or **"WHEEL FAULT – call staff"** (red). Staff fix the wheel and press **R** to retry.

## 5. F1 Arcade Launcher (F1-Launcher.ps1) – replaces section 4
Full-screen home screen with live wheel status, game picker (F1 25 / F1 24) and a big PLAY button that only works when the wheel is detected and working. Returns to the home screen when the game closes.

1. Edit the SETTINGS block at the top (venue name, **staff PIN**, games).
2. Run once as Administrator: `powershell -ExecutionPolicy Bypass -File .\F1-Launcher.ps1 -Install`
3. Turn on Windows automatic login.

Staff menu: press **F12**, enter the PIN → re-check/repair wheel, open log, exit to Windows, shut down PC.

### Multiplayer over LAN
Every rig runs the launcher and they find each other automatically on the same network (UDP port 47800; `-Install` opens the firewall).
1. In SETTINGS give each rig a **unique `$CarNumber`** (1, 2, 3 …) before running `-Install`.
2. Home screen shows a bar of every car: **Ready / Racing / Fixing / Fault / Offline**.
3. **SINGLE PLAYER** works whenever this car's wheel works – no network needed.
4. **MULTIPLAYER** only lights up when the network is connected and at least one other car is ready ("3 cars ready"). Otherwise it says "Network not connected" or "Waiting for other cars".
5. After pressing Multiplayer, players join the same lobby in F1's Multiplayer menu (F1 can't be auto-joined by outside software). Note: recent F1 games run multiplayer through EA's online servers, so the rigs also need internet for the race itself.
