const { app, BrowserWindow, ipcMain, Tray, Menu, nativeImage, Notification, globalShortcut, shell } = require('electron');
const path = require('path');
const { spawn } = require('child_process');
const smartLights = require('./smartLights');
const profiles = require('./profiles');
const calendar = require('./calendar');
const settingsStore = require('./settings');
const lastLight = require('./lastLight');
const streaks = require('./streaks');
const alarm = require('./alarm');
const updater = require('./updater');
const calProviders = require('./calendarProviders');
const companion = require('./companion');
const media = require('./media');
const unsavedGuard = require('./unsavedGuard');
const family = require('./family');
const wifiGuard = require('./wifiGuard');
const contentBlocker = require('./contentBlocker');
const accountability = require('./accountability');
const focusSessions = require('./focusSessions');
const screenTime = require('./screenTime');
const sleepDebt = require('./sleepDebt');
const emergencyOverride = require('./emergencyOverride');
const runReceipts = require('./runReceipts');
const idleDetection = require('./idleDetection');
const bedtimeReminder = require('./bedtimeReminder');

const APP_ICON = path.join(__dirname, 'assets', 'icon.ico');

// Pre-built tray icon variants (generated on first use).
let trayIcons = null;

async function ensureTrayIcons() {
  if (trayIcons) return trayIcons;
  try {
    const sharp = require('sharp');
    const base16 = await sharp(APP_ICON).resize(16, 16).png().toBuffer();

    async function withDot(color, opacity) {
      const dotSvg = `<svg width="16" height="16"><circle cx="13" cy="13" r="3" fill="${color}" opacity="${opacity || 0.9}"/></svg>`;
      const dotBuf = await sharp(Buffer.from(dotSvg)).png().toBuffer();
      return await sharp(base16).composite([{ input: dotBuf, blend: 'over' }]).png().toBuffer();
    }

    const [idle, running, paused, dim] = await Promise.all([
      withDot('#6b7685', 0.5),
      withDot('#4caf50', 0.9),
      withDot('#d4a50a', 0.9),
      withDot('#5b8cff', 0.9)
    ]);

    trayIcons = {
      idle: nativeImage.createFromBuffer(idle, { width: 16, height: 16 }),
      running: nativeImage.createFromBuffer(running, { width: 16, height: 16 }),
      paused: nativeImage.createFromBuffer(paused, { width: 16, height: 16 }),
      dim: nativeImage.createFromBuffer(dim, { width: 16, height: 16 })
    };
  } catch {
    // Fallback: just use the base icon for all states.
    const base = nativeImage.createFromPath(APP_ICON);
    trayIcons = { idle: base, running: base, paused: base, dim: base };
  }
  return trayIcons;
}

let mainWindow;
let widgetWindow = null;
let tray = null;
let miniMode = false;
let widgetMode = false;
let timerInterval = null;
let activeReceiptId = null;

const launchOptions = parseLaunchOptions(process.argv);

const timerState = {
  running: false,
  paused: false,
  totalSeconds: 0,
  remainingSeconds: 0,
  action: 'shutdown',
  dryRun: false,
  forceShutdown: false,
  muteSystem: false,
  gracePeriod: 2,
  endsAt: null,
  phase: 'idle'        // idle | focus | dim | lastlight
};

// Wind-down phase boundaries (fraction of total time remaining).
// Focus: 100% → 25%, Dim: 25% → gracePeriod, Last Light: gracePeriod → 0.
function computePhase(remaining, total, gracePeriod) {
  if (remaining <= 0 || total <= 0) return 'lastlight';
  const graceSeconds = Math.max(0, (gracePeriod || 0) * 60);
  if (remaining <= graceSeconds) return 'lastlight';
  if (remaining / total <= 0.25) return 'dim';
  return 'focus';
}

function parseLaunchOptions(argv) {
  const options = {
    minimized: false,
    noAutoStart: false,
    timerMinutes: 0,
    action: 'shutdown',
    wakeAlarm: false,
    firstLight: false
  };

  for (const arg of argv) {
    const lower = String(arg).toLowerCase();
    if (lower === '--minimized' || lower === '--minimized-to-tray') options.minimized = true;
    if (lower === '--no-auto-start') options.noAutoStart = true;
    if (lower.startsWith('--timer=')) options.timerMinutes = Number(lower.split('=')[1]) || 0;
    if (lower.startsWith('--action=')) options.action = lower.split('=')[1] || 'shutdown';
    if (lower === '--wake-alarm' || lower === '--first-light') options.firstLight = true;
  }

  return options;
}

function createWindow() {
  const windowConfig = miniMode ? {
    width: 260,
    height: 320,
    minWidth: 240,
    minHeight: 280,
    maxWidth: 340,
    maxHeight: 420,
    alwaysOnTop: true,
    resizable: true
  } : {
    width: 520,
    height: 720,
    minWidth: 480,
    minHeight: 600,
    alwaysOnTop: false,
    resizable: true
  };

  mainWindow = new BrowserWindow({
    ...windowConfig,
    frame: true,
    titleBarStyle: 'default',
    show: false,
    icon: APP_ICON,
    webPreferences: {
      nodeIntegration: false,
      contextIsolation: true,
      preload: path.join(__dirname, 'preload.js'),
      backgroundThrottling: false
    }
  });

  mainWindow.miniMode = miniMode;
  mainWindow.loadFile('index.html');

  mainWindow.once('ready-to-show', () => {
    if (launchOptions.minimized) {
      mainWindow.minimize();
      mainWindow.hide();
    } else {
      mainWindow.show();
    }

    if (launchOptions.timerMinutes > 0 && !launchOptions.noAutoStart) {
      startTimer({
        durationSeconds: launchOptions.timerMinutes * 60,
        action: launchOptions.action
      });
    }
  });

  mainWindow.on('close', event => {
    if (app.isQuitting) return;
    event.preventDefault();
    mainWindow.hide();
    refreshTrayMenu();
  });

  mainWindow.on('closed', () => {
    mainWindow = null;
    if (app.isQuitting) clearTimerInterval();
  });
}

async function createTray() {
  await ensureTrayIcons();
  tray = new Tray(trayIcons.idle);
  refreshTrayMenu();

  tray.setToolTip('Lights Out - idle');
  tray.on('click', toggleMainWindow);
}

function refreshTrayMenu() {
  if (!tray) return;

  const active = timerState.running || timerState.paused;
  const remaining = active ? formatTime(timerState.remainingSeconds) : '';
  const phaseLabel = timerState.phase === 'dim' ? 'Dim' : timerState.phase === 'lastlight' ? 'Last Light' : '';
  const statusLine = active
    ? (timerState.paused ? `Paused - ${remaining}` : `${phaseLabel ? phaseLabel + ' - ' : ''}${remaining} left`)
    : 'Idle';

  const contextMenu = Menu.buildFromTemplate([
    {
      label: `Lights Out  ·  ${statusLine}`,
      enabled: false
    },
    { type: 'separator' },
    {
      label: mainWindow && mainWindow.isVisible() ? 'Hide Window' : 'Show Window',
      click: toggleMainWindow
    },
    {
      label: 'Desktop Widget',
      type: 'checkbox',
      checked: widgetMode,
      click: () => {
        if (widgetMode) closeWidgetWindow();
        else createWidgetWindow();
      }
    },
    { type: 'separator' },
    ...active ? [
      {
        label: timerState.paused ? 'Resume' : 'Pause',
        click: () => (timerState.paused ? resumeTimer() : pauseTimer())
      },
      {
        label: 'Snooze +5 min',
        click: () => snoozeTimer(300)
      },
      {
        label: 'Cancel Timer',
        click: cancelTimer
      }
    ] : [
      { label: '15 min until bed', click: () => startTimer({ durationSeconds: 15 * 60, action: 'shutdown' }) },
      { label: '30 min until bed', click: () => startTimer({ durationSeconds: 30 * 60, action: 'shutdown' }) },
      { label: '45 min until bed', click: () => startTimer({ durationSeconds: 45 * 60, action: 'shutdown' }) },
      { label: '1 hour until bed', click: () => startTimer({ durationSeconds: 60 * 60, action: 'shutdown' }) }
    ],
    { type: 'separator' },
    {
      label: 'Quit',
      click: () => {
        app.isQuitting = true;
        app.quit();
      }
    }
  ]);

  tray.setContextMenu(contextMenu);
}

function toggleMainWindow() {
  if (!mainWindow) return;
  if (mainWindow.isVisible()) {
    mainWindow.hide();
  } else {
    mainWindow.show();
    if (mainWindow.isMinimized()) mainWindow.restore();
    mainWindow.focus();
  }
  refreshTrayMenu();
}

