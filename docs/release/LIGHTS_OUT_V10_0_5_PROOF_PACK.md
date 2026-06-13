# Lights Out v10.0.5 Proof Pack

**Version:** 10.0.5

**Release line:**
Lights Out v10.0.5 is a brand-polish patch on top of v10.0.4. It fixes the small-size
app icon (the taskbar/titlebar mark was a shrunk-down detailed lamp that blurred at
16/24/32 px), adds a real About dialog featuring the brand wordmark, and refines the
"LIGHTS OUT" wordmark (clearer word spacing, more legible "OUT", plus a transparent
variant). No timer/shutdown behavior changed.

## Patch v10.0.5 (brand patch after v10.0.4)

User-facing changes in this patch, all verified before the `v10.0.5` tag:

- **Crisp small-size app icon.** New `lights-out-icon-small.svg` (badge + bold glowing
  power/countdown ring, no fine lamp detail) is used for the 16/24/32 px frames; the
  detailed lamp icon is retained for 48 px and up. `scripts/make-icons.js` routes sizes
  `<=32` to the small mark and `48+` to the detailed mark when building `icon.ico`.
- **About dialog.** Help → About Lights Out now opens a real modal showing the brand
  wordmark, a one-line description, and the version (previously fired a stale toast that
  read "v5.3.0").
- **Refined wordmark.** Clearer spacing between "LIGHTS" and "OUT", brighter/more legible
  "OUT", and a new `lights-out-wordmark-transparent.svg` (no baked-in dark plate) plus a
  rendered `wordmark-1272.png` for About/splash/docs use.

### Patch v10.0.5 verification

- Smoke tests: **41/41 PASS** (`npm run smoke`), including `icon: assets/icon.ico is a
  valid multi-size ICO`.
- `npm run dist`: **PASS** — portable `LightsOut.exe` + `Lights Out Setup 10.0.5.exe`.
- **Icon proof (authoritative):** the icon was extracted from the packaged `Lights Out.exe`
  via the Win32 `PrivateExtractIcons` API (the same call the Windows shell/taskbar uses)
  and read directly from the shipped `icon.ico` frames. The 16/24/32 px frames render as a
  crisp glowing power ring; 48/64 px render the detailed lamp. The taskbar fuzziness is
  fixed. See `screenshots/v10.0.5/icon_sizes.png`.
- About dialog DOM/styles verified: `#about-modal` markup follows the existing modal
  pattern; computed styles confirmed the modal centers and the wordmark renders at the
  intended size on the app's dark surface.

> Note: a live full-app / installed-build screenshot (taskbar pinned icon, the About
> dialog open in the running app) was not captured in this pass and remains a manual
> post-publish check. The icon evidence above is taken from the actual shipped binary.

### Patch v10.0.5 screenshots

- `docs/release/screenshots/v10.0.5/icon_sizes.png` — `icon.ico` frames at 16/24/32/48/64 px
  (magnified, nearest-neighbor): crisp small power-ring mark at 16/24/32, detailed lamp at 48/64.
- `docs/release/screenshots/v10.0.5/wordmark.png` — the refined transparent "LIGHTS OUT"
  wordmark on the app surface, as shown in the About dialog.

## Release artifacts

- `Lights Out Setup 10.0.5.exe` — NSIS installer
- `LightsOut.exe` — portable
- `SHA256SUMS.txt` — checksums

### SHA256SUMS

```
3b8e3db825aee6342fb60e746d9efba5fdcbc9370641a34e1016a59a043a5433  Lights Out Setup 10.0.5.exe
003fdb38987c718b1e32fa1cb6e411a2e01e369d9876b8c6a3b605725cf528f4  LightsOut.exe
```

## Version markers (all 10.0.5)

- `electron/package.json` version: `10.0.5`
- `electron/package-lock.json` version: `10.0.5`
- HTML footer: `v10.0.5`
- About dialog: `Version 10.0.5`
- Git tag: `v10.0.5`

## Git / publish

- `0fa1ced` brand: refine Lights Out logo system for small-size icons
- `2379d28` brand: regenerate icon.ico with crisp small-size mark + wordmark PNG
- `1d0612e` brand: add About dialog featuring the transparent wordmark
- `7c48bf4` release: v10.0.5 - crisp small-size icons, About dialog, refined wordmark
- `8ef5e91` docs: mark v10.0.5 as latest on the landing page
- Tag `v10.0.5` pushed; GitHub release published (NSIS + portable + SHA256SUMS):
  https://github.com/Z3r0DayZion-install/lights-out/releases/tag/v10.0.5
