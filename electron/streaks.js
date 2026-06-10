// Sleep streaks + insights engine.
// Records bedtime events and computes streaks, weekly stats, and achievements.

const { app } = require('electron');
const path = require('path');
const fs = require('fs');

const STREAKS_FILE = 'streaks.json';

let configPath = null;
let cache = null;

const DEFAULTS = {
  events: [],       // [{ date: '2026-06-10', bedTime: '22:30', action: 'shutdown', snoozed: false }]
  streak: 0,
  bestStreak: 0,
  achievements: []  // ['first_light', '7_night_streak', ...]
};

function load() {
  if (cache) return cache;
  try {
    if (!configPath) configPath = path.join(app.getPath('userData'), STREAKS_FILE);
    if (fs.existsSync(configPath)) {
      cache = deepMerge(structuredClone(DEFAULTS), JSON.parse(fs.readFileSync(configPath, 'utf8')));
    } else {
      cache = structuredClone(DEFAULTS);
    }
  } catch {
    cache = structuredClone(DEFAULTS);
  }
  return cache;
}

function save() {
  try {
    if (!configPath) configPath = path.join(app.getPath('userData'), STREAKS_FILE);
    fs.writeFileSync(configPath, JSON.stringify(cache, null, 2), 'utf8');
  } catch { /* best-effort */ }
}

function deepMerge(target, source) {
  for (const key of Object.keys(source)) {
    if (source[key] && typeof source[key] === 'object' && !Array.isArray(source[key]) &&
        target[key] && typeof target[key] === 'object' && !Array.isArray(target[key])) {
      deepMerge(target[key], source[key]);
    } else {
      target[key] = source[key];
    }
  }
  return target;
}

// ─────────────────────────────────────────────────────────────────────────────
// Public API
// ─────────────────────────────────────────────────────────────────────────────

function recordEvent(bedTime, action, snoozed) {
  const data = load();
  const today = new Date().toISOString().slice(0, 10);
  // Only one event per day (use the latest bedtime).
  data.events = data.events.filter(e => e.date !== today);
  data.events.push({ date: today, bedTime: bedTime || formatTime(), action: action || 'shutdown', snoozed: Boolean(snoozed) });

  // Keep last 365 days.
  if (data.events.length > 365) data.events = data.events.slice(-365);

  // Recompute streak.
  const streakInfo = computeStreak(data.events);
  data.streak = streakInfo.current;
  data.bestStreak = Math.max(data.bestStreak || 0, streakInfo.current);

  // Check achievements.
  data.achievements = checkAchievements(data);

  save();
  return getSummary();
}

function computeStreak(events) {
  if (!events.length) return { current: 0 };
  const sorted = [...events].sort((a, b) => a.date.localeCompare(b.date));
  let current = 1;
  let best = 1;
  for (let i = sorted.length - 1; i > 0; i--) {
    const prev = new Date(sorted[i - 1].date);
    const curr = new Date(sorted[i].date);
    const diffDays = Math.round((curr - prev) / 86400000);
    if (diffDays === 1) {
      current++;
      best = Math.max(best, current);
    } else {
      break;
    }
  }
  return { current, best: Math.max(best, current) };
}

function checkAchievements(data) {
  const unlocked = [...(data.achievements || [])];
  const add = (id) => { if (!unlocked.includes(id)) unlocked.push(id); };

  if (data.events.length >= 1) add('first_light');
  if (data.events.length >= 7) add('weekly_warrior');
  if (data.streak >= 3) add('3_night_streak');
  if (data.streak >= 7) add('7_night_streak');
  if (data.streak >= 14) add('14_night_streak');
  if (data.streak >= 30) add('30_night_streak');
  if (data.bestStreak >= 100) add('centurion');
  // No-snooze for 7 consecutive days.
  const recent7 = data.events.slice(-7);
  if (recent7.length === 7 && recent7.every(e => !e.snoozed)) add('no_snooze_7');
  // Used Last Light at least once.
  if (data.events.some(e => e.action === 'lastlight')) add('last_light_activated');

  return unlocked;
}

function getSummary() {
  const data = load();
  const week = getWeekStats(data.events);
  return {
    streak: data.streak || 0,
    bestStreak: data.bestStreak || 0,
    totalNights: data.events.length,
    achievements: data.achievements || [],
    weekAvg: week.avgBedTime,
    weekOnTime: week.onTimePercent,
    weekDays: week.days
  };
}