function showNativeNotification(title, body) {
  if (!Notification.isSupported()) return null;

  const notification = new Notification({
    title,
    body,
    icon: APP_ICON,
    silent: false,
    timeoutType: 'default'
  });
  notification.show();
  return notification;
}

function setTaskbarProgress(percent, mode = 'normal') {
  if (!mainWindow || mainWindow.isDestroyed()) return;
  if (mode === 'none') {
    mainWindow.setProgressBar(-1);
    return;
  }
  mainWindow.setProgressBar(Math.max(0, Math.min(1, percent / 100)), { mode });
}

function emitTimerUpdate(type, data = {}) {
  const payload = {
    type,
    running: timerState.running,
    paused: timerState.paused,
    totalSeconds: timerState.totalSeconds,
    remainingSeconds: timerState.remainingSeconds,
    total: timerState.totalSeconds,
    remaining: timerState.remainingSeconds,
    action: timerState.action,
    dryRun: timerState.dryRun,
    forceShutdown: timerState.forceShutdown,
    gracePeriod: timerState.gracePeriod,
    endsAt: timerState.endsAt,
    phase: timerState.phase,
    ...data
  };

  if (mainWindow && !mainWindow.isDestroyed()) {
    mainWindow.webContents.send('timer-update', payload);
  }

  updateTrayText();
  refreshTrayMenu();
}

function updateTrayText() {
  if (!tray) return;

  if (!timerState.running && !timerState.paused) {
    tray.setToolTip('Lights Out - idle');
    if (trayIcons) tray.setImage(trayIcons.idle);
    return;
  }

  const prefix = timerState.paused ? 'Paused' : 'Running';
  tray.setToolTip(`Lights Out - ${prefix}, ${formatTime(timerState.remainingSeconds)} left`);
  if (trayIcons) {
    const icon = timerState.paused ? trayIcons.paused
      : timerState.phase === 'dim' ? trayIcons.dim
      : trayIcons.running;
    tray.setImage(icon);
  }
}

function clearTimerInterval() {
  if (timerInterval) {
    clearInterval(timerInterval);
    timerInterval = null;
  }
}

function persistActiveTimer() {
  if (!timerState.running && !timerState.paused) {
    settingsStore.setActiveTimer(null);
    return;
  }
  settingsStore.setActiveTimer({
    action: timerState.action,
    dryRun: timerState.dryRun,
    forceShutdown: timerState.forceShutdown,
    muteSystem: timerState.muteSystem,
    gracePeriod: timerState.gracePeriod,
    totalSeconds: timerState.totalSeconds,
    remainingSeconds: timerState.remainingSeconds,
    paused: timerState.paused,
    endsAt: timerState.endsAt,
    savedAt: new Date().toISOString()
  });
}

function getRecoverableTimer() {
  const snapshot = settingsStore.getActiveTimer();
  if (!snapshot || !snapshot.endsAt) return null;
  const remainingMs = new Date(snapshot.endsAt).getTime() - Date.now();
  const remainingSeconds = snapshot.paused
    ? Math.max(0, Math.round(snapshot.remainingSeconds || 0))
    : Math.max(0, Math.round(remainingMs / 1000));
  if (remainingSeconds <= 0) {
    settingsStore.setActiveTimer(null);
    return null;
  }
  return { ...snapshot, remainingSeconds };
}

function normalizeTimerOptions(input, legacyAction) {
  if (typeof input === 'number') {
    return {
      durationSeconds: Math.max(1, Math.round(input * 60)),
      action: legacyAction || 'shutdown'
    };
  }

  const options = input || {};
  const durationSeconds = Number(options.durationSeconds)
    || (Number(options.minutes) * 60)
    || (Number(options.seconds))
    || 60;

  return {
    durationSeconds: Math.max(1, Math.round(durationSeconds)),
    action: options.action || legacyAction || 'shutdown',
    dryRun: Boolean(options.dryRun),
    forceShutdown: Boolean(options.forceShutdown),
    muteSystem: Boolean(options.muteSystem),
    gracePeriod: Number.isFinite(Number(options.gracePeriod)) ? Math.max(0, Number(options.gracePeriod)) : 2
  };
}

function startTimer(input, legacyAction) {
  const options = normalizeTimerOptions(input, legacyAction);
  clearTimerInterval();

  timerState.running = true;
  timerState.paused = false;
  timerState.totalSeconds = options.durationSeconds;
  timerState.remainingSeconds = options.durationSeconds;
  timerState.action = options.action;
  timerState.dryRun = options.dryRun;
  timerState.forceShutdown = options.forceShutdown;
  timerState.muteSystem = options.muteSystem;
  timerState.gracePeriod = options.gracePeriod;
  timerState.endsAt = new Date(Date.now() + options.durationSeconds * 1000).toISOString();
  timerState.phase = 'focus';

  emitTimerUpdate('started');
  // Create a run receipt for this timer session.
  const receipt = runReceipts.createRunReceipt(timerState);
  activeReceiptId = receipt.id;
  // Send screen time reality check to renderer.
  screenTime.getScreenTimeToday().then(st => {
    const msg = screenTime.getRealityCheckMessage(st);
    if (msg && mainWindow && !mainWindow.isDestroyed()) {
      mainWindow.webContents.send('reality-check', { message: msg, screenTime: st });
    }
  }).catch(() => {});
  // Accountability: notify partner that wind-down started.
  sendAccountability('TIMER_STARTED');
  persistActiveTimer();
  setTaskbarProgress(100, 'normal');

  timerInterval = setInterval(() => {
    if (!timerState.running || timerState.paused) return;

    timerState.remainingSeconds = Math.max(0, timerState.remainingSeconds - 1);
    const percent = timerState.totalSeconds > 0
      ? (timerState.remainingSeconds / timerState.totalSeconds) * 100
      : 0;

    // Phase transition detection
    const prevPhase = timerState.phase;
    timerState.phase = computePhase(timerState.remainingSeconds, timerState.totalSeconds, timerState.gracePeriod);
    if (timerState.phase !== prevPhase) {
      emitTimerUpdate('phase', { phase: timerState.phase, from: prevPhase, percent });
      if (timerState.phase === 'dim') applyDimPhase(timerState.remainingSeconds, timerState.totalSeconds);
      updateTrayText();
    }

    // During dim phase, progressively reduce window opacity for a visual wind-down.
    if (timerState.phase === 'dim' && mainWindow && !mainWindow.isDestroyed()) {
      const dimFraction = timerState.remainingSeconds / (timerState.totalSeconds * 0.25);
      const opacity = 0.55 + 0.45 * Math.max(0, Math.min(1, dimFraction));
      mainWindow.setOpacity(opacity);
    }

    // Smart Lights integration
    if (smartLights.shouldStartDim(timerState.remainingSeconds)) {
      smartLights.startSmartLightDim(timerState.remainingSeconds);
    }
    if (smartLights.getConfig().enabled) {
      smartLights.updateSmartLightTick(timerState.remainingSeconds);
    }

    emitTimerUpdate('tick', { percent, phase: timerState.phase });
    updateWidget();
    setTaskbarProgress(percent, percent <= 10 ? 'error' : 'normal');

    if (timerState.gracePeriod > 0 && timerState.remainingSeconds === timerState.gracePeriod * 60) {
      emitTimerUpdate('warning', {
        message: `${formatAction(timerState.action)} in ${timerState.gracePeriod} minutes`
      });
      // Record warning in receipt.
      if (activeReceiptId) runReceipts.receiptWarning(activeReceiptId);
      // Fire-and-forget browser awareness check.
      getOpenBrowsers().then(browsers => {
        if (browsers.length > 0 && mainWindow && !mainWindow.isDestroyed()) {
          const names = browsers.map(b => `${b.name} (${b.windowCount})`).join(', ');
          mainWindow.webContents.send('browser-warning', { browsers, message: `Open browsers detected: ${names}. Save your work!` });
        }
      }).catch(() => {});
    }

    if (timerState.remainingSeconds <= 0) {
      completeTimer();
    }
  }, 1000);

  return { success: true, state: { ...timerState } };
}

function pauseTimer() {
  if (!timerState.running || timerState.paused) return { success: false };
  timerState.paused = true;
  if (activeReceiptId) runReceipts.receiptPaused(activeReceiptId);
  emitTimerUpdate('paused');
  persistActiveTimer();
  setTaskbarProgress(
    timerState.totalSeconds > 0 ? (timerState.remainingSeconds / timerState.totalSeconds) * 100 : 0,
    'paused'
  );
  return { success: true, state: { ...timerState } };
}

