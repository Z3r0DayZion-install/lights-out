# Lights Out

I built a Windows shutdown timer I would actually use every night.

Windows commands work, but they are annoying.
Old shutdown timer apps work, but most feel clunky.

Lights Out is free:
No account.
No subscription.
No ads.

Installer, portable build, SHA256 checksums, and proof-backed releases are all public.

**Download:** https://github.com/Z3r0DayZion-install/lights-out/releases/latest

![Lights Out cockpit - analog/hybrid clock face and the new desk-lamp logo](release/screenshots/v10.0.4/01_clock_face_hybrid.png)

## What it does

- **Nightly tray utility.** It sits in your tray and shows the current time while
  idle (Clock Mode) - pick a digital, analog, or hybrid clock face and recolor the
  hands. Start common timers (28 min / 1 hour), or pause / resume / snooze / cancel
  straight from the tray. The live countdown stays in the tray tooltip.
- **Countdown to shutdown, restart, sleep, hibernate, or log out.**
- **Wind-down phase** with ambient visuals (fireplace, rain, starfield, aurora),
  a warm color shift, and optional Night Light / media pause.
- **Smart lights, saved profiles, calendar scheduling (.ics), and a Last Light
  finale** for the people who want the full ritual.

## Safe by default

- Opens idle, never as an instant countdown.
- Force shutdown is an explicit, clearly named action - never the default, never
  hidden in the tray.
- "Run at login" means start minimized and idle, nothing more.
- System actions (Night Light, media pause, window lockout during wind-down) are
  all OFF by default. The app never touches your OS unless you turn them on.

![Settings - wind-down system actions OFF by default](release/screenshots/v10.0.2/04_settings_winddown.png)

## Proof-backed releases

Every release ships an installer, a portable EXE, and a `SHA256SUMS.txt` so you can
verify exactly what you downloaded. Builds are produced and published by CI, and
each release is gated on `node --check`, a smoke suite, and a successful package
step.

**Latest: v10.0.6** - a smooth sweeping second hand, a new Classic (Roman) watch
face, Hybrid as the default clock, clock prefs that persist instantly, and a fix
for a startup crash when a companion port was already in use.
Release notes: https://github.com/Z3r0DayZion-install/lights-out/releases/tag/v10.0.6

Previously, v10.0.5 brought a crisp small-size app icon and an About dialog with
the brand wordmark; v10.0.4 added customizable clock faces (digital / analog /
hybrid), the desk-lamp logo, and right-click menus on profiles and the clock.

---

### Short version (for social / forum posts)

> Lights Out - a free Windows bedtime shutdown timer that lives in your tray.
> Shows the clock while idle, starts a 28-min or 1-hour timer in one click, winds
> down with ambient visuals, and never force-shuts-down unless you ask it to.
> No account, no ads. Installer + portable + SHA256 checksums, all public.
> https://github.com/Z3r0DayZion-install/lights-out/releases/latest
