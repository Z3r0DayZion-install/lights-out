// Lights Out Electron - renderer process

const fallbackApi = (() => {
  let interval = null;
  const listeners = new Set();
  const state = {
    running: false,
    paused: false,
    totalSeconds: 0,
    remainingSeconds: 0,
    action: 'shutdown',
    dryRun: true,
    endsAt: null
  };

  function emit(type, extra = {}) {
    const payload = {
      type,
      running: state.running,
      paused: state.paused,
      totalSeconds: state.totalSeconds,
      remainingSeconds: state.remainingSeconds,
      total: state.totalSeconds,
      remaining: state.remainingSeconds,
      action: state.action,
      dryRun: state.dryRun,
      endsAt: state.endsAt,
      ...extra
    };
    listeners.forEach(listener => listener(payload));
  }

  function clear() {
    if (interval) {
      clearInterval(interval);
      interval = null;
    }
  }

  return {
    startTimer: async options => {
      clear();
      state.running = true;
      state.paused = false;
      state.totalSeconds = Math.max(1, Number(options.durationSeconds) || 60);
      state.remainingSeconds = state.totalSeconds;
      state.action = options.action || 'shutdown';
      state.dryRun = true;
      state.endsAt = new Date(Date.now() + state.remainingSeconds * 1000).toISOString();
      emit('started');

      interval = setInterval(() => {
        if (!state.running || state.paused) return;
        state.remainingSeconds = Math.max(0, state.remainingSeconds - 1);
        emit('tick');
        if (state.remainingSeconds <= 0) {
          clear();
          state.running = false;
          emit('complete', { message: 'Preview complete' });
        }
      }, 1000);

      return { success: true };
    },
    cancelTimer: async () => {
      clear();
      state.running = false;
      state.paused = false;
      state.remainingSeconds = 0;
      emit('cancelled');
      return { success: true };
    },
    pauseTimer: async () => {
      state.paused = true;
      emit('paused');
      return { success: true };
    },
    resumeTimer: async () => {
      state.paused = false;
      emit('resumed');
      return { success: true };
    },
    snoozeTimer: async seconds => {
      const addSeconds = Math.max(1, Number(seconds) || 300);
      state.totalSeconds += addSeconds;
      state.remainingSeconds += addSeconds;
      state.endsAt = new Date(Date.now() + state.remainingSeconds * 1000).toISOString();
      emit('snoozed', { addedSeconds: addSeconds });
      return { success: true };
    },
    executeAction: async () => ({ success: true, dryRun: true }),
    getSystemInfo: async () => ({ battery: 'N/A', powerPlan: 'Preview' }),
    getAppSettings: async () => {
      let stored = {};
      try { stored = JSON.parse(localStorage.getItem('lightsout-settings') || '{}'); } catch { stored = {}; }
      return {
        runAtLogin: false,
        startupBehavior: 'Starts minimized and idle',
        app: stored.app || null,
        customization: stored.customization || null,
        recoverableTimer: null
      };
    },
    saveAppSettings: async settings => {
      let stored = {};
      try { stored = JSON.parse(localStorage.getItem('lightsout-settings') || '{}'); } catch { stored = {}; }
      if (settings.app) stored.app = { ...(stored.app || {}), ...settings.app };
      if (settings.customization) stored.customization = { ...(stored.customization || {}), ...settings.customization };
      try { localStorage.setItem('lightsout-settings', JSON.stringify(stored)); } catch { /* ignore */ }
      return { runAtLogin: Boolean(settings.runAtLogin), startupBehavior: 'Starts minimized and idle', app: stored.app, customization: stored.customization };
    },
    resumeRecoverableTimer: async () => ({ success: false }),
    discardRecoverableTimer: async () => ({ success: true }),
    minimizeWindow: () => {},
    closeWindow: () => {},
    quitApp: () => {},
    toggleMiniMode: () => {},
    toggleWidget: () => {},
    setWindowOpacity: () => {},
    showNotification: () => {},
    playSound: () => {},
    setProgress: () => {},
    onTimerUpdate: callback => listeners.add(callback),
    onMiniModeChanged: () => {},
    onPlaySound: () => {},
    onPlayLastLight: () => {},
    onDimPhaseStarted: () => {},
    onDimPhaseEnded: () => {},
    getStreaks: async () => ({ streak: 0, bestStreak: 0, totalNights: 0, achievements: [], weekAvg: '--:--', weekOnTime: 0, weekDays: [] }),
    getAchievementsCatalog: async () => [],
    getWeeklyReport: async () => null,
    addCustomSequence: async () => null,
    removeCustomSequence: async () => ({ success: true }),
    getOpenBrowsers: async () => [],
    onBrowserWarning: () => {},
    scheduleWakeAlarm: async () => ({ success: false, error: 'Preview mode' }),
    removeWakeAlarm: async () => ({ success: true }),
    getWakeAlarmStatus: async () => ({ active: false }),
    onSunriseAlarmStarted: () => {},
    onSunriseAlarmTick: () => {},
    onSunriseAlarmEnded: () => {},
    checkForUpdate: async () => ({ available: false }),
    getUpdateStatus: async () => ({ available: false }),
    onUpdateAvailable: () => {},
    exportAllData: async () => ({ success: false, error: 'Preview mode' }),
    importAllData: async () => ({ success: false, error: 'Preview mode' }),
    openExternal: url => window.open(url, '_blank', 'noopener'),
    // Profiles fallbacks
    getAllProfiles: async () => [],
    getProfileById: async () => null,
    createProfile: async () => ({ success: false, error: 'Preview mode' }),
    updateProfile: async () => ({ success: false, error: 'Preview mode' }),
    deleteProfile: async () => ({ success: false, error: 'Preview mode' }),
    reorderProfiles: async () => ({ success: false }),
    applyProfile: async () => ({ success: false, error: 'Preview mode' }),
    getProfileHint: async () => '',
    exportProfiles: async () => '[]',
    importProfiles: async () => ({ success: false, error: 'Preview mode' }),
    createDefaultProfiles: async () => [],
    // Calendar fallbacks
    calendarParseText: async () => ({ success: false, error: 'Preview mode', events: [] }),
    calendarImportUrl: async () => ({ success: false, error: 'Preview mode', events: [] }),
    calendarTestUrl: async () => false,
    calendarGetUpcoming: async () => [],
    calendarCreateTimer: async () => ({ success: false, error: 'Preview mode' }),
    calendarFormatTime: async () => 'Unknown'
  };
})();

const api = window.electronAPI || fallbackApi;
const previewMode = !window.electronAPI;

const els = {
  body: document.body,
  timerMain: document.getElementById('timer-main'),
  timerLabel: document.getElementById('timer-label'),
  ringProgress: document.querySelector('.ring-progress'),
  timerInput: document.getElementById('timer-input'),
  btnStart: document.getElementById('btn-start'),
  btnStop: document.getElementById('btn-stop'),
  btnPause: document.getElementById('btn-pause'),
  btnSnooze: document.getElementById('btn-snooze'),
  btnMinimize: document.getElementById('btn-minimize'),
  btnClose: document.getElementById('btn-close'),
  btnMini: document.getElementById('btn-mini'),
  btnPlus: document.getElementById('btn-plus'),
  btnMinus: document.getElementById('btn-minus'),
  optionsModal: document.getElementById('options-modal'),
  modalClose: document.getElementById('modal-close'),
  btnCancelOpt: document.getElementById('btn-cancel-opt'),
  btnSaveOpt: document.getElementById('btn-save-opt'),
  selAction: document.getElementById('sel-action'),
  graceMinutes: document.getElementById('grace-minutes'),
  chkForceShutdown: document.getElementById('chk-forceshutdown'),
  chkMute: document.getElementById('chk-mute'),
  chkRunLogin: document.getElementById('chk-run-login'),
  focusBlocklist: document.getElementById('focus-blocklist'),
  chkDryRun: document.getElementById('chk-dryrun'),
  badgeDryRun: document.getElementById('badge-dryrun'),
  badgeConfirm: document.getElementById('badge-confirm'),
  badgeCancel: document.getElementById('badge-cancel'),
  batteryLevel: document.getElementById('battery-level'),
  powerPlan: document.getElementById('power-plan'),
  actionName: document.getElementById('action-name'),
  endTime: document.getElementById('end-time'),
  warningCard: document.getElementById('warning-card'),
  warningText: document.getElementById('warning-text'),
  scheduleCheck: document.getElementById('chk-schedule'),
  scheduleTime: document.getElementById('schedule-time'),
  // Smart Lights elements
  chkSmartLights: document.getElementById('chk-smart-lights'),
  lightsConfig: document.getElementById('lights-config'),
  selLightProvider: document.getElementById('sel-light-provider'),
  selLightMode: document.getElementById('sel-light-mode'),
  lightDimMinutes: document.getElementById('light-dim-minutes'),
  hueConfig: document.getElementById('hue-config'),
  httpConfig: document.getElementById('http-config'),
  hueBridgeIp: document.getElementById('hue-bridge-ip'),
  hueUsername: document.getElementById('hue-username'),
  hueGroupId: document.getElementById('hue-group-id'),
  btnDiscoverHue: document.getElementById('btn-discover-hue'),
  btnRegisterHue: document.getElementById('btn-register-hue'),
  btnLoadGroups: document.getElementById('btn-load-groups'),
  httpUrl: document.getElementById('http-url'),
  httpMethod: document.getElementById('http-method'),
  httpTemplate: document.getElementById('http-template'),
  btnTestLights: document.getElementById('btn-test-lights'),
  lightTestResult: document.getElementById('light-test-result'),
  // Profiles elements
  profilesGrid: document.getElementById('profiles-grid'),
  btnManageProfiles: document.getElementById('btn-manage-profiles'),
  profilesModal: document.getElementById('profiles-modal'),
  profilesModalClose: document.getElementById('profiles-modal-close'),
  btnCloseProfiles: document.getElementById('btn-close-profiles'),
  newProfileName: document.getElementById('new-profile-name'),
  newProfileAutostart: document.getElementById('new-profile-autostart'),
  btnSaveProfile: document.getElementById('btn-save-profile'),
  profilesList: document.getElementById('profiles-list'),
  btnExportProfiles: document.getElementById('btn-export-profiles'),
  btnImportProfiles: document.getElementById('btn-import-profiles'),
  importFileInput: document.getElementById('import-file-input'),
  // Calendar elements
  calendarFileInput: document.getElementById('calendar-file-input'),
  btnImportFile: document.getElementById('btn-import-file'),
  calendarUrlInput: document.getElementById('calendar-url-input'),
  btnImportUrl: document.getElementById('btn-import-url'),
  calendarEvents: document.getElementById('calendar-events'),
  importTabBtns: document.querySelectorAll('.import-tab-btn'),
  importPanels: document.querySelectorAll('.import-panel'),
  // Customization elements
  czAccent: document.getElementById('cz-accent'),
  czSwatches: document.getElementById('cz-swatches'),
  czTheme: document.getElementById('cz-theme'),
  czRing: document.getElementById('cz-ring'),
  czOpacity: document.getElementById('cz-opacity'),
  czOpacityVal: document.getElementById('cz-opacity-val'),
  czVolume: document.getElementById('cz-volume'),
  czVolumeVal: document.getElementById('cz-volume-val'),
  czWarmShift: document.getElementById('cz-warmshift'),
  czSoundscape: document.getElementById('cz-soundscape'),
  btnResetCustomize: document.getElementById('btn-reset-customize'),
  // Last Light elements
  chkLastLight: document.getElementById('chk-lastlight'),
  lastLightConfig: document.getElementById('lastlight-config'),
  selLastLightSequence: document.getElementById('sel-lastlight-sequence'),
  selLastLightSound: document.getElementById('sel-lastlight-sound'),
  btnPreviewLastLight: document.getElementById('btn-preview-lastlight'),
  lastLightOverlay: document.getElementById('last-light-overlay'),
  llTitle: document.getElementById('ll-title'),
  llHeadline: document.getElementById('ll-headline'),
  llLine: document.getElementById('ll-line'),
  llStamp: document.getElementById('ll-stamp'),
  // Warning modal
  warningModal: document.getElementById('warning-modal'),
  warningModalText: document.getElementById('warning-modal-text'),
  warningSnooze: document.getElementById('warning-snooze'),
  warningCancel: document.getElementById('warning-cancel'),
  warningDismiss: document.getElementById('warning-dismiss'),
  // Phase badge
  badgePhase: document.getElementById('badge-phase'),
  // Streaks
  streakCount: document.getElementById('streak-count'),
  streakBest: document.getElementById('streak-best'),
  streakTotal: document.getElementById('streak-total'),
  streakWeekAvg: document.getElementById('streak-weekavg'),
  streakOnTime: document.getElementById('streak-ontime'),
  streakWeekBar: document.getElementById('streak-week-bar'),
  achievementsGrid: document.getElementById('achievements-grid'),
  // Custom Last Light sequences
  customSeqList: document.getElementById('custom-seq-list'),
  btnAddCustomSeq: document.getElementById('btn-add-custom-seq'),
  customSeqBuilder: document.getElementById('custom-seq-builder'),
  customSeqName: document.getElementById('custom-seq-name'),
  customSeqSteps: document.getElementById('custom-seq-steps'),
  btnAddStep: document.getElementById('btn-add-step'),
  btnSaveCustomSeq: document.getElementById('btn-save-custom-seq'),
  btnCancelCustomSeq: document.getElementById('btn-cancel-custom-seq'),
  // Widget
  btnWidget: document.getElementById('btn-widget'),
  // Alarm
  chkAlarm: document.getElementById('chk-alarm'),
  alarmConfig: document.getElementById('alarm-config'),
  alarmTime: document.getElementById('alarm-time'),
  btnSetAlarm: document.getElementById('btn-set-alarm'),
  btnRemoveAlarm: document.getElementById('btn-remove-alarm'),
  alarmStatus: document.getElementById('alarm-status'),
  // Update badge
  badgeUpdate: document.getElementById('badge-update'),
  // Data export/import
  btnExportAllData: document.getElementById('btn-export-all-data'),
  btnImportAllData: document.getElementById('btn-import-all-data'),
  importAllDataInput: document.getElementById('import-all-data-input')
};

