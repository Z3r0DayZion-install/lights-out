// Profiles Module for Lights Out Electron
// Ported from PowerShell LightsOut.Profiles.psm1
// Manages saved timer profiles with quick-load capability

const { app } = require('electron');
const path = require('path');
const fs = require('fs');

// Default profiles storage
const PROFILES_FILE = 'profiles.json';

// In-memory cache
let profilesCache = [];
let configPath = null;

// ─────────────────────────────────────────────────────────────────────────────
// Configuration Persistence
// ─────────────────────────────────────────────────────────────────────────────

function getConfigPath() {
  if (!configPath) {
    const userData = app.getPath('userData');
    configPath = path.join(userData, PROFILES_FILE);
  }
  return configPath;
}

function loadProfilesFromDisk() {
  try {
    const configFile = getConfigPath();
    if (fs.existsSync(configFile)) {
      const data = fs.readFileSync(configFile, 'utf8');
      const parsed = JSON.parse(data);
      if (Array.isArray(parsed)) {
        profilesCache = parsed.map(normalizeProfile).filter(p => p !== null);
        return profilesCache;
      }
    }
  } catch (error) {
    console.error('Failed to load profiles:', error.message);
  }
  profilesCache = [];
  return profilesCache;
}

function saveProfilesToDisk() {
  try {
    const configFile = getConfigPath();
    fs.writeFileSync(configFile, JSON.stringify(profilesCache, null, 2), 'utf8');
    return true;
  } catch (error) {
    console.error('Failed to save profiles:', error.message);
    return false;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Profile Normalization & Validation
// ─────────────────────────────────────────────────────────────────────────────

function normalizeProfile(raw) {
  if (!raw) return null;

  const name = String(raw.name || '').trim();
  if (!name) return null;

  const validActions = ['shutdown', 'restart', 'sleep', 'hibernate', 'logout', 'lock'];
  const action = validActions.includes(raw.action) ? raw.action : 'shutdown';

  const validModes = ['duration', 'clock', 'calendar'];
  const mode = validModes.includes(raw.mode) ? raw.mode : 'duration';

  const id = raw.id || generateId();
  const seconds = Math.max(60, Math.round(Number(raw.seconds) || 1800));
  const clock = raw.clock || '23:30';
  const autoStart = raw.autoStart !== undefined ? Boolean(raw.autoStart) : true;

  return {
    id,
    name: name.substring(0, 32),
    action,
    mode,
    seconds,
    clock,
    scheduledAt: raw.scheduledAt || '',
    calendarSource: raw.calendarSource || '',
    calendarEventUid: raw.calendarEventUid || '',
    calendarEventTitle: raw.calendarEventTitle || '',
    autoStart,
    // Extended options
    dryRun: Boolean(raw.dryRun),
    forceShutdown: Boolean(raw.forceShutdown),
    muteSystem: Boolean(raw.muteSystem),
    gracePeriod: Number.isFinite(Number(raw.gracePeriod)) ? Math.max(0, Number(raw.gracePeriod)) : 2,
    smartLightsEnabled: Boolean(raw.smartLightsEnabled),
    smartLightsMode: raw.smartLightsMode || 'gradual_dim',
    createdAt: raw.createdAt || new Date().toISOString(),
    updatedAt: new Date().toISOString()
  };
}

function generateId() {
  return Date.now().toString(36) + Math.random().toString(36).substring(2, 9);
}

// ─────────────────────────────────────────────────────────────────────────────
// Profile CRUD Operations
// ─────────────────────────────────────────────────────────────────────────────

function getAllProfiles() {
  return [...profilesCache];
}

function getProfileById(id) {
  return profilesCache.find(p => p.id === id) || null;
}

function createProfile(profileData) {
  const normalized = normalizeProfile(profileData);
  if (!normalized) {
    return { success: false, error: 'Invalid profile data' };
  }

  // Check for duplicate names
  const existingIndex = profilesCache.findIndex(p => 
    p.name.toLowerCase() === normalized.name.toLowerCase()
  );

  if (existingIndex >= 0) {
    // Update existing
    normalized.id = profilesCache[existingIndex].id;
    normalized.createdAt = profilesCache[existingIndex].createdAt;
    profilesCache[existingIndex] = normalized;
  } else {
    // Add new
    profilesCache.push(normalized);
  }

  const saved = saveProfilesToDisk();
  return saved 
    ? { success: true, profile: normalized, action: existingIndex >= 0 ? 'updated' : 'created' }
    : { success: false, error: 'Failed to save profile' };
}

function updateProfile(id, updates) {
  const index = profilesCache.findIndex(p => p.id === id);
  if (index < 0) {
    return { success: false, error: 'Profile not found' };
  }

  const merged = { ...profilesCache[index], ...updates, id, updatedAt: new Date().toISOString() };
  const normalized = normalizeProfile(merged);
  if (!normalized) {
    return { success: false, error: 'Invalid profile data' };
  }

  profilesCache[index] = normalized;
  const saved = saveProfilesToDisk();
  return saved 
    ? { success: true, profile: normalized }
    : { success: false, error: 'Failed to save profile' };
}

function deleteProfile(id) {
  const initialLength = profilesCache.length;
  profilesCache = profilesCache.filter(p => p.id !== id);
  
  if (profilesCache.length === initialLength) {
    return { success: false, error: 'Profile not found' };
  }

  const saved = saveProfilesToDisk();
  return saved 
    ? { success: true }
    : { success: false, error: 'Failed to save after delete' };
}

function reorderProfiles(orderedIds) {
  const orderedMap = new Map();
  orderedIds.forEach((id, index) => orderedMap.set(id, index));

  profilesCache.sort((a, b) => {
    const aIndex = orderedMap.get(a.id);
    const bIndex = orderedMap.get(b.id);
    if (aIndex !== undefined && bIndex !== undefined) {
      return aIndex - bIndex;
    }
    if (aIndex !== undefined) return -1;
    if (bIndex !== undefined) return 1;
    return 0;
  });

  saveProfilesToDisk();
  return { success: true, profiles: [...profilesCache] };
}

// ─────────────────────────────────────────────────────────────────────────────
// Profile Application
// ─────────────────────────────────────────────────────────────────────────────

function applyProfile(profileId, currentState = {}) {
  const profile = getProfileById(profileId);
  if (!profile) {
    return { success: false, error: 'Profile not found' };
  }

  // Calculate duration based on mode
  let durationSeconds = profile.seconds;
  let endsAt = null;

  if (profile.mode === 'clock' && profile.clock) {
    const [hours, minutes] = profile.clock.split(':').map(Number);
    const now = new Date();
    const target = new Date(now);
    target.setHours(hours, minutes, 0, 0);
    if (target <= now) target.setDate(target.getDate() + 1);
    durationSeconds = Math.max(60, Math.round((target - now) / 1000));
    endsAt = target.toISOString();
  }

  return {
    success: true,
    profile,
    timerOptions: {
      durationSeconds,
      action: profile.action,
      dryRun: profile.dryRun,
      forceShutdown: profile.forceShutdown,
      muteSystem: profile.muteSystem,
      gracePeriod: profile.gracePeriod,
      endsAt
    },
    autoStart: profile.autoStart
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// Profile Hints & Display
// ─────────────────────────────────────────────────────────────────────────────

function getProfileHint(profile) {
  if (!profile) return '';

  const actionLabel = profile.action.charAt(0).toUpperCase() + profile.action.slice(1);

  switch (profile.mode) {
    case 'clock':
      return `${actionLabel} at ${profile.clock}`;
    case 'calendar':
      if (profile.calendarEventTitle) {
        return `${actionLabel} - ${profile.calendarEventTitle}`;
      }
      if (profile.scheduledAt) {
        try {
          const dt = new Date(profile.scheduledAt);
          return `${actionLabel} at ${dt.toLocaleString('en-US', { month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' })}`;
        } catch {}
      }
      return `${actionLabel} (calendar)`;
    default:
      const minutes = Math.ceil(profile.seconds / 60);
      return `${actionLabel} in ${minutes}m`;
  }
}

function formatDuration(seconds) {
  const hours = Math.floor(seconds / 3600);
  const mins = Math.floor((seconds % 3600) / 60);
  if (hours > 0) return `${hours}h ${mins}m`;
  return `${mins}m`;
}

// ─────────────────────────────────────────────────────────────────────────────
// Import/Export
// ─────────────────────────────────────────────────────────────────────────────

function exportProfiles() {
  return JSON.stringify(profilesCache, null, 2);
}

function importProfiles(jsonString) {
  try {
    const parsed = JSON.parse(jsonString);
    if (!Array.isArray(parsed)) {
      return { success: false, error: 'Invalid format: expected array' };
    }

    const normalized = parsed.map(normalizeProfile).filter(p => p !== null);
    profilesCache = normalized;
    saveProfilesToDisk();
    return { success: true, count: normalized.length };
  } catch (error) {
    return { success: false, error: `Import failed: ${error.message}` };
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Default Profiles
// ─────────────────────────────────────────────────────────────────────────────

function createDefaultProfiles() {
  const defaults = [
    {
      name: 'Movie Night',
      action: 'sleep',
      mode: 'duration',
      seconds: 7200, // 2 hours
      autoStart: false
    },
    {
      name: 'Quick Nap',
      action: 'sleep',
      mode: 'duration',
      seconds: 1800, // 30 min
      autoStart: false
    },
    {
      name: 'Work Focus',
      action: 'shutdown',
      mode: 'duration',
      seconds: 3600, // 1 hour
      forceShutdown: false,
      autoStart: false
    },
    {
      name: 'Hard Stop',
      action: 'shutdown',
      mode: 'duration',
      seconds: 900, // 15 min
      forceShutdown: true,
      autoStart: false
    }
  ];

  const results = [];
  for (const def of defaults) {
    // Only create if no profile with this name exists
    const exists = profilesCache.some(p => 
      p.name.toLowerCase() === def.name.toLowerCase()
    );
    if (!exists) {
      const result = createProfile(def);
      if (result.success) results.push(result.profile);
    }
  }

  return results;
}

// ─────────────────────────────────────────────────────────────────────────────
// Initialization
// ─────────────────────────────────────────────────────────────────────────────

function initialize() {
  loadProfilesFromDisk();
  
  // Create defaults if no profiles exist
  if (profilesCache.length === 0) {
    createDefaultProfiles();
  }
  
  return profilesCache.length;
}

// ─────────────────────────────────────────────────────────────────────────────
// Exports
// ─────────────────────────────────────────────────────────────────────────────

module.exports = {
  // Initialization
  initialize,
  reload: loadProfilesFromDisk,
  
  // CRUD
  getAll: getAllProfiles,
  getById: getProfileById,
  create: createProfile,
  update: updateProfile,
  delete: deleteProfile,
  reorder: reorderProfiles,
  
  // Application
  apply: applyProfile,
  
  // Utilities
  getHint: getProfileHint,
  formatDuration,
  normalize: normalizeProfile,
  
  // Import/Export
  export: exportProfiles,
  import: importProfiles,
  
  // Defaults
  createDefaults: createDefaultProfiles,
  
  // Direct access (use with caution)
  get cache() { return [...profilesCache]; }
};
