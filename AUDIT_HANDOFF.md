# Lights Out - Audit Handoff

Purpose: hand this session's changes to an external reviewer (e.g. ChatGPT) for an independent audit.
Scope: Electron edition only (`electron/`). The PowerShell app was not touched.

Work is split into TWO branches so the functional fixes are not bundled with the UI polish:

| Branch | Contains | Tip |
|--------|----------|-----|
| `fix/settings-and-system-actions` | functional fixes only | `f29152c` |
| `ui/polish-hero-tabs-cleanup` | UI/CSS polish, built ON TOP of the fix branch | `e75fca9` |

Base both diverged from: `ce654d9` on `main`.
Nothing has been pushed, tagged, or released.

Merge order (intended):
1. Review + merge `fix/settings-and-system-actions` first.
2. Then rebase/merge `ui/polish-hero-tabs-cleanup` (it already sits on top of the fix branch, so it lands clean).
3. Only then consider a tag/release.

Commit graph:
```
ce654d9  (main base)
  └─ f29152c  fix: settings persistence, theme hijack removal, wind-down toggles, menu/window   [fix branch tip]
       └─ e75fca9  ui: polish hero, tabs, cards                                                  [ui branch tip]
```

Inspect with:
```
git log --oneline --graph ui/polish-hero-tabs-cleanup -4
git show f29152c        # functional
git show e75fca9        # UI polish (CSS/screenshots/capture script only)
```

---

## 1. Functional fixes — branch `fix/settings-and-system-actions` (commit f29152c)

### A. Settings persistence
User report: "it wont let me save force shutdown, or sound off".

1. `electron/renderer.js` `render()` was unconditionally writing the options-modal
   checkboxes from `state` on every render. The running timer calls `render()` each tick,
   so any checkbox toggled in the open modal was reset before the user clicked Save. Fix:
   the checkbox sync block is guarded by `if (!els.optionsModal?.classList.contains('active'))`.
2. `electron/renderer.js` `toggle-mute` / `toggle-dryrun` / `toggle-graceful` quick toggles
   updated `state` only, never persisted. They now call
   `api.saveAppSettings({ app: collectAppSettings() })` after `render()`.

AUDIT FOCUS:
- Confirm the modal guard does not block legitimate sync when the modal is closed.
- EDGE CASE worth checking: open modal, toggle a checkbox, Cancel (no Save), reopen — the
  checkbox may show the stale unsaved value until the next `render()` re-syncs it. Not fixed
  here (kept minimal/stable for audit). Decide if it needs a `render()` on modal close.
- PRE-EXISTING latent bug (NOT introduced/fixed here): handlers
  `chkIdleDetect/chkBedtimeReminder/chkCalendarAutostart` do
  `const app = api.getAppSettings?.() || {}` where `getAppSettings` is async (returns a
  Promise), then mutate and save it. Flag separately if in scope.

### B. Removed Windows desktop-theme hijack
User report: "it switched my desktop from dark to light".

`electron/main.js` previously called `applyNightMode(true/false)` which wrote
`AppsUseLightTheme` / `SystemUsesLightTheme`, forcing the OS to light mode on restore. The
function and both call sites were removed entirely.

AUDIT FOCUS:
- `git grep -n "applyNightMode\|UsesLightTheme" electron/` should return nothing (verified empty).
- `restoreAfterTimer()` still restores opacity, night-light blob, media, wifi, content
  blocker, and lockout.

### C. Opt-in "Wind-down system actions" toggles (all default OFF)
- `nightLightOnDim`, `pauseMediaOnDim`, `lockoutOnDim`.
- `electron/settings.js` — DEFAULTS.app gains the three keys (`false`).
- `electron/index.html` — new "Wind-down system actions" section (3 checkboxes).
- `electron/renderer.js` — element refs; persisted in `collectAppSettings`; restored in
  `applyAppSettings`.