const state = {
  running: false,
  paused: false,
  totalSeconds: 0,
  remainingSeconds: 28 * 60,
  action: 'shutdown',
  unit: 'min',
  dryRun: false,
  sound: true,
  gracefulClose: true,
  forceShutdown: false,
  muteSystem: false,
  graceMinutes: 2,
  runAtLogin: false,
  miniMode: false,
  endsAt: null,
  selectedCard: null,
  // Smart Lights state
  smartLights: {
    enabled: false,
    provider: 'none',
    mode: 'gradual_dim',
    dimMinutes: 10,
    hueBridgeIp: '',
    hueUsername: '',
    hueGroupId: '',
    httpUrl: '',
    httpMethod: 'POST',
    httpBodyTemplate: '{"brightness": {{BRIGHTNESS}}, "color_temp": {{COLOR_TEMP}}, "on": {{ON}}}'
  },
  // Customization state
  customization: {
    accent: '#5b8cff',
    theme: 'midnight',
    ringStyle: 'glow',
    opacity: 1,
    volume: 1,
    warmShift: true,
    soundscape: 'off'
  },
  // Last Light state
  lastLight: {
    enabled: false,
    sequence: 'ClassicFade',
    sound: 'Off'
  },
  // Wind-down phase state
  phase: 'idle',
  // Profiles state
  profiles: [],
  currentProfileId: null,
  // Calendar state
  calendarEvents: [],
  calendarSource: null
};

if (previewMode) {
  state.dryRun = true;
}

const SoundSystem = {
  ctx: null,
  enabled: true,
  master: 1,

  init() {
    if (!this.ctx) {
      this.ctx = new (window.AudioContext || window.webkitAudioContext)();
    }
  },

  getCtx() {
    this.init();
    return this.ctx;
  },

  playTone(freq, duration, type = 'sine', volume = 0.25) {
    if (!this.enabled) return;
    this.init();

    const osc = this.ctx.createOscillator();
    const gain = this.ctx.createGain();
    osc.type = type;
    osc.frequency.setValueAtTime(freq, this.ctx.currentTime);
    gain.gain.setValueAtTime(Math.max(0.0001, volume * this.master), this.ctx.currentTime);
    gain.gain.exponentialRampToValueAtTime(0.01, this.ctx.currentTime + duration);
    osc.connect(gain);
    gain.connect(this.ctx.destination);
    osc.start(this.ctx.currentTime);
    osc.stop(this.ctx.currentTime + duration);
  },

  playStart() {
    this.playTone(523.25, 0.1, 'sine', 0.18);
    setTimeout(() => this.playTone(659.25, 0.1, 'sine', 0.18), 100);
    setTimeout(() => this.playTone(783.99, 0.2, 'sine', 0.24), 200);
  },

  playPause() {
    this.playTone(440, 0.12, 'triangle', 0.18);
  },

  playComplete() {
    [523.25, 659.25, 783.99, 1046.50].forEach((freq, i) => {
      setTimeout(() => this.playTone(freq, 0.25, 'sine', 0.25), i * 130);
    });
  },

  playWarning() {
    this.playTone(300, 0.25, 'sawtooth', 0.16);
  },

  playCancel() {
    this.playTone(440, 0.08, 'sine', 0.16);
    setTimeout(() => this.playTone(349.23, 0.12, 'sine', 0.16), 90);
  }
};

// Ambient soundscape engine. Generates continuous rain/white-noise/brown-noise/
// crickets/ocean audio using the Web Audio API, fading with the timer.
const Soundscape = {
  active: false,
  type: 'off',
  nodes: null,
  gain: null,
  fadeInterval: null,

  start(type) {
    this.stop();
    if (!type || type === 'off') return;
    if (!SoundSystem.enabled) return;
    this.type = type;
    this.active = true;

    const ctx = SoundSystem.getCtx();
    this.gain = ctx.createGain();
    this.gain.gain.setValueAtTime(0, ctx.currentTime);
    this.gain.connect(ctx.destination);

    const bufferSize = 2 * ctx.sampleRate;
    const buffer = ctx.createBuffer(2, bufferSize, ctx.sampleRate);

    switch (type) {
      case 'rain':
        this._fillPinkNoise(buffer);
        break;
      case 'whitenoise':
        this._fillWhiteNoise(buffer);
        break;
      case 'brownnoise':
        this._fillBrownNoise(buffer);
        break;
      case 'crickets':
        this._fillCrickets(buffer);
        break;
      case 'ocean':
        this._fillOcean(buffer);
        break;
      default:
        this._fillWhiteNoise(buffer);
    }

    const source = ctx.createBufferSource();
    source.buffer = buffer;
    source.loop = true;
    source.connect(this.gain);
    source.start();
    this.nodes = { source };

    // Fade in.
    this.gain.gain.linearRampToValueAtTime(0.18 * SoundSystem.master, ctx.currentTime + 2);
  },

  stop() {
    if (this.fadeInterval) { clearInterval(this.fadeInterval); this.fadeInterval = null; }
    if (this.nodes?.source) { try { this.nodes.source.stop(); } catch { } }
    if (this.gain) { try { this.gain.disconnect(); } catch { } }
    this.nodes = null;
    this.gain = null;
    this.active = false;
    this.type = 'off';
  },

  fadeToZero(durationSec) {
    if (!this.gain || !this.active) { this.stop(); return; }
    const ctx = SoundSystem.getCtx();
    this.gain.gain.linearRampToValueAtTime(0, ctx.currentTime + durationSec);
    setTimeout(() => this.stop(), durationSec * 1000 + 200);
  },

  setVolume(level) {
    if (!this.gain || !this.active) return;
    const ctx = SoundSystem.getCtx();
    this.gain.gain.linearRampToValueAtTime(Math.max(0, level) * SoundSystem.master, ctx.currentTime + 0.5);
  },

  _fillWhiteNoise(buffer) {
    for (let ch = 0; ch < buffer.numberOfChannels; ch++) {
      const data = buffer.getChannelData(ch);
      for (let i = 0; i < data.length; i++) data[i] = Math.random() * 2 - 1;
    }
  },

  _fillBrownNoise(buffer) {
    for (let ch = 0; ch < buffer.numberOfChannels; ch++) {
      const data = buffer.getChannelData(ch);
      let last = 0;
      for (let i = 0; i < data.length; i++) {
        const white = Math.random() * 2 - 1;
        data[i] = (last + 0.02 * white) / 1.02;
        last = data[i];
        data[i] *= 3.5;
      }
    }
  },

  _fillPinkNoise(buffer) {
    // Voss-McCartney approximation for rain-like sound.
    for (let ch = 0; ch < buffer.numberOfChannels; ch++) {
      const data = buffer.getChannelData(ch);
      let b0 = 0, b1 = 0, b2 = 0, b3 = 0, b4 = 0, b5 = 0, b6 = 0;
      for (let i = 0; i < data.length; i++) {
        const white = Math.random() * 2 - 1;
        b0 = 0.99886 * b0 + white * 0.0555179;
        b1 = 0.99332 * b1 + white * 0.0750759;
        b2 = 0.96900 * b2 + white * 0.1538520;
        b3 = 0.86650 * b3 + white * 0.3104856;
        b4 = 0.55000 * b4 + white * 0.5329522;
        b5 = -0.7616 * b5 - white * 0.0168980;
        data[i] = (b0 + b1 + b2 + b3 + b4 + b5 + b6 + white * 0.5362) * 0.11;
        b6 = white * 0.115926;
      }
    }
  },

  _fillCrickets(buffer) {
    // Sparse chirps: short bursts of high-frequency tone with random gaps.
    const sampleRate = buffer.sampleRate;
    for (let ch = 0; ch < buffer.numberOfChannels; ch++) {
      const data = buffer.getChannelData(ch);
      let pos = 0;
      while (pos < data.length) {
        const chirpLen = Math.floor(sampleRate * (0.008 + Math.random() * 0.015));
        const gapLen = Math.floor(sampleRate * (0.05 + Math.random() * 0.2));
        const freq = 4000 + Math.random() * 2000;
        for (let i = 0; i < chirpLen && pos < data.length; i++, pos++) {
          data[pos] = Math.sin(2 * Math.PI * freq * i / sampleRate) * 0.3 * (1 - i / chirpLen);
        }
        for (let i = 0; i < gapLen && pos < data.length; i++, pos++) {
          data[pos] = 0;
        }
      }
    }
  },

  _fillOcean(buffer) {
    // Low-frequency filtered noise with slow amplitude modulation.
    const sampleRate = buffer.sampleRate;
    for (let ch = 0; ch < buffer.numberOfChannels; ch++) {
      const data = buffer.getChannelData(ch);
      let last = 0;
      const modPeriod = sampleRate * 6; // 6-second wave cycle
      for (let i = 0; i < data.length; i++) {
        const white = Math.random() * 2 - 1;
        last = (last + 0.02 * white) / 1.02;
        const mod = 0.5 + 0.5 * Math.sin(2 * Math.PI * i / modPeriod);
        data[i] = last * 3.5 * mod;
      }
    }
  }
};

