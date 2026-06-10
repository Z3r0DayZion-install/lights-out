// Dev-only: render the real renderer in Electron and capture screenshots for UI review.
// Usage: npx electron scripts/ui-capture.js
const { app, BrowserWindow } = require('electron');
const path = require('path');
const fs = require('fs');

const outDir = path.join(__dirname, '..', 'assets');
const wait = ms => new Promise(r => setTimeout(r, ms));

async function capture(win, name) {
  const img = await win.webContents.capturePage();
  fs.writeFileSync(path.join(outDir, name), img.toPNG());
  console.log('wrote', name);
}

app.whenReady().then(async () => {
  const win = new BrowserWindow({
    width: 520,
    height: 760,
    show: false,
    webPreferences: { offscreen: false }
  });

  await win.loadFile(path.join(__dirname, '..', 'index.html'));
  await wait(1200);
  await capture(win, '_ui_cockpit.png');

  // Open the options modal and reveal the Customize section.
  await win.webContents.executeJavaScript(`
    (function(){
      if (typeof syncCustomizeUI === 'function') syncCustomizeUI();
      var m = document.getElementById('options-modal');
      if (m) m.classList.add('active');
      var cz = document.querySelector('.customize-section');
      if (cz) cz.scrollIntoView({block:'start'});
      return true;
    })();
  `);
  await wait(600);
  await capture(win, '_ui_customize.png');

  // Apply a violet accent + aurora theme to verify live theming.
  await win.webContents.executeJavaScript(`
    (function(){
      if (typeof applyCustomization === 'function') {
        applyCustomization({ accent: '#a855f7', theme: 'aurora', ringStyle: 'glow', opacity: 1, volume: 1 });
      }
      var m = document.getElementById('options-modal');
      if (m) m.classList.remove('active');
      return true;
    })();
  `);
  await wait(500);
  await capture(win, '_ui_themed.png');

  app.quit();
}).catch(err => {
  console.error(err);
  app.exit(1);
});

setTimeout(() => { console.error('timeout'); app.exit(1); }, 20000);
