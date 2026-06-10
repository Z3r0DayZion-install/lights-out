// WiFi Guard: shut down internet access for kids at bedtime.
// Supports router API integration (TP-Link, ASUS, Netgear) and
// Windows Firewall rules as a fallback. Can also disable the
// local WiFi adapter as a nuclear option.

const http = require('http');
const https = require('https');
const { spawn } = require('child_process');

// ─────────────────────────────────────────────────────────────────────────────
// Router API providers
// ─────────────────────────────────────────────────────────────────────────────

// TP-Link routers (common modern models: Archer, Deco).
async function tplinkBlock(routerIp, username, password, deviceMacs) {
  // TP-Link uses a session-based API.
  const base = `http://${routerIp}`;
  try {
    // Login.
    const loginRes = await httpPost(`${base}/cgi-bin/luci/admin/login`, {
      username, password, operation: 'write'
    });
    // Set parental control rules for each MAC.
    for (const mac of deviceMacs) {
      await httpPost(`${base}/cgi-bin/luci/admin/parental_control`, {
        mac, enable: 1, description: 'Lights Out Bedtime Block'
      });
    }
    return { success: true, provider: 'tplink' };
  } catch (e) {
    return { success: false, provider: 'tplink', error: e.message };
  }
}

async function tplinkUnblock(routerIp, username, password, deviceMacs) {
  const base = `http://${routerIp}`;
  try {
    await httpPost(`${base}/cgi-bin/luci/admin/login`, { username, password, operation: 'write' });
    for (const mac of deviceMacs) {
      await httpPost(`${base}/cgi-bin/luci/admin/parental_control`, {
        mac, enable: 0
      });
    }
    return { success: true, provider: 'tplink' };
  } catch (e) {
    return { success: false, provider: 'tplink', error: e.message };
  }
}

// ASUS routers (uses the AiProtection / Parental Control API).
async function asusBlock(routerIp, username, password, deviceMacs) {
  const base = `http://${routerIp}`;
  try {
    // ASUS uses a token-based auth on their web UI.
    const loginRes = await httpPost(`${base}/login.cgi`, {
      login_authorization: Buffer.from(`${username}:${password}`).toString('base64')
    });
    for (const mac of deviceMacs) {
      await httpPost(`${base}/apply.cgi`, {
        action_mode: 'apply',
        current_page: 'ParentalControl.asp',
        blocked_mac: mac,
        blocked_desc: 'Lights Out'
      });
    }
    return { success: true, provider: 'asus' };
  } catch (e) {
    return { success: false, provider: 'asus', error: e.message };
  }
}

async function asusUnblock(routerIp, username, password, deviceMacs) {
  const base = `http://${routerIp}`;
  try {
    await httpPost(`${base}/login.cgi`, {
      login_authorization: Buffer.from(`${username}:${password}`).toString('base64')
    });
    for (const mac of deviceMacs) {
      await httpPost(`${base}/apply.cgi`, {
        action_mode: 'apply',
        current_page: 'ParentalControl.asp',
        unblocked_mac: mac
      });
    }
    return { success: true, provider: 'asus' };
  } catch (e) {
    return { success: false, provider: 'asus', error: e.message };
  }
}

// Netgear routers (uses SOAP API over HTTP).
async function netgearBlock(routerIp, username, password, deviceMacs) {
  const base = `http://${routerIp}`;
  try {
    // Netgear uses a SOAP body for auth.
    const authBody = `<?xml version="1.0"?><SOAP-ENV:Envelope><SOAP-ENV:Body><Login><Username>${username}</Username><Password>${password}</Password></Login></SOAP-ENV:Body></SOAP-ENV:Envelope>`;
    await httpPost(`${base}/soap/server_sa/`, authBody, { 'SOAPAction': 'Login' });
    for (const mac of deviceMacs) {
      const blockBody = `<?xml version="1.0"?><SOAP-ENV:Envelope><SOAP-ENV:Body><SetBlockDeviceByMAC><MAC>${mac}</MAC><Enable>1</Enable></SetBlockDeviceByMAC></SOAP-ENV:Body></SOAP-ENV:Envelope>`;
      await httpPost(`${base}/soap/server_sa/`, blockBody, { 'SOAPAction': 'SetBlockDeviceByMAC' });
    }
    return { success: true, provider: 'netgear' };
  } catch (e) {
    return { success: false, provider: 'netgear', error: e.message };
  }
}