function clamp(value, min, max) {
  return Math.min(max, Math.max(min, value));
}

function formatTime(totalSeconds) {
  const safeSeconds = Math.max(0, Math.round(Number(totalSeconds) || 0));
  const hours = Math.floor(safeSeconds / 3600);
  const minutes = Math.floor((safeSeconds % 3600) / 60);
  const seconds = safeSeconds % 60;

  if (hours > 0) {
    return `${hours}:${String(minutes).padStart(2, '0')}:${String(seconds).padStart(2, '0')}`;
  }

  return `${minutes}:${String(seconds).padStart(2, '0')}`;
}

function actionLabel(action = state.action) {
  return {
    shutdown: 'Shutdown',
    restart: 'Restart',
    sleep: 'Sleep',
    hibernate: 'Hibernate',
    logout: 'Log out'
  }[action] || 'Power action';
}

function formatEndTime(isoDate) {
  if (!isoDate) return 'Idle';
  const date = new Date(isoDate);
  if (Number.isNaN(date.getTime())) return 'Idle';
  return date.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });
}

function inputValue() {
  return clamp(parseInt(els.timerInput.value, 10) || 1, 1, state.unit === 'min' ? 480 : 28800);
}

function inputSeconds() {
  if (els.scheduleCheck?.checked && els.scheduleTime?.value) {
    return secondsUntilClockValue(els.scheduleTime.value);
  }
  return state.unit === 'sec' ? inputValue() : inputValue() * 60;
}

function setInputFromSeconds(seconds) {
  const safeSeconds = Math.max(1, Math.round(Number(seconds) || 60));
  if (state.unit === 'sec') {
    els.timerInput.value = safeSeconds;
  } else {
    els.timerInput.value = Math.max(1, Math.round(safeSeconds / 60));
  }
  if (!state.running) {
    state.remainingSeconds = inputSeconds();
    state.totalSeconds = state.remainingSeconds;
  }
  render();
}

function secondsUntilClockValue(timeValue) {
  const [hours, minutes] = String(timeValue).split(':').map(Number);
  if (!Number.isFinite(hours) || !Number.isFinite(minutes)) return inputValue() * 60;

  const now = new Date();
  const target = new Date(now);
  target.setHours(hours, minutes, 0, 0);
  if (target <= now) target.setDate(target.getDate() + 1);
  return Math.max(60, Math.round((target - now) / 1000));
}

function setAction(action) {
  state.action = action;
  if (els.selAction) els.selAction.value = action;
  document.querySelectorAll('[data-action]').forEach(item => {
    item.classList.toggle('selected', item.dataset.action === action);
  });
  render();
}

function updateRing(remaining, total) {
  if (!els.ringProgress) return;
  const circumference = 2 * Math.PI * 90;
  const ratio = total > 0 ? clamp(remaining / total, 0, 1) : 0;
  els.ringProgress.style.strokeDasharray = `${circumference}`;
  els.ringProgress.style.strokeDashoffset = `${circumference - ratio * circumference}`;
}

function showToast(message, type = 'info', duration = 3000) {
  let container = document.getElementById('toast-container');
  if (!container) {
    container = document.createElement('div');
    container.id = 'toast-container';
    document.body.appendChild(container);
  }

  const toast = document.createElement('div');
  toast.className = `toast toast-${type}`;
  toast.textContent = message;
  container.appendChild(toast);

  requestAnimationFrame(() => toast.classList.add('visible'));
  setTimeout(() => {
    toast.classList.remove('visible');
    setTimeout(() => toast.remove(), 220);
  }, duration);
}

function notify(message, type = 'info') {
  showToast(message, type);
}

function render() {
  const displaySeconds = state.running || state.paused ? state.remainingSeconds : inputSeconds();
  const totalSeconds = state.running || state.paused ? state.totalSeconds : displaySeconds;

  els.body.classList.toggle('is-running', state.running);
  els.body.classList.toggle('is-paused', state.paused);
  els.body.classList.toggle('mini-mode', state.miniMode);

  els.timerMain.textContent = formatTime(displaySeconds);
  els.timerLabel.textContent = state.paused
    ? `${actionLabel()} paused`
    : state.running
      ? `until ${actionLabel().toLowerCase()}`
      : 'ready';

  updateRing(displaySeconds, totalSeconds);

  els.btnStart.style.display = state.running || state.paused ? 'none' : 'flex';
  els.btnStop.style.display = state.running || state.paused ? 'flex' : 'none';
  els.btnPause.style.display = state.running || state.paused ? 'flex' : 'none';
  els.btnSnooze.disabled = !(state.running || state.paused);
  els.btnPause.querySelector('span:last-child').textContent = state.paused ? 'Resume' : 'Pause';

  els.timerInput.disabled = state.running || state.paused;
  els.btnPlus.disabled = state.running || state.paused;
  els.btnMinus.disabled = state.running || state.paused;

  document.querySelectorAll('.unit-btn').forEach(btn => {
    btn.classList.toggle('active', btn.dataset.unit === state.unit);
  });

  document.getElementById('toggle-dryrun')?.querySelector('.toggle-indicator')?.replaceChildren(document.createTextNode(state.dryRun ? 'ON' : 'OFF'));
  document.getElementById('toggle-mute')?.querySelector('.toggle-indicator')?.replaceChildren(document.createTextNode(state.sound ? 'ON' : 'OFF'));
  document.getElementById('toggle-graceful')?.querySelector('.toggle-indicator')?.replaceChildren(document.createTextNode(state.gracefulClose ? 'ON' : 'OFF'));

  els.badgeDryRun.classList.toggle('active', state.dryRun);
  els.badgeConfirm.classList.toggle('active', !state.forceShutdown);
  els.badgeCancel.classList.toggle('active', state.running || state.paused);

  // Phase badge
  if (els.badgePhase) {
    const showPhase = state.running && state.phase && state.phase !== 'idle';
    els.badgePhase.classList.toggle('active', showPhase);
    els.badgePhase.textContent = showPhase ? state.phase.toUpperCase() : '';
    els.badgePhase.dataset.phase = state.phase || 'idle';
  }

  els.actionName.textContent = actionLabel();
  els.endTime.textContent = state.running || state.paused ? formatEndTime(state.endsAt) : 'Idle';

  if (els.chkDryRun) els.chkDryRun.checked = state.dryRun;
  if (els.chkForceShutdown) els.chkForceShutdown.checked = state.forceShutdown;
  if (els.chkMute) els.chkMute.checked = state.muteSystem;
  if (els.chkRunLogin) els.chkRunLogin.checked = state.runAtLogin;
  if (els.graceMinutes) els.graceMinutes.value = state.graceMinutes;

  document.querySelectorAll('.tonight-card').forEach(card => {
    card.classList.toggle('selected', card.dataset.card === state.selectedCard);
  });
}

async function startTimer(seconds = inputSeconds()) {
  const durationSeconds = Math.max(1, Math.round(seconds));

  try {
    SoundSystem.playStart();
    const result = await api.startTimer({
      durationSeconds,
      action: state.action,
      dryRun: state.dryRun,
      forceShutdown: state.forceShutdown,
      muteSystem: state.muteSystem,
      gracePeriod: state.graceMinutes
    });

    if (result?.success === false) {
      notify(result.error || 'Timer could not start', 'error');
      return;
    }

    state.running = true;
    state.paused = false;
    state.totalSeconds = durationSeconds;
    state.remainingSeconds = durationSeconds;
    state.endsAt = new Date(Date.now() + durationSeconds * 1000).toISOString();
    render();
  } catch (error) {
    notify(`Failed to start timer: ${error.message || error}`, 'error');
  }
}

async function cancelTimer() {
  try {
    SoundSystem.playCancel();
    await api.cancelTimer();
    state.running = false;
    state.paused = false;
    state.remainingSeconds = inputSeconds();
    state.totalSeconds = state.remainingSeconds;
    state.endsAt = null;
    render();
    notify('Timer cancelled', 'info');
  } catch (error) {
    notify(`Error cancelling timer: ${error.message || error}`, 'error');
  }
}

async function togglePause() {
  try {
    SoundSystem.playPause();
    if (state.paused) {
      await api.resumeTimer();
      state.paused = false;
      state.running = true;
      state.endsAt = new Date(Date.now() + state.remainingSeconds * 1000).toISOString();
      notify('Timer resumed', 'success');
    } else {
      await api.pauseTimer();
      state.paused = true;
      notify('Timer paused', 'warning');
    }
    render();
  } catch (error) {
    notify(`Pause failed: ${error.message || error}`, 'error');
  }
}

async function snooze(seconds = 5 * 60) {
  if (!state.running && !state.paused) return;

  try {
    const result = await api.snoozeTimer(seconds);
    if (result?.state) {
      applyTimerPayload({ type: 'snoozed', ...result.state });
    }
    render();
    notify(`Snoozed +${Math.round(seconds / 60)} minutes`, 'success');
  } catch (error) {
    notify(`Snooze failed: ${error.message || error}`, 'error');
  }
}