function resumeTimer() {
  if (!timerState.running || !timerState.paused) return { success: false };
  timerState.paused = false;
  timerState.endsAt = new Date(Date.now() + timerState.remainingSeconds * 1000).toISOString();
  if (activeReceiptId) runReceipts.updateRunReceipt(activeReceiptId, { notes: 'Resumed' });
  emitTimerUpdate('resumed');
  persistActiveTimer();
  return { success: true, state: { ...timerState } };
}

function snoozeTimer(seconds = 300) {
  if (!timerState.running && !timerState.paused) return { success: false };
  const addSeconds = Math.max(1, Math.round(Number(seconds) || 300));
  timerState.totalSeconds += addSeconds;
  timerState.remainingSeconds += addSeconds;
  timerState.endsAt = new Date(Date.now() + timerState.remainingSeconds * 1000).toISOString();
  emitTimerUpdate('snoozed', { addedSeconds: addSeconds });
  if (activeReceiptId) runReceipts.receiptSnoozed(activeReceiptId);
  sendAccountability('TIMER_SNOOZED', { addedSeconds: addSeconds });
  return { success: true, state: { ...timerState } };
}

function cancelTimer() {
  clearTimerInterval();
  timerState.running = false;
  timerState.paused = false;
  timerState.remainingSeconds = 0;
  timerState.endsAt = null;
  timerState.phase = 'idle';
  setTaskbarProgress(0, 'none');
  smartLights.resetSmartLightState();
  persistActiveTimer();
  restoreAfterTimer();
  emitTimerUpdate('cancelled');
  // Update receipt: cancelled.
  if (activeReceiptId) {
    runReceipts.updateRunReceipt(activeReceiptId, {
      endedAt: new Date().toISOString(),
      remainingSeconds: timerState.remainingSeconds,
      result: 'cancelled'
    });
    activeReceiptId = null;
  }
  sendAccountability('TIMER_CANCELLED');
  return { success: true };
}

async function completeTimer() {
  clearTimerInterval();
  timerState.running = false;
  timerState.paused = false;
  timerState.remainingSeconds = 0;
  timerState.endsAt = null;
  timerState.phase = 'idle';
  setTaskbarProgress(0, 'none');
  persistActiveTimer();
  restoreAfterTimer();
  
  // Turn off smart lights at timer completion
  if (smartLights.getConfig().enabled) {
    await smartLights.invokeSmartLightOff();
    smartLights.resetSmartLightState();
  }
  
  emitTimerUpdate('complete', { message: 'Timer complete' });
  showNativeNotification('Lights Out', timerState.dryRun
    ? `Dry run complete: ${formatAction(timerState.action)} skipped.`
    : `Timer complete: ${formatAction(timerState.action)} now.`);

  // Record a streak event for the completed ritual.
  try { streaks.recordEvent(null, timerState.action, false); } catch {}
  // Update receipt: completing.
  if (activeReceiptId) {
    runReceipts.updateRunReceipt(activeReceiptId, {
      endedAt: new Date().toISOString(),
      remainingSeconds: 0,
      result: timerState.dryRun ? 'dry_run_completed' : 'completing',
      lastLightSequence: settingsStore.getSection('lastLight')?.sequence || null
    });
  }
  sendAccountability('TIMER_COMPLETE');
  // Record sleep debt for tonight.
  try {
    const appSettings = settingsStore.getSection('app') || {};
    const bedTime = new Date().toTimeString().slice(0, 5);
    const estimated = sleepDebt.estimateSleepHours(bedTime, appSettings.wakeTime || '07:00');
    sleepDebt.recordNight(bedTime, appSettings.wakeTime || '07:00', estimated);
  } catch {}

  // Unsaved work guardian: check for unsaved work before power action.
  if (!timerState.dryRun) {
    try {
      const unsaved = await unsavedGuard.scanUnsavedWork();
      if (unsaved.length > 0) {
        const titles = unsaved.map(w => `"${w.title}" (${w.process})`).join(', ');
        showNativeNotification('Lights Out', `Unsaved work detected: ${titles}. Save before shutdown!`);
        if (mainWindow && !mainWindow.isDestroyed()) {
          mainWindow.webContents.send('unsaved-work-warning', { warnings: unsaved });
        }
        // Delay the power action by 10 seconds to give the user time to save.
        await new Promise(resolve => setTimeout(resolve, 10000));
      }
    } catch { /* best-effort */ }
  }

  await playLastLightRitual(timerState.dryRun);
  await executePowerAction({ ...timerState });
}

// Plays the Last Light finale in the renderer before the power action fires.
// Only delays when enabled and the window is visible, so a hidden/idle app
// never holds up the shutdown.
function playLastLightRitual(dryRun) {
  const cfg = settingsStore.getSection('lastLight') || {};
  if (!cfg.enabled) return Promise.resolve();
  if (!mainWindow || mainWindow.isDestroyed() || !mainWindow.isVisible()) return Promise.resolve();

  const sequence = lastLight.normalizeId(cfg.sequence);
  const durationMs = lastLight.getDurationMs(sequence, Boolean(dryRun));
  mainWindow.webContents.send('play-last-light', { sequence, dryRun: Boolean(dryRun), sound: cfg.sound });
  return new Promise(resolve => setTimeout(resolve, durationMs + 300));
}

// Applies the dim-phase visual wind-down.
// Enables Windows Night Light (blue-light filter) via registry if the
// customization setting is on, and tells the renderer to warm the UI.
function applyDimPhase(remainingSeconds, totalSeconds) {
  const custom = settingsStore.getSection('customization') || {};
  if (custom.warmShift !== false) {
    // Enable Windows Night Light (blue-light filter) during dim phase.
    executePowerShell(
      'Set-ItemProperty -Path "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\CloudStore\\Store\\DefaultAccount\\Current\\default$windows.data.bluelightreduction\\windows.data.bluelightreduction.bluelightreductionstate" -Name "Data" -Value ([byte[]](2,0,0,0) ) -ErrorAction SilentlyContinue'
    ).catch(() => { /* Night Light registry path may not exist on all systems */ });
  }
  // Enable Windows dark mode (system-wide) during wind-down.
  applyNightMode(true);
  // Focus mode: close distracting apps during dim phase.
  applyFocusMode(true);
  // Media auto-pause: pause detected media players during dim phase.
  media.pauseAllDetectedMedia().then(result => {
    if (result.count > 0 && mainWindow && !mainWindow.isDestroyed()) {
      mainWindow.webContents.send('media-paused', { players: result.paused });
    }
  }).catch(() => {});
  // WiFi Guard: block internet for kids during dim phase.
  const wifiConfig = settingsStore.getSection('wifiGuard');
  if (wifiConfig && wifiConfig.enabled && wifiConfig.blockOnDim !== false) {
    wifiGuard.blockInternet(wifiConfig).then(result => {
      if (result.success && mainWindow && !mainWindow.isDestroyed()) {
        mainWindow.webContents.send('wifi-guard-status', { blocked: true, provider: result.provider });
      }
    }).catch(() => {});
  }
  // Content Blocker: block distracting websites during dim phase.
  const cbConfig = settingsStore.getSection('contentBlocker');
  if (cbConfig && cbConfig.enabled && cbConfig.blockOnDim !== false) {
    const sites = (cbConfig.useDefault !== false) ? contentBlocker.DEFAULT_BLOCKLIST : (cbConfig.blocklist || []);
    contentBlocker.blockSites(sites).then(result => {
      if (result.success && mainWindow && !mainWindow.isDestroyed()) {
        mainWindow.webContents.send('content-blocked', { sites: result.sites, blocked: true });
      }
    }).catch(() => {});
  }
  // Progressive screen lockout: make window always-on-top and hide menu during dim.
  if (mainWindow && !mainWindow.isDestroyed()) {
    mainWindow.setAlwaysOnTop(true, 'floating');
    mainWindow.setMenuBarVisibility(false);
  }
  if (mainWindow && !mainWindow.isDestroyed()) {
    mainWindow.webContents.send('dim-phase-started', { remainingSeconds, totalSeconds });
  }
}

// Focus mode: close configurable distracting apps during wind-down.
function applyFocusMode(enable) {
  const appSettings = settingsStore.getSection('app') || {};
  const blocklist = appSettings.focusBlocklist || [];
  if (!blocklist.length) return;

  if (enable) {
    // Gracefully close each blocked app.
    const cmd = blocklist.map(proc =>
      `Get-Process -Name '${proc}' -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -ne '' } | ForEach-Object { $_.CloseMainWindow() | Out-Null }`
    ).join('; ');
    executePowerShell(cmd).catch(() => {});
  }
  // On disable, we don't restart the apps (the user will reopen what they need).
}