async function netgearUnblock(routerIp, username, password, deviceMacs) {
  const base = `http://${routerIp}`;
  try {
    const authBody = `<?xml version="1.0"?><SOAP-ENV:Envelope><SOAP-ENV:Body><Login><Username>${username}</Username><Password>${password}</Password></Login></SOAP-ENV:Body></SOAP-ENV:Envelope>`;
    await httpPost(`${base}/soap/server_sa/`, authBody, { 'SOAPAction': 'Login' });
    for (const mac of deviceMacs) {
      const unblockBody = `<?xml version="1.0"?><SOAP-ENV:Envelope><SOAP-ENV:Body><SetBlockDeviceByMAC><MAC>${mac}</MAC><Enable>0</Enable></SetBlockDeviceByMAC></SOAP-ENV:Body></SOAP-ENV:Envelope>`;
      await httpPost(`${base}/soap/server_sa/`, unblockBody, { 'SOAPAction': 'SetBlockDeviceByMAC' });
    }
    return { success: true, provider: 'netgear' };
  } catch (e) {
    return { success: false, provider: 'netgear', error: e.message };
  }
}

// Generic HTTP webhook (for any router with a REST API or automation hook).
async function webhookBlock(url, deviceMacs, headers) {
  try {
    await httpPost(url, { action: 'block', macs: deviceMacs }, headers);
    return { success: true, provider: 'webhook' };
  } catch (e) {
    return { success: false, provider: 'webhook', error: e.message };
  }
}