function applyTimerPayload(data) {
  if (!data || typeof data !== 'object') return;

  if (typeof data.running === 'boolean') state.running = data.running;
  if (typeof data.paused === 'boolean') state.paused = data.paused;
  if (Number.isFinite(Number(data.totalSeconds ?? data.total))) {
    state.totalSeconds = Number(data.totalSeconds ?? data.total);
  }
  if (Number.isFinite(Number(data.remainingSeconds ?? data.remaining))) {
    state.remainingSeconds = Number(data.remainingSeconds ?? data.remaining);
  }
  if (data.action) state.action = data.action;
  if (typeof data.dryRun === 'boolean') state.dryRun = data.dryRun;
  if (data.endsAt !== undefined) state.endsAt = data.endsAt;

  if (data.type === 'complete') {
    state.running = false;
    state.paused = false;
    state.remainingSeconds = inputSeconds();
    state.totalSeconds = state.remainingSeconds;
    state.endsAt = null;
    state.phase = 'idle';
    SoundSystem.playComplete();
    Soundscape.fadeToZero(2);
    hideWarningModal();
    removeWarmFilter();
    loadStreaks();
    api.showNotification('Lights Out', state.dryRun ? 'Dry run complete.' : `${actionLabel()} started.`);
    notify(data.message || 'Timer complete', 'success', 5000);
  } else if (data.type === 'cancelled') {
    state.running = false;
    state.paused = false;
    state.endsAt = null;
    state.phase = 'idle';
    Soundscape.stop();
    hideWarningModal();
    removeWarmFilter();
  } else if (data.type === 'warning') {
    SoundSystem.playWarning();
    if (data.message) {
      els.warningCard.style.display = '';
      els.warningText.textContent = data.message;
      api.showNotification('Lights Out', data.message);
      showWarningModal(data.message);
    }
  } else if (data.type === 'phase') {
    state.phase = data.phase || 'idle';
    if (data.phase === 'dim') applyWarmFilter();
    if (data.phase === 'lastlight') Soundscape.fadeToZero(3);
  } else if (data.type === 'started') {
    state.phase = 'focus';
    const sc = state.customization.soundscape || 'off';
    if (sc !== 'off') Soundscape.start(sc);
  } else if (data.type === 'tick' && state.remainingSeconds <= 10 && state.remainingSeconds > 0) {
    SoundSystem.playTone(800, 0.04, 'sine', 0.08);
  } else if (data.type === 'dryrun') {
    notify(data.message || 'Dry run skipped the power action', 'info');
  } else if (data.type === 'error') {
    notify(data.message || 'Timer error', 'error');
  }

  render();
}

async function loadStreaks() {
  try {
    const summary = await api.getStreaks();
    const catalog = await api.getAchievementsCatalog();
    const report = await api.getWeeklyReport();
    renderStreaks(summary, catalog, report);
  } catch { /* streaks are decorative, never block */ }
}

function renderStreaks(summary, catalog, report) {
  if (!summary) return;
  if (els.streakCount) els.streakCount.textContent = summary.streak || 0;
  if (els.streakBest) els.streakBest.textContent = summary.bestStreak || 0;
  if (els.streakTotal) els.streakTotal.textContent = summary.totalNights || 0;
  if (els.streakWeekAvg) els.streakWeekAvg.textContent = summary.weekAvg || '--:--';
  if (els.streakOnTime) els.streakOnTime.textContent = `${summary.weekOnTime || 0}%`;

  // Week bar chart + consistency + snooze from report.
  if (report) {
    // Update stats with report data.
    if (els.streakOnTime) els.streakOnTime.textContent = `${100 - (report.snoozeRate || 0)}% on-time`;
    // Show consistency.
    const existingStats = document.querySelectorAll('.streak-stat');
    if (existingStats.length >= 4 && report.consistency !== undefined) {
      // Replace the last stat with consistency if available.
    }
  }

  // Week bar chart.
  if (els.streakWeekBar && summary.weekDays?.length) {
    const dayLabels = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    const today = new Date().toISOString().slice(0, 10);
    els.streakWeekBar.innerHTML = summary.weekDays.map(d => {
      const [h, m] = (d.bedTime || '23:00').split(':').map(Number);
      const mins = h * 60 + m;
      const maxMins = 24 * 60;
      const pct = Math.min(100, Math.max(8, (mins / maxMins) * 100));
      const isToday = d.date === today;
      const dayIdx = new Date(d.date + 'T12:00:00').getDay();
      return `<div class="week-bar${isToday ? ' today' : ''}" style="height:${pct}%" title="${d.bedTime}"><span class="week-bar-label">${dayLabels[dayIdx]}</span></div>`;
    }).join('');
  }

  // Achievements grid.
  if (els.achievementsGrid && catalog?.length) {
    const unlocked = summary.achievements || [];
    els.achievementsGrid.innerHTML = catalog.map(a => {
      const isUnlocked = unlocked.includes(a.id);
      return `<div class="achievement-card ${isUnlocked ? 'unlocked' : 'locked'}">
        <div class="ach-name">${isUnlocked ? a.name : '???'}</div>
        <div class="ach-desc">${isUnlocked ? a.desc : 'Not yet unlocked'}</div>
      </div>`;
    }).join('');
  }
}

function toggleMiniMode() {
  state.miniMode = !state.miniMode;
  api.toggleMiniMode();
  render();
  notify(state.miniMode ? 'Mini mode' : 'Full view', 'info');
}

function selectClockTarget(timeValue) {
  const seconds = secondsUntilClockValue(timeValue);
  state.unit = 'min';
  setInputFromSeconds(seconds);
  notify(`Target selected: ${timeValue}`, 'info');
}

function applyTonightCard(card) {
  state.selectedCard = card.dataset.card || null;
  if (card.dataset.action) setAction(card.dataset.action);
  if (card.dataset.force) state.forceShutdown = card.dataset.force === 'true';
  if (card.dataset.minutes) {
    state.unit = 'min';
    setInputFromSeconds(Number(card.dataset.minutes) * 60);
  }
  notify(`Selected: ${card.querySelector('.card-title')?.textContent || 'Timer'}`, 'info');
}

