// UI polish before/after capture. Usage: node scripts/polish-capture.js <prefix>
// Requires the app launched with --remote-debugging-port=9222.
const http = require('http');
const WebSocket = require('ws');
const fs = require('fs');
const path = require('path');

const PREFIX = process.argv[2] || 'before';
const OUT = path.join('C:\\Users\\KickA\\Desktop\\Lights Out\\docs\\release\\screenshots\\polish');
fs.mkdirSync(OUT, { recursive: true });

function getTarget() {
  return new Promise((resolve, reject) => {
    http.get('http://localhost:9222/json', res => {
      let d = ''; res.on('data', c => d += c);
      res.on('end', () => {
        const t = JSON.parse(d).find(t => t.title === 'Lights Out');
        if (!t) return reject('No target');
        resolve(t.webSocketDebuggerUrl);
      });
    }).on('error', reject);
  });
}

async function main() {
  const url = await getTarget();
  const ws = new WebSocket(url);
  let id = 0;
  const pending = new Map();
  ws.on('message', raw => {
    const msg = JSON.parse(raw.toString());
    if (msg.id && pending.has(msg.id)) { pending.get(msg.id)(msg); pending.delete(msg.id); }
  });
  function send(method, params = {}) {
    return new Promise(resolve => { const cur = ++id; pending.set(cur, resolve); ws.send(JSON.stringify({ id: cur, method, params })); });
  }
  function evalJS(expr) { return send('Runtime.evaluate', { expression: expr, returnByValue: true }); }

  await new Promise(r => ws.on('open', r));
  await send('Page.enable');

  function save(name, b64) {
    const buf = Buffer.from(b64, 'base64');
    fs.writeFileSync(path.join(OUT, name), buf);
    console.log(`Saved ${name}  ${buf.length} bytes`);
  }

  const viewResult = await evalJS(`JSON.stringify({ w: window.innerWidth, h: window.innerHeight })`);
  const viewSize = JSON.parse(viewResult.result.result.value);
  console.log('Viewport:', viewSize.w, 'x', viewSize.h);
  const clip = { x: 0, y: 0, width: viewSize.w, height: viewSize.h, scale: 1 };

  // Cancel any real timer running in main so it stops sending tick updates.
  await evalJS(`(function(){ try { if (typeof cancelTimer === 'function') cancelTimer(); } catch(e){ return String(e); } return 'cancel'; })();`);
  await new Promise(r => setTimeout(r, 2200));

  // Ready state
  await evalJS(`(function(){
    if (typeof state !== 'undefined') {
      state.running = false; state.paused = false; state.phase = 'idle';
      state.remainingSeconds = 1680; state.totalSeconds = 1680; state.endsAt = null;
    }
    document.body.className = document.body.className.replace(/phase-\\w+|is-running|is-paused/g, '').trim();
    if (typeof render === 'function') render();
    return 'ready';
  })();`);
  await new Promise(r => setTimeout(r, 1500));
  let r1 = await send('Page.captureScreenshot', { format: 'png', clip });
  save(`${PREFIX}_ready.png`, r1.result.data);

  // Running state
  await evalJS(`(function(){
    if (typeof state !== 'undefined') {
      state.running = true; state.paused = false; state.totalSeconds = 1680;
      state.remainingSeconds = 1320; state.action = 'shutdown'; state.phase = 'focus';
      state.endsAt = Date.now() + 1320000; state.dryRun = false; state.forceShutdown = false;
    }
    if (typeof render === 'function') render();
    return 'running';
  })();`);
  await new Promise(r => setTimeout(r, 1200));
  let r2 = await send('Page.captureScreenshot', { format: 'png', clip });
  save(`${PREFIX}_running.png`, r2.result.data);

  // Reset to ready so the live app is left clean
  await evalJS(`(function(){
    if (typeof state !== 'undefined') {
      state.running = false; state.paused = false; state.phase = 'idle';
      state.remainingSeconds = 1680; state.totalSeconds = 1680; state.endsAt = null;
    }
    if (typeof render === 'function') render();
    return 'reset';
  })();`);

  ws.close();
  console.log(`\nDone. Captured ${PREFIX}_ready.png and ${PREFIX}_running.png`);
}

main().catch(err => { console.error('FATAL:', err); process.exit(1); });