function getWeekStats(events) {
  const now = new Date();
  const weekAgo = new Date(now - 7 * 86400000).toISOString().slice(0, 10);
  const recent = events.filter(e => e.date >= weekAgo);
  if (!recent.length) return { avgBedTime: '--:--', onTimePercent: 0, days: [] };

  // Average bedtime.
  let totalMin = 0;
  const days = recent.map(e => {
    const [h, m] = (e.bedTime || '22:00').split(':').map(Number);
    const mins = (h * 60 + m);
    totalMin += mins;
    return { date: e.date, bedTime: e.bedTime, onTime: mins <= 23 * 60, snoozed: e.snoozed };
  });
  const avgMin = Math.round(totalMin / recent.length);
  const avgH = Math.floor(avgMin / 60) % 24;
  const avgM = avgMin % 60;
  const onTimeCount = days.filter(d => d.onTime).length;

  return {
    avgBedTime: `${String(avgH).padStart(2, '0')}:${String(avgM).padStart(2, '0')}`,
    onTimePercent: recent.length ? Math.round(onTimeCount / recent.length * 100) : 0,
    days
  };
}

function getAchievementCatalog() {
  return [
    { id: 'first_light', name: 'First Light', desc: 'Completed your first bedtime ritual' },
    { id: 'weekly_warrior', name: 'Weekly Warrior', desc: '7 nights using Lights Out' },
    { id: '3_night_streak', name: 'Triple Threat', desc: '3-night sleep streak' },
    { id: '7_night_streak', name: 'Seven Strong', desc: '7-night sleep streak' },
    { id: '14_night_streak', name: 'Fortnight Force', desc: '14-night sleep streak' },
    { id: '30_night_streak', name: 'Monthly Monument', desc: '30-night sleep streak' },
    { id: 'centurion', name: 'Centurion', desc: 'Best streak of 100 nights' },
    { id: 'no_snooze_7', name: 'No Snooze Zone', desc: '7 nights with no snooze' },
    { id: 'last_light_activated', name: 'Last Light', desc: 'Used the Last Light finale' }
  ];
}

// Digital wellbeing report: a weekly summary with trend data.
function getWeeklyReport() {
  const data = load();
  const now = new Date();
  const weekAgo = new Date(now - 7 * 86400000).toISOString().slice(0, 10);
  const recent = data.events.filter(e => e.date >= weekAgo);
  const total = data.events.length;

  // Bedtime trend (last 7 days, oldest first).
  const trend = recent.map(e => {
    const [h, m] = (e.bedTime || '23:00').split(':').map(Number);
    return { date: e.date, bedTime: e.bedTime, mins: h * 60 + m };
  }).sort((a, b) => a.date.localeCompare(b.date));

  // Consistency: standard deviation of bedtimes (lower = more consistent).
  let consistency = 0;
  if (trend.length > 1) {
    const mean = trend.reduce((s, t) => s + t.mins, 0) / trend.length;
    const variance = trend.reduce((s, t) => s + Math.pow(t.mins - mean, 2), 0) / trend.length;
    consistency = Math.round(Math.sqrt(variance));
  }

  // Snooze rate.
  const snoozeCount = recent.filter(e => e.snoozed).length;
  const snoozeRate = recent.length ? Math.round(snoozeCount / recent.length * 100) : 0;

  // Action breakdown.
  const actionCounts = {};
  recent.forEach(e => { actionCounts[e.action] = (actionCounts[e.action] || 0) + 1; });

  return {
    weekStart: weekAgo,
    weekEnd: now.toISOString().slice(0, 10),
    nightsThisWeek: recent.length,
    totalNights: total,
    streak: data.streak || 0,
    bestStreak: data.bestStreak || 0,
    consistency,
    snoozeRate,
    actionCounts,
    trend,
    achievements: data.achievements || []
  };
}

function formatTime() {
  const now = new Date();
  return `${String(now.getHours()).padStart(2, '0')}:${String(now.getMinutes()).padStart(2, '0')}`;
}

module.exports = {
  recordEvent,
  getSummary,
  getWeekStats,
  getAchievementCatalog,
  getWeeklyReport,
  // Testing helpers.
  _load: load,
  _reset: () => { cache = null; }
};