async function webhookUnblock(url, deviceMacs, headers) {
  try {
    await httpPost(url, { action: 'unblock', macs: deviceMacs }, headers);
    return { success: true, provider: 'webhook' };
  } catch (e) {
    return { success: false, provider: 'webhook', error: e.message };
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Windows Firewall fallback: block outbound traffic for device IPs.
// Creates a "Lights Out WiFi Guard" rule group.
// ─────────────────────────────────────────────────────────────────────────────

const FW_RULE_PREFIX = 'LightsOut_WiFiGuard';

async function firewallBlock(deviceIps) {
  if (!deviceIps || !deviceIps.length) return { success: false, error: 'No IPs specified' };
  const cmds = deviceIps.map(ip =>
    `New-NetFirewallRule -DisplayName '${FW_RULE_PREFIX}_${ip}' -Direction Outbound -Action Block -RemoteAddress '0.0.0.0/0' -LocalAddress '${ip}' -Profile Any -Enabled True -ErrorAction SilentlyContinue`
  );
  try {
    await executePS(cmds.join('; '));
    return { success: true, provider: 'firewall' };
  } catch (e) {
    return { success: false, provider: 'firewall', error: e.message };
  }
}

async function firewallUnblock(deviceIps) {
  if (!deviceIps || !deviceIps.length) return { success: false, error: 'No IPs specified' };
  const cmds = deviceIps.map(ip =>
    `Remove-NetFirewallRule -DisplayName '${FW_RULE_PREFIX}_${ip}' -ErrorAction SilentlyContinue`
  );
  try {
    await executePS(cmds.join('; '));
    return { success: true, provider: 'firewall' };
  } catch (e) {
    return { success: false, provider: 'firewall', error: e.message };
  }
}

// Remove ALL Lights Out firewall rules (cleanup).
async function firewallCleanup() {
  try {
    await executePS(`Remove-NetFirewallRule -DisplayName '${FW_RULE_PREFIX}*' -ErrorAction SilentlyContinue`);
    return { success: true };
  } catch { return { success: false }; }
}

// ─────────────────────────────────────────────────────────────────────────────
// Nuclear option: disable the local WiFi adapter entirely.
// Use with caution -- this kills WiFi for ALL devices connected
// to this machine's hosted network, and for this machine itself.
// ─────────────────────────────────────────────────────────────────────────────

async function disableWiFiAdapter() {
  try {
    // Find the WiFi adapter and disable it.
    await executePS(
      `$adapter = Get-NetAdapter | Where-Object { $_.InterfaceDescription -match 'Wi-Fi|Wireless|802.11|WLAN' -and $_.Status -eq 'Up' } | Select-Object -First 1; if ($adapter) { Disable-NetAdapter -Name $adapter.Name -Confirm:$false; Write-Output $adapter.Name }`
    );
    return { success: true, provider: 'adapter' };
  } catch (e) {
    return { success: false, provider: 'adapter', error: e.message };
  }
}

async function enableWiFiAdapter() {
  try {
    await executePS(
      `$adapter = Get-NetAdapter | Where-Object { $_.InterfaceDescription -match 'Wi-Fi|Wireless|802.11|WLAN' -and $_.Status -ne 'Up' } | Select-Object -First 1; if ($adapter) { Enable-NetAdapter -Name $adapter.Name -Confirm:$false; Write-Output $adapter.Name }`
    );
    return { success: true, provider: 'adapter' };
  } catch (e) {
    return { success: false, provider: 'adapter', error: e.message };
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Unified block/unblock: uses the configured provider.
// ─────────────────────────────────────────────────────────────────────────────

async function blockInternet(config) {
  const { provider, routerIp, routerUser, routerPass, deviceMacs, deviceIps, webhookUrl, webhookHeaders } = config;
  switch (provider) {
    case 'tplink':
      return tplinkBlock(routerIp, routerUser, routerPass, deviceMacs || []);
    case 'asus':
      return asusBlock(routerIp, routerUser, routerPass, deviceMacs || []);
    case 'netgear':
      return netgearBlock(routerIp, routerUser, routerPass, deviceMacs || []);
    case 'webhook':
      return webhookBlock(webhookUrl, deviceMacs || [], webhookHeaders || {});
    case 'firewall':
      return firewallBlock(deviceIps || []);
    case 'adapter':
      return disableWiFiAdapter();
    default:
      return { success: false, error: `Unknown provider: ${provider}` };
  }
}

async function unblockInternet(config) {
  const { provider, routerIp, routerUser, routerPass, deviceMacs, deviceIps, webhookUrl, webhookHeaders } = config;
  switch (provider) {
    case 'tplink':
      return tplinkUnblock(routerIp, routerUser, routerPass, deviceMacs || []);
    case 'asus':
      return asusUnblock(routerIp, routerUser, routerPass, deviceMacs || []);
    case 'netgear':
      return netgearUnblock(routerIp, routerUser, routerPass, deviceMacs || []);
    case 'webhook':
      return webhookUnblock(webhookUrl, deviceMacs || [], webhookHeaders || {});
    case 'firewall':
      return firewallUnblock(deviceIps || []);
    case 'adapter':
      return enableWiFiAdapter();
    default:
      return { success: false, error: `Unknown provider: ${provider}` };
  }
}

// Scan the local network for connected devices (arp table).
async function scanDevices() {
  try {
    const raw = await executePS(
      `Get-NetNeighbor -State Reachable | Where-Object { $_.IPAddress -notmatch '^(127|0\.|169\.254|ff00)' } | Select-Object IPAddress, LinkLayerAddress, InterfaceAlias | ConvertTo-Json -Compress`
    );
    if (!raw || raw === 'null') return [];
    const entries = JSON.parse(raw);
    const list = Array.isArray(entries) ? entries : [entries];
    return list.map(e => ({
      ip: e.IPAddress,
      mac: e.LinkLayerAddress,
      interface: e.InterfaceAlias
    }));
  } catch { return []; }
}

// ─────────────────────────────────────────────────────────────────────────────
// HTTP helper
// ─────────────────────────────────────────────────────────────────────────────

function httpPost(url, body, extraHeaders = {}) {
  return new Promise((resolve, reject) => {
    const urlObj = new URL(url);
    const isHttps = urlObj.protocol === 'https:';
    const mod = isHttps ? https : http;
    const data = typeof body === 'string' ? body : JSON.stringify(body);
    const options = {
      hostname: urlObj.hostname,
      port: urlObj.port || (isHttps ? 443 : 80),
      path: urlObj.pathname + urlObj.search,
      method: 'POST',
      headers: {
        'Content-Type': typeof body === 'string' ? 'text/xml' : 'application/json',
        'Content-Length': Buffer.byteLength(data),
        ...extraHeaders
      },
      rejectUnauthorized: false // router certs are often self-signed
    };
    const req = mod.request(options, (res) => {
      let result = '';
      res.on('data', chunk => result += chunk);
      res.on('end', () => resolve(result));
    });
    req.on('error', reject);
    req.setTimeout(8000, () => { req.destroy(); reject(new Error('Timeout')); });
    req.write(data);
    req.end();
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// PowerShell helper
// ─────────────────────────────────────────────────────────────────────────────

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
  blockInternet,
  unblockInternet,
  firewallCleanup,
  scanDevices,
  disableWiFiAdapter,
  enableWiFiAdapter
};
