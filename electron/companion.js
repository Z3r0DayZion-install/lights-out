// Companion PWA server.
// Serves a mobile-friendly web app and communicates via WebSocket
// so users can start/pause/snooze/cancel the timer from their phone.

const http = require('http');
const { EventEmitter } = require('events');
const path = require('path');
const fs = require('fs');

const PWA_PORT = 58732;
let server = null;
let wss = null;
let clients = new Set();
const emitter = new EventEmitter();

// ─────────────────────────────────────────────────────────────────────────────
// Minimal WebSocket server (no external deps)
// ─────────────────────────────────────────────────────────────────────────────

function upgradeHandler(req, socket, head) {
  if (req.headers.upgrade?.toLowerCase() !== 'websocket') return;

  const key = req.headers['sec-websocket-key'];
  if (!key) { socket.destroy(); return; }

  const accept = require('crypto').createHash('sha1')
    .update(key + '258EAFA5-E914-47DA-95CA-5AB5E50F7B97')
    .digest('base64');

  socket.write(
    'HTTP/1.1 101 Switching Protocols\r\n' +
    'Upgrade: websocket\r\n' +
    'Connection: Upgrade\r\n' +
    `Sec-WebSocket-Accept: ${accept}\r\n\r\n`
  );

  const client = { socket, alive: true };
  clients.add(client);

  socket.on('data', (buf) => {
    try {
      const msg = decodeWS(buf);
      if (msg) emitter.emit('message', JSON.parse(msg), client);
    } catch { /* ignore malformed */ }
  });

  socket.on('close', () => { client.alive = false; clients.delete(client); });
  socket.on('error', () => { client.alive = false; clients.delete(client); });

  emitter.emit('connect', client);
}

function decodeWS(buf) {
  if (buf.length < 2) return null;
  const second = buf[1];
  const payloadLen = second & 0x7F;
  let offset = 2;
  if (payloadLen === 126) { offset = 4; }
  else if (payloadLen === 127) { offset = 10; }
  const masks = buf.slice(offset, offset + 4);
  offset += 4;
  let decoded = '';
  for (let i = 0; i < payloadLen; i++) {
    decoded += String.fromCharCode(buf[offset + i] ^ masks[i % 4]);
  }
  return decoded;
}

function encodeWS(data) {
  const payload = Buffer.from(data);
  let header;
  if (payload.length < 126) {
    header = Buffer.alloc(2);
    header[0] = 0x81; // text frame, FIN
    header[1] = payload.length;
  } else if (payload.length < 65536) {
    header = Buffer.alloc(4);
    header[0] = 0x81;
    header[1] = 126;
    header.writeUInt16BE(payload.length, 2);
  } else {
    header = Buffer.alloc(10);
    header[0] = 0x81;
    header[1] = 127;
    header.writeBigUInt64BE(BigInt(payload.length), 2);
  }
  return Buffer.concat([header, payload]);
}

function broadcast(data) {
  const msg = encodeWS(JSON.stringify(data));
  for (const client of clients) {
    if (client.alive) {
      try { client.socket.write(msg); } catch { client.alive = false; clients.delete(client); }
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HTTP server for the PWA page
// ─────────────────────────────────────────────────────────────────────────────

function requestHandler(req, res) {
  if (req.url === '/' || req.url === '/index.html') {
    const htmlPath = path.join(__dirname, 'companion.html');
    try {
      const html = fs.readFileSync(htmlPath, 'utf8');
      res.writeHead(200, { 'Content-Type': 'text/html' });
      res.end(html);
    } catch {
      res.writeHead(404);
      res.end('Companion page not found');
    }
  } else if (req.url === '/manifest.json') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
      name: 'Lights Out Companion',
      short_name: 'Lights Out',
      start_url: '/',
      display: 'standalone',
      background_color: '#0d0e11',
      theme_color: '#5b8cff',
      icons: [{ src: '/icon', sizes: '192x192', type: 'image/png' }]
    }));
  } else if (req.url === '/icon') {
    const iconPath = path.join(__dirname, 'assets', 'icon.ico');
    try {
      const icon = fs.readFileSync(iconPath);
      res.writeHead(200, { 'Content-Type': 'image/x-icon' });
      res.end(icon);
    } catch {
      res.writeHead(404);
      res.end();
    }
  } else {
    res.writeHead(404);
    res.end();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Public API
// ─────────────────────────────────────────────────────────────────────────────

function start() {
  if (server) return;
  server = http.createServer(requestHandler);
  server.on('upgrade', upgradeHandler);

  // Degrade gracefully if the port is already taken (most commonly another
  // Lights Out instance, or a leftover dev build). Without this handler the
  // server emits an unhandled 'error' that crashes the whole main process.
  server.on('error', (err) => {
    server = null;
    if (err && err.code === 'EADDRINUSE') {
      console.warn(`Companion PWA port ${PWA_PORT} is already in use - companion features disabled for this instance.`);
    } else {
      console.warn(`Companion PWA server error: ${err && (err.message || err.code)}`);
    }
  });

  server.listen(PWA_PORT, '0.0.0.0', () => {
    console.log(`Companion PWA running at http://localhost:${PWA_PORT}`);
  });
}

function stop() {
  if (server) {
    server.close();
    server = null;
  }
  for (const client of clients) {
    try { client.socket.destroy(); } catch {}
  }
  clients.clear();
}

function getStatus() {
  return {
    running: !!server,
    port: PWA_PORT,
    clients: clients.size,
    url: `http://localhost:${PWA_PORT}`
  };
}

function onMessage(callback) {
  emitter.on('message', callback);
}

function onConnect(callback) {
  emitter.on('connect', callback);
}

module.exports = {
  start,
  stop,
  broadcast,
  getStatus,
  onMessage,
  onConnect,
  PWA_PORT
};
