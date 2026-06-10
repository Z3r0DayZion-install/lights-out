# Lights Out - Electron Edition

A modern, native-like desktop application built with Electron. Features a cockpit-style dashboard UI with proper window controls, menus, and PowerShell backend integration.

## Agent Handoff

Before making code changes, read `..\AGENTS.md`.
It explains which runtime is authoritative for a task and what verification path to use afterward.

## Prerequisites

- **Node.js** 18+ (Download from https://nodejs.org/)
- **Windows 10/11**
- PowerShell 5.1+

## Quick Start

### Option 1: Run with Batch File (Easiest)
```batch
# In File Explorer, navigate to: Lights Out\electron\
# Double-click: run-electron.bat
```

### Option 2: Run from PowerShell/Terminal
```powershell
cd "C:\Users\KickA\Desktop\Lights Out\electron"
npm install   # Only needed first time
npm start
```

## Features

### Native Window
- ✅ Standard Windows frame (can be moved, resized, minimized)
- ✅ Native minimize/close buttons
- ✅ System tray integration
- ✅ Single instance lock

### Cockpit Dashboard UI
- **Timer Ring** - Visual countdown with progress ring
- **Quick Actions** - Start, pause, resume, snooze, cancel
- **Menu Bar** - Select power action, start presets, open settings, view help
- **Status Cards** - Selected action, end time, battery, power plan, warnings
- **Tabbed Section** - Library, Schedule, Clock, Countdown tabs
- **Tonight Picks** - Quick preset cards wired to action, duration, and force mode

### Power Integration
- Shutdown, Restart, Sleep, Hibernate
- Grace period and dry-run options
- Force shutdown capability
- Battery-aware warnings
- Run at login creates a lightweight startup entry that opens minimized and idle

## Project Structure

```
electron/
├── package.json          # Electron dependencies
├── main.js               # Main process (window, tray, IPC)
├── preload.js            # Secure IPC bridge
├── index.html            # Main UI
├── styles.css            # Dark cockpit theme
├── renderer.js           # Frontend logic
├── run-electron.bat      # Easy launcher
└── README.md             # This file
```

## Building Executable

To create a standalone `.exe`:

```bash
cd "C:\Users\KickA\Desktop\Lights Out\electron"
npm install
npm run build
```

Output will be in `dist/` folder.

## How It Works

1. **Electron** creates the native window with HTML/CSS UI
2. **Electron main process** owns the timer state for pause, resume, snooze, cancel, tray, and taskbar progress
3. **PowerShell / Windows commands** handle system information and final power actions

## Troubleshooting

### "Node.js not found"
Install Node.js from https://nodejs.org/ and restart your terminal.

### "npm install fails"
Run PowerShell as Administrator and try again, or check your internet connection.

### Window won't show
Check the console for errors. Press `Ctrl+Shift+I` in the window to open DevTools.

## Development

Edit these files to customize:
- `styles.css` - Colors, layout, animations
- `index.html` - UI structure
- `renderer.js` - Frontend behavior
- `main.js` - Window behavior, system integration

## License

Same as original Lights Out project.