function applyNightMode(enable) {
  const val = enable ? 0 : 1; // 0 = dark, 1 = light (AppsUseLightTheme)
  const cmds = [
    // System apps theme
    `Set-ItemProperty -Path 'HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize' -Name 'AppsUseLightTheme' -Value ${val} -Type DWord -ErrorAction SilentlyContinue`,
    // System theme
    `Set-ItemProperty -Path 'HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize' -Name 'SystemUsesLightTheme' -Value ${val} -Type DWord -ErrorAction SilentlyContinue`
  ];
  for (const cmd of cmds) {
    executePowerShell(cmd).catch(() => {});
  }
}

function restoreAfterTimer() {
  // Restore window opacity.
  if (mainWindow && !mainWindow.isDestroyed()) mainWindow.setOpacity(1);
  // Tell renderer to end dim phase.
  if (mainWindow && !mainWindow.isDestroyed()) mainWindow.webContents.send('dim-phase-ended');
  // Restore Windows light theme.
  applyNightMode(false);
  // Disable Windows Night Light (restore original state).
  executePowerShell(
    'Remove-ItemProperty -Path "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\CloudStore\\Store\\DefaultAccount\\Current\\default$windows.data.bluelightreduction\\windows.data.bluelightreduction.bluelightreductionstate" -Name "Data" -ErrorAction SilentlyContinue'
  ).catch(() => {});
  // Resume media that was auto-paused during dim phase.
  media.resumeAllMedia().catch(() => {});
  // Restore WiFi access if WiFi Guard was active.
  const wifiConfig = settingsStore.getSection('wifiGuard');
  if (wifiConfig && wifiConfig.enabled && wifiConfig.unblockOnCancel !== false) {
    wifiGuard.unblockInternet(wifiConfig).then(result => {
      if (result.success && mainWindow && !mainWindow.isDestroyed()) {
        mainWindow.webContents.send('wifi-guard-status', { blocked: false, provider: result.provider });
      }
    }).catch(() => {});
  }
  // Unblock distracting websites.
  const cbConfig = settingsStore.getSection('contentBlocker');
  if (cbConfig && cbConfig.enabled && cbConfig.unblockOnComplete !== false) {
    contentBlocker.unblockSites().catch(() => {});
  }
  // Undo progressive lockout: restore normal window behavior.
  if (mainWindow && !mainWindow.isDestroyed()) {
    mainWindow.setAlwaysOnTop(false);
    mainWindow.setMenuBarVisibility(true);
  }
}

// First Light: the morning bookend to Last Light.
// Gradually increases window opacity from 0 to 1 over FIRST_LIGHT_DURATION
// seconds, simulating a sunrise. Called when the app launches via the
// --first-light scheduled task.
const FIRST_LIGHT_DURATION = 60; // 60 seconds of gradual brightening

function playFirstLight() {
  if (!mainWindow || mainWindow.isDestroyed()) return;
  mainWindow.show();
  mainWindow.setOpacity(0);
  mainWindow.webContents.send('first-light-started');

  // Smart Light Sunrise: gradually brighten room lights during First Light.
  const slConfig = smartLights.getConfig();
  if (slConfig.enabled) {
    let slElapsed = 0;
    const slInterval = setInterval(() => {
      slElapsed++;
      const brightness = Math.min(100, Math.round((slElapsed / FIRST_LIGHT_DURATION) * 100));
      smartLights.invokeSmartLightAction({ on: true, brightness, colorTemp: 400 - Math.round(brightness * 1.5) }).catch(() => {});
      if (slElapsed >= FIRST_LIGHT_DURATION) clearInterval(slInterval);
    }, 5000); // update every 5s to avoid API spam
  }

  // Morning Routine: send briefing data to renderer.
  setTimeout(async () => {
    try {
      const calSettings = settingsStore.getSection('calendar') || {};
      const events = await calProviders.fetchEvents(calSettings, 1);
      if (mainWindow && !mainWindow.isDestroyed()) {
        mainWindow.webContents.send('morning-briefing', {
          events: (events || []).slice(0, 5),
          sleepDebt: sleepDebt.getDebtSummary(),
          streaks: streaks.getSummary()
        });
      }
    } catch {}
  }, 5000);

  let elapsed = 0;
  const interval = setInterval(() => {
    elapsed++;
    const progress = Math.min(1, elapsed / FIRST_LIGHT_DURATION);
    if (mainWindow && !mainWindow.isDestroyed()) {
      mainWindow.setOpacity(progress);
      mainWindow.webContents.send('first-light-tick', { progress, elapsed });
    }
    if (elapsed >= FIRST_LIGHT_DURATION) {
      clearInterval(interval);
      if (mainWindow && !mainWindow.isDestroyed()) {
        mainWindow.setOpacity(1);
        mainWindow.webContents.send('first-light-ended');
      }
      // Clean up the scheduled task after it fires.
      alarm.removeWakeAlarm().catch(() => {});
    }
  }, 1000);
}

function formatAction(action) {
  const labels = {
    shutdown: 'Shutdown',
    restart: 'Restart',
    sleep: 'Sleep',
    hibernate: 'Hibernate',
    logout: 'Log out'
  };
  return labels[action] || 'Power action';
}

// ─────────────────────────────────────────────────────────────────────────────
// Accountability Partner: notify on timer events
// ─────────────────────────────────────────────────────────────────────────────

function sendAccountability(eventType, extra = {}) {
  const accConfig = settingsStore.getSection('accountability');
  if (!accConfig || !accConfig.enabled) return;
  // Only send for events the user has enabled.
  const eventMap = {
    'TIMER_STARTED': accConfig.notifyOnStart,
    'TIMER_SNOOZED': accConfig.notifyOnSnooze,
    'TIMER_CANCELLED': accConfig.notifyOnCancel,
    'TIMER_COMPLETE': accConfig.notifyOnComplete
  };
  if (eventMap[eventType] === false) return;
  const appSettings = settingsStore.getSection('app') || {};
  accountability.notifyPartner(eventType, {
    config: accConfig,
    timerName: appSettings.timerName || 'Witching Hour',
    remainingSeconds: timerState.remainingSeconds,
    phase: timerState.phase,
    ...extra
  }).catch(() => {}); // best-effort, never block
}

// ─────────────────────────────────────────────────────────────────────────────
// Calendar Auto-Start: zero-friction timer from calendar events.
// ─────────────────────────────────────────────────────────────────────────────

async function checkCalendarAutoStart() {
  const calSettings = settingsStore.getSection('calendar') || {};
  if (!calSettings.enabled || !calSettings.autoStartFromEvents) return;
  if (timerState.running) return; // already running

  try {
    const events = await calProviders.fetchEvents(calSettings, 1); // within 1 day
    if (!events || !events.length) return;

    const now = new Date();
    for (const event of events) {
      const start = new Date(event.start);
      const diffMin = (start - now) / 60000;
      // If event starts within the next 2 minutes, auto-start.
      if (diffMin >= -1 && diffMin <= 2) {
        const duration = Math.max(300, Math.round((new Date(event.end) - now) / 1000));
        const action = event.action || calSettings.builtin?.action || 'shutdown';
        startTimer({ durationSeconds: duration, action });
        showNativeNotification('Lights Out', `Auto-started from calendar: ${event.title || 'Bedtime'}`);
        break;
      }
    }
  } catch { /* best effort */ }
}

// ─────────────────────────────────────────────────────────────────────────────
// Companion PWA message handling
// ─────────────────────────────────────────────────────────────────────────────

function handleCompanionMessage(msg, client) {
  if (!msg || !msg.action) return;
  switch (msg.action) {
    case 'start':
      startTimer({
        durationSeconds: msg.durationSeconds || 1800,
        action: msg.timerAction || 'shutdown'
      });
      break;
    case 'togglePause':
      if (timerState.paused) resumeTimer();
      else if (timerState.running) pauseTimer();
      break;
    case 'snooze':
      snoozeTimer(msg.seconds || 300);
      break;
    case 'cancel':
      cancelTimer();
      break;
  }
  // Immediately broadcast updated state after action.
  setTimeout(broadcastCompanionState, 300);
}

function broadcastCompanionState() {
  const appSettings = settingsStore.getSection('app') || {};
  companion.broadcast({
    type: 'state',
    running: timerState.running,
    paused: timerState.paused,
    remainingSeconds: timerState.remainingSeconds,
    totalSeconds: timerState.totalSeconds,
    action: timerState.action,
    phase: timerState.phase,
    timerName: appSettings.timerName || 'Witching Hour',
    dryRun: timerState.dryRun
  });
}

function formatTime(totalSeconds) {
  const seconds = Math.max(0, Math.round(totalSeconds));
  const hours = Math.floor(seconds / 3600);
  const minutes = Math.floor((seconds % 3600) / 60);
  const secs = seconds % 60;
  if (hours > 0) return `${hours}:${String(minutes).padStart(2, '0')}:${String(secs).padStart(2, '0')}`;
  return `${minutes}:${String(secs).padStart(2, '0')}`;
}

