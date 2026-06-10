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
  calendarFormatTime: (isoString) => ipcRenderer.invoke('calendar-format-time', isoString)
});
