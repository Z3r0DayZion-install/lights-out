# Lights Out Agent Master Plan

This file is the handoff document for any code agent working in this repo.
Read it first, then decide whether the task belongs to the PowerShell app, the Electron app, or both.

## Mission

Lights Out is a Windows bedtime shutdown ritual app.
The core product idea is:

- open safely by default
- make shutdown intent clear
- allow stronger actions only when the user chooses them explicitly
- support a "lobby first" flow instead of surprising the user with an immediate countdown

## Product Surfaces

There are two real app surfaces in this repo.

1. `electron\`
   This is the Electron edition and the primary shipping UI.
   It has a real build and packaging flow and is no longer just static mock UI.
   The WinForms UI has been deprecated in favor of this cockpit dashboard.

2. `source\SleepTimer-Tonight.ps1`
   This is the original PowerShell / WinForms app.
   It compiles to `SleepTimer.exe`.
   It remains available as a fallback and for backend system operations, but new feature work targets Electron.

## Current State

As of 2026-06-09, the important behavior is:

- `Lights Out.bat` opens the Steam UI idle by default.
- force shutdown is no longer the default launcher behavior
- the explicitly named force-shutdown batch file is still the only obvious "hard stop" shortcut
- "Run at login" now means "start minimized and idle"
- login startup should never silently imply force shutdown
- displayed app/docs version is aligned to `5.3.0` across the shipping PowerShell app and Electron
- `SleepTimer.exe` was rebuilt after the login-startup behavior change
- Electron build packaging succeeds with `npm run build`

## Source Of Truth

Use these rules to avoid changing the wrong layer.

- If the user is talking about the classic app, tray behavior, settings in the WinForms UI, or the shipped root launcher files:
  work in `source\SleepTimer-Tonight.ps1`, then rebuild `SleepTimer.exe`.

- If the user is talking about the cockpit UI, Electron menus, Electron tray behavior, or the packaged `dist\LightsOut.exe`:
  work in `electron\main.js`, `electron\renderer.js`, `electron\preload.js`, `electron\index.html`, and `electron\styles.css`.

- `source\SleepTimer-Backend.ps1` is deprecated. The Electron app uses `main.js` as the timer authority.
  PowerShell is still used for ad-hoc system calls (battery, power plans, shutdown commands).

## Safe Defaults

These are intentional product constraints.
Do not casually remove them.

- default open behavior should be idle, not auto-start
- preview paths should prefer `DryRun` when possible
- force shutdown should be explicit and discoverable, not hidden behind the normal launcher
- "Run at login" wording must stay aligned with actual behavior: minimized and idle

## Files To Treat Carefully

- `SleepTimer.exe`
  Build output. Safe to replace only by rebuilding from `source\SleepTimer-Tonight.ps1`.

- `dist\`
  Electron build output. Do not hand-edit files here.

- `archive\`
  Historical backups. Do not edit unless the user explicitly asks.

- `system-tune-backup-*`
  Reference material only. Not part of normal feature work.

## Known Architecture Notes

### PowerShell app

- local modules under `modules\` provide calendar, profiles, smart lights, theme, demo, and ritual features
- the app expects to run from the Lights Out folder or a compiled exe beside the needed assets
- the startup shortcut now uses:
  `-SteamUi -Minimized -NoAutoStart`

### Electron app

- `main.js` owns timer state, tray behavior, login-item behavior, and final Windows power actions
- `renderer.js` owns view state, browser-preview fallback behavior, and UI interactions
- `preload.js` is the IPC bridge
- static preview in a browser is useful for layout smoke tests, but it is not the authoritative runtime
- browser preview uses a fallback API because there is no Electron preload bridge in plain browser mode

## Immediate Priorities

If the user does not give a more specific request, this is the default backlog.

1. Decide whether a task belongs to the primary PowerShell app or the Electron app.
2. Preserve safe startup behavior and clear wording around login startup.
3. Close Electron feature gaps before adding decorative surface area.
4. Keep shipping behavior and docs in sync after every user-facing change.

## Suggested Next Work

These are the most useful follow-on projects for an agent.

1. Close Electron parity gaps.
   Port these PowerShell features to Electron:
   - ✅ Smart lights (Philips Hue / HTTP webhook) - COMPLETE in v5.3.0+
   - ✅ Saved profiles - COMPLETE in v5.3.0+
   - ✅ Calendar scheduling (.ics import) - COMPLETE in v5.3.0+
   - Last Light ritual
   - Richer warning dialogs

2. Add repeatable smoke checks.
   At minimum, keep a quick path to verify:
   start, pause, resume, snooze, cancel, mini mode, tray hide/show, and login-startup wording.

3. Archive or remove deprecated code.
   `SleepTimer-Backend.ps1` is no longer used. Consider removing it to reduce confusion.

## Verification Checklist

### For PowerShell app changes

1. Rebuild:
   `Invoke-ps2exe -inputFile "source\SleepTimer-Tonight.ps1" -outputFile "SleepTimer.exe" -noConsole -title "Lights Out" -iconFile "SleepTimer.ico"`
2. Launch:
   `.\Lights Out.bat`
3. Verify:
   idle open, tray behavior, settings wording, and any changed action flow

### For Electron changes

1. Syntax-check:
   `node --check .\electron\main.js`
   `node --check .\electron\renderer.js`
   `node --check .\electron\preload.js`
2. Run:
   `cd electron`
   `npm start`
3. Package when the change is meaningful:
   `npm run build`

### For static browser preview of Electron UI

Use this only for layout and interaction smoke tests.
It is not a substitute for running Electron itself.

1. Start a local server from repo root:
   `python -m http.server 58731 --bind 127.0.0.1 --directory electron`
2. Open:
   `http://localhost:58731/index.html`
3. Expect the renderer fallback path, not the Electron preload path.

## Definition Of Done

A task is not done until:

- the change landed in the correct runtime
- the safest default behavior still makes sense
- verification was actually run for the surface you changed
- docs or launcher text were updated if user-facing behavior changed
- `SleepTimer.exe` was rebuilt if the PowerShell source changed

## Do Not Reintroduce

Avoid these regressions unless the user explicitly asks for them.

- default launcher starts with `-ForceShutdown`
- login startup begins an active countdown without user intent
- docs claiming a flow is "idle" when the code actually auto-starts
- editing backup files instead of current source files

## First Question For The Next Agent

Before making a large change, answer this:

"Is this task a new feature (target Electron), a backend system call (use PowerShell), or a bug fix in legacy code?"

New UI work always targets Electron. PowerShell remains for Windows system integration only.
