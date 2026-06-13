// Family mode: LAN-based remote control of multiple Lights Out instances.
// Uses UDP broadcast for discovery and WebSocket for commands.

const dgram = require('dgram');
const http = require('http');
const { EventEmitter } = require('events');

const DISCOVERY_PORT = 58733;
const BROADCAST_INTERVAL = 10000; // 10s beacon
const FAMILY_MAGIC = 'LIGHTSOUT_FAMILY_V1';

let discoverySocket = null;
let beaconTimer = null;
const emitter = new EventEmitter();
const knownPeers = new Map(); // ip -> { ip, port, lastSeen }

// ─────────────────────────────────────────────────────────────────────────────
// Discovery: broadcast presence on LAN and listen for other instances.
// ─────────────────────────────────────────────────────────────────────────────

function startDiscovery(peerName) {
  if (discoverySocket) return;
  const name = peerName || require('os').hostname();

  discoverySocket = dgram.createSocket('udp4');
  discoverySocket.bind(DISCOVERY_PORT, () => {
    discoverySocket.setBroadcast(true);

    // Periodically broadcast presence.
    const msg = Buffer.from(`${FAMILY_MAGIC}|${name}|${DISCOVERY_PORT}`);
    beaconTimer = setInterval(() => {
      try {
        discoverySocket.send(msg, 0, msg.length, DISCOVERY_PORT, '255.255.255.255');
      } catch { /* socket may be closed */ }
    }, BROADCAST_INTERVAL);

    // Also send immediately.
    try {
      discoverySocket.send(msg, 0, msg.length, DISCOVERY_PORT, '255.255.255.255');
    } catch {}
  });

  discoverySocket.on('message', (data, rinfo) => {
    const str = data.toString();
    if (!str.startsWith(FAMILY_MAGIC)) return;
    const parts = str.split('|');
    if (parts.length < 2) return;
    const peerIp = rinfo.address;
    const peerLabel = parts[1] || peerIp;

    // Don't add ourselves (same IP).
    const localIps = getLocalIPs();
    if (localIps.includes(peerIp)) return;

    knownPeers.set(peerIp, { ip: peerIp, name: peerLabel, lastSeen: Date.now() });
    emitter.emit('peer-found', { ip: peerIp, name: peerLabel });
  });

  discoverySocket.on('error', () => { /* ignore */ });
}

function stopDiscovery() {
  if (beaconTimer) { clearInterval(beaconTimer); beaconTimer = null; }
  if (discoverySocket) {
    try { discoverySocket.close(); } catch {}
    discoverySocket = null;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Remote commands: send timer actions to a peer via HTTP.
// ─────────────────────────────────────────────────────────────────────────────

function sendRemoteCommand(peerIp, command, payload = {}) {
  return new Promise((resolve, reject) => {
    const data = JSON.stringify({ command, ...payload });
    const options = {
      hostname: peerIp,
      port: 58734, // Family command port (separate from PWA)
      path: '/command',
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(data) },
      timeout: 5000
    };

    const req = http.request(options, (res) => {
      let body = '';
      res.on('data', chunk => body += chunk);
      res.on('end', () => {
        try { resolve(JSON.parse(body)); }
        catch { resolve({ success: true }); }
      });
    });

    req.on('error', reject);
    req.on('timeout', () => { req.destroy(); reject(new Error('Timeout')); });
    req.write(data);
    req.end();
  });
}

async function remoteStart(peerIp, durationSeconds, action = 'shutdown') {
  return sendRemoteCommand(peerIp, 'start', { durationSeconds, action });
}

async function remotePause(peerIp) {
  return sendRemoteCommand(peerIp, 'pause');
}

async function remoteResume(peerIp) {
  return sendRemoteCommand(peerIp, 'resume');
}

async function remoteCancel(peerIp) {
  return sendRemoteCommand(peerIp, 'cancel');
}

async function remoteSnooze(peerIp, seconds = 300) {
  return sendRemoteCommand(peerIp, 'snooze', { seconds });
}

// ─────────────────────────────────────────────────────────────────────────────
// Family command server: receives commands from other instances.
// Runs on port 58734, separate from the companion PWA server.
// ─────────────────────────────────────────────────────────────────────────────

let commandServer = null;

function startCommandServer(onCommand) {
  if (commandServer) return;
  commandServer = http.createServer((req, res) => {
    if (req.method === 'POST' && req.url === '/command') {
      let body = '';
      req.on('data', chunk => body += chunk);
      req.on('end', () => {
        try {
          const cmd = JSON.parse(body);
          onCommand(cmd);
          res.writeHead(200, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ success: true }));
        } catch {
          res.writeHead(400);
          res.end(JSON.stringify({ success: false, error: 'Invalid command' }));
        }
      });
    } else {
      res.writeHead(404);
      res.end();
    }
  });

  // Degrade gracefully if the port is taken instead of crashing the main process.
  commandServer.on('error', (err) => {
    commandServer = null;
    if (err && err.code === 'EADDRINUSE') {
      console.warn('Family command port 58734 already in use - family remote disabled for this instance.');
    } else {
      console.warn(`Family command server error: ${err && (err.message || err.code)}`);
    }
  });

  commandServer.listen(58734, '0.0.0.0', () => {
    console.log('Family command server on port 58734');
  });
}

function stopCommandServer() {
  if (commandServer) {
    try { commandServer.close(); } catch {}
    commandServer = null;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Peer management
// ─────────────────────────────────────────────────────────────────────────────

function getPeers() {
  // Expire peers not seen in 30s.
  const now = Date.now();
  for (const [ip, peer] of knownPeers) {
    if (now - peer.lastSeen > 30000) knownPeers.delete(ip);
  }
  return [...knownPeers.values()];
}

function getLocalIPs() {
  const os = require('os');
  const interfaces = os.networkInterfaces();
  const ips = [];
  for (const name of Object.keys(interfaces)) {
    for (const iface of interfaces[name]) {
      if (iface.family === 'IPv4' && !iface.internal) ips.push(iface.address);
    }
  }
  return ips;
}

// ─────────────────────────────────────────────────────────────────────────────────
// Exports
// ─────────────────────────────────────────────────────────────────────────────

module.exports = {
  startDiscovery,
  stopDiscovery,
  startCommandServer,
  stopCommandServer,
  getPeers,
  getLocalIPs,
  sendRemoteCommand,
  remoteStart,
  remotePause,
  remoteResume,
  remoteCancel,
  remoteSnooze,
  onPeerFound: (callback) => emitter.on('peer-found', callback)
};