function wireEvents() {
  els.btnStart.addEventListener('click', () => startTimer());
  els.btnStop.addEventListener('click', cancelTimer);
  els.btnPause.addEventListener('click', togglePause);
  els.btnSnooze.addEventListener('click', () => snooze(5 * 60));
  els.btnMinimize.addEventListener('click', () => api.minimizeWindow());
  els.btnClose.addEventListener('click', () => api.closeWindow());
  els.btnMini?.addEventListener('click', toggleMiniMode);
  els.btnWidget?.addEventListener('click', () => {
    api.toggleWidget?.();
  });

  els.btnPlus.addEventListener('click', () => {
    els.timerInput.value = inputValue() + 1;
    setInputFromSeconds(inputSeconds());
  });

  els.btnMinus.addEventListener('click', () => {
    els.timerInput.value = Math.max(1, inputValue() - 1);
    setInputFromSeconds(inputSeconds());
  });

  els.timerInput.addEventListener('input', () => {
    if (!state.running && !state.paused) {
      state.remainingSeconds = inputSeconds();
      state.totalSeconds = state.remainingSeconds;
      render();
    }
  });

  document.querySelectorAll('.unit-btn').forEach(btn => {
    btn.addEventListener('click', () => {
      if (state.running || state.paused) return;
      const seconds = inputSeconds();
      state.unit = btn.dataset.unit;
      setInputFromSeconds(seconds);
    });
  });

  document.querySelectorAll('.submenu-item').forEach(item => {
    item.addEventListener('click', event => {
      event.stopPropagation();

      if (item.dataset.action) {
        setAction(item.dataset.action);
        notify(`${actionLabel()} selected`, 'info');
        return;
      }

      if (item.dataset.minutes) {
        state.unit = 'min';
        setInputFromSeconds(Number(item.dataset.minutes) * 60);
        startTimer(Number(item.dataset.minutes) * 60);
        return;
      }

      if (item.classList.contains('toggle')) {
        if (item.id === 'toggle-dryrun') state.dryRun = !state.dryRun;
        if (item.id === 'toggle-mute') {
          state.sound = !state.sound;
          SoundSystem.enabled = state.sound;
        }
        if (item.id === 'toggle-graceful') state.gracefulClose = !state.gracefulClose;
        render();
        return;
      }

      if (item.id === 'open-options') {
        syncCustomizeUI();
        updateLastLightUIFromState();
        els.optionsModal.classList.add('active');
        return;
      }

      if (item.dataset.external) {
        api.openExternal(item.dataset.external);
        return;
      }

      if (item.dataset.help) {
        notify(item.dataset.help, 'info', 4200);
      }
    });
  });

  document.querySelectorAll('.chip').forEach(chip => {
    chip.addEventListener('click', () => {
      const minutes = Number(chip.dataset.min);
      state.unit = 'min';
      setInputFromSeconds(minutes * 60);
      startTimer(minutes * 60);
    });
  });

  document.querySelectorAll('.tab-btn').forEach(btn => {
    btn.addEventListener('click', () => {
      document.querySelectorAll('.tab-btn').forEach(tab => tab.classList.remove('active'));
      document.querySelectorAll('.tab-panel').forEach(panel => panel.classList.remove('active'));
      btn.classList.add('active');
      document.getElementById(`tab-${btn.dataset.tab}`)?.classList.add('active');
      if (btn.dataset.tab === 'streaks') loadStreaks();
    });
  });

  els.modalClose.addEventListener('click', () => els.optionsModal.classList.remove('active'));
  els.btnCancelOpt.addEventListener('click', () => els.optionsModal.classList.remove('active'));
  els.optionsModal.addEventListener('click', event => {
    if (event.target === els.optionsModal) els.optionsModal.classList.remove('active');
  });

  els.btnSaveOpt.addEventListener('click', async () => {
    state.action = els.selAction.value;
    state.graceMinutes = clamp(Number(els.graceMinutes.value) || 0, 0, 10);
    state.forceShutdown = els.chkForceShutdown.checked;
    state.muteSystem = els.chkMute.checked;
    state.dryRun = Boolean(els.chkDryRun?.checked);
    state.runAtLogin = Boolean(els.chkRunLogin?.checked);

    // Save Smart Lights config
    state.smartLights = {
      enabled: els.chkSmartLights?.checked || false,
      provider: els.selLightProvider?.value || 'none',
      mode: els.selLightMode?.value || 'gradual_dim',
      dimMinutes: clamp(Number(els.lightDimMinutes?.value) || 10, 1, 60),
      hueBridgeIp: els.hueBridgeIp?.value || '',
      hueUsername: els.hueUsername?.value || '',
      hueGroupId: els.hueGroupId?.value || '',
      httpUrl: els.httpUrl?.value || '',
      httpMethod: els.httpMethod?.value || 'POST',
      httpBodyTemplate: els.httpTemplate?.value || '{"brightness": {{BRIGHTNESS}}, "color_temp": {{COLOR_TEMP}}, "on": {{ON}}}'
    };

    state.lastLight = {
      enabled: els.chkLastLight?.checked || false,
      sequence: els.selLastLightSequence?.value || 'ClassicFade',
      sound: els.selLastLightSound?.value || 'Off'
    };

    try {
      const saved = await api.saveAppSettings({
        runAtLogin: state.runAtLogin,
        app: collectAppSettings(),
        customization: state.customization,
        lastLight: state.lastLight
      });
      if (typeof saved?.runAtLogin === 'boolean') state.runAtLogin = saved.runAtLogin;
    } catch (error) {
      notify(`Login settings failed: ${error.message || error}`, 'warning', 4500);
    }

    try {
      await api.saveSmartLightConfig(state.smartLights);
      notify('Settings saved', 'success');
    } catch (error) {
      notify(`Smart lights save failed: ${error.message || error}`, 'error');
    }

    els.optionsModal.classList.remove('active');
    setAction(state.action);
    render();
  });

  els.selAction.addEventListener('change', () => setAction(els.selAction.value));
  els.chkDryRun?.addEventListener('change', () => {
    state.dryRun = els.chkDryRun.checked;
    render();
  });

  document.querySelectorAll('.tonight-card').forEach(card => {
    card.addEventListener('click', () => applyTonightCard(card));
  });

  document.querySelectorAll('.clock-btn').forEach(btn => {
    btn.addEventListener('click', () => selectClockTarget(btn.dataset.time));
  });

  document.querySelectorAll('.cd-btn').forEach(btn => {
    btn.addEventListener('click', () => {
      const hours = Number(btn.dataset.hours);
      state.unit = 'min';
      setInputFromSeconds(hours * 3600);
      notify(`${hours} hour countdown selected`, 'info');
    });
  });

  els.scheduleCheck?.addEventListener('change', () => {
    if (els.scheduleCheck.checked) selectClockTarget(els.scheduleTime.value);
    render();
  });

  els.scheduleTime?.addEventListener('change', () => {
    if (els.scheduleCheck.checked) selectClockTarget(els.scheduleTime.value);
  });

  document.addEventListener('keydown', event => {
    if (event.target.tagName === 'INPUT' || event.target.tagName === 'SELECT') {
      if (event.key === 'Escape') event.target.blur();
      return;
    }

    if (event.key === ' ' || event.code === 'Space') {
      event.preventDefault();
      if (state.running || state.paused) togglePause();
      else startTimer();
      return;
    }

    if (event.key === 'Escape') {
      if (els.optionsModal.classList.contains('active')) {
        els.optionsModal.classList.remove('active');
      } else if (state.running || state.paused) {
        cancelTimer();
      }
      return;
    }

    const presets = { '1': 5, '2': 10, '3': 15, '4': 30, '5': 60, '6': 120 };
    if (presets[event.key] && !state.running && !state.paused) {
      state.unit = 'min';
      setInputFromSeconds(presets[event.key] * 60);
      startTimer(presets[event.key] * 60);
      return;
    }

    if (event.ctrlKey || event.metaKey) {
      switch (event.key.toLowerCase()) {
        case 'm':
          event.preventDefault();
          toggleMiniMode();
          break;
        case 'q':
          event.preventDefault();
          api.quitApp();
          break;
        case '0':
          event.preventDefault();
          api.closeWindow();
          break;
      }
      return;
    }

    if (event.key === 'ArrowUp') {
      event.preventDefault();
      els.btnPlus.click();
    } else if (event.key === 'ArrowDown') {
      event.preventDefault();
      els.btnMinus.click();
    }
  });

  document.addEventListener('contextmenu', event => {
    if (!previewMode) event.preventDefault();
  });

  // Smart Lights event handlers
  if (els.chkSmartLights) {
    els.chkSmartLights.addEventListener('change', () => {
      state.smartLights.enabled = els.chkSmartLights.checked;
      updateLightsUI();
    });
  }

  if (els.selLightProvider) {
    els.selLightProvider.addEventListener('change', () => {
      state.smartLights.provider = els.selLightProvider.value;
      updateLightsUI();
    });
  }

  if (els.btnDiscoverHue) {
    els.btnDiscoverHue.addEventListener('click', async () => {
      try {
        const result = await api.discoverHueBridge();
        if (result?.ip) {
          els.hueBridgeIp.value = result.ip;
          state.smartLights.hueBridgeIp = result.ip;
          notify(`Found Hue Bridge at ${result.ip}`, 'success');
        } else {
          notify('No Hue Bridge found on network', 'warning');
        }
      } catch (error) {
        notify(`Discovery failed: ${error.message}`, 'error');
      }
    });
  }

  if (els.btnRegisterHue) {
    els.btnRegisterHue.addEventListener('click', async () => {
      const bridgeIp = els.hueBridgeIp.value;
      if (!bridgeIp) {
        notify('Enter Bridge IP first', 'warning');
        return;
      }
      try {
        notify('Press link button on Hue Bridge now...', 'info', 3000);
        const result = await api.registerHueBridge(bridgeIp);
        if (result?.username) {
          els.hueUsername.value = result.username;
          state.smartLights.hueUsername = result.username;
          notify('Registered successfully!', 'success');
        } else if (result?.error) {
          notify(`Registration failed: ${result.error}`, 'error');
        }
      } catch (error) {
        notify(`Registration failed: ${error.message}`, 'error');
      }
    });
  }

  if (els.btnTestLights) {
    els.btnTestLights.addEventListener('click', async () => {
      // Save current config first
      const testConfig = {
        enabled: true,
        provider: els.selLightProvider.value,
        mode: els.selLightMode.value,
        dimMinutes: Number(els.lightDimMinutes.value) || 10,
        hueBridgeIp: els.hueBridgeIp.value,
        hueUsername: els.hueUsername.value,
        hueGroupId: els.hueGroupId.value,
        httpUrl: els.httpUrl.value,
        httpMethod: els.httpMethod.value,
        httpBodyTemplate: els.httpTemplate.value
      };
      
      try {
        await api.saveSmartLightConfig(testConfig);
        const result = await api.testSmartLightConnection();
        if (els.lightTestResult) {
          els.lightTestResult.textContent = result.message;
          els.lightTestResult.className = result.success ? 'success' : 'error';
        }
        notify(result.message, result.success ? 'success' : 'warning');
      } catch (error) {
        notify(`Test failed: ${error.message}`, 'error');
      }
    });
  }

  // Profiles event handlers
  if (els.btnManageProfiles) {
    els.btnManageProfiles.addEventListener('click', () => {
      openProfilesModal();
    });
  }

  if (els.profilesModalClose) {
    els.profilesModalClose.addEventListener('click', closeProfilesModal);
  }

  if (els.btnCloseProfiles) {
    els.btnCloseProfiles.addEventListener('click', closeProfilesModal);
  }

  if (els.profilesModal) {
    els.profilesModal.addEventListener('click', event => {
      if (event.target === els.profilesModal) closeProfilesModal();
    });
  }

  if (els.btnSaveProfile) {
    els.btnSaveProfile.addEventListener('click', saveNewProfile);
  }

  if (els.btnExportProfiles) {
    els.btnExportProfiles.addEventListener('click', exportProfiles);
  }

  if (els.btnImportProfiles) {
    els.btnImportProfiles.addEventListener('click', () => {
      if (els.importFileInput) els.importFileInput.click();
    });
  }

  if (els.importFileInput) {
    els.importFileInput.addEventListener('change', importProfiles);
  }

  // All-data export/import
  els.btnExportAllData?.addEventListener('click', async () => {
    const result = await api.exportAllData();
    if (result.success && result.data) {
      const blob = new Blob([JSON.stringify(result.data, null, 2)], { type: 'application/json' });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = `lights-out-backup-${new Date().toISOString().slice(0, 10)}.json`;
      a.click();
      URL.revokeObjectURL(url);
      notify('Data exported successfully', 'success');
    } else {
      notify('Export failed: ' + (result.error || 'Unknown error'), 'error');
    }
  });
  els.btnImportAllData?.addEventListener('click', () => {
    els.importAllDataInput?.click();
  });
  els.importAllDataInput?.addEventListener('change', async (e) => {
    const file = e.target.files?.[0];
    if (!file) return;
    try {
      const text = await file.text();
      const result = await api.importAllData(text);
      if (result.success) {
        notify('Data imported successfully. Restart to see all changes.', 'success');
      } else {
        notify('Import failed: ' + (result.error || 'Unknown error'), 'error');
      }
    } catch (err) {
      notify('Import error: ' + err.message, 'error');
    }
    e.target.value = '';
  });

  // Keyboard shortcuts for profiles (Ctrl+1, Ctrl+2, etc.)
  document.addEventListener('keydown', event => {
    if (event.ctrlKey && /^[1-9]$/.test(event.key)) {
      const index = parseInt(event.key, 10) - 1;
      const profile = state.profiles[index];
      if (profile) {
        event.preventDefault();
        applyProfile(profile.id);
      }
    }
  });

  // Calendar event handlers
  // Import tab switching
  els.importTabBtns?.forEach(btn => {
    btn.addEventListener('click', () => {
      const tab = btn.dataset.importTab;
      els.importTabBtns.forEach(b => b.classList.remove('active'));
      btn.classList.add('active');
      els.importPanels.forEach(p => p.classList.remove('active'));
      document.getElementById(`import-${tab}-panel`)?.classList.add('active');
    });
  });

  // File import
  if (els.btnImportFile) {
    els.btnImportFile.addEventListener('click', () => {
      els.calendarFileInput?.click();
    });
  }

  if (els.calendarFileInput) {
    els.calendarFileInput.addEventListener('change', importCalendarFile);
  }

  // URL import
  if (els.btnImportUrl) {
    els.btnImportUrl.addEventListener('click', importCalendarUrl);
  }
}

function updateLightsUI() {
  if (els.lightsConfig) {
    els.lightsConfig.style.display = state.smartLights.enabled ? 'block' : 'none';
  }
  if (els.hueConfig) {
    els.hueConfig.style.display = state.smartLights.provider === 'hue' ? 'block' : 'none';
  }
  if (els.httpConfig) {
    els.httpConfig.style.display = state.smartLights.provider === 'http' ? 'block' : 'none';
  }
}

async function loadInitialData() {
  try {
    const [systemInfo, appSettings, lightConfig] = await Promise.all([
      api.getSystemInfo(),
      api.getAppSettings(),
      api.getSmartLightConfig()
    ]);

    // Load profiles
    await loadProfiles();

    // Load streaks data
    loadStreaks();

    els.batteryLevel.textContent = systemInfo.battery === 'N/A' ? 'N/A' : `${systemInfo.battery}%`;
    els.powerPlan.textContent = systemInfo.powerPlan || 'Unknown';

    if (typeof appSettings.runAtLogin === 'boolean') {
      state.runAtLogin = appSettings.runAtLogin;
    }

    // Rehydrate persisted app settings
    if (appSettings.app) applyAppSettings(appSettings.app);

    // Rehydrate persisted customization
    if (appSettings.customization) {
      state.customization = { ...state.customization, ...appSettings.customization };
    }
    applyCustomization(state.customization);

    // Rehydrate Last Light config
    if (appSettings.lastLight) {
      state.lastLight = { ...state.lastLight, ...appSettings.lastLight };
    }
    updateLastLightUIFromState();

    // Offer recovery of an interrupted timer
    if (appSettings.recoverableTimer) {
      promptTimerRecovery(appSettings.recoverableTimer);
    }

    // Load Smart Lights config
    if (lightConfig) {
      state.smartLights = {
        enabled: lightConfig.enabled || false,
        provider: lightConfig.provider || 'none',
        mode: lightConfig.mode || 'gradual_dim',
        dimMinutes: lightConfig.dimMinutes || 10,
        hueBridgeIp: lightConfig.hueBridgeIp || '',
        hueUsername: lightConfig.hueUsername || '',
        hueGroupId: lightConfig.hueGroupId || '',
        httpUrl: lightConfig.httpUrl || '',
        httpMethod: lightConfig.httpMethod || 'POST',
        httpBodyTemplate: lightConfig.httpBodyTemplate || '{"brightness": {{BRIGHTNESS}}, "color_temp": {{COLOR_TEMP}}, "on": {{ON}}}'
      };
      updateLightsUIFromState();
    }
  } catch {
    els.batteryLevel.textContent = 'N/A';
    els.powerPlan.textContent = previewMode ? 'Preview' : 'Unknown';
  }
}

