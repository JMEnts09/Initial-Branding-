# Fanatec DD+ – stop dropouts & firmware corruption

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
