// Emergency Override: you CAN stay up, but it costs.
// Breaks your streak, notifies your accountability partner,
// shows you the math, and requires you to type a reason.

const accountability = require('./accountability');
const streaks = require('./streaks');
const settingsStore = require('./settings');

// Override consequences.
function getOverrideConsequences(timerState) {
  const appSettings = settingsStore.getSection('app') || {};
  const accConfig = settingsStore.getSection('accountability') || {};
  const bedtime = appSettings.bedtime || '22:30';
  const now = new Date();
  const [bh, bm] = bedtime.split(':').map(Number);
  const bedMin = bh * 60 + bm;
  const nowMin = now.getHours() * 60 + now.getMinutes();
  const minutesPastBedtime = Math.max(0, nowMin - bedMin);

  // Calculate estimated sleep if they stay up another 30/60 min.
  const wakeTime = appSettings.wakeTime || '07:00';
  const [wh, wm] = wakeTime.split(':').map(Number);
  let wakeMin = wh * 60 + wm;
  if (wakeMin <= nowMin) wakeMin += 24 * 60; // next day

  const sleepIf30 = Math.max(0, (wakeMin - (nowMin + 30)) / 60);
  const sleepIf60 = Math.max(0, (wakeMin - (nowMin + 60)) / 60);

  const consequences = [];

  // 1. Streak will be broken.
  const streak = streaks.getSummary()?.streak || 0;
  if (streak > 0) {
    consequences.push({
      type: 'streak',
      severity: 'high',
      message: `Your ${streak}-night streak will be broken.`,
      icon: '\u{1F525}'
    });
  }

  // 2. Accountability partner will be notified.
  if (accConfig.enabled && accConfig.partners?.length) {
    consequences.push({
      type: 'accountability',
      severity: 'high',
      message: `Your partner will be notified that you overrode the timer.`,
      icon: '\u{1F4E2}'
    });
  }

  // 3. Sleep math.
  if (sleepIf30 > 0) {
    consequences.push({
      type: 'math',
      severity: 'medium',
      message: `+30 min = ${sleepIf30.toFixed(1)}h sleep. +60 min = ${sleepIf60.toFixed(1)}h sleep.`,
      icon: '\u{1F4CA}'
    });
  }

  // 4. Already past bedtime.
  if (minutesPastBedtime > 0) {
    consequences.push({
      type: 'time',
      severity: 'medium',
      message: `You're already ${minutesPastBedtime} min past your ${bedtime} bedtime.`,
      icon: '\u{23F0}'
    });
  }

  // 5. Sleep debt.
  try {
    const sleepDebt = require('./sleepDebt');
    const debt = sleepDebt.getDebtSummary();
    if (debt.netDebt > 0) {
      consequences.push({
        type: 'debt',
        severity: 'high',
        message: `You already owe ${debt.netDebt}h of sleep this week.`,
        icon: '\u{1F4B8}'
      });
    }
  } catch {}

  return {
    allowed: true, // you CAN override, but...
    consequences,
    minutesPastBedtime,
    sleepIf30,
    sleepIf60,
    streak
  };
}

// Execute the override: record the consequences.
async function executeOverride(reason, timerState) {
  // 1. Notify accountability partner.
  try {
    const accConfig = settingsStore.getSection('accountability') || {};
    if (accConfig.enabled) {
      await accountability.notifyPartner('OVERRIDE', {
        config: accConfig,
        timerName: settingsStore.getSection('app')?.timerName || 'Witching Hour',
        remainingSeconds: timerState?.remainingSeconds,
        phase: timerState?.phase
      });
    }
  } catch {}

  // 2. Record the override event in streaks (with snooze=true to mark as "not clean").
  try {
    streaks.recordEvent(null, 'override', true);
  } catch {}

  // 3. Record sleep debt.
  try {
    const sleepDebt = require('./sleepDebt');
    const appSettings = settingsStore.getSection('app') || {};
    const bedTime = new Date().toTimeString().slice(0, 5);
    const estimated = sleepDebt.estimateSleepHours(bedTime, appSettings.wakeTime || '07:00');
    sleepDebt.recordNight(bedTime, appSettings.wakeTime || '07:00', estimated);
  } catch {}

  return {
    overridden: true,
    reason,
    timestamp: new Date().toISOString()
  };
}

module.exports = {
  getOverrideConsequences,
  executeOverride
};