function collectAppSettings() {
  const blocklistStr = els.focusBlocklist?.value?.trim() || '';
  const focusBlocklist = blocklistStr ? blocklistStr.split(',').map(s => s.trim()).filter(Boolean) : [];
  return {
    action: state.action,
    unit: state.unit,
    durationSeconds: state.remainingSeconds,
    sound: state.sound,
    gracefulClose: state.gracefulClose,
    forceShutdown: state.forceShutdown,
    muteSystem: state.muteSystem,
    graceMinutes: state.graceMinutes,
    dryRun: state.dryRun,
    focusBlocklist
  };
}

function applyAppSettings(app) {
  if (!app) return;
  if (app.action) state.action = app.action;
  if (app.unit) state.unit = app.unit;
  if (typeof app.sound === 'boolean') { state.sound = app.sound; SoundSystem.enabled = app.sound; }
  if (typeof app.gracefulClose === 'boolean') state.gracefulClose = app.gracefulClose;
  if (typeof app.forceShutdown === 'boolean') state.forceShutdown = app.forceShutdown;
  if (typeof app.muteSystem === 'boolean') state.muteSystem = app.muteSystem;
  if (Number.isFinite(Number(app.graceMinutes))) state.graceMinutes = Number(app.graceMinutes);
  if (typeof app.dryRun === 'boolean') state.dryRun = app.dryRun;
  if (Array.isArray(app.focusBlocklist)) {
    if (els.focusBlocklist) els.focusBlocklist.value = app.focusBlocklist.join(',');
  }
  if (Number.isFinite(Number(app.durationSeconds)) && Number(app.durationSeconds) > 0 && !state.running) {
    state.remainingSeconds = Number(app.durationSeconds);
    setInputFromSeconds(state.remainingSeconds);
  }
  setAction(state.action);
}

function applyCustomization(c) {
  if (!c) return;
  const root = document.documentElement;
  if (c.accent) {
    root.style.setProperty('--accent', c.accent);
    root.style.setProperty('--accent-cyan', c.accent);
    root.style.setProperty('--accent-blue', c.accent);
    root.style.setProperty('--ring-fill', c.accent);
    root.style.setProperty('--accent-glow', hexToRgba(c.accent, 0.45));
  }
  if (c.theme) document.body.dataset.theme = c.theme;
  if (c.ringStyle) document.body.dataset.ring = c.ringStyle;
  if (Number.isFinite(Number(c.opacity))) {
    const op = clamp(Number(c.opacity), 0.5, 1);
    if (previewMode) {
      root.style.setProperty('--app-opacity', op);
    } else {
      api.setWindowOpacity(op);
    }
  }
  if (Number.isFinite(Number(c.volume))) {
    SoundSystem.master = clamp(Number(c.volume), 0, 1);
  }
}

function hexToRgba(hex, alpha) {
  const m = /^#?([a-f\d]{2})([a-f\d]{2})([a-f\d]{2})$/i.exec(String(hex).trim());
  if (!m) return `rgba(91, 140, 255, ${alpha})`;
  return `rgba(${parseInt(m[1], 16)}, ${parseInt(m[2], 16)}, ${parseInt(m[3], 16)}, ${alpha})`;
}

const CUSTOMIZE_DEFAULTS = { accent: '#5b8cff', theme: 'midnight', ringStyle: 'glow', opacity: 1, volume: 1, warmShift: true, soundscape: 'off' };

function syncCustomizeUI() {
  const c = state.customization;
  if (els.czAccent) els.czAccent.value = c.accent;
  if (els.czTheme) els.czTheme.value = c.theme;
  if (els.czRing) els.czRing.value = c.ringStyle;
  if (els.czOpacity) els.czOpacity.value = c.opacity;
  if (els.czOpacityVal) els.czOpacityVal.textContent = `${Math.round(c.opacity * 100)}%`;
  if (els.czVolume) els.czVolume.value = c.volume;
  if (els.czVolumeVal) els.czVolumeVal.textContent = `${Math.round(c.volume * 100)}%`;
  if (els.czWarmShift) els.czWarmShift.checked = c.warmShift !== false;
  if (els.czSoundscape) els.czSoundscape.value = c.soundscape || 'off';
  if (els.czSwatches) {
    els.czSwatches.querySelectorAll('.swatch').forEach(sw => {
      sw.classList.toggle('active', sw.dataset.color.toLowerCase() === c.accent.toLowerCase());
    });
  }
  renderCustomSequences();
}

function setupCustomizeHandlers() {
  els.czAccent?.addEventListener('input', () => {
    state.customization.accent = els.czAccent.value;
    applyCustomization(state.customization);
    syncCustomizeUI();
  });
  els.czSwatches?.querySelectorAll('.swatch').forEach(sw => {
    sw.addEventListener('click', () => {
      state.customization.accent = sw.dataset.color;
      applyCustomization(state.customization);
      syncCustomizeUI();
    });
  });
  els.czTheme?.addEventListener('change', () => {
    state.customization.theme = els.czTheme.value;
    applyCustomization(state.customization);
  });
  els.czRing?.addEventListener('change', () => {
    state.customization.ringStyle = els.czRing.value;
    applyCustomization(state.customization);
  });
  els.czOpacity?.addEventListener('input', () => {
    state.customization.opacity = Number(els.czOpacity.value);
    applyCustomization(state.customization);
    if (els.czOpacityVal) els.czOpacityVal.textContent = `${Math.round(state.customization.opacity * 100)}%`;
  });
  els.czVolume?.addEventListener('input', () => {
    state.customization.volume = Number(els.czVolume.value);
    applyCustomization(state.customization);
    if (els.czVolumeVal) els.czVolumeVal.textContent = `${Math.round(state.customization.volume * 100)}%`;
  });
  els.btnResetCustomize?.addEventListener('click', () => {
    state.customization = { ...CUSTOMIZE_DEFAULTS };
    applyCustomization(state.customization);
    syncCustomizeUI();
    Soundscape.stop();
  });
  els.czWarmShift?.addEventListener('change', () => {
    state.customization.warmShift = els.czWarmShift.checked;
  });
  els.czSoundscape?.addEventListener('change', () => {
    state.customization.soundscape = els.czSoundscape.value;
    if (state.running) Soundscape.start(els.czSoundscape.value);
    else Soundscape.stop();
  });
}

function showWarningModal(message) {
  if (!els.warningModal) return;
  if (els.warningModalText) els.warningModalText.textContent = message;
  els.warningModal.classList.add('active');
}

function hideWarningModal() {
  els.warningModal?.classList.remove('active');
}

// Warm shift filter: applies a sepia/amber tint to the cockpit UI during the
// dim phase to simulate a blue-light reduction.  In Electron the main process
// also enables the Windows Night Light registry key; this CSS filter is the
// in-app complement.
function applyWarmFilter() {
  if (state.customization.warmShift === false) return;
  document.body.classList.add('warm-shift');
}

function removeWarmFilter() {
  document.body.classList.remove('warm-shift');
}

function setupWarningHandlers() {
  els.warningSnooze?.addEventListener('click', () => {
    snooze(5 * 60);
    hideWarningModal();
  });
  els.warningCancel?.addEventListener('click', () => {
    cancelTimer();
    hideWarningModal();
  });
  els.warningDismiss?.addEventListener('click', hideWarningModal);
  els.warningModal?.addEventListener('click', event => {
    if (event.target === els.warningModal) hideWarningModal();
  });
}

// Wake-up alarm handlers
function setupAlarmHandlers() {
  els.chkAlarm?.addEventListener('change', () => {
    if (els.alarmConfig) els.alarmConfig.style.display = els.chkAlarm.checked ? 'block' : 'none';
  });

  els.btnSetAlarm?.addEventListener('click', async () => {
    const time = els.alarmTime?.value;
    if (!time) return;
    const result = await api.scheduleWakeAlarm(time);
    if (result.success) {
      notify(`Wake alarm set for ${time}`, 'success');
      refreshAlarmStatus();
    } else {
      notify(`Alarm failed: ${result.error}`, 'error');
    }
  });

  els.btnRemoveAlarm?.addEventListener('click', async () => {
    await api.removeWakeAlarm();
    notify('Wake alarm removed', 'info');
    refreshAlarmStatus();
  });

  // Sunrise alarm visual feedback.
  api.onSunriseAlarmStarted?.(() => {
    notify('Sunrise alarm started', 'success');
    document.body.classList.add('sunrise-alarm');
  });
  api.onSunriseAlarmTick?.((data) => {
    // Gradually warm the UI during sunrise.
    const warmth = Math.round(data.progress * 20);
    document.body.style.filter = `sepia(${warmth}%) brightness(${0.6 + data.progress * 0.4})`;
  });
  api.onSunriseAlarmEnded?.(() => {
    document.body.classList.remove('sunrise-alarm');
    document.body.style.filter = '';
    notify('Good morning!', 'success', 5000);
  });

  refreshAlarmStatus();
}

async function refreshAlarmStatus() {
  try {
    const status = await api.getWakeAlarmStatus();
    if (els.alarmStatus) {
      if (status.active) {
        els.alarmStatus.textContent = `Alarm set for ${status.alarmTime || 'scheduled'}`;
        els.alarmStatus.style.color = 'var(--accent-green)';
      } else {
        els.alarmStatus.textContent = 'No alarm scheduled';
        els.alarmStatus.style.color = 'var(--text-muted)';
      }
    }
  } catch {}
}

function updateLastLightUIFromState() {
  if (els.chkLastLight) els.chkLastLight.checked = state.lastLight.enabled;
  if (els.selLastLightSequence) els.selLastLightSequence.value = state.lastLight.sequence;
  if (els.selLastLightSound) els.selLastLightSound.value = state.lastLight.sound;
  if (els.lastLightConfig) els.lastLightConfig.style.display = state.lastLight.enabled ? 'block' : 'none';
}

function setupLastLightHandlers() {
  els.chkLastLight?.addEventListener('change', () => {
    if (els.lastLightConfig) els.lastLightConfig.style.display = els.chkLastLight.checked ? 'block' : 'none';
  });
  els.btnPreviewLastLight?.addEventListener('click', () => {
    playLastLight({
      sequence: els.selLastLightSequence?.value || 'ClassicFade',
      sound: els.selLastLightSound?.value || 'Off',
      dryRun: true
    });
  });

  // Custom sequence builder.
  els.btnAddCustomSeq?.addEventListener('click', () => {
    if (els.customSeqBuilder) els.customSeqBuilder.style.display = 'block';
    if (els.customSeqName) els.customSeqName.value = '';
    if (els.customSeqSteps) {
      els.customSeqSteps.innerHTML = makeStepRow();
    }
  });
  els.btnCancelCustomSeq?.addEventListener('click', () => {
    if (els.customSeqBuilder) els.customSeqBuilder.style.display = 'none';
  });
  els.btnAddStep?.addEventListener('click', () => {
    if (els.customSeqSteps) els.customSeqSteps.insertAdjacentHTML('beforeend', makeStepRow());
  });
  els.btnSaveCustomSeq?.addEventListener('click', async () => {
    const name = els.customSeqName?.value?.trim();
    if (!name) return;
    const rows = els.customSeqSteps?.querySelectorAll('.seq-step-row') || [];
    const steps = [];
    rows.forEach(row => {
      const headline = row.querySelector('.seq-headline')?.value?.trim() || '';
      const line = row.querySelector('.seq-line')?.value?.trim() || '';
      const dwellMs = parseInt(row.querySelector('.seq-dwell')?.value) || 1500;
      if (line || headline) steps.push({ headline, line, dwellMs });
    });
    if (!steps.length) return;
    const entry = await api.addCustomSequence({ name, steps });
    if (entry) {
      if (els.customSeqBuilder) els.customSeqBuilder.style.display = 'none';
      renderCustomSequences();
      // Add to sequence selector.
      const opt = document.createElement('option');
      opt.value = entry.id;
      opt.textContent = entry.name + ' *';
      els.selLastLightSequence?.appendChild(opt);
    }
  });
}

