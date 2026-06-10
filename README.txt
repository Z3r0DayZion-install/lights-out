Lights Out v5.3.0

START HERE
  Double-click "Lights Out.bat"                    (Steam UI — opens idle)
  Double-click "Lights Out Premium Preview.bat"    (Night Lobby — safe DryRun preview)
  Double-click "Lights Out - Force Shutdown Within 1 Hour.bat" only when you want force shutdown

IN THIS FOLDER
  SleepTimer.exe      - the app
  modules\            - calendar, novel, smart lights, etc. (required)
  SleepTimer.ico      - tray icon
  LightsOut-Logo.png  - title logo
  source\             - PowerShell source (for dev)
  archive\            - previous exe backup

Settings:  %LOCALAPPDATA%\CoolTimer\settings.json
Emergency cancel: Ctrl+Shift+S
Run at login: creates a startup shortcut that opens Lights Out minimized and idle.
Agent handoff: read AGENTS.md before making code changes. It explains whether a task belongs to the PowerShell app, the Electron app, or both.

NEW (Electron edition)
  Customization console - accent color, theme (Midnight/Carbon/Aurora),
    ring style, window opacity, and sound volume, applied live
  Stateful settings - all options persist and restore on launch
  Last Light finale - optional cinematic timer-zero sequence (Settings)
  Warning dialog - grace-period heads-up with Snooze / Cancel
  Crash recovery - an interrupted countdown offers Resume / Dismiss on restart

NEW IN 5.3.0
  Safe startup defaults
    • "Lights Out.bat" opens the Steam UI idle by default
    • Run at login now starts minimized and idle
    • Force shutdown stays in the explicitly named hard-stop launcher
  Electron edition
    • Cockpit UI now supports start, pause, resume, snooze, cancel, mini mode, tray, and taskbar progress
    • Electron build packaging is aligned to v5.3.0

NEW IN 5.2.2
  Smart Lights - control Philips Hue or HTTP webhook lights
    • Gradual dim - slowly dims over last N minutes
    • Warm shift + dim - shifts color temp to warm and dims
    • Off at end - instant off when timer fires
  UI Polish - breathing ring glow, deeper gradients, glow orbs
  Tray menu - dark themed with icons and logical sections
  Options panel - 💡 LIGHTS section with provider/mode/setup/test

NEW IN 5.1
  Calendar - import .ics from Google/Outlook/Apple
  Dim phase - 90s wind-down before power action
  Sleep ledger - streak tracker (top-right link)
  Bedtime pact + Household sync (card buttons)

SMART LIGHTS SETUP
  1. Open Options > LIGHTS section
  2. Check "Smart Light control"
  3. Select provider: Philips Hue or HTTP Webhook
  4. Click "Setup / Pair":
     - Hue: auto-discovers bridge, press link button, click OK
     - HTTP: enter your webhook URL (body template uses {{BRIGHTNESS}}, {{COLOR_TEMP}}, {{ON}})
  5. Pick mode and dim duration
  6. Click "Test" to verify connectivity

LUXGRID RGB (optional)
  Check "LuxGrid RGB" in app settings
  Pair with LuxGrid Studio - Sleep Ritual profile

BUILD FROM SOURCE
  Invoke-ps2exe -inputFile "source\SleepTimer-Tonight.ps1" `
    -outputFile "SleepTimer.exe" -noConsole `
    -title "Lights Out" -iconFile "SleepTimer.ico"
  Requires: ps2exe module (Install-Module ps2exe)

CI / TESTING
  Launch with flags for safe testing:
    .\SleepTimer.exe -SteamUi -NoAutoStart -DryRun
  DryRun mode skips actual power actions (shutdown/sleep/etc.)
  Verify: no popup errors, ring animation, options expand, tray menu works
