// Screen Time Reality Check: shows how much time you spent on
// distracting apps today before wind-down starts. Guilt works.

const { spawn } = require('child_process');

// Categories of apps with their process names.
const CATEGORIES = {
  social: {
    label: 'Social Media',
    icon: '\u{1F4F1}',
    processes: ['chrome', 'msedge', 'firefox', 'brave', 'Discord', 'Telegram', 'slack']
  },
  video: {
    label: 'Video/Streaming',
    icon: '\u{1F3AC}',
    processes: ['vlc', 'wmplayer', 'Spotify', 'Music.UI', 'Video.UI']
  },
  gaming: {
    label: 'Gaming',
    icon: '\u{1F3AE}',
    processes: ['steam', 'SteamService', 'GameBar', 'GameBarFT', 'Discord']
  },
  productivity: {
    label: 'Productivity',
    icon: '\u{1F4DD}',
    processes: ['Code', 'devenv', 'WINWORD', 'EXCEL', 'POWERPNT', 'ONENOTE', 'Notion', 'obs64']
  }
};

// Get screen time for today by querying process runtime from Windows.
async function getScreenTimeToday() {
  const results = {};
  const allProcesses = new Set();

  for (const [catKey, cat] of Object.entries(CATEGORIES)) {
    for (const proc of cat.processes) {
      allProcesses.add(proc);
    }
  }

  // Query each process's total CPU time today via PowerShell.
  const procList = [...allProcesses];
  const cmd = procList.map(proc => {
    return `
      $p = Get-Process -Name '${proc}' -ErrorAction SilentlyContinue
      if ($p) {
        $totalSec = ($p | Measure-Object -Property TotalProcessorTime -Sum).Sum.TotalSeconds
        "${proc}:$([math]::Round($totalSec))"
      }
    `;
  }).join('; ');

  try {
    const raw = await executePS(cmd);
    if (!raw) return emptyResult();

    const procTimes = {};
    for (const line of raw.split('\n').map(s => s.trim()).filter(Boolean)) {
      const [name, sec] = line.split(':');
      if (name && sec) procTimes[name] = parseFloat(sec) || 0;
    }

    // Aggregate by category.
    for (const [catKey, cat] of Object.entries(CATEGORIES)) {
      let totalSec = 0;
      const details = [];
      for (const proc of cat.processes) {
        const t = procTimes[proc] || 0;
        if (t > 0) {
          totalSec += t;
          details.push({ process: proc, seconds: t });
        }
      }
      results[catKey] = {
        label: cat.label,
        icon: cat.icon,
        totalSeconds: totalSec,
        details
      };
    }
  } catch {
    return emptyResult();
  }

  // Calculate totals and "distracting" time.
  const distracting = (results.social?.totalSeconds || 0) + (results.video?.totalSeconds || 0) + (results.gaming?.totalSeconds || 0);
  const productive = results.productivity?.totalSeconds || 0;

  return {
    categories: results,
    distracting,
    productive,
    total: distracting + productive,
    ratio: productive > 0 ? Math.round(productive / (productive + distracting) * 100) : (distracting > 0 ? 0 : 100)
  };
}

// Get a motivational shame message based on screen time.
function getRealityCheckMessage(screenTime) {
  if (!screenTime || screenTime.total === 0) return null;

  const distHours = (screenTime.distracting / 3600).toFixed(1);
  const prodHours = (screenTime.productive / 3600).toFixed(1);

  if (screenTime.ratio < 20) {
    return `You spent ${distHours}h on distractions today and only ${prodHours}h on productive work. Time to wind down?`;
  } else if (screenTime.ratio < 50) {
    return `${distHours}h distracting vs ${prodHours}h productive today. Could be worse, but still time to unplug.`;
  } else if (screenTime.distracting > 3600) {
    return `Good productivity today, but you still spent ${distHours}h on distractions. Wind down?`;
  }
  return null;
}

function emptyResult() {
  return { categories: {}, distracting: 0, productive: 0, total: 0, ratio: 100 };
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
  getScreenTimeToday,
  getRealityCheckMessage,
  CATEGORIES
};
