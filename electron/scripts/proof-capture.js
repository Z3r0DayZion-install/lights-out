// v10.0.2 proof-pack screenshot capture (marketing). Screenshots only; no app changes.
// Usage: npx electron scripts/proof-capture.js
// Captures the 4 app states + the live GitHub release page into docs/release/screenshots/v10.0.2.
const { app, BrowserWindow } = require('electron');
const path = require('path');
const fs = require('fs');

// Disable web security at the Chromium level so the release window can
// load an external GitHub URL. This flag must be set before app.on('ready').
app.commandLine.appendSwitch('disable-web-security');
app.commandLine.appendSwitch('disable-features', 'IsolateOrigins,site-per-process');

const OUT = path.join(__dirname, '..', '..', 'docs', 'release', 'screenshots', 'v10.0.2');
const INDEX = path.join(__dirname, '..', 'index.html');
const RELEASE_URL = 'https://github.com/Z3r0DayZion-install/lights-out/releases/tag/v10.0.2';
const wait = ms => new Promise(r => setTimeout(r, ms));

fs.mkdirSync(OUT, { recursive: true });

async function shoot(win, name) {
  const img = await win.webContents.capturePage();
  const file = path.join(OUT, name);
  fs.writeFileSync(file, img.toPNG());
  console.log('wrote', name, img.getSize());
}

async function fit(win) {
  const h = await win.webContents.executeJavaScript(
    'Math.ceil(Math.max(document.documentElement.scrollHeight, document.body.scrollHeight))'
  );
  win.setContentSize(520, Math.min(Math.max(h, 800), 1040));
  await wait(400);
}

async function captureApp() {
  const win = new BrowserWindow({
    width: 520, height: 820, show: true,
    backgroundColor: '#0b0f1a',
    webPreferences: { backgroundThrottling: false }
  });

  // Seed localStorage with onboarded=true so the app skips the first-run
  // bedtime wizard and goes straight to the cockpit dashboard.
  await win.loadFile(INDEX);
  await win.webContents.executeJavaScript(`(function(){
    var stored = {};
    try { stored = JSON.parse(localStorage.getItem('lightsout-settings') || '{}'); } catch {}
    stored.app = Object.assign(stored.app || {}, { onboarded: true });
    localStorage.setItem('lightsout-settings', JSON.stringify(stored));
    return true;
  })();`);
  // Reload so checkOnboarding() reads the seeded flag and skips the wizard.
  await win.webContents.reload();
  await wait(2500);

  // 1. Ready state
  await win.webContents.executeJavaScript(`(function(){
    if (typeof state !== 'undefined') {
      state.running = false; state.paused = false; state.phase = 'idle';
      state.remainingSeconds = 1680; state.totalSeconds = 1680; state.endsAt = null;
    }
    document.body.className = document.body.className.replace(/phase-\\w+|is-running|is-paused|warm-shift/g, '').trim();
    if (typeof AmbientVisuals !== 'undefined') AmbientVisuals.stop();
    if (typeof render === 'function') render();
    return true;
  })();`);
  await fit(win);
  await wait(800);
  await shoot(win, '01_ready.png');

  // 2. Running countdown (focus phase)
  await win.webContents.executeJavaScript(`(function(){
    if (typeof state !== 'undefined') {
      state.running = true; state.paused = false; state.totalSeconds = 1680;
      state.remainingSeconds = 1320; state.action = 'shutdown'; state.phase = 'focus';
      state.endsAt = Date.now() + 1320000; state.dryRun = false; state.forceShutdown = false;
    }
    if (typeof render === 'function') render();
    return true;
  })();`);
  await fit(win);
  await wait(800);
  await shoot(win, '02_running.png');

  // 3. Wind-down / ambient (dim phase + fireplace)
  await win.webContents.executeJavaScript(`(function(){
    if (typeof state !== 'undefined') {
      state.running = true; state.paused = false; state.totalSeconds = 1680;
      state.remainingSeconds = 300; state.action = 'shutdown'; state.phase = 'dim';
      state.endsAt = Date.now() + 300000;
      state.customization = state.customization || {};
      state.customization.ambientVisual = 'fireplace';
    }
    if (typeof render === 'function') render();
    document.body.classList.add('phase-dim'); document.body.classList.add('warm-shift');
    if (typeof AmbientVisuals !== 'undefined') {
      AmbientVisuals.init(document.getElementById('ambient-canvas'));
      AmbientVisuals.start('fireplace');
    }
    return true;
  })();`);
  await fit(win);
  await wait(2000);
  await shoot(win, '03_winddown_ambient.png');

  // 4. Settings: Wind-down system actions (opt-in, default OFF)
  await win.webContents.executeJavaScript(`(function(){
    document.body.classList.remove('phase-dim'); document.body.classList.remove('warm-shift');
    if (typeof AmbientVisuals !== 'undefined') AmbientVisuals.stop();
    var modal = document.getElementById('options-modal');
    if (modal) modal.classList.add('active');
    var hs = Array.from(document.querySelectorAll('#options-modal h3'));
    var target = hs.find(function(h){ return /wind-down system actions/i.test(h.textContent); });
    if (target) target.scrollIntoView({ block: 'start' });
    return true;
  })();`);
  await wait(1200);
  await shoot(win, '04_settings_winddown.png');

  win.destroy();
}

async function captureRelease() {
  // Electron cannot load external GitHub URLs (ERR_FAILED).
  // Use capture-website-cli (Puppeteer-based) instead:
  //   npx capture-website-cli "$RELEASE_URL" --output="$OUT/05_github_release.png" --width=1200 --height=1000
  // Or screenshot manually in a browser.
  console.log('NOTE: GitHub release screenshot must be captured separately.');
  console.log('  npx capture-website-cli "' + RELEASE_URL + '" --output="' + path.join(OUT, '05_github_release.png') + '" --width=1200 --height=1000');
}

app.whenReady().then(async () => {
  try {
    await captureApp();
    await captureRelease();
  } catch (e) {
    console.error('FATAL', e);
    app.exit(1);
    return;
  }
  console.log('\nProof pack captured ->', OUT);
  app.quit();
});

setTimeout(() => { console.error('global timeout'); app.exit(1); }, 90000);
