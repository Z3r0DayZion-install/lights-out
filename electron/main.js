const { app, BrowserWindow, ipcMain, Tray, Menu, nativeImage, Notification, globalShortcut, shell } = require('electron');
const path = require('path');
const { spawn } = require('child_process');
const smartLights = require('./smartLights');
const profiles = require('./profiles');
const calendar = require('./calendar');
const settingsStore = require('./settings');

const APP_ICON = path.join(__dirname, 'assets', 'icon.ico');

let mainWindow;
let tray = null;
let miniMode = false;
let timerInterval = null;

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
  endsAt: null
};

function parseLaunchOptions(argv) {
  const options = {
    minimized: false,
    noAutoStart: false,
    timerMinutes: 0,
    action: 'shutdown'
  };

  for (const arg of argv) {
    const lower = String(arg).toLowerCase();
    if (lower === '--minimized' || lower === '--minimized-to-tray') options.minimized = true;
    if (lower === '--no-auto-start') options.noAutoStart = true;
    if (lower.startsWith('--timer=')) options.timerMinutes = Number(lower.split('=')[1]) || 0;
    if (lower.startsWith('--action=')) options.action = lower.split('=')[1] || 'shutdown';
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

function createTray() {
  tray = new Tray(nativeImage.createFromPath(APP_ICON));
  refreshTrayMenu();

  tray.setToolTip('Lights Out - idle');
  tray.on('click', toggleMainWindow);
}

function refreshTrayMenu() {
  if (!tray) return;

  const active = timerState.running || timerState.paused;
  const contextMenu = Menu.buildFromTemplate([
    {
      label: mainWindow && mainWindow.isVisible() ? 'Hide Lights Out' : 'Show Lights Out',
      click: toggleMainWindow
    },
    { type: 'separator' },
    {
      label: timerState.paused ? 'Resume Timer' : 'Pause Timer',
      enabled: active,
      click: () => (timerState.paused ? resumeTimer() : pauseTimer())
    },
    {
      label: 'Snooze +5 Minutes',
      enabled: active,
      click: () => snoozeTimer(300)
    },
    {
      label: 'Cancel Timer',
      enabled: active,
      click: cancelTimer
    },
    { type: 'separator' },
    { label: 'Start 5 Minutes', click: () => startTimer({ durationSeconds: 5 * 60, action: 'shutdown' }) },
    { label: 'Start 15 Minutes', click: () => startTimer({ durationSeconds: 15 * 60, action: 'shutdown' }) },
    { label: 'Start 30 Minutes', click: () => startTimer({ durationSeconds: 30 * 60, action: 'shutdown' }) },
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
    return;
  }

  const prefix = timerState.paused ? 'Paused' : 'Running';
  tray.setToolTip(`Lights Out - ${prefix}, ${formatTime(timerState.remainingSeconds)} left`);
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

  emitTimerUpdate('started');
  persistActiveTimer();
  setTaskbarProgress(100, 'normal');

  timerInterval = setInterval(() => {
    if (!timerState.running || timerState.paused) return;

    timerState.remainingSeconds = Math.max(0, timerState.remainingSeconds - 1);
    const percent = timerState.totalSeconds > 0
      ? (timerState.remainingSeconds / timerState.totalSeconds) * 100
      : 0;

    // Smart Lights integration
    if (smartLights.shouldStartDim(timerState.remainingSeconds)) {
      smartLights.startSmartLightDim(timerState.remainingSeconds);
    }
    if (smartLights.getConfig().enabled) {
      smartLights.updateSmartLightTick(timerState.remainingSeconds);
    }

    emitTimerUpdate('tick', { percent });
    setTaskbarProgress(percent, percent <= 10 ? 'error' : 'normal');

    if (timerState.gracePeriod > 0 && timerState.remainingSeconds === timerState.gracePeriod * 60) {
      emitTimerUpdate('warning', {
        message: `${formatAction(timerState.action)} in ${timerState.gracePeriod} minutes`
      });
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
  return { success: true, state: { ...timerState } };
}

function cancelTimer() {
  clearTimerInterval();
  timerState.running = false;
  timerState.paused = false;
  timerState.remainingSeconds = 0;
  timerState.endsAt = null;
  setTaskbarProgress(0, 'none');
  smartLights.resetSmartLightState();
  persistActiveTimer();
  emitTimerUpdate('cancelled');
  return { success: true };
}

async function completeTimer() {
  clearTimerInterval();
  timerState.running = false;
  timerState.paused = false;
  timerState.remainingSeconds = 0;
  timerState.endsAt = null;
  setTaskbarProgress(0, 'none');
  persistActiveTimer();
  
  // Turn off smart lights at timer completion
  if (smartLights.getConfig().enabled) {
    await smartLights.invokeSmartLightOff();
    smartLights.resetSmartLightState();
  }
  
  emitTimerUpdate('complete', { message: 'Timer complete' });
  showNativeNotification('Lights Out', timerState.dryRun
    ? `Dry run complete: ${formatAction(timerState.action)} skipped.`
    : `Timer complete: ${formatAction(timerState.action)} now.`);
  await executePowerAction({ ...timerState });
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

function formatTime(totalSeconds) {
  const seconds = Math.max(0, Math.round(totalSeconds));
  const hours = Math.floor(seconds / 3600);
  const minutes = Math.floor((seconds % 3600) / 60);
  const secs = seconds % 60;
  if (hours > 0) return `${hours}:${String(minutes).padStart(2, '0')}:${String(secs).padStart(2, '0')}`;
  return `${minutes}:${String(secs).padStart(2, '0')}`;
}

function executePowerShell(command) {
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

async function executePowerAction(options = {}) {
  const action = options.action || 'shutdown';
  const dryRun = Boolean(options.dryRun);
  const forceShutdown = Boolean(options.forceShutdown);
  const muteSystem = Boolean(options.muteSystem);

  if (dryRun) {
    emitTimerUpdate('dryrun', { action, message: `Dry run: ${formatAction(action)} skipped` });
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

    return { success: true };
  } catch (error) {
    emitTimerUpdate('error', { message: error.message });
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

ipcMain.handle('get-system-info', async () => {
  try {
    const battery = await executePowerShell('(Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue).EstimatedChargeRemaining');
    const powerPlan = await executePowerShell('(Get-CimInstance -Namespace "root\\cimv2\\power" -ClassName Win32_PowerPlan | Where-Object { $_.IsActive }).ElementName');
    return { battery: battery || 'N/A', powerPlan: powerPlan || 'Unknown' };
  } catch {
    return { battery: 'N/A', powerPlan: 'Unknown' };
  }
});

ipcMain.handle('get-app-settings', async () => ({
  ...getLoginSettings(),
  app: settingsStore.getSection('app'),
  customization: settingsStore.getSection('customization'),
  recoverableTimer: getRecoverableTimer()
}));
ipcMain.handle('save-app-settings', async (event, settings = {}) => {
  if (typeof settings.runAtLogin === 'boolean') setRunAtLogin(settings.runAtLogin);
  if (settings.app) settingsStore.updateSection('app', settings.app);
  if (settings.customization) settingsStore.updateSection('customization', settings.customization);
  return {
    ...getLoginSettings(),
    app: settingsStore.getSection('app'),
    customization: settingsStore.getSection('customization')
  };
});
ipcMain.handle('discard-recoverable-timer', async () => {
  settingsStore.setActiveTimer(null);
  return { success: true };
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
  globalShortcut.register('Ctrl+Shift+L', () => {
    if (mainWindow) {
      mainWindow.show();
      mainWindow.focus();
      startTimer({ durationSeconds: 15 * 60, action: 'shutdown' });
      showNativeNotification('Lights Out', '15 minute timer started');
    }
  });

  globalShortcut.register('Ctrl+Shift+S', toggleMainWindow);
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

app.whenReady().then(() => {
  // Load persisted settings and rehydrate the smart-lights module.
  settingsStore.load();
  smartLights.loadConfig(settingsStore.getSection('smartLights'));

  // Initialize profiles module
  const profileCount = profiles.initialize();
  console.log(`Loaded ${profileCount} profiles`);
  
  createWindow();
  createTray();
  setupJumpList();
  registerGlobalShortcuts();

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
});
