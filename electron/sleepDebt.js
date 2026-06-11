// Sleep Debt Tracker: tracks cumulative sleep debt against
// your target bedtime. More motivating than streaks.

const fs = require('fs');
const path = require('path');
const { app } = require('electron');

const DEBT_FILE = 'sleepDebt.json';
let cache = null;
let configPath = null;

// Target sleep hours (configurable, default 8).
const DEFAULT_TARGET_HOURS = 8;

function getConfigPath() {
  if (!configPath) {
    configPath = path.join(app.getPath('userData'), DEBT_FILE);
  }
  return configPath;
}

function load() {
  if (cache) return cache;
  try {
    const raw = fs.readFileSync(getConfigPath(), 'utf-8');
    cache = JSON.parse(raw);
  } catch {
    cache = {
      targetHours: DEFAULT_TARGET_HOURS,
      wakeTime: '07:00',
      dailyLog: [] // [{ date, bedTime, wakeTime, actualHours, targetHours, debt }]
    };
  }
  return cache;
}

function save() {
  if (!cache) return;
  try {
    fs.writeFileSync(getConfigPath(), JSON.stringify(cache, null, 2), 'utf-8');
  } catch { /* best effort */ }
}

// Record a night's sleep. Called when a timer completes.
function recordNight(bedTime, wakeTime, actualHours) {
  const data = load();
  const today = new Date().toISOString().slice(0, 10);

  // Calculate debt for this night.
  const debt = Math.max(0, data.targetHours - actualHours);
  const surplus = Math.max(0, actualHours - data.targetHours);

  // Update or add entry for today.
  const existing = data.dailyLog.findIndex(e => e.date === today);
  const entry = {
    date: today,
    bedTime: bedTime || '23:00',
    wakeTime: wakeTime || data.wakeTime || '07:00',
    actualHours: Math.round(actualHours * 10) / 10,
    targetHours: data.targetHours,
    debt: Math.round(debt * 10) / 10,
    surplus: Math.round(surplus * 10) / 10
  };

  if (existing >= 0) data.dailyLog[existing] = entry;
  else data.dailyLog.push(entry);

  // Keep only last 90 days.
  const cutoff = new Date(Date.now() - 90 * 86400000).toISOString().slice(0, 10);
  data.dailyLog = data.dailyLog.filter(e => e.date >= cutoff);

  save();
  return entry;
}

// Get sleep debt summary.
function getDebtSummary() {
  const data = load();
  const now = new Date();
  const weekAgo = new Date(now - 7 * 86400000).toISOString().slice(0, 10);
  const recent = data.dailyLog.filter(e => e.date >= weekAgo);

  const weekDebt = recent.reduce((sum, e) => sum + (e.debt || 0), 0);
  const weekSurplus = recent.reduce((sum, e) => sum + (e.surplus || 0), 0);
  const weekAvg = recent.length ? (recent.reduce((sum, e) => sum + e.actualHours, 0) / recent.length) : 0;

  const totalDebt = data.dailyLog.reduce((sum, e) => sum + (e.debt || 0), 0);
  const totalSurplus = data.dailyLog.reduce((sum, e) => sum + (e.surplus || 0), 0);

  return {
    targetHours: data.targetHours,
    wakeTime: data.wakeTime || '07:00',
    weekDebt: Math.round(weekDebt * 10) / 10,
    weekSurplus: Math.round(weekSurplus * 10) / 10,
    weekAvg: Math.round(weekAvg * 10) / 10,
    totalDebt: Math.round(totalDebt * 10) / 10,
    totalSurplus: Math.round(totalSurplus * 10) / 10,
    nightsTracked: data.dailyLog.length,
    weekNights: recent.length,
    dailyLog: data.dailyLog.slice(-7).reverse(),
    netDebt: Math.round((totalDebt - totalSurplus) * 10) / 10
  };
}

// Set target hours.
function setTargetHours(hours) {
  const data = load();
  data.targetHours = Math.max(4, Math.min(12, hours));
  save();
  return data.targetHours;
}

// Set wake time.
function setWakeTime(time) {
  const data = load();
  data.wakeTime = time;
  save();
  return data.wakeTime;
}

// Calculate estimated actual sleep hours from bed time to wake time.
function estimateSleepHours(bedTime, wakeTime) {
  const [bh, bm] = bedTime.split(':').map(Number);
  const [wh, wm] = (wakeTime || '07:00').split(':').map(Number);
  let bedMin = bh * 60 + bm;
  let wakeMin = wh * 60 + wm;
  if (wakeMin <= bedMin) wakeMin += 24 * 60; // crossed midnight
  return (wakeMin - bedMin) / 60;
}

// Get debt status label.
function getDebtLabel(netDebt) {
  if (netDebt <= 0) return { label: 'Sleep Rich', color: '#4caf50', icon: '\u{1F929}' };
  if (netDebt <= 2) return { label: 'Slight Deficit', color: '#8bc34a', icon: '\u{1F610}' };
  if (netDebt <= 5) return { label: 'In Debt', color: '#ff9800', icon: '\u{1F614}' };
  if (netDebt <= 10) return { label: 'Deep Debt', color: '#ff5722', icon: '\u{1F635}' };
  return { label: 'Critical Debt', color: '#ff4d4d', icon: '\u{1F624}' };
}

function reset() {
  cache = null;
}

module.exports = {
  recordNight,
  getDebtSummary,
  setTargetHours,
  setWakeTime,
  estimateSleepHours,
  getDebtLabel,
  _load: load,
  _reset: reset
};