async function executePowerShell(command) {
  return new Promise((resolve, reject) => {
    const ps = spawn('powershell.exe', [
      '-NoProfile',
      '-ExecutionPolicy', 'Bypass',
      '-Command', command
    ], { stdio: ['ignore', 'pipe', 'pipe'] });

    let output = '';
    let error = '';
    ps.stdout.on('data', data => {
      output += data.toString();
    });
    ps.stderr.on('data', data => {
      error += data.toString();
    });
    ps.on('error', reject);
    ps.on('close', code => {
      if (code === 0) resolve(output.trim());
      else reject(new Error(error.trim() || `PowerShell exited with code ${code}`));
    });
  });
}

// Detect running browsers that may have unsaved work.
// Returns an array of { name, windowCount } for each detected browser.
async function getOpenBrowsers() {
  const browsers = [
    { process: 'chrome', name: 'Chrome' },
    { process: 'msedge', name: 'Edge' },
    { process: 'firefox', name: 'Firefox' },
    { process: 'brave', name: 'Brave' },
    { process: 'opera', name: 'Opera' },
    { process: 'vivaldi', name: 'Vivaldi' }
  ];
  const results = [];
  const cmd = browsers.map(b =>
    `$p = Get-Process -Name '${b.process}' -ErrorAction SilentlyContinue; if ($p) { '${b.name}:' + $p.Count }`
  ).join('; ');
  try {
    const raw = await executePowerShell(cmd);
    if (!raw) return [];
    for (const part of raw.split(';').map(s => s.trim()).filter(Boolean)) {
      const [name, count] = part.split(':');
      if (name && count && parseInt(count) > 0) {
        results.push({ name, windowCount: parseInt(count) });
      }
    }
  } catch { /* best-effort */ }
  return results;
}

async function executePowerAction(options = {}) {
  const action = options.action || 'shutdown';
  const dryRun = Boolean(options.dryRun);
  const forceShutdown = Boolean(options.forceShutdown);
  const muteSystem = Boolean(options.muteSystem);

  if (dryRun) {
    emitTimerUpdate('dryrun', { action, message: `Dry run: ${formatAction(action)} skipped` });
    // Update receipt: dry run completed.
    if (activeReceiptId) {
      runReceipts.updateRunReceipt(activeReceiptId, {
        result: 'dry_run_completed',
        endedAt: new Date().toISOString(),
        notes: 'Dry run - no power action executed'
      });
      activeReceiptId = null;
    }
    return { success: true, dryRun: true };
  }

  try {
    if (muteSystem) {
      await executePowerShell('(New-Object -ComObject WScript.Shell).SendKeys([char]173)');
    }

    switch (action) {
      case 'shutdown':
        spawn('shutdown.exe', forceShutdown ? ['/s', '/f', '/t', '0'] : ['/s', '/t', '0'], { detached: true, stdio: 'ignore' }).unref();
        break;
      case 'restart':
        spawn('shutdown.exe', forceShutdown ? ['/r', '/f', '/t', '0'] : ['/r', '/t', '0'], { detached: true, stdio: 'ignore' }).unref();
        break;
      case 'sleep':
        spawn('rundll32.exe', ['powrprof.dll,SetSuspendState', '0,1,0'], { detached: true, stdio: 'ignore' }).unref();
        break;
      case 'hibernate':
        spawn('rundll32.exe', ['powrprof.dll,SetSuspendState', '1,1,0'], { detached: true, stdio: 'ignore' }).unref();
        break;
      case 'logout':
        spawn('shutdown.exe', ['/l'], { detached: true, stdio: 'ignore' }).unref();
        break;
      default:
        return { success: false, error: `Unknown action: ${action}` };
    }

    // Update receipt: power executed.
    if (activeReceiptId) {
      runReceipts.updateRunReceipt(activeReceiptId, {
        result: 'power_executed',
        powerCommand: action + (forceShutdown ? ' /f' : ''),
        endedAt: new Date().toISOString()
      });
      activeReceiptId = null;
    }
    return { success: true };
  } catch (error) {
    emitTimerUpdate('error', { message: error.message });
    // Update receipt: blocked/error.
    if (activeReceiptId) {
      runReceipts.updateRunReceipt(activeReceiptId, {
        result: 'error',
        notes: error.message,
        endedAt: new Date().toISOString()
      });
      activeReceiptId = null;
    }
    return { success: false, error: error.message };
  }
}

function getLoginSettings() {
  const loginSettings = app.getLoginItemSettings();
  return {
    runAtLogin: Boolean(loginSettings.openAtLogin),
    startupBehavior: 'Starts minimized and idle'
  };
}

function setRunAtLogin(enabled) {
  app.setLoginItemSettings({
    openAtLogin: Boolean(enabled),
    openAsHidden: false,
    args: ['--minimized', '--no-auto-start']
  });
  return getLoginSettings();
}

ipcMain.handle('start-timer', async (event, options, legacyAction) => startTimer(options, legacyAction));
ipcMain.handle('cancel-timer', async () => cancelTimer());
ipcMain.handle('pause-timer', async () => pauseTimer());
ipcMain.handle('resume-timer', async () => resumeTimer());
ipcMain.handle('snooze-timer', async (event, seconds) => snoozeTimer(seconds));
ipcMain.handle('execute-action', async (event, action, options = {}) => executePowerAction({ ...options, action }));

let systemInfoCache = null;
let systemInfoCachedAt = 0;
const SYSTEM_INFO_TTL_MS = 15000;

ipcMain.handle('get-system-info', async () => {
  if (systemInfoCache && Date.now() - systemInfoCachedAt < SYSTEM_INFO_TTL_MS) {
    return systemInfoCache;
  }
  try {
    const battery = await executePowerShell('(Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue).EstimatedChargeRemaining');
    const powerPlan = await executePowerShell('(Get-CimInstance -Namespace "root\\cimv2\\power" -ClassName Win32_PowerPlan | Where-Object { $_.IsActive }).ElementName');
    systemInfoCache = { battery: battery || 'N/A', powerPlan: powerPlan || 'Unknown' };
    systemInfoCachedAt = Date.now();
    return systemInfoCache;
  } catch {
    return { battery: 'N/A', powerPlan: 'Unknown' };
  }
});

ipcMain.on('set-window-opacity', (event, value) => {
  if (!mainWindow || mainWindow.isDestroyed()) return;
  const v = Math.max(0.5, Math.min(1, Number(value) || 1));
  mainWindow.setOpacity(v);
});

ipcMain.handle('get-app-settings', async () => ({
  ...getLoginSettings(),
  app: settingsStore.getSection('app'),
  customization: settingsStore.getSection('customization'),
  lastLight: settingsStore.getSection('lastLight'),
  calendar: settingsStore.getSection('calendar'),
  recoverableTimer: getRecoverableTimer()
}));
ipcMain.handle('save-app-settings', async (event, settings = {}) => {
  if (typeof settings.runAtLogin === 'boolean') setRunAtLogin(settings.runAtLogin);
  if (settings.app) settingsStore.updateSection('app', settings.app);
  if (settings.customization) settingsStore.updateSection('customization', settings.customization);
  if (settings.lastLight) settingsStore.updateSection('lastLight', settings.lastLight);
  if (settings.calendar) settingsStore.updateSection('calendar', settings.calendar);
  return {
    ...getLoginSettings(),
    app: settingsStore.getSection('app'),
    customization: settingsStore.getSection('customization'),
    lastLight: settingsStore.getSection('lastLight'),
    calendar: settingsStore.getSection('calendar')
  };
});
ipcMain.handle('discard-recoverable-timer', async () => {
  settingsStore.setActiveTimer(null);
  return { success: true };
});
ipcMain.handle('get-streaks', async () => {
  try { return streaks.getSummary(); } catch { return { streak: 0, bestStreak: 0, totalNights: 0, achievements: [], weekAvg: '--:--', weekOnTime: 0, weekDays: [] }; }
});
ipcMain.handle('get-achievements-catalog', async () => {
  try { return streaks.getAchievementCatalog(); } catch { return []; }
});
ipcMain.handle('get-weekly-report', async () => {
  try { return streaks.getWeeklyReport(); } catch { return null; }
});
ipcMain.handle('get-sleep-score', async () => {
  try { return streaks.getSleepScore(); } catch { return { score: null, label: 'Error', breakdown: {} }; }
});
ipcMain.handle('add-custom-sequence', async (event, seq) => {
  const entry = lastLight.addCustomSequence(seq);
  if (entry) {
    const ll = settingsStore.getSection('lastLight') || {};
    ll.customSequences = lastLight.getCustomSequences();
    settingsStore.updateSection('lastLight', ll);
  }
  return entry;
});
ipcMain.handle('remove-custom-sequence', async (event, id) => {
  lastLight.removeCustomSequence(id);
  const ll = settingsStore.getSection('lastLight') || {};
  ll.customSequences = lastLight.getCustomSequences();
  settingsStore.updateSection('lastLight', ll);
  return { success: true };
});
ipcMain.handle('get-open-browsers', async () => {
  try { return await getOpenBrowsers(); } catch { return []; }
});