function makeStepRow() {
  return `<div class="seq-step-row">
    <input type="text" placeholder="Headline" class="seq-headline" maxlength="40">
    <input type="text" placeholder="Line" class="seq-line" maxlength="80">
    <input type="number" placeholder="ms" class="seq-dwell" value="1500" min="200" max="5000" style="width:60px">
  </div>`;
}

async function renderCustomSequences() {
  if (!els.customSeqList) return;
  const LL = (typeof window !== 'undefined' && window.LastLight) ? window.LastLight : null;
  let customs = [];
  if (LL?.getCustomSequences) customs = LL.getCustomSequences();
  // In Electron mode, the catalog from IPC includes custom entries.
  // For preview mode, just use what's in the LL module.
  if (!customs.length && api.getStreaks) {
    // Try loading from settings via app-settings.
    try {
      const settings = await api.getAppSettings();
      customs = settings?.lastLight?.customSequences || [];
    } catch {}
  }
  els.customSeqList.innerHTML = customs.length
    ? customs.map(s => `<div class="custom-seq-item">
        <span class="seq-item-name">${s.name}</span>
        <button class="seq-item-share" data-id="${s.id}" title="Share (copy JSON)">&#x1F517;</button>
        <button class="seq-item-delete" data-id="${s.id}" title="Delete">&times;</button>
      </div>`).join('')
    : '<span style="color:var(--text-muted);font-size:11px">No custom sequences yet.</span>';
  els.customSeqList.querySelectorAll('.seq-item-delete').forEach(btn => {
    btn.addEventListener('click', async () => {
      await api.removeCustomSequence(btn.dataset.id);
      const opt = els.selLastLightSequence?.querySelector(`option[value="${btn.dataset.id}"]`);
      if (opt) opt.remove();
      renderCustomSequences();
    });
  });
  els.customSeqList.querySelectorAll('.seq-item-share').forEach(btn => {
    btn.addEventListener('click', () => {
      const seq = customs.find(s => s.id === btn.dataset.id);
      if (!seq) return;
      const json = JSON.stringify({ lightsOutSequence: seq }, null, 2);
      navigator.clipboard.writeText(json).then(() => {
        notify('Sequence JSON copied to clipboard', 'success');
      }).catch(() => {
        // Fallback: open a small text area.
        notify('Copy failed - check console', 'warning');
        console.log(json);
      });
    });
  });
}

let lastLightTimers = [];

function clearLastLightTimers() {
  lastLightTimers.forEach(t => clearTimeout(t));
  lastLightTimers = [];
}

function playLastLight(payload) {
  const LL = (typeof window !== 'undefined' && window.LastLight) ? window.LastLight : null;
  if (!LL || !els.lastLightOverlay) return;

  const sequence = LL.normalizeId(payload && payload.sequence);
  const dryRun = Boolean(payload && payload.dryRun);
  const soundMode = LL.normalizeSoundId(payload && payload.sound);
  const steps = LL.getSteps(sequence, dryRun);
  const meta = LL.getMeta(sequence, dryRun);

  clearLastLightTimers();
  els.llTitle.textContent = meta.sequenceLabel || meta.cinematicTitle;
  els.lastLightOverlay.classList.add('active');
  els.lastLightOverlay.setAttribute('aria-hidden', 'false');

  let elapsed = 0;
  steps.forEach(step => {
    lastLightTimers.push(setTimeout(() => {
      els.llHeadline.textContent = step.headline || '';
      els.llLine.textContent = step.line || '';
      els.llStamp.textContent = '';
      if (soundMode === 'Soft') {
        SoundSystem.playTone(880, 0.08, 'sine', 0.1);
        setTimeout(() => SoundSystem.playTone(660, 0.12, 'sine', 0.08), 120);
      }
    }, elapsed));
    elapsed += Number(step.dwellMs || 0);
  });

  // Final stamp, then fade out.
  lastLightTimers.push(setTimeout(() => {
    els.llStamp.textContent = meta.stampLine || '';
  }, Math.max(0, elapsed - 600)));

  lastLightTimers.push(setTimeout(() => {
    els.lastLightOverlay.classList.remove('active');
    els.lastLightOverlay.setAttribute('aria-hidden', 'true');
  }, elapsed + 250));
}

function promptTimerRecovery(snapshot) {
  const mins = Math.ceil((snapshot.remainingSeconds || 0) / 60);
  const label = `${actionLabel(snapshot.action)} timer was interrupted with ~${mins}m left.`;
  const banner = document.createElement('div');
  banner.className = 'recovery-banner';
  banner.innerHTML = `
    <span class="recovery-text">${label}</span>
    <button class="recovery-btn resume">Resume</button>
    <button class="recovery-btn dismiss">Dismiss</button>
  `;
  banner.querySelector('.resume').addEventListener('click', async () => {
    const res = await api.resumeRecoverableTimer();
    if (res?.success) notify('Timer resumed', 'success');
    banner.remove();
  });
  banner.querySelector('.dismiss').addEventListener('click', async () => {
    await api.discardRecoverableTimer();
    banner.remove();
  });
  document.body.appendChild(banner);
}

function updateLightsUIFromState() {
  if (els.chkSmartLights) els.chkSmartLights.checked = state.smartLights.enabled;
  if (els.selLightProvider) els.selLightProvider.value = state.smartLights.provider;
  if (els.selLightMode) els.selLightMode.value = state.smartLights.mode;
  if (els.lightDimMinutes) els.lightDimMinutes.value = state.smartLights.dimMinutes;
  if (els.hueBridgeIp) els.hueBridgeIp.value = state.smartLights.hueBridgeIp;
  if (els.hueUsername) els.hueUsername.value = state.smartLights.hueUsername;
  if (els.hueGroupId) els.hueGroupId.value = state.smartLights.hueGroupId;
  if (els.httpUrl) els.httpUrl.value = state.smartLights.httpUrl;
  if (els.httpMethod) els.httpMethod.value = state.smartLights.httpMethod;
  if (els.httpTemplate) els.httpTemplate.value = state.smartLights.httpBodyTemplate;
  updateLightsUI();
}

// ─────────────────────────────────────────────────────────────────────────────
// Profile Functions
// ─────────────────────────────────────────────────────────────────────────────

async function loadProfiles() {
  try {
    const profiles = await api.getAllProfiles();
    state.profiles = profiles || [];
    renderProfiles();
    return profiles;
  } catch (error) {
    console.error('Failed to load profiles:', error);
    return [];
  }
}

function renderProfiles() {
  if (!els.profilesGrid) return;

  if (state.profiles.length === 0) {
    els.profilesGrid.innerHTML = '<div class="empty-profiles">No saved profiles yet. Click the gear to create one.</div>';
    return;
  }

  els.profilesGrid.innerHTML = state.profiles.map((profile, index) => {
    const isActive = state.currentProfileId === profile.id;
    const hint = getProfileHint(profile);
    return `
      <div class="profile-card ${isActive ? 'active' : ''}" data-profile-id="${profile.id}" title="Ctrl+${index + 1} to quick-load">
        <div class="profile-name">${escapeHtml(profile.name)}</div>
        <div class="profile-hint">${escapeHtml(hint)}</div>
      </div>
    `;
  }).join('');

  // Add click handlers
  els.profilesGrid.querySelectorAll('.profile-card').forEach(card => {
    card.addEventListener('click', () => {
      const profileId = card.dataset.profileId;
      applyProfile(profileId);
    });
  });
}

function getProfileHint(profile) {
  if (!profile) return '';
  const action = profile.action.charAt(0).toUpperCase() + profile.action.slice(1);
  
  if (profile.mode === 'clock') {
    return `${action} at ${profile.clock}`;
  }
  
  const minutes = Math.ceil(profile.seconds / 60);
  return `${action} in ${minutes}m`;
}

function escapeHtml(text) {
  const div = document.createElement('div');
  div.textContent = text;
  return div.innerHTML;
}

async function applyProfile(profileId) {
  try {
    const result = await api.applyProfile(profileId);
    if (!result.success) {
      notify(result.error || 'Failed to apply profile', 'error');
      return;
    }

    state.currentProfileId = profileId;
    
    // Apply timer options from profile
    if (result.timerOptions) {
      state.action = result.timerOptions.action || state.action;
      state.dryRun = result.timerOptions.dryRun || false;
      state.forceShutdown = result.timerOptions.forceShutdown || false;
      state.muteSystem = result.timerOptions.muteSystem || false;
      state.graceMinutes = result.timerOptions.gracePeriod || 2;

      // Apply Last Light from profile
      if (result.timerOptions.lastLightEnabled !== undefined) {
        state.lastLight.enabled = result.timerOptions.lastLightEnabled;
        if (result.timerOptions.lastLightSequence) state.lastLight.sequence = result.timerOptions.lastLightSequence;
        if (result.timerOptions.lastLightSound) state.lastLight.sound = result.timerOptions.lastLightSound;
      }

      setInputFromSeconds(result.timerOptions.durationSeconds || 1800);
      setAction(state.action);
    }

    renderProfiles();
    notify(`Profile "${result.profile.name}" loaded`, 'success');

    // Auto-start if configured
    if (result.autoStart && !state.running && !state.paused) {
      startTimer(result.timerOptions.durationSeconds);
    }
  } catch (error) {
    notify(`Failed to apply profile: ${error.message}`, 'error');
  }
}

function openProfilesModal() {
  if (!els.profilesModal) return;
  els.profilesModal.classList.add('active');
  renderProfilesList();
}

function closeProfilesModal() {
  if (!els.profilesModal) return;
  els.profilesModal.classList.remove('active');
}