- `electron/main.js` — `applyDimPhase()` gates Night Light, media pause, and the
  always-on-top/menu lockout behind these settings (Night Light was previously tied to
  `customization.warmShift`; now `app.nightLightOnDim === true`).

AUDIT FOCUS: each gated block reads `settingsStore.getSection('app')` and checks `=== true`;
restore paths are harmless when a feature was never enabled.

### D. Menu clickable + window auto-fit
- `electron/main.js` — new IPC `fit-window-height` resizes the window to content within the
  display work area (floor 600, leaves 48px margin); skipped in mini/maximized/fullscreen.
- `electron/preload.js` — exposes `fitWindowHeight`.
- `electron/renderer.js` — `setupAutoFitWindow()` IIFE measures dashboard content and asks
  main to resize, via a debounced MutationObserver.
- NOTE: the `.chrome-header { z-index }` + `.submenu::before` hover-bridge CSS for clickable
  dropdowns lives in the UI-polish commit (`styles.css`), not here.

AUDIT FOCUS: no resize feedback loop between `setupAutoFitWindow` and `fit-window-height`;
disabled in mini-mode and when maximized/fullscreen.

---

## 2. UI polish — branch `ui/polish-hero-tabs-cleanup` (commit e75fca9)

`electron/styles.css` only (plus before/after screenshots and `scripts/polish-capture.js`).
No behavior changes. Hero radial glow + glass disc behind the ring, larger countdown
hierarchy, calm-blue START button (was green), stronger tab active/hover states, layered
cards with accent rails, tightened vertical rhythm, subtle version label, plus the menu
z-index/hover-bridge CSS. Screenshots in `docs/release/screenshots/polish/`.

AUDIT FOCUS: pure CSS; confirm no selectors broken and no JS/markup changed in this commit.
Safe-state visuals: Ready shows START + Idle pill; Running hides START and shows
Pause/Snooze/Cancel with the phase pill (not "Idle").

---

## 3. How to verify (reproduce locally)

```
cd electron

# Static checks
node --check main.js
node --check renderer.js
node --check settings.js
node --check preload.js

# Smoke suite (expected: 41 passed, 0 failed)
node scripts/smoke-test.js

# Package (expected: portable LightsOut.exe + NSIS installer in ../dist)
npm run build

# Run
npm start
```

Verified this session on BOTH branches: syntax OK, smoke 41/41, build OK.

### Manual UI checks
1. Settings → tick "Force shutdown", Save, reopen → stays ticked.
2. Toggle sound (mute) off, restart app → stays off.
3. Run a timer to the dim/wind-down phase → Windows theme does NOT change.
4. All three wind-down toggles OFF (default) → no Night Light, no media pause, no on-top lockout.
5. Ready shows START + "Idle" pill; Running hides START, shows Pause/Snooze/Cancel, pill is
   "Focus"/"Winding Down", never "Idle".

---

## 4. Intentional safe defaults (do not flag as bugs)
- All wind-down system actions default OFF.
- Default launcher opens idle; no auto force-shutdown.
- "Run at login" means minimized + idle, never an active countdown.
- The app must never change the user's desktop theme.

## 5. Out of scope / left as-is
- Untracked, uncommitted helper files left in the working tree (not part of either branch):
  `electron/assets/v10_*.png`, older `electron/scripts/cdp-capture*.js`,
  `electron/scripts/test-ambient-global.js`, `electron/scripts/reload-app.js` (unused).
- PowerShell app (`source/`, `modules/`, `SleepTimer.exe`) untouched.
- App version strings untouched.

## 6. Suggested auditor questions
1. Modal-close staleness (see 1.A edge case): worth a `render()` on cancel/close?
2. Is `api.saveAppSettings` debounced enough that quick-toggle persistence won't thrash disk?
3. Any resize feedback loop risk between `setupAutoFitWindow` and `fit-window-height`?
4. Does the pre-existing async-`getAppSettings` pattern (1.A) actually persist correctly today?
