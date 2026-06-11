// Stateful settings persistence for the Electron edition.
// Stores all user-facing settings (app, smart lights, customization, active timer)
// in userData\settings.json. Mirrors the persistence pattern used by profiles.js.

const { app } = require('electron');
const path = require('path');
const fs = require('fs');

const SETTINGS_FILE = 'settings.json';

let configPath = null;
let cache = null;

const DEFAULTS = {
  app: {
    action: 'shutdown',
    unit: 'min',
    durationSeconds: 28 * 60,
    sound: true,
    gracefulClose: true,
    forceShutdown: false,
    muteSystem: false,
    graceMinutes: 2,
    dryRun: false,
    focusBlocklist: [],
    onboarded: false,
    bedtime: '22:30',
    timerName: 'Witching Hour'
  },
  calendar: {
    enabled: true,
    provider: 'builtin',
    syncIntervalMin: 30,
    autoStartFromEvents: false,
    builtin: {
      enabled: true,
      bedtime: '22:30',
      days: ['sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat'],
      action: 'shutdown'
    },
    ical: { url: '' },
    google: { apiKey: '', calendarId: '' },
    outlook: { accessToken: '' },
    calendly: { personalToken: '' }
  },
  smartLights: {
    enabled: false,
    provider: 'none',
    mode: 'gradual_dim',
    dimMinutes: 10,
    hueBridgeIp: '',
    hueUsername: '',
    hueLightIds: [],
    hueGroupId: '',
    httpUrl: '',
    httpMethod: 'POST',
    httpHeaders: {},
    httpBodyTemplate: '{"brightness": {{BRIGHTNESS}}, "color_temp": {{COLOR_TEMP}}, "on": {{ON}}}'
  },
  customization: {
    accent: '#5b8cff',
    theme: 'midnight',
    ringStyle: 'glow',
    opacity: 1,
    volume: 1,
    warmShift: true,
    soundscape: 'off',
    ambientVisual: 'off'
  },
  lastLight: {
    enabled: false,
    sequence: 'ClassicFade',
    sound: 'Off',
    customSequences: []
  },
  wifiGuard: {
    enabled: false,
    provider: 'firewall',
    routerIp: '',
    routerUser: 'admin',
    routerPass: '',
    deviceMacs: [],
    deviceIps: [],
    webhookUrl: '',
    webhookHeaders: {},
    blockOnDim: true,
    unblockOnCancel: true
  },
  contentBlocker: {
    enabled: false,
    blockOnDim: true,
    unblockOnComplete: true,
    blocklist: [],
    useDefault: true
  },
  accountability: {
    enabled: false,
    notifyOnStart: true,
    notifyOnSnooze: true,
    notifyOnCancel: true,
    notifyOnComplete: true,
    partners: []
  },
  // Persisted running-timer snapshot for crash/quit recovery. null when idle.
  activeTimer: null
};

function getConfigPath() {
  if (!configPath) {
    configPath = path.join(app.getPath('userData'), SETTINGS_FILE);
  }
  return configPath;
}

function deepMerge(base, override) {
  if (!override || typeof override !== 'object') return clone(base);
  const out = clone(base);
  for (const key of Object.keys(override)) {
    const val = override[key];
    if (val && typeof val === 'object' && !Array.isArray(val) && base[key] && typeof base[key] === 'object' && !Array.isArray(base[key])) {
      out[key] = deepMerge(base[key], val);
    } else if (val !== undefined) {
      out[key] = clone(val);
    }
  }
  return out;
}

function clone(value) {
  return value === null || typeof value !== 'object'
    ? value
    : JSON.parse(JSON.stringify(value));
}

function load() {
  try {
    const file = getConfigPath();
    if (fs.existsSync(file)) {
      const parsed = JSON.parse(fs.readFileSync(file, 'utf8'));
      cache = deepMerge(DEFAULTS, parsed);
      return cache;
    }
  } catch (error) {
    console.error('Failed to load settings:', error.message);
  }
  cache = clone(DEFAULTS);
  return cache;
}

function ensureLoaded() {
  if (!cache) load();
  return cache;
}

function save() {
  try {
    fs.writeFileSync(getConfigPath(), JSON.stringify(ensureLoaded(), null, 2), 'utf8');
    return true;
  } catch (error) {
    console.error('Failed to save settings:', error.message);
    return false;
  }
}

function getAll() {
  return clone(ensureLoaded());
}

function getSection(section) {
  return clone(ensureLoaded()[section]);
}

function updateSection(section, patch) {
  ensureLoaded();
  if (!cache[section] || typeof cache[section] !== 'object' || Array.isArray(cache[section])) {
    cache[section] = clone(patch);
  } else {
    cache[section] = deepMerge(cache[section], patch || {});
  }
  save();
  return clone(cache[section]);
}

function setActiveTimer(snapshot) {
  ensureLoaded();
  cache.activeTimer = snapshot ? clone(snapshot) : null;
  save();
  return cache.activeTimer;
}

function getActiveTimer() {
  return clone(ensureLoaded().activeTimer);
}

module.exports = {
  DEFAULTS,
  load,
  save,
  getAll,
  getSection,
  updateSection,
  setActiveTimer,
  getActiveTimer
};
