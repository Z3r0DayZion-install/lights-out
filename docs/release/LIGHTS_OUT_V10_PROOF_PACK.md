# Lights Out v10.0.3 Proof Pack

**Version:** 10.0.3

**Release line:**
Lights Out v10.0.3 is the zero-friction sleep/shutdown timer: calendar-aware, idle-aware, bedtime-aware, with ambient visuals, smart-light sunrise, and proof-backed Windows builds. v10.0.3 is a UX patch that reworks the system-tray context menu, adds an idle Clock Mode hero, and fixes a tray-menu rebuild bug that could drop a click on the open menu.

## Patch v10.0.3 (UX patch after v10.0.2)

These are the user-facing changes in this patch. All were verified before the `v10.0.3` tag.

- **Reworked tray context menu** — phase-aware status header, Show Lights Out / Hide to Tray, **Open Settings** (focuses the window and opens settings via the new `open-settings` IPC), quick **Start 28 min** / **Start 1 hour**, and a clean Quit. While a timer runs the menu offers **Pause/Resume**, **Snooze +5 min**, and **Cancel Timer**.
- **No Force Shutdown in the tray** — the hard stop stays explicit and discoverable elsewhere; it is never one click away in the tray.
- **Clock Mode (idle hero)** — when idle, the hero ring shows the current local time with a "READY" sublabel (and bedtime line when configured), switching to the live countdown the moment a timer starts. Lives in **Customize → "Show current time when idle"**, default ON.
- **Tray menu rebuild fix** — the timer tick used to rebuild the tray context menu every second (`tray.setContextMenu()` per tick). On Windows that can drop a click on an open menu (e.g. Pause), leaving the timer running and the menu stuck on "Pause". The menu is now rebuilt only on real state transitions; the live countdown stays in the tray **tooltip** via `updateTrayText()` each tick.

### Patch v10.0.3 verification

- `node --check` (main/renderer/settings/preload): PASS
- Smoke tests: 41/41 PASS
- `npm run build`: PASS (portable + installer)
- CDP runtime test (Clock Mode placement, idle clock, countdown switch, START hidden, Cancel, toggles OFF, no theme hijack, settings modal): 16/16 PASS
- Tray rebuild fix verified via instrumentation: menu rebuilds once per state transition, zero per-tick rebuilds

### Patch v10.0.3 screenshots

- `docs/release/screenshots/v10.0.3/01_clock_mode_idle.png` — idle hero showing current time + READY
- `docs/release/screenshots/v10.0.3/02_clock_mode_setting.png` — Customize section with "Show current time when idle"

## Patch v10.0.2 (fixes after v10.0.1)

These are the user-facing fixes and improvements in this patch. All were verified before the `v10.0.2` tag.

- **Settings persistence fix** — the options modal no longer gets reset by render() ticks while open, so toggles (including **Force Shutdown** and **sound off**) actually save. Quick toggles (mute/dry-run/graceful) now persist across relaunch.
- **No more desktop-theme hijack** — removed `applyNightMode()` and its call sites. The app no longer flips the user's Windows dark/light theme during wind-down or restore.
- **Opt-in Wind-down system actions (default OFF)** — new settings `nightLightOnDim`, `pauseMediaOnDim`, `lockoutOnDim`, surfaced in a new "Wind-down system actions" settings section. The app never touches the OS unless explicitly enabled.
- **Menu / window cleanup** — dropdown menus stay clickable (z-index + hover bridge), and the window auto-fits its height to content within the display work area (skipped in mini/maximized/fullscreen).
- **UI polish** — hero radial glow + glass disc behind the ring, larger countdown hierarchy, calm-blue START, stronger tab states, layered cards with accent rails, tightened layout rhythm, subtle version label. CSS-only; before/after evidence in `docs/release/screenshots/polish/`.

### Patch v10.0.2 verification

- `node --check` (main/renderer/settings/preload): PASS
- Smoke tests: 41/41 PASS
- `npm run build`: PASS (portable + installer)

## Patch v10.0.1 (fixes after v10.0.0 was cut)

These fixes are why a patch was required. They were found and verified after the `v10.0.0` tag.