// Wake-up alarm IPC
ipcMain.handle('schedule-wake-alarm', async (event, alarmTime) => {
  const appExePath = process.execPath;
  return alarm.scheduleWakeAlarm(alarmTime, appExePath);
});
ipcMain.handle('remove-wake-alarm', async () => {
  return alarm.removeWakeAlarm();
});
ipcMain.handle('get-wake-alarm-status', async () => {
  return alarm.getWakeAlarmStatus();
});

// Auto-update checker
ipcMain.handle('check-for-update', async () => {
  return updater.checkForUpdate();
});
ipcMain.handle('get-update-status', async () => {
  return updater.getLastCheckResult();
});

// Data export/import
ipcMain.handle('export-all-data', async () => {
  try {
    const data = {
      version: updater.currentVersion,
      exportedAt: new Date().toISOString(),
      settings: settingsStore.getAll(),
      streaks: streaks.getSummary(),
      profiles: profiles.getAllProfiles()
    };
    return { success: true, data };
  } catch (err) {
    return { success: false, error: err.message };
  }
});
ipcMain.handle('import-all-data', async (event, jsonData) => {
  try {
    const parsed = typeof jsonData === 'string' ? JSON.parse(jsonData) : jsonData;
    if (!parsed || typeof parsed !== 'object') return { success: false, error: 'Invalid data format' };
    if (parsed.settings) {
      for (const [section, value] of Object.entries(parsed.settings)) {
        if (value && typeof value === 'object') settingsStore.updateSection(section, value);
      }
    }
    if (parsed.profiles && Array.isArray(parsed.profiles)) {
      for (const p of parsed.profiles) {
        if (p.name) profiles.create(p);
      }
    }
    return { success: true };
  } catch (err) {
    return { success: false, error: err.message };
  }
});

// Calendar providers
ipcMain.handle('get-calendar-providers', async () => {
  return calProviders.getProviders();
});
ipcMain.handle('fetch-calendar-events', async (event, withinDays) => {
  try {
    const calConfig = settingsStore.getSection('calendar') || {};
    const events = await calProviders.fetchAllEvents(calConfig, new Date(), withinDays || 14);
    return events.map(e => ({
      uid: e.uid,
      summary: e.summary,
      start: e.start.toISOString(),
      end: e.end?.toISOString() || null,
      location: e.location || '',
      source: e.source,
      action: e.action || 'shutdown'
    }));
  } catch (err) {
    return [];
  }
});
ipcMain.handle('save-calendar-settings', async (event, calSettings) => {
  settingsStore.updateSection('calendar', calSettings);
  return { success: true };
});
ipcMain.handle('get-calendar-settings', async () => {
  return settingsStore.getSection('calendar');
});
ipcMain.handle('get-companion-status', async () => {
  return companion.getStatus();
});
ipcMain.handle('get-family-peers', async () => {
  return family.getPeers();
});
ipcMain.handle('family-remote-start', async (e, ip, durationSeconds, action) => {
  return family.remoteStart(ip, durationSeconds, action);
});
ipcMain.handle('family-remote-pause', async (e, ip) => {
  return family.remotePause(ip);
});
ipcMain.handle('family-remote-resume', async (e, ip) => {
  return family.remoteResume(ip);
});
ipcMain.handle('family-remote-cancel', async (e, ip) => {
  return family.remoteCancel(ip);
});
ipcMain.handle('family-remote-snooze', async (e, ip, seconds) => {
  return family.remoteSnooze(ip, seconds || 300);
});
ipcMain.handle('get-media-sessions', async () => {
  try { return await media.detectMediaSessions(); } catch { return []; }
});
ipcMain.handle('wifi-guard-scan', async () => {
  try { return await wifiGuard.scanDevices(); } catch { return []; }
});
ipcMain.handle('wifi-guard-block', async () => {
  const config = settingsStore.getSection('wifiGuard');
  if (!config || !config.enabled) return { success: false, error: 'WiFi Guard not enabled' };
  return wifiGuard.blockInternet(config);
});
ipcMain.handle('wifi-guard-unblock', async () => {
  const config = settingsStore.getSection('wifiGuard');
  if (!config) return { success: false };
  return wifiGuard.unblockInternet(config);
});
ipcMain.handle('save-wifi-guard-settings', async (e, wifiSettings) => {
  settingsStore.setSection('wifiGuard', wifiSettings);
  return { saved: true };
});
ipcMain.handle('get-wifi-guard-settings', async () => {
  return settingsStore.getSection('wifiGuard');
});
ipcMain.handle('content-block', async (e, blocklist) => {
  return contentBlocker.blockSites(blocklist);
});
ipcMain.handle('content-unblock', async () => {
  return contentBlocker.unblockSites();
});
ipcMain.handle('content-block-status', async () => {
  return { blocked: contentBlocker.isBlocked(), sites: contentBlocker.getActiveBlocklist() };
});
ipcMain.handle('save-content-blocker-settings', async (e, s) => {
  settingsStore.setSection('contentBlocker', s);
  return { saved: true };
});
ipcMain.handle('get-content-blocker-settings', async () => {
  return settingsStore.getSection('contentBlocker');
});
ipcMain.handle('save-accountability-settings', async (e, s) => {
  settingsStore.setSection('accountability', s);
  return { saved: true };
});
ipcMain.handle('get-accountability-settings', async () => {
  return settingsStore.getSection('accountability');
});
ipcMain.handle('test-accountability-partner', async (e, partner) => {
  return accountability.testPartner(partner);
});

// Focus Sessions IPC.
ipcMain.handle('focus-start', async (e, preset, customConfig) => {
  return focusSessions.startFocusSession(preset, customConfig);
});
ipcMain.handle('focus-pause', async () => {
  return focusSessions.pauseFocusSession();
});
ipcMain.handle('focus-resume', async () => {
  return focusSessions.resumeFocusSession();
});
ipcMain.handle('focus-stop', async () => {
  return focusSessions.stopFocusSession();
});
ipcMain.handle('focus-state', async () => {
  return focusSessions.getFocusState();
});

// Screen Time IPC.
ipcMain.handle('get-screen-time', async () => {
  try { return await screenTime.getScreenTimeToday(); } catch { return null; }
});
ipcMain.handle('get-reality-check', async () => {
  try {
    const st = await screenTime.getScreenTimeToday();
    return screenTime.getRealityCheckMessage(st);
  } catch { return null; }
});

// Sleep Debt IPC.
ipcMain.handle('get-sleep-debt', async () => {
  try { return sleepDebt.getDebtSummary(); } catch { return null; }
});
ipcMain.handle('set-sleep-target', async (e, hours) => {
  return sleepDebt.setTargetHours(hours);
});
ipcMain.handle('set-wake-time', async (e, time) => {
  return sleepDebt.setWakeTime(time);
});

// Emergency Override IPC.
ipcMain.handle('get-override-consequences', async () => {
  return emergencyOverride.getOverrideConsequences(timerState);
});
ipcMain.handle('execute-override', async (e, reason) => {
  return emergencyOverride.executeOverride(reason, timerState);
});

// Run Receipts IPC.
ipcMain.handle('get-latest-receipt', async () => {
  return runReceipts.getLatestReceipt();
});
ipcMain.handle('list-receipts', async (e, limit) => {
  return runReceipts.listReceipts(limit || 20);
});
ipcMain.handle('clear-receipts', async () => {
  return runReceipts.clearReceipts();
});
ipcMain.handle('get-receipt-stats', async () => {
  return runReceipts.getReceiptStats();
});
ipcMain.handle('get-idle-seconds', async () => {
  try { return await idleDetection.getIdleSeconds(); } catch { return 0; }
});
ipcMain.handle('set-idle-threshold', async (e, sec) => {
  idleDetection.setThreshold(sec);
  return { threshold: idleDetection.getThreshold() };
});
ipcMain.handle('set-bedtime-reminder', async (e, min) => {
  bedtimeReminder.setMinutesBefore(min);
  return { minutesBefore: bedtimeReminder.getMinutesBefore() };
});
ipcMain.handle('set-calendar-auto-start', async (e, enabled) => {
  const cal = settingsStore.getSection('calendar') || {};
  cal.autoStartFromEvents = !!enabled;
  settingsStore.setSection('calendar', cal);
  return { autoStartFromEvents: cal.autoStartFromEvents };
});
ipcMain.handle('resume-recoverable-timer', async () => {
  const snapshot = getRecoverableTimer();
  if (!snapshot) return { success: false };
  const result = startTimer({
    durationSeconds: snapshot.remainingSeconds,
    action: snapshot.action,
    dryRun: snapshot.dryRun,
    forceShutdown: snapshot.forceShutdown,
    muteSystem: snapshot.muteSystem,
    gracePeriod: snapshot.gracePeriod
  });
  return result;
});