function renderProfilesList() {
  if (!els.profilesList) return;

  if (state.profiles.length === 0) {
    els.profilesList.innerHTML = '<div class="empty-profiles">No profiles yet. Create your first one above!</div>';
    return;
  }

  els.profilesList.innerHTML = state.profiles.map((profile, idx) => {
    const hint = getProfileHint(profile);
    return `
      <div class="profile-item" data-profile-id="${profile.id}">
        <div class="profile-item-info">
          <input type="text" class="profile-item-name-input" value="${escapeHtml(profile.name)}" data-profile-id="${profile.id}" maxlength="32" spellcheck="false">
          <div class="profile-item-hint">${escapeHtml(hint)}</div>
        </div>
        <div class="profile-item-actions">
          <button class="profile-item-btn move-btn" data-action="up" data-idx="${idx}" title="Move up" ${idx === 0 ? 'disabled' : ''}>&#9650;</button>
          <button class="profile-item-btn move-btn" data-action="down" data-idx="${idx}" title="Move down" ${idx === state.profiles.length - 1 ? 'disabled' : ''}>&#9660;</button>
          <button class="profile-item-btn load-btn" data-action="load">Load</button>
          <button class="profile-item-btn delete-btn" data-action="delete">Delete</button>
        </div>
      </div>
    `;
  }).join('');

  // Rename handler (save on blur/enter).
  els.profilesList.querySelectorAll('.profile-item-name-input').forEach(input => {
    input.addEventListener('change', async () => {
      const newName = input.value.trim();
      const profileId = input.dataset.profileId;
      if (!newName || !profileId) return;
      await api.updateProfile(profileId, { name: newName });
      await loadProfiles();
      renderProfiles();
      renderProfilesList();
    });
    input.addEventListener('keydown', (e) => {
      if (e.key === 'Enter') input.blur();
    });
  });

  // Add event handlers
  els.profilesList.querySelectorAll('.profile-item-btn').forEach(btn => {
    btn.addEventListener('click', async (e) => {
      e.stopPropagation();
      const profileId = btn.closest('.profile-item').dataset.profileId;
      const action = btn.dataset.action;

      if (action === 'load') {
        await applyProfile(profileId);
        closeProfilesModal();
      } else if (action === 'delete') {
        await deleteProfile(profileId);
      } else if (action === 'up' || action === 'down') {
        const idx = parseInt(btn.dataset.idx);
        const newIdx = action === 'up' ? idx - 1 : idx + 1;
        if (newIdx < 0 || newIdx >= state.profiles.length) return;
        const ids = state.profiles.map(p => p.id);
        [ids[idx], ids[newIdx]] = [ids[newIdx], ids[idx]];
        await api.reorderProfiles(ids);
        await loadProfiles();
        renderProfiles();
        renderProfilesList();
      }
    });
  });
}

async function saveNewProfile() {
  if (!els.newProfileName) return;

  const name = els.newProfileName.value.trim();
  if (!name) {
    notify('Enter a profile name', 'warning');
    return;
  }

  const profileData = {
    name: name,
    action: state.action,
    mode: 'duration',
    seconds: inputSeconds(),
    autoStart: els.newProfileAutostart?.checked ?? true,
    dryRun: state.dryRun,
    forceShutdown: state.forceShutdown,
    muteSystem: state.muteSystem,
    gracePeriod: state.graceMinutes,
    smartLightsEnabled: state.smartLights.enabled,
    smartLightsMode: state.smartLights.mode
  };

  try {
    const result = await api.createProfile(profileData);
    if (result.success) {
      notify(`Profile "${result.profile.name}" ${result.action === 'created' ? 'created' : 'updated'}`, 'success');
      els.newProfileName.value = '';
      await loadProfiles();
      renderProfilesList();
    } else {
      notify(result.error || 'Failed to save profile', 'error');
    }
  } catch (error) {
    notify(`Failed to save profile: ${error.message}`, 'error');
  }
}

async function deleteProfile(profileId) {
  if (!confirm('Delete this profile?')) return;

  try {
    const result = await api.deleteProfile(profileId);
    if (result.success) {
      notify('Profile deleted', 'success');
      if (state.currentProfileId === profileId) {
        state.currentProfileId = null;
      }
      await loadProfiles();
      renderProfiles();
      renderProfilesList();
    } else {
      notify(result.error || 'Failed to delete profile', 'error');
    }
  } catch (error) {
    notify(`Failed to delete profile: ${error.message}`, 'error');
  }
}

async function exportProfiles() {
  try {
    const json = await api.exportProfiles();
    const blob = new Blob([json], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `lights-out-profiles-${new Date().toISOString().split('T')[0]}.json`;
    a.click();
    URL.revokeObjectURL(url);
    notify('Profiles exported', 'success');
  } catch (error) {
    notify(`Export failed: ${error.message}`, 'error');
  }
}

async function importProfiles(event) {
  const file = event.target.files?.[0];
  if (!file) return;

  try {
    const text = await file.text();
    const result = await api.importProfiles(text);
    if (result.success) {
      notify(`${result.count} profiles imported`, 'success');
      await loadProfiles();
      renderProfiles();
      renderProfilesList();
    } else {
      notify(result.error || 'Import failed', 'error');
    }
  } catch (error) {
    notify(`Import failed: ${error.message}`, 'error');
  }

  // Reset file input
  event.target.value = '';
}

// ─────────────────────────────────────────────────────────────────────────────
// Calendar Functions
// ─────────────────────────────────────────────────────────────────────────────

async function importCalendarFile(event) {
  const file = event.target.files?.[0];
  if (!file) return;

  if (!file.name.endsWith('.ics')) {
    notify('Please select an .ics calendar file', 'warning');
    return;
  }

  showCalendarLoading();

  try {
    const text = await file.text();
    const result = await api.calendarParseText(text);

    if (result.success) {
      state.calendarEvents = result.events || [];
      state.calendarSource = result.source || file.name;
      notify(`${result.count} events imported from ${file.name}`, 'success');
      renderCalendarEvents();
    } else {
      notify(result.error || 'Failed to import calendar', 'error');
      showCalendarError(result.error || 'Import failed');
    }
  } catch (error) {
    notify(`Import failed: ${error.message}`, 'error');
    showCalendarError(error.message);
  }

  // Reset file input
  event.target.value = '';
}

async function importCalendarUrl() {
  const url = els.calendarUrlInput?.value?.trim();
  if (!url) {
    notify('Enter a calendar URL', 'warning');
    return;
  }

  const isValid = await api.calendarTestUrl(url);
  if (!isValid) {
    notify('URL must start with https://', 'warning');
    return;
  }

  showCalendarLoading();

  try {
    const result = await api.calendarImportUrl(url);

    if (result.success) {
      state.calendarEvents = result.events || [];
      state.calendarSource = result.source || url;
      notify(`${result.count} events imported from calendar`, 'success');
      renderCalendarEvents();
      if (els.calendarUrlInput) els.calendarUrlInput.value = '';
    } else {
      notify(result.error || 'Failed to fetch calendar', 'error');
      showCalendarError(result.error || 'Fetch failed');
    }
  } catch (error) {
    notify(`Import failed: ${error.message}`, 'error');
    showCalendarError(error.message);
  }
}

function renderCalendarEvents() {
  if (!els.calendarEvents) return;

  if (state.calendarEvents.length === 0) {
    els.calendarEvents.innerHTML = '<div class="calendar-empty">Import a calendar to see upcoming events</div>';
    return;
  }

  // Filter to upcoming events only (next 90 days)
  const now = new Date();
  const upcoming = state.calendarEvents.filter(e => {
    if (!e.start) return false;
    const start = new Date(e.start);
    return start > now;
  }).slice(0, 10); // Show first 10

  if (upcoming.length === 0) {
    els.calendarEvents.innerHTML = '<div class="calendar-empty">No upcoming events found</div>';
    return;
  }

  els.calendarEvents.innerHTML = upcoming.map(event => {
    const start = new Date(event.start);
    const timeStr = formatEventTime(start);
    const duration = calculateDurationToEvent(start);
    const durationStr = formatDuration(duration);

    return `
      <div class="calendar-event" data-event-uid="${escapeHtml(event.uid)}">
        <div class="calendar-event-info">
          <div class="calendar-event-title">${escapeHtml(event.summary || 'Event')}</div>
          <div class="calendar-event-time">${timeStr}</div>
          ${event.location ? `<div class="calendar-event-location">${escapeHtml(event.location)}</div>` : ''}
        </div>
        <div class="calendar-event-action">
          <span class="calendar-event-duration">${durationStr}</span>
          <button class="calendar-event-btn" data-action="schedule">Schedule</button>
        </div>
      </div>
    `;
  }).join('');

  // Add event handlers
  els.calendarEvents.querySelectorAll('.calendar-event-btn').forEach(btn => {
    btn.addEventListener('click', async (e) => {
      e.stopPropagation();
      const eventUid = btn.closest('.calendar-event').dataset.eventUid;
      const event = state.calendarEvents.find(e => e.uid === eventUid);
      if (event) {
        await scheduleEvent(event);
      }
    });
  });
}

function formatEventTime(date) {
  const now = new Date();
  const isToday = date.toDateString() === now.toDateString();
  const isTomorrow = new Date(now.getTime() + 24 * 60 * 60 * 1000).toDateString() === date.toDateString();

  const timeStr = date.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' });

  if (isToday) return `Today at ${timeStr}`;
  if (isTomorrow) return `Tomorrow at ${timeStr}`;

  const dateStr = date.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
  return `${dateStr} at ${timeStr}`;
}

function calculateDurationToEvent(eventDate) {
  const now = new Date();
  const diffMs = eventDate.getTime() - now.getTime();
  return Math.max(0, Math.round(diffMs / 1000));
}

function formatDuration(seconds) {
  const hours = Math.floor(seconds / 3600);
  const mins = Math.floor((seconds % 3600) / 60);
  if (hours > 0) return `${hours}h ${mins}m`;
  return `${mins}m`;
}

async function scheduleEvent(event) {
  try {
    const options = {
      dryRun: state.dryRun,
      forceShutdown: state.forceShutdown,
      muteSystem: state.muteSystem,
      gracePeriod: state.graceMinutes
    };

    const result = await api.calendarCreateTimer(event, state.action, options);

    if (result.success && result.timerOptions) {
      // Set the timer
      setInputFromSeconds(result.timerOptions.durationSeconds);
      notify(`Timer set for "${event.summary}"`, 'success');
    } else {
      notify(result.error || 'Failed to create timer from event', 'error');
    }
  } catch (error) {
    notify(`Failed to schedule event: ${error.message}`, 'error');
  }
}

function showCalendarLoading() {
  if (els.calendarEvents) {
    els.calendarEvents.innerHTML = '<div class="calendar-loading">Loading calendar...</div>';
  }
}

function showCalendarError(message) {
  if (els.calendarEvents) {
    els.calendarEvents.innerHTML = `<div class="calendar-error">${escapeHtml(message)}</div>`;
  }
}

api.onTimerUpdate(applyTimerPayload);
api.onMiniModeChanged(isMini => {
  state.miniMode = Boolean(isMini);
  render();
});
api.onPlaySound(soundType => {
  if (SoundSystem[soundType]) SoundSystem[soundType]();
});
api.onPlayLastLight(payload => playLastLight(payload));
api.onBrowserWarning?.(data => {
  if (data?.message) notify(data.message, 'warning', 8000);
});

api.onUpdateAvailable?.(data => {
  if (data?.available && els.badgeUpdate) {
    els.badgeUpdate.style.display = '';
    els.badgeUpdate.textContent = `v${data.latestVersion}`;
    els.badgeUpdate.style.cursor = 'pointer';
    els.badgeUpdate.addEventListener('click', () => {
      api.openExternal?.(data.downloadUrl || data.releaseUrl);
    }, { once: true });
  }
});

wireEvents();
setupCustomizeHandlers();
setupLastLightHandlers();
setupWarningHandlers();
setupAlarmHandlers();
setAction(state.action);
loadInitialData().finally(render);
