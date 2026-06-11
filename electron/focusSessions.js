// Focus Sessions: daytime Pomodoro-style deep work sessions.
// Reuses the wind-down engine but inverted: focus phase is deep work,
// break phase is a short rest. Same ring, same phases, same sounds.

const { spawn } = require('child_process');

// Default focus presets.
const PRESETS = {
  pomodoro:   { focus: 25 * 60, break: 5 * 60, longBreak: 15 * 60, cycles: 4 },
  deep:       { focus: 50 * 60, break: 10 * 60, longBreak: 20 * 60, cycles: 3 },
  sprint:     { focus: 15 * 60, break: 3 * 60, longBreak: 10 * 60, cycles: 6 },
  custom:     { focus: 25 * 60, break: 5 * 60, longBreak: 15 * 60, cycles: 4 }
};

let focusState = {
  active: false,
  paused: false,
  preset: 'pomodoro',
  cycle: 0,
  totalCycles: 4,
  inBreak: false,
  inLongBreak: false,
  remainingSeconds: 0,
  totalSeconds: 0,
  focusSeconds: 25 * 60,
  breakSeconds: 5 * 60,
  longBreakSeconds: 15 * 60,
  completedCycles: 0,
  totalFocusTime: 0,
  interval: null
};

let onTickCallback = null;
let onPhaseCallback = null;
let onCompleteCallback = null;

function startFocusSession(preset = 'pomodoro', customConfig) {
  const config = customConfig || PRESETS[preset] || PRESETS.pomodoro;
  stopFocusSession(); // clean up any existing session

  focusState = {
    active: true,
    paused: false,
    preset,
    cycle: 0,
    totalCycles: config.cycles || 4,
    inBreak: false,
    inLongBreak: false,
    remainingSeconds: config.focus,
    totalSeconds: config.focus,
    focusSeconds: config.focus,
    breakSeconds: config.break,
    longBreakSeconds: config.longBreak,
    completedCycles: 0,
    totalFocusTime: 0,
    interval: null
  };

  // Notify phase change.
  if (onPhaseCallback) onPhaseCallback('focus', focusState);

  focusState.interval = setInterval(() => {
    if (!focusState.active || focusState.paused) return;
    focusState.remainingSeconds--;

    if (onTickCallback) onTickCallback(focusState);

    if (focusState.remainingSeconds <= 0) {
      handlePhaseEnd();
    }
  }, 1000);

  return { ...focusState };
}

function handlePhaseEnd() {
  if (focusState.inBreak || focusState.inLongBreak) {
    // Break ended, start new focus cycle.
    focusState.inBreak = false;
    focusState.inLongBreak = false;
    focusState.cycle++;
    focusState.remainingSeconds = focusState.focusSeconds;
    focusState.totalSeconds = focusState.focusSeconds;
    if (onPhaseCallback) onPhaseCallback('focus', focusState);
  } else {
    // Focus ended, start break.
    focusState.completedCycles++;
    focusState.totalFocusTime += focusState.focusSeconds;
    const isLast = focusState.cycle >= focusState.totalCycles - 1;

    if (isLast) {
      // All cycles done.
      stopFocusSession();
      if (onCompleteCallback) onCompleteCallback(focusState);
      return;
    }

    const isLongBreak = (focusState.completedCycles > 0 && focusState.completedCycles % focusState.totalCycles === 0);
    if (isLongBreak) {
      focusState.inLongBreak = true;
      focusState.remainingSeconds = focusState.longBreakSeconds;
      focusState.totalSeconds = focusState.longBreakSeconds;
      if (onPhaseCallback) onPhaseCallback('longbreak', focusState);
    } else {
      focusState.inBreak = true;
      focusState.remainingSeconds = focusState.breakSeconds;
      focusState.totalSeconds = focusState.breakSeconds;
      if (onPhaseCallback) onPhaseCallback('break', focusState);
    }
  }
}

function pauseFocusSession() {
  focusState.paused = true;
  return { ...focusState };
}

function resumeFocusSession() {
  focusState.paused = false;
  return { ...focusState };
}

function stopFocusSession() {
  if (focusState.interval) { clearInterval(focusState.interval); focusState.interval = null; }
  const wasActive = focusState.active;
  focusState.active = false;
  focusState.paused = false;
  focusState.remainingSeconds = 0;
  return { wasActive, completedCycles: focusState.completedCycles, totalFocusTime: focusState.totalFocusTime };
}

function getFocusState() {
  return { ...focusState };
}

function onTick(cb) { onTickCallback = cb; }
function onPhase(cb) { onPhaseCallback = cb; }
function onComplete(cb) { onCompleteCallback = cb; }

// Get daily focus stats.
function getFocusStats() {
  return {
    completedCycles: focusState.completedCycles,
    totalFocusTime: focusState.totalFocusTime,
    active: focusState.active
  };
}

module.exports = {
  startFocusSession,
  pauseFocusSession,
  resumeFocusSession,
  stopFocusSession,
  getFocusState,
  getFocusStats,
  onTick,
  onPhase,
  onComplete,
  PRESETS
};