// Smart Lights IPC handlers
ipcMain.handle('get-smartlight-config', async () => smartLights.getConfig());
ipcMain.handle('save-smartlight-config', async (event, settings) => {
  smartLights.loadConfig(settings);
  const merged = smartLights.getConfig();
  settingsStore.updateSection('smartLights', merged);
  return merged;
});
ipcMain.handle('test-smartlight-connection', async () => smartLights.testSmartLightConnection());
ipcMain.handle('discover-hue-bridge', async () => smartLights.findHueBridge());
ipcMain.handle('register-hue-bridge', async (event, bridgeIp) => smartLights.registerHueBridge(bridgeIp));
ipcMain.handle('get-hue-lights', async (event, bridgeIp, username) => smartLights.getHueLights(bridgeIp, username));
ipcMain.handle('get-hue-groups', async (event, bridgeIp, username) => smartLights.getHueGroups(bridgeIp, username));

// Profiles IPC handlers
ipcMain.handle('profiles-get-all', async () => profiles.getAll());
ipcMain.handle('profiles-get-by-id', async (event, id) => profiles.getById(id));
ipcMain.handle('profiles-create', async (event, data) => profiles.create(data));
ipcMain.handle('profiles-update', async (event, id, data) => profiles.update(id, data));
ipcMain.handle('profiles-delete', async (event, id) => profiles.delete(id));
ipcMain.handle('profiles-reorder', async (event, orderedIds) => profiles.reorder(orderedIds));
ipcMain.handle('profiles-apply', async (event, id) => profiles.apply(id));
ipcMain.handle('profiles-get-hint', async (event, profile) => profiles.getHint(profile));
ipcMain.handle('profiles-export', async () => profiles.export());
ipcMain.handle('profiles-import', async (event, jsonString) => profiles.import(jsonString));
ipcMain.handle('profiles-create-defaults', async () => profiles.createDefaults());

// Calendar IPC handlers
ipcMain.handle('calendar-parse-text', async (event, text) => {
  try {
    const result = calendar.importIcsFromText(text);
    // Convert Date objects to ISO strings for IPC serialization
    result.events = result.events.map(e => ({
      ...e,
      start: e.start ? e.start.toISOString() : null,
      end: e.end ? e.end.toISOString() : null
    }));
    return { success: true, ...result };
  } catch (error) {
    return { success: false, error: error.message };
  }
});

ipcMain.handle('calendar-import-url', async (event, url) => {
  try {
    const result = await calendar.importIcsFromUrl(url);
    // Convert Date objects to ISO strings for IPC serialization
    result.events = result.events.map(e => ({
      ...e,
      start: e.start ? e.start.toISOString() : null,
      end: e.end ? e.end.toISOString() : null
    }));
    return { success: true, ...result };
  } catch (error) {
    return { success: false, error: error.message };
  }
});

ipcMain.handle('calendar-test-url', async (event, url) => calendar.testCalendarFeedUrl(url));

ipcMain.handle('calendar-get-upcoming', async (event, events, from, withinDays, maxCount) => {
  // Convert ISO strings back to Date objects
  const parsedEvents = events.map(e => ({
    ...e,
    start: e.start ? new Date(e.start) : null,
    end: e.end ? new Date(e.end) : null
  }));
  const fromDate = from ? new Date(from) : new Date();
  const upcoming = calendar.getUpcomingEvents(parsedEvents, fromDate, withinDays, maxCount);
  return upcoming.map(e => ({
    ...e,
    start: e.start ? e.start.toISOString() : null,
    end: e.end ? e.end.toISOString() : null
  }));
});

ipcMain.handle('calendar-create-timer', async (event, evt, action, options) => {
  try {
    // Convert ISO strings back to Date objects
    const eventObj = {
      ...evt,
      start: evt.start ? new Date(evt.start) : null,
      end: evt.end ? new Date(evt.end) : null
    };
    const result = calendar.createTimerFromEvent(eventObj, action, options);
    return result;
  } catch (error) {
    return { success: false, error: error.message };
  }
});

ipcMain.handle('calendar-format-time', async (event, isoString) => calendar.formatEventTime(isoString ? new Date(isoString) : null));

ipcMain.on('minimize-window', () => {
  if (mainWindow) mainWindow.minimize();
});

ipcMain.on('toggle-mini-mode', () => {
  miniMode = !miniMode;
  if (!mainWindow) return;

  if (miniMode) {
    mainWindow.setSize(260, 320);
    mainWindow.setAlwaysOnTop(true, 'floating');
  } else {
    mainWindow.setSize(520, 720);
    mainWindow.setAlwaysOnTop(false);
  }

  mainWindow.webContents.send('mini-mode-changed', miniMode);
});

// Desktop widget: tiny always-on-top "bed in N min" clock.
function createWidgetWindow() {
  if (widgetWindow && !widgetWindow.isDestroyed()) {
    widgetWindow.show();
    return;
  }
  widgetWindow = new BrowserWindow({
    width: 180,
    height: 52,
    frame: false,
    transparent: true,
    alwaysOnTop: true,
    resizable: false,
    skipTaskbar: true,
    hasShadow: false,
    webPreferences: {
      nodeIntegration: false,
      contextIsolation: true,
      preload: path.join(__dirname, 'preload.js')
    }
  });
  widgetWindow.setVisibleOnAllWorkspaces(true);
  widgetWindow.setPosition(20, 20); // top-left corner
  widgetWindow.loadFile('widget.html');
  widgetWindow.on('closed', () => { widgetWindow = null; widgetMode = false; });
  widgetMode = true;
}

function closeWidgetWindow() {
  if (widgetWindow && !widgetWindow.isDestroyed()) widgetWindow.close();
  widgetWindow = null;
  widgetMode = false;
}

function updateWidget() {
  if (!widgetWindow || widgetWindow.isDestroyed()) return;
  const running = timerState.running || timerState.paused;
  const remaining = running ? formatTime(timerState.remainingSeconds) : '';
  const phase = timerState.phase || 'idle';
  widgetWindow.webContents.send('widget-update', {
    running,
    paused: timerState.paused,
    remaining,
    phase,
    action: timerState.action
  });
}

ipcMain.on('toggle-widget', () => {
  if (widgetMode) closeWidgetWindow();
  else createWidgetWindow();
});

ipcMain.on('close-widget', () => {
  closeWidgetWindow();
});

ipcMain.on('show-notification', (event, title, body) => {
  showNativeNotification(title, body);
});

ipcMain.on('play-sound', (event, soundType) => {
  if (mainWindow && !mainWindow.isDestroyed()) {
    mainWindow.webContents.send('play-sound', soundType);
  }
});

ipcMain.on('set-progress', (event, percent, mode) => {
  setTaskbarProgress(percent, mode);
});

ipcMain.on('close-window', () => {
  if (mainWindow) mainWindow.hide();
  refreshTrayMenu();
});

ipcMain.on('quit-app', () => {
  app.isQuitting = true;
  app.quit();
});

ipcMain.on('open-external', (event, url) => {
  if (typeof url === 'string' && /^https?:\/\//.test(url)) {
    shell.openExternal(url);
  }
});

function setupJumpList() {
  if (!app.setUserTasks) return;

  app.setUserTasks([
    {
      program: process.execPath,
      arguments: '--timer=5',
      iconPath: process.execPath,
      iconIndex: 0,
      title: 'Start 5 min timer',
      description: 'Start a 5 minute shutdown timer'
    },
    {
      program: process.execPath,
      arguments: '--timer=15',
      iconPath: process.execPath,
      iconIndex: 0,
      title: 'Start 15 min timer',
      description: 'Start a 15 minute shutdown timer'
    },
    {
      program: process.execPath,
      arguments: '--timer=30',
      iconPath: process.execPath,
      iconIndex: 0,
      title: 'Start 30 min timer',
      description: 'Start a 30 minute shutdown timer'
    }
  ]);
}

