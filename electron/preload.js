const { contextBridge, ipcRenderer } = require('electron');

// Secure IPC bridge
contextBridge.exposeInMainWorld('electronAPI', {
  // Timer control
  startTimer: (options, action) => ipcRenderer.invoke('start-timer', options, action),
  cancelTimer: () => ipcRenderer.invoke('cancel-timer'),
  pauseTimer: () => ipcRenderer.invoke('pause-timer'),
  resumeTimer: () => ipcRenderer.invoke('resume-timer'),
  snoozeTimer: (seconds) => ipcRenderer.invoke('snooze-timer', seconds),
  executeAction: (action, options) => ipcRenderer.invoke('execute-action', action, options),
  
  // System info
  getSystemInfo: () => ipcRenderer.invoke('get-system-info'),
  getAppSettings: () => ipcRenderer.invoke('get-app-settings'),
  saveAppSettings: (settings) => ipcRenderer.invoke('save-app-settings', settings),
  resumeRecoverableTimer: () => ipcRenderer.invoke('resume-recoverable-timer'),
  discardRecoverableTimer: () => ipcRenderer.invoke('discard-recoverable-timer'),
  
  // Window control
  minimizeWindow: () => ipcRenderer.send('minimize-window'),
  closeWindow: () => ipcRenderer.send('close-window'),
  quitApp: () => ipcRenderer.send('quit-app'),
  toggleMiniMode: () => ipcRenderer.send('toggle-mini-mode'),
  setWindowOpacity: (value) => ipcRenderer.send('set-window-opacity', value),
  fitWindowHeight: (height) => ipcRenderer.send('fit-window-height', height),
  
  // Notifications & sounds
  showNotification: (title, body) => ipcRenderer.send('show-notification', title, body),
  playSound: (soundType) => ipcRenderer.send('play-sound', soundType),
  setProgress: (percent, mode) => ipcRenderer.send('set-progress', percent, mode),
  
  // Timer events from backend
  onTimerUpdate: (callback) => {
    ipcRenderer.on('timer-update', (event, data) => callback(data));
  },
  
  // Mini mode changes
  onMiniModeChanged: (callback) => {
    ipcRenderer.on('mini-mode-changed', (event, isMini) => callback(isMini));
  },
  
  // Sound playback from main
  onPlaySound: (callback) => {
    ipcRenderer.on('play-sound', (event, soundType) => callback(soundType));
  },

  // Last Light finale trigger from main
  onPlayLastLight: (callback) => {
    ipcRenderer.on('play-last-light', (event, payload) => callback(payload));
  },

  // Dim phase events from main
  onDimPhaseStarted: (callback) => {
    ipcRenderer.on('dim-phase-started', (event, data) => callback(data));
  },
  onDimPhaseEnded: (callback) => {
    ipcRenderer.on('dim-phase-ended', () => callback());
  },
  
  // External links
  openExternal: (url) => ipcRenderer.send('open-external', url),

  // Smart Lights
  getSmartLightConfig: () => ipcRenderer.invoke('get-smartlight-config'),
  saveSmartLightConfig: (settings) => ipcRenderer.invoke('save-smartlight-config', settings),
  testSmartLightConnection: () => ipcRenderer.invoke('test-smartlight-connection'),
  discoverHueBridge: () => ipcRenderer.invoke('discover-hue-bridge'),
  registerHueBridge: (bridgeIp) => ipcRenderer.invoke('register-hue-bridge', bridgeIp),
  getHueLights: (bridgeIp, username) => ipcRenderer.invoke('get-hue-lights', bridgeIp, username),
  getHueGroups: (bridgeIp, username) => ipcRenderer.invoke('get-hue-groups', bridgeIp, username),

  // Profiles
  getAllProfiles: () => ipcRenderer.invoke('profiles-get-all'),
  getProfileById: (id) => ipcRenderer.invoke('profiles-get-by-id', id),
  createProfile: (data) => ipcRenderer.invoke('profiles-create', data),
  updateProfile: (id, data) => ipcRenderer.invoke('profiles-update', id, data),
  deleteProfile: (id) => ipcRenderer.invoke('profiles-delete', id),
  reorderProfiles: (orderedIds) => ipcRenderer.invoke('profiles-reorder', orderedIds),
  applyProfile: (id) => ipcRenderer.invoke('profiles-apply', id),
  getProfileHint: (profile) => ipcRenderer.invoke('profiles-get-hint', profile),
  exportProfiles: () => ipcRenderer.invoke('profiles-export'),
  importProfiles: (jsonString) => ipcRenderer.invoke('profiles-import', jsonString),
  createDefaultProfiles: () => ipcRenderer.invoke('profiles-create-defaults'),

  // Calendar
  calendarParseText: (text) => ipcRenderer.invoke('calendar-parse-text', text),
  calendarImportUrl: (url) => ipcRenderer.invoke('calendar-import-url', url),
  calendarTestUrl: (url) => ipcRenderer.invoke('calendar-test-url', url),
  calendarGetUpcoming: (events, from, withinDays, maxCount) => ipcRenderer.invoke('calendar-get-upcoming', events, from, withinDays, maxCount),
  calendarCreateTimer: (evt, action, options) => ipcRenderer.invoke('calendar-create-timer', evt, action, options),
  calendarFormatTime: (isoString) => ipcRenderer.invoke('calendar-format-time', isoString),

  // Streaks + insights
  getStreaks: () => ipcRenderer.invoke('get-streaks'),
  getAchievementsCatalog: () => ipcRenderer.invoke('get-achievements-catalog'),
  getWeeklyReport: () => ipcRenderer.invoke('get-weekly-report'),
  getSleepScore: () => ipcRenderer.invoke('get-sleep-score'),

  // Custom Last Light sequences
  addCustomSequence: (seq) => ipcRenderer.invoke('add-custom-sequence', seq),
  removeCustomSequence: (id) => ipcRenderer.invoke('remove-custom-sequence', id),

  // Desktop widget
  toggleWidget: () => ipcRenderer.send('toggle-widget'),
  onWidgetUpdate: (callback) => {
    ipcRenderer.on('widget-update', (event, data) => callback(data));
  },
  closeWidget: () => ipcRenderer.send('close-widget'),

  // Browser awareness
  getOpenBrowsers: () => ipcRenderer.invoke('get-open-browsers'),
  onBrowserWarning: (callback) => {
    ipcRenderer.on('browser-warning', (event, data) => callback(data));
  },

  // First Light (wake-up alarm)
  scheduleWakeAlarm: (alarmTime) => ipcRenderer.invoke('schedule-wake-alarm', alarmTime),
  removeWakeAlarm: () => ipcRenderer.invoke('remove-wake-alarm'),
  getWakeAlarmStatus: () => ipcRenderer.invoke('get-wake-alarm-status'),
  onFirstLightStarted: (callback) => {
    ipcRenderer.on('first-light-started', () => callback());
  },
  onFirstLightTick: (callback) => {
    ipcRenderer.on('first-light-tick', (event, data) => callback(data));
  },
  onFirstLightEnded: (callback) => {
    ipcRenderer.on('first-light-ended', () => callback());
  },

  // Auto-update
  checkForUpdate: () => ipcRenderer.invoke('check-for-update'),
  getUpdateStatus: () => ipcRenderer.invoke('get-update-status'),
  onUpdateAvailable: (callback) => {
    ipcRenderer.on('update-available', (event, data) => callback(data));
  },

  // Data export/import
  exportAllData: () => ipcRenderer.invoke('export-all-data'),
  importAllData: (jsonData) => ipcRenderer.invoke('import-all-data', jsonData),

  // Calendar providers
  getCalendarProviders: () => ipcRenderer.invoke('get-calendar-providers'),
  fetchCalendarEvents: (withinDays) => ipcRenderer.invoke('fetch-calendar-events', withinDays),
  saveCalendarSettings: (calSettings) => ipcRenderer.invoke('save-calendar-settings', calSettings),
  getCalendarSettings: () => ipcRenderer.invoke('get-calendar-settings'),

  // Companion PWA
  getCompanionStatus: () => ipcRenderer.invoke('get-companion-status'),

  // Family mode
  getFamilyPeers: () => ipcRenderer.invoke('get-family-peers'),
  familyRemoteStart: (ip, durationSeconds, action) => ipcRenderer.invoke('family-remote-start', ip, durationSeconds, action),
  familyRemotePause: (ip) => ipcRenderer.invoke('family-remote-pause', ip),
  familyRemoteResume: (ip) => ipcRenderer.invoke('family-remote-resume', ip),
  familyRemoteCancel: (ip) => ipcRenderer.invoke('family-remote-cancel', ip),
  familyRemoteSnooze: (ip, seconds) => ipcRenderer.invoke('family-remote-snooze', ip, seconds),

  // Media
  getMediaSessions: () => ipcRenderer.invoke('get-media-sessions'),
  onMediaPaused: (cb) => ipcRenderer.on('media-paused', (e, data) => cb(data)),
  onUnsavedWorkWarning: (cb) => ipcRenderer.on('unsaved-work-warning', (e, data) => cb(data)),
  onWifiGuardStatus: (cb) => ipcRenderer.on('wifi-guard-status', (e, data) => cb(data)),

  // WiFi Guard
  wifiGuardScan: () => ipcRenderer.invoke('wifi-guard-scan'),
  wifiGuardBlock: () => ipcRenderer.invoke('wifi-guard-block'),
  wifiGuardUnblock: () => ipcRenderer.invoke('wifi-guard-unblock'),
  saveWifiGuardSettings: (s) => ipcRenderer.invoke('save-wifi-guard-settings', s),
  getWifiGuardSettings: () => ipcRenderer.invoke('get-wifi-guard-settings'),

  // Content Blocker
  contentBlock: (list) => ipcRenderer.invoke('content-block', list),
  contentUnblock: () => ipcRenderer.invoke('content-unblock'),
  contentBlockStatus: () => ipcRenderer.invoke('content-block-status'),
  saveContentBlockerSettings: (s) => ipcRenderer.invoke('save-content-blocker-settings', s),
  getContentBlockerSettings: () => ipcRenderer.invoke('get-content-blocker-settings'),
  onContentBlocked: (cb) => ipcRenderer.on('content-blocked', (e, data) => cb(data)),

  // Accountability
  saveAccountabilitySettings: (s) => ipcRenderer.invoke('save-accountability-settings', s),
  getAccountabilitySettings: () => ipcRenderer.invoke('get-accountability-settings'),
  testAccountabilityPartner: (p) => ipcRenderer.invoke('test-accountability-partner', p),

  // Focus Sessions
  focusStart: (preset, custom) => ipcRenderer.invoke('focus-start', preset, custom),
  focusPause: () => ipcRenderer.invoke('focus-pause'),
  focusResume: () => ipcRenderer.invoke('focus-resume'),
  focusStop: () => ipcRenderer.invoke('focus-stop'),
  focusState: () => ipcRenderer.invoke('focus-state'),
  onFocusTick: (cb) => ipcRenderer.on('focus-tick', (e, data) => cb(data)),
  onFocusPhase: (cb) => ipcRenderer.on('focus-phase', (e, data) => cb(data)),
  onFocusComplete: (cb) => ipcRenderer.on('focus-complete', (e, data) => cb(data)),

  // Screen Time
  getScreenTime: () => ipcRenderer.invoke('get-screen-time'),
  getRealityCheck: () => ipcRenderer.invoke('get-reality-check'),
  onRealityCheck: (cb) => ipcRenderer.on('reality-check', (e, data) => cb(data)),

  // Sleep Debt
  getSleepDebt: () => ipcRenderer.invoke('get-sleep-debt'),
  setSleepTarget: (h) => ipcRenderer.invoke('set-sleep-target', h),
  setWakeTime: (t) => ipcRenderer.invoke('set-wake-time', t),

  // Emergency Override
  getOverrideConsequences: () => ipcRenderer.invoke('get-override-consequences'),
  executeOverride: (reason) => ipcRenderer.invoke('execute-override', reason),

  // Run Receipts / Morning Proof
  getLatestReceipt: () => ipcRenderer.invoke('get-latest-receipt'),
  listReceipts: (limit) => ipcRenderer.invoke('list-receipts', limit),
  clearReceipts: () => ipcRenderer.invoke('clear-receipts'),
  getReceiptStats: () => ipcRenderer.invoke('get-receipt-stats'),

  // Idle Detection
  getIdleSeconds: () => ipcRenderer.invoke('get-idle-seconds'),
  setIdleThreshold: (sec) => ipcRenderer.invoke('set-idle-threshold', sec),
  onIdleDetected: (cb) => ipcRenderer.on('idle-detected', (e, data) => cb(data)),
  onUserReturned: (cb) => ipcRenderer.on('user-returned', () => cb()),

  // Bedtime Reminder
  setBedtimeReminder: (min) => ipcRenderer.invoke('set-bedtime-reminder', min),
  onBedtimeReminder: (cb) => ipcRenderer.on('bedtime-reminder', (e, data) => cb(data)),

  // Morning Routine / Briefing
  onMorningBriefing: (cb) => ipcRenderer.on('morning-briefing', (e, data) => cb(data)),

  // Calendar Auto-Start
  setCalendarAutoStart: (enabled) => ipcRenderer.invoke('set-calendar-auto-start', enabled)
});
