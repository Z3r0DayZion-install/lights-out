// Media auto-pause engine.
// Detects running media players and sends pause commands during wind-down.

const { spawn } = require('child_process');

// Known media process names that support keyboard media-key pause.
const MEDIA_PROCESSES = [
  'spotify', 'Spotify',
  'chrome', 'msedge', 'firefox', 'brave', 'opera', 'vivaldi',
  'vlc', 'wmplayer', 'Music.UI', 'Video.UI',
  'Amazon Music', 'Pandora', 'TIDAL',
  'Discord', 'Telegram', 'slack'
];

// Check which media processes are currently running.
async function detectMediaSessions() {
  const results = [];
  const cmd = MEDIA_PROCESSES.map(proc =>
    `$p = Get-Process -Name '${proc}' -ErrorAction SilentlyContinue; if ($p) { '${proc}:' + $p.Count }`
  ).join('; ');

  try {
    const raw = await executePS(cmd);
    if (!raw) return [];
    for (const part of raw.split(';').map(s => s.trim()).filter(Boolean)) {
      const [name, count] = part.split(':');
      if (name && count && parseInt(count) > 0) {
        results.push({ name, processCount: parseInt(count) });
      }
    }
  } catch { /* best-effort */ }
  return results;
}

// Pause all detected media by sending the Windows media pause key.
// This uses the global media key (VK_MEDIA_PLAY_PAUSE = 0xB3) which
// works with any app that listens for media keys (Spotify, browsers, etc.).
async function pauseAllMedia() {
  // Send the media play/pause key via PowerShell SendKeys.
  try {
    await executePS(
      `(New-Object -ComObject WScript.Shell).SendKeys([char]174)`  // 174 = VK_MEDIA_PLAY_PAUSE
    );
  } catch {
    // Fallback: send via .NET SendKey.
    try {
      await executePS(
        `Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.SendKeys]::SendWait('^{F8}')`  // Ctrl+F8 on some systems
      );
    } catch { /* best-effort */ }
  }
}

// Pause specific apps by name using their keyboard shortcuts.
// Many media apps have Ctrl+P or Space as pause.
async function pauseAppByName(processName) {
  const appShortcuts = {
    'spotify': `(New-Object -ComObject WScript.Shell).SendKeys('^{F8}')`,
    'chrome': `(New-Object -ComObject WScript.Shell).SendKeys(' ')`,   // Space pauses YouTube/etc
    'msedge': `(New-Object -ComObject WScript.Shell).SendKeys(' ')`,
    'firefox': `(New-Object -ComObject WScript.Shell).SendKeys(' ')`,
    'vlc': `(New-Object -ComObject WScript.Shell).SendKeys(' ')`,
    'wmplayer': `(New-Object -ComObject WScript.Shell).SendKeys('^{P}')`,
  };

  const shortcut = appShortcuts[processName.toLowerCase()];
  if (shortcut) {
    try { await executePS(shortcut); } catch { /* best-effort */ }
  }
}

// Pause all detected media: global media key + per-app shortcuts.
async function pauseAllDetectedMedia() {
  const sessions = await detectMediaSessions();
  if (sessions.length === 0) return { paused: [], count: 0 };

  // Send global media pause key first.
  await pauseAllMedia();

  // Then try per-app shortcuts for each detected player.
  for (const session of sessions) {
    await pauseAppByName(session.name);
  }

  return { paused: sessions.map(s => s.name), count: sessions.length };
}

// Resume media (send play key) after cancel/manual resume.
async function resumeAllMedia() {
  try {
    await executePS(
      `(New-Object -ComObject WScript.Shell).SendKeys([char]174)`
    );
  } catch { /* best-effort */ }
}

// Mute system volume.
async function muteSystemVolume() {
  try {
    await executePS(
      `(New-Object -ComObject WScript.Shell).SendKeys([char]173)`
    );
  } catch { /* best-effort */ }
}

// Unmute system volume.
async function unmuteSystemVolume() {
  try {
    await executePS(
      `(New-Object -ComObject WScript.Shell).SendKeys([char]173)`
    );
  } catch { /* best-effort */ }
}

// Set system volume (0-100).
async function setSystemVolume(percent) {
  const vol = Math.max(0, Math.min(100, percent));
  try {
    await executePS(
      `$wsh = New-Object -ComObject WScript.Shell; 1..50 | ForEach-Object { $wsh.SendKeys([char]174) }; 1..([math]::Floor($vol / 2)) | ForEach-Object { $wsh.SendKeys([char]175) }`
    );
  } catch { /* best-effort */ }
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
  detectMediaSessions,
  pauseAllMedia,
  pauseAppByName,
  pauseAllDetectedMedia,
  resumeAllMedia,
  muteSystemVolume,
  unmuteSystemVolume,
  setSystemVolume
};