function registerGlobalShortcuts() {
  // Ctrl+Shift+L: Quick 15-min timer
  globalShortcut.register('Ctrl+Shift+L', () => {
    if (mainWindow) {
      mainWindow.show();
      mainWindow.focus();
      startTimer({ durationSeconds: 15 * 60, action: 'shutdown' });
      showNativeNotification('Lights Out', '15 minute timer started');
    }
  });

  // Ctrl+Shift+S: Show/hide window
  globalShortcut.register('Ctrl+Shift+S', toggleMainWindow);

  // Ctrl+Shift+P: Preview Last Light
  globalShortcut.register('Ctrl+Shift+P', () => {
    if (mainWindow && !mainWindow.isDestroyed()) {
      mainWindow.show();
      mainWindow.focus();
      const cfg = settingsStore.getSection('lastLight') || {};
      mainWindow.webContents.send('play-last-light', {
        sequence: lastLight.normalizeId(cfg.sequence),
        dryRun: true,
        sound: cfg.sound || 'Off'
      });
    }
  });

  // Ctrl+Shift+Space: Pause/Resume toggle
  globalShortcut.register('Ctrl+Shift+Space', () => {
    if (timerState.paused) {
      resumeTimer();
      showNativeNotification('Lights Out', 'Timer resumed');
    } else if (timerState.running) {
      pauseTimer();
      showNativeNotification('Lights Out', 'Timer paused');
    }
  });

  // Ctrl+Shift+Z: Snooze +5 min
  globalShortcut.register('Ctrl+Shift+Z', () => {
    if (timerState.running || timerState.paused) {
      snoozeTimer(300);
      showNativeNotification('Lights Out', 'Snoozed +5 minutes');
    }
  });

  // Ctrl+Shift+X: Cancel timer
  globalShortcut.register('Ctrl+Shift+X', () => {
    if (timerState.running || timerState.paused) {
      cancelTimer();
      showNativeNotification('Lights Out', 'Timer cancelled');
    }
  });

  // Ctrl+Shift+1: 30-min timer
  globalShortcut.register('Ctrl+Shift+1', () => {
    startTimer({ durationSeconds: 30 * 60, action: 'shutdown' });
    showNativeNotification('Lights Out', '30 minute timer started');
  });

  // Ctrl+Shift+2: 45-min timer
  globalShortcut.register('Ctrl+Shift+2', () => {
    startTimer({ durationSeconds: 45 * 60, action: 'shutdown' });
    showNativeNotification('Lights Out', '45 minute timer started');
  });

  // Ctrl+Shift+3: 60-min timer
  globalShortcut.register('Ctrl+Shift+3', () => {
    startTimer({ durationSeconds: 60 * 60, action: 'shutdown' });
    showNativeNotification('Lights Out', '1 hour timer started');
  });

  // Ctrl+Shift+4: 90-min timer
  globalShortcut.register('Ctrl+Shift+4', () => {
    startTimer({ durationSeconds: 90 * 60, action: 'shutdown' });
    showNativeNotification('Lights Out', '90 minute timer started');
  });

  // Ctrl+Shift+W: Toggle widget
  globalShortcut.register('Ctrl+Shift+W', () => {
    if (widgetMode) closeWidgetWindow();
    else createWidgetWindow();
  });

  // Ctrl+Shift+A: Toggle alarm
  globalShortcut.register('Ctrl+Shift+A', () => {
    if (mainWindow && !mainWindow.isDestroyed()) {
      mainWindow.show();
      mainWindow.focus();
      mainWindow.webContents.send('toggle-alarm-focus');
    }
  });
}

const gotTheLock = app.requestSingleInstanceLock();

if (!gotTheLock) {
  app.quit();
} else {
  app.on('second-instance', () => {
    if (!mainWindow) return;
    if (mainWindow.isMinimized()) mainWindow.restore();
    mainWindow.show();
    mainWindow.focus();
    refreshTrayMenu();
  });
}

app.whenReady().then(async () => {
  // Load persisted settings and rehydrate the smart-lights module.
  settingsStore.load();
  smartLights.loadConfig(settingsStore.getSection('smartLights'));

  // Load custom Last Light sequences from settings.
  const llSettings = settingsStore.getSection('lastLight') || {};
  if (llSettings.customSequences) lastLight.loadCustomSequences(llSettings.customSequences);

  // Initialize profiles module
  const profileCount = profiles.initialize();
  console.log(`Loaded ${profileCount} profiles`);
  
  createWindow();
  await createTray();
  setupJumpList();
  registerGlobalShortcuts();

  // If launched via --first-light, run the First Light sunrise sequence.
  if (launchOptions.firstLight) {
    playFirstLight();
  }

  // Start periodic update checker.
  updater.startPeriodicCheck((result) => {
    if (result.available) {
      showNativeNotification('Lights Out Update', `v${result.latestVersion} available. Click to download.`);
      if (mainWindow && !mainWindow.isDestroyed()) {
        mainWindow.webContents.send('update-available', result);
      }
    }
  });

  // Start companion PWA server.
  companion.start();
  companion.onMessage((msg, client) => {
    handleCompanionMessage(msg, client);
  });
  companion.onConnect((client) => {
    // Send initial state + streaks on connect.
    setTimeout(() => {
      broadcastCompanionState();
      try {
        const summary = streaks.getSummary();
        companion.broadcast({ type: 'streaks', streak: summary.streak || 0, bestStreak: summary.bestStreak || 0 });
      } catch {}
    }, 500);
  });

  // Broadcast timer state to companion clients periodically.
  setInterval(broadcastCompanionState, 2000);

  // Start family mode: discovery + command server.
  family.startDiscovery();
  family.startCommandServer((cmd) => {
    if (!cmd || !cmd.command) return;
    switch (cmd.command) {
      case 'start':
        startTimer({
          durationSeconds: cmd.durationSeconds || 1800,
          action: cmd.action || 'shutdown'
        });
        break;
      case 'pause':
        if (timerState.running && !timerState.paused) pauseTimer();
        break;
      case 'resume':
        if (timerState.running && timerState.paused) resumeTimer();
        break;
      case 'snooze':
        if (timerState.running) snoozeTimer(cmd.seconds || 300);
        break;
      case 'cancel':
        if (timerState.running) cancelTimer();
        break;
    }
  });

  // Focus Sessions: forward ticks and phase changes to renderer.
  focusSessions.onTick((fs) => {
    if (mainWindow && !mainWindow.isDestroyed()) {
      mainWindow.webContents.send('focus-tick', fs);
    }
  });
  focusSessions.onPhase((phase, fs) => {
    if (mainWindow && !mainWindow.isDestroyed()) {
      mainWindow.webContents.send('focus-phase', { phase, ...fs });
    }
    // Play sound on phase transitions.
    if (phase === 'break' || phase === 'longbreak') {
      showNativeNotification('Focus Session', 'Break time! Rest your eyes.');
    } else if (phase === 'focus') {
      showNativeNotification('Focus Session', 'Focus time! Get back to work.');
    }
  });
  focusSessions.onComplete((fs) => {
    if (mainWindow && !mainWindow.isDestroyed()) {
      mainWindow.webContents.send('focus-complete', fs);
    }
    showNativeNotification('Focus Session', `All cycles done! ${Math.round(fs.totalFocusTime / 60)} min of deep work.`);
  });

  // Idle Detection: nudge when user walks away during wind-down.
  idleDetection.startMonitoring({
    thresholdSeconds: 300,
    onIdle: (idleSec) => {
      if (timerState.running && !timerState.paused) {
        if (mainWindow && !mainWindow.isDestroyed()) {
          mainWindow.webContents.send('idle-detected', { idleSeconds: idleSec });
        }
      }
    },
    onReturn: () => {
      if (mainWindow && !mainWindow.isDestroyed()) {
        mainWindow.webContents.send('user-returned');
      }
    }
  });

  // Bedtime Reminder: gentle nudge 15 min before bedtime.
  bedtimeReminder.startReminder({
    minutesBefore: 15,
    onReminder: (data) => {
      if (mainWindow && !mainWindow.isDestroyed()) {
        mainWindow.webContents.send('bedtime-reminder', data);
      }
    }
  });

  // Calendar Auto-Start: check for upcoming events and auto-start timer.
  setInterval(checkCalendarAutoStart, 60000);

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) {
      createWindow();
    } else if (mainWindow) {
      mainWindow.show();
      mainWindow.focus();
    }
  });
});

app.on('window-all-closed', () => {
  // Keep running in tray.
});

app.on('before-quit', () => {
  app.isQuitting = true;
  clearTimerInterval();
  globalShortcut.unregisterAll();
  companion.stop();
  family.stopDiscovery();
  family.stopCommandServer();
  idleDetection.stopMonitoring();
  bedtimeReminder.stopReminder();
});