- **AmbientVisuals global export fix** — `ambientVisuals.js` is now a UMD module: it exports via `module.exports` for Node/main and assigns `window.AmbientVisuals` for the renderer `<script>` path. Before this, the renderer had no `AmbientVisuals` global, so ambient visuals never initialized in the packaged `v10.0.0` build.
- **Customize modal scroll fix** — `.customize`/options container now uses `overflow-y: auto` with `max-height: calc(100vh - 120px)`, so all toggles are reachable instead of being clipped below the fold.
- **Menu bar hidden** — `autoHideMenuBar: true` on the main window, and `restoreAfterTimer()` now restores to hidden (`setMenuBarVisibility(false)`) instead of showing the menu bar.
- **AC Power fallback** — when no battery is present and the power plan reads `Unknown`, the UI now shows `AC Power` instead of `Unknown` (both in the normal load path and the catch fallback).
- **Taller default window** — default window height raised from `720` to `800` so the full cockpit fits without scrolling.
- **Screenshot capture correction** — release screenshots regenerated to reflect actual rendered UI state.

### Patch verification

- `node --check` (all modules): PASS
- Smoke tests: 41/41 PASS
- `npm run build`: PASS (portable + installer)

## Commits

- `75a1f57` original v10 implementation
- `18748a0` hardening/proof fixes
- v10.0.1 patch: ambient visuals global export, customize scroll, menu bar, AC power fallback, window height, screenshots
- `48461d4` v10.0.2: settings persistence, drop desktop-theme hijack, opt-in wind-down toggles, menu/window (#3)
- `a750430` v10.0.2: hero/tabs/cards UI polish (#4)
- `d365e59` v10.0.3: tray context menu + Clock Mode, with per-tick tray rebuild fix (#5)

## Build

- `npm run build`: PASS
- `node --check` (all modules): PASS
- Smoke tests: 41/41 PASS

## Artifacts

- `Lights Out Setup 10.0.3.exe`
- `LightsOut.exe` portable
- `SHA256SUMS.txt` (checksums for both artifacts, generated in CI release step)

## Feature Proof

### Ambient Visuals
- Canvas-rendered backgrounds (fireplace, rain, starfield, aurora) during dim phase
- **Proof:** `AmbientVisuals.stop()` called on both cancel and complete code paths
- UMD module: `module.exports` for Node/main, `window.AmbientVisuals` for the renderer `<script>` path (v10.0.1 fix)
- CSS `opacity: 0` by default, fades to `0.6` only during dim phase

### Calendar Auto-Start
- Checks every 60s for calendar events starting within 2 minutes
- **Proof:** Only matches events containing keywords: "lights out", "bedtime", "wind down", "shutdown", "sleep timer", "goodnight", "lights off"
- "Team Standup" and "Lunch with Sarah" correctly skipped in test
- Calendar fetch failure caught silently (`try/catch`), does not crash app

### Idle Detection
- Win32 `GetLastInputInfo` via PowerShell, checks every 15s
- **Proof:** `wasIdle` flag fires once on idle enter, once on return
- No repeat notifications within the same idle/return cycle
- Threshold configurable, default 5 minutes

### Bedtime Reminder
- Checks every 60s against configured bedtime
- **Proof:** `bedtimeReminderEnabled` and `bedtimeReminderMinutes` persisted in settings
- Toggle state restores on app launch
- Fires once per day per date check (`lastReminderDate` guard)

### Smart Light Sunrise Sync
- During First Light, gradually brightens room lights 0-100% over 60s
- **Proof:** `invokeSmartLightAction().catch(() => {})` swallows all failures
- Timer completes regardless of smart light availability
- Hue/HA/IFTTT/MQTT offline = silent skip, no crash

### Morning Routine Builder
- 5s after First Light, fetches calendar + sleep debt + streaks
- **Proof:** Only notifies `if (data?.events?.length)` -- honest empty state
- Calendar fetch failure caught, briefing simply not sent
- No fabricated placeholder data

## Version Alignment

- `package.json` version: `10.0.3`
- Build output: `Lights Out Setup 10.0.3.exe`
- HTML footer: `v10.0.3`
- Git tag: `v10.0.3`

## Safety Guarantees

- No real shutdown during tests
- No cloud telemetry (all data local)
- Smart light failure does not block timer
- Calendar failure does not crash app
- Ambient visuals clean up on timer end
- Idle detection does not spam notifications
- Calendar auto-start does not trigger from non-bedtime events
- Morning briefing does not fabricate data
