// Idle Detection: notices when you walk away from the computer
// and nudges wind-down. Uses PowerShell to query last input time.

const { spawn } = require('child_process');

let idleCheckInterval = null;
let lastIdleSeconds = 0;
let idleThresholdSeconds = 300; // 5 min default
let onIdleCallback = null;
let onReturnCallback = null;
let wasIdle = false;

// Start monitoring idle time.
function startMonitoring(options = {}) {
  idleThresholdSeconds = options.thresholdSeconds || 300;
  onIdleCallback = options.onIdle || null;
  onReturnCallback = options.onReturn || null;
  wasIdle = false;

  if (idleCheckInterval) clearInterval(idleCheckInterval);
  idleCheckInterval = setInterval(checkIdle, 15000); // check every 15s
}

function stopMonitoring() {
  if (idleCheckInterval) { clearInterval(idleCheckInterval); idleCheckInterval = null; }
}

async function checkIdle() {
  try {
    const idleSec = await getIdleSeconds();
    lastIdleSeconds = idleSec;

    if (!wasIdle && idleSec >= idleThresholdSeconds) {
      wasIdle = true;
      if (onIdleCallback) onIdleCallback(idleSec);
    } else if (wasIdle && idleSec < 10) {
      wasIdle = false;
      if (onReturnCallback) onReturnCallback();
    }
  } catch { /* best effort */ }
}

// Get system idle time in seconds via PowerShell.
async function getIdleSeconds() {
  const cmd = `
    Add-Type @"
      using System;
      using System.Runtime.InteropServices;
      public class Idle {
        [DllImport("user32.dll")] public static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);
        [StructLayout(LayoutKind.Sequential)] public struct LASTINPUTINFO { public uint cbSize; public uint dwTime; }
        public static uint GetIdle() {
          var li = new LASTINPUTINFO(); li.cbSize = (uint)Marshal.SizeOf(li);
          GetLastInputInfo(ref li);
          return ((uint)Environment.TickCount - li.dwTime) / 1000;
        }
      }
    "@
    [Idle]::GetIdle()
  `;
  try {
    const raw = await executePS(cmd);
    return parseInt(raw) || 0;
  } catch { return 0; }
}

function setThreshold(seconds) {
  idleThresholdSeconds = Math.max(60, seconds);
}

function getThreshold() {
  return idleThresholdSeconds;
}

function isIdle() {
  return wasIdle;
}

function getLastIdleSeconds() {
  return lastIdleSeconds;
}

function executePS(command) {
  return new Promise((resolve, reject) => {
    const ps = spawn('powershell.exe', [
      '-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', command
    ], { stdio: ['ignore', 'pipe', 'pipe'] });
    let output = '';
    ps.stdout.on('data', data => { output += data.toString(); });
    ps.stderr.on('data', data => { output += data.toString(); });
    ps.on('error', reject);
    ps.on('close', code => {
      if (code === 0) resolve(output.trim());
      else reject(new Error(output.trim() || `PS exit ${code}`));
    });
  });
}

module.exports = {
  startMonitoring,
  stopMonitoring,
  getIdleSeconds,
  setThreshold,
  getThreshold,
  isIdle,
  getLastIdleSeconds
};
