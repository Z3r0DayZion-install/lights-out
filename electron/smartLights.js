// Smart Lights Module for Lights Out Electron
// Ported from PowerShell LightsOut.SmartLights.psm1
// Supports: Philips Hue Bridge, Generic HTTP webhook

const { net } = require('electron');
const https = require('https');
const http = require('http');

// Configuration state
let config = {
  provider: 'none',        // 'none', 'hue', 'http'
  mode: 'gradual_dim',     // 'gradual_dim', 'warm_dim', 'off_at_end'
  dimMinutes: 10,          // minutes before end to start dimming
  enabled: false,
  // Hue settings
  hueBridgeIp: '',
  hueUsername: '',
  hueLightIds: [],         // array of light IDs (empty = all)
  hueGroupId: '',          // group/room ID (optional)
  // HTTP settings
  httpUrl: '',
  httpMethod: 'POST',
  httpHeaders: {},
  httpBodyTemplate: '{"brightness": {{BRIGHTNESS}}, "color_temp": {{COLOR_TEMP}}, "on": {{ON}}}',
  // MQTT settings
  mqttBroker: '',
  mqttPort: 1883,
  mqttTopic: 'lights/out/command',
  mqttUsername: '',
  mqttPassword: '',
  // Home Assistant settings
  haUrl: '',
  haToken: '',
  haEntityId: '',
  // IFTTT settings
  iftttWebhookKey: '',
  iftttEventName: 'lights_out'
};

// Runtime state
let state = {
  dimStarted: false,
  originalLightState: null,
  dimStartTime: null,
  dimDurationMs: 0
};

// ─────────────────────────────────────────────────────────────────────────────
// Hue Bridge Discovery & Registration
// ─────────────────────────────────────────────────────────────────────────────

async function findHueBridge() {
  try {
    const response = await fetch('https://discovery.meethue.com', { timeout: 5000 });
    const data = await response.json();
    if (data && data.length > 0) {
      return {
        ip: data[0].internalipaddress,
        id: data[0].id
      };
    }
  } catch (error) {
    console.error('Hue bridge discovery failed:', error.message);
  }
  return null;
}

async function registerHueBridge(bridgeIp) {
  try {
    const response = await fetch(`http://${bridgeIp}/api`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ devicetype: 'LightsOut#SleepTimer' }),
      timeout: 10000
    });
    const data = await response.json();
    if (data[0]?.success?.username) {
      return { username: data[0].success.username };
    }
    if (data[0]?.error) {
      return { error: data[0].error.description };
    }
  } catch (error) {
    return { error: error.message };
  }
  return null;
}

async function getHueLights(bridgeIp, username) {
  try {
    const response = await fetch(`http://${bridgeIp}/api/${username}/lights`, { timeout: 5000 });
    const data = await response.json();
    const lights = [];
    for (const [id, light] of Object.entries(data)) {
      lights.push({
        id: id,
        name: light.name,
        on: light.state.on,
        bri: light.state.bri || 0,
        ct: light.state.ct || 0,
        type: light.type
      });
    }
    return lights;
  } catch (error) {
    console.error('Failed to get Hue lights:', error.message);
    return [];
  }
}

async function getHueGroups(bridgeIp, username) {
  try {
    const response = await fetch(`http://${bridgeIp}/api/${username}/groups`, { timeout: 5000 });
    const data = await response.json();
    const groups = [];
    for (const [id, group] of Object.entries(data)) {
      groups.push({
        id: id,
        name: group.name,
        type: group.type,
        lights: group.lights
      });
    }
    return groups;
  } catch (error) {
    console.error('Failed to get Hue groups:', error.message);
    return [];
  }
}

async function setHueLightState(bridgeIp, username, lightId, lightState) {
  try {
    await fetch(`http://${bridgeIp}/api/${username}/lights/${lightId}/state`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(lightState),
      timeout: 5000
    });
  } catch (error) {
    console.error(`Failed to set Hue light ${lightId} state:`, error.message);
  }
}

async function setHueGroupState(bridgeIp, username, groupId, groupState) {
  try {
    await fetch(`http://${bridgeIp}/api/${username}/groups/${groupId}/action`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(groupState),
      timeout: 5000
    });
  } catch (error) {
    console.error(`Failed to set Hue group ${groupId} state:`, error.message);
  }
}

async function saveHueCurrentState(bridgeIp, username) {
  const lights = await getHueLights(bridgeIp, username);
  state.originalLightState = lights.filter(l => l.on);
}

// ─────────────────────────────────────────────────────────────────────────────
// HTTP Webhook Functions
// ─────────────────────────────────────────────────────────────────────────────

async function invokeHttpLightAction(brightness = 254, colorTemp = 366, on = true) {
  if (!config.httpUrl) return;
  try {
    const bodyStr = config.httpBodyTemplate
      .replace(/\{\{BRIGHTNESS\}\}/g, brightness)
      .replace(/\{\{COLOR_TEMP\}\}/g, colorTemp)
      .replace(/\{\{ON\}\}/g, on ? 'true' : 'false');

    const url = new URL(config.httpUrl);
    const options = {
      hostname: url.hostname,
      port: url.port || (url.protocol === 'https:' ? 443 : 80),
      path: url.pathname + url.search,
      method: config.httpMethod,
      headers: {
        'Content-Type': 'application/json',
        ...config.httpHeaders
      },
      timeout: 5000
    };

    const client = url.protocol === 'https:' ? https : http;
    
    return new Promise((resolve, reject) => {
      const req = client.request(options, (res) => {
        let data = '';
        res.on('data', chunk => data += chunk);
        res.on('end', () => resolve(data));
      });
      req.on('error', reject);
      req.on('timeout', () => {
        req.destroy();
        reject(new Error('Request timeout'));
      });
      req.write(bodyStr);
      req.end();
    });
  } catch (error) {
    console.error('HTTP light action failed:', error.message);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Home Assistant webhook
// ─────────────────────────────────────────────────────────────────────────────

async function invokeHAAction(brightness = 254, colorTemp = 366, on = true) {
  if (!config.haUrl || !config.haToken || !config.haEntityId) return;
  try {
    const url = `${config.haUrl.replace(/\/$/, '')}/api/services/light/turn_${on ? 'on' : 'off'}`;
    const body = on ? {
      entity_id: config.haEntityId,
      brightness: brightness,
      color_temp: colorTemp,
      transition: 1
    } : { entity_id: config.haEntityId };
    await fetch(url, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${config.haToken}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(5000)
    });
  } catch (err) {
    console.error('HA action failed:', err.message);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// IFTTT webhook
// ─────────────────────────────────────────────────────────────────────────────

async function invokeIFTTTAction(brightness = 254, on = true) {
  if (!config.iftttWebhookKey || !config.iftttEventName) return;
  try {
    const url = `https://maker.ifttt.com/trigger/${config.iftttEventName}/with/key/${config.iftttWebhookKey}`;
    await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ value1: brightness, value2: on ? 'on' : 'off', value3: 'lightsout' }),
      signal: AbortSignal.timeout(5000)
    });
  } catch (err) {
    console.error('IFTTT action failed:', err.message);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MQTT publish (TCP socket, no external deps)
// ─────────────────────────────────────────────────────────────────────────────

async function invokeMQTTAction(brightness = 254, on = true) {
  if (!config.mqttBroker) return;
  try {
    const net = require('net');
    const port = config.mqttPort || 1883;
    const topic = config.mqttTopic || 'lights/out/command';
    const payload = JSON.stringify({ brightness, on, source: 'lightsout' });
    // Simplified MQTT PUBLISH (QoS 0) - this is a minimal implementation
    // that encodes the packet manually without a full MQTT library.
    const topicBuf = Buffer.from(topic);
    const payloadBuf = Buffer.from(payload);
    const remainingLength = 2 + topicBuf.length + payloadBuf.length;
    const packet = Buffer.alloc(5 + remainingLength);
    packet[0] = 0x30; // PUBLISH, QoS 0
    let pos = 1;
    // Encode remaining length
    packet[pos++] = remainingLength;
    // Topic length (MSB, LSB)
    packet[pos++] = (topicBuf.length >> 8) & 0xFF;
    packet[pos++] = topicBuf.length & 0xFF;
    topicBuf.copy(packet, pos); pos += topicBuf.length;
    payloadBuf.copy(packet, pos);

    const client = net.createConnection({ host: config.mqttBroker, port }, () => {
      // CONNECT packet first
      const clientId = 'LightsOut_' + Date.now().toString(36);
      const connectPayload = Buffer.from(clientId);
      const connectRemaining = 10 + 2 + connectPayload.length;
      const connectPacket = Buffer.alloc(5 + connectRemaining + 2 + connectPayload.length);
      let cp = 0;
      connectPacket[cp++] = 0x10; // CONNECT
      // Remaining length encoding (simplified for small values)
      connectPacket[cp++] = connectRemaining + 2 + connectPayload.length;
      // Protocol name "MQTT"
      connectPacket[cp++] = 0; connectPacket[cp++] = 4;
      connectPacket.write('MQTT', cp); cp += 4;
      connectPacket[cp++] = 4; // Protocol level 4 (MQTT 3.1.1)
      connectPacket[cp++] = 0x02; // Clean session
      connectPacket[cp++] = 0; connectPacket[cp++] = 0; // Keep alive 0
      // Client ID
      connectPacket[cp++] = (connectPayload.length >> 8) & 0xFF;
      connectPacket[cp++] = connectPayload.length & 0xFF;
      connectPayload.copy(connectPacket, cp);
      client.write(connectPacket);
      // Then publish
      setTimeout(() => { client.write(packet); setTimeout(() => client.end(), 200); }, 100);
    });
    client.setTimeout(3000);
    client.on('timeout', () => client.destroy());
    client.on('error', () => client.destroy());
  } catch (err) {
    console.error('MQTT action failed:', err.message);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Timer Integration
// ─────────────────────────────────────────────────────────────────────────────

function startSmartLightDim(remainingSeconds) {
  if (!config.enabled || state.dimStarted) return;
  
  state.dimStarted = true;
  state.dimStartTime = Date.now();
  state.dimDurationMs = Math.min(remainingSeconds, config.dimMinutes * 60) * 1000;

  if (config.provider === 'hue' && config.hueBridgeIp && config.hueUsername) {
    saveHueCurrentState(config.hueBridgeIp, config.hueUsername);
  }
}

function updateSmartLightTick(remainingSeconds) {
  if (!config.enabled || !state.dimStarted) return;
  if (config.mode === 'off_at_end') return;

  const elapsedMs = Date.now() - state.dimStartTime;
  const progress = Math.min(1.0, Math.max(0.0, elapsedMs / state.dimDurationMs));

  // Calculate target brightness (254 -> 0)
  const targetBri = Math.round(254 * (1.0 - progress));

  // Calculate color temp for warm_dim mode (neutral 366 -> warm 500)
  const targetCt = config.mode === 'warm_dim' 
    ? Math.round(366 + (134 * progress))
    : 366;

  // Transition time in 100ms units (smooth 1-second steps = 10)
  const transition = 10;

  switch (config.provider) {
    case 'hue': {
      const lightState = { bri: targetBri, transitiontime: transition };
      if (config.mode === 'warm_dim') lightState.ct = targetCt;
      if (targetBri <= 0) lightState.on = false;

      if (config.hueGroupId) {
        setHueGroupState(config.hueBridgeIp, config.hueUsername, config.hueGroupId, lightState);
      } else {
        const ids = config.hueLightIds.length > 0 
          ? config.hueLightIds 
          : (state.originalLightState || []).map(l => l.id);
        for (const id of ids) {
          setHueLightState(config.hueBridgeIp, config.hueUsername, id, lightState);
        }
      }
      break;
    }
    case 'http': {
      invokeHttpLightAction(targetBri, targetCt, targetBri > 0);
      break;
    }
    case 'homeassistant': {
      invokeHAAction(targetBri, targetCt, targetBri > 0);
      break;
    }
    case 'ifttt': {
      invokeIFTTTAction(targetBri, targetBri > 0);
      break;
    }
    case 'mqtt': {
      invokeMQTTAction(targetBri, targetBri > 0);
      break;
    }
  }
}

async function invokeSmartLightOff() {
  if (!config.enabled) return;

  switch (config.provider) {
    case 'hue': {
      const lightState = { on: false, transitiontime: 10 };
      if (config.hueGroupId) {
        await setHueGroupState(config.hueBridgeIp, config.hueUsername, config.hueGroupId, lightState);
      } else {
        const ids = config.hueLightIds.length > 0 
          ? config.hueLightIds 
          : (state.originalLightState || []).map(l => l.id);
        for (const id of ids) {
          await setHueLightState(config.hueBridgeIp, config.hueUsername, id, lightState);
        }
      }
      break;
    }
    case 'http': {
      await invokeHttpLightAction(0, 366, false);
      break;
    }
    case 'homeassistant': {
      await invokeHAAction(0, 366, false);
      break;
    }
    case 'ifttt': {
      await invokeIFTTTAction(0, false);
      break;
    }
    case 'mqtt': {
      await invokeMQTTAction(0, false);
      break;
    }
  }
  state.dimStarted = false;
}

function resetSmartLightState() {
  state.dimStarted = false;
  state.originalLightState = null;
  state.dimStartTime = null;
  state.dimDurationMs = 0;
}

async function testSmartLightConnection() {
  switch (config.provider) {
    case 'hue': {
      if (!config.hueBridgeIp || !config.hueUsername) {
        return { success: false, message: 'Hue Bridge not configured' };
      }
      const lights = await getHueLights(config.hueBridgeIp, config.hueUsername);
      if (lights.length > 0) {
        return { success: true, message: `Connected: ${lights.length} lights found` };
      }
      return { success: false, message: 'No lights found - check bridge IP/username' };
    }
    case 'http': {
      if (!config.httpUrl) {
        return { success: false, message: 'No webhook URL configured' };
      }
      try {
        await invokeHttpLightAction(254, 366, true);
        return { success: true, message: `Sent test to ${config.httpUrl}` };
      } catch (error) {
        return { success: false, message: error.message };
      }
    }
    case 'homeassistant': {
      if (!config.haUrl || !config.haToken) return { success: false, message: 'HA URL/token not configured' };
      try {
        await invokeHAAction(254, 366, true);
        return { success: true, message: `Sent test to Home Assistant` };
      } catch (error) { return { success: false, message: error.message }; }
    }
    case 'ifttt': {
      if (!config.iftttWebhookKey) return { success: false, message: 'IFTTT key not configured' };
      try {
        await invokeIFTTTAction(254, true);
        return { success: true, message: 'Sent test to IFTTT' };
      } catch (error) { return { success: false, message: error.message }; }
    }
    case 'mqtt': {
      if (!config.mqttBroker) return { success: false, message: 'MQTT broker not configured' };
      try {
        await invokeMQTTAction(254, true);
        return { success: true, message: `Sent test to MQTT ${config.mqttBroker}:${config.mqttPort || 1883}` };
      } catch (error) { return { success: false, message: error.message }; }
    }
    default: {
      return { success: false, message: 'No provider selected' };
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Configuration Management
// ─────────────────────────────────────────────────────────────────────────────

function loadConfig(newConfig) {
  if (!newConfig) return;
  config = {
    ...config,
    provider: newConfig.provider || config.provider,
    mode: newConfig.mode || config.mode,
    dimMinutes: newConfig.dimMinutes !== undefined ? Number(newConfig.dimMinutes) : config.dimMinutes,
    enabled: newConfig.enabled !== undefined ? Boolean(newConfig.enabled) : config.enabled,
    hueBridgeIp: newConfig.hueBridgeIp || config.hueBridgeIp,
    hueUsername: newConfig.hueUsername || config.hueUsername,
    hueLightIds: newConfig.hueLightIds || config.hueLightIds,
    hueGroupId: newConfig.hueGroupId || config.hueGroupId,
    httpUrl: newConfig.httpUrl || config.httpUrl,
    httpMethod: newConfig.httpMethod || config.httpMethod,
    httpHeaders: newConfig.httpHeaders || config.httpHeaders,
    httpBodyTemplate: newConfig.httpBodyTemplate || config.httpBodyTemplate
  };
}

function getConfig() {
  return { ...config };
}

function shouldStartDim(remainingSeconds) {
  return config.enabled && !state.dimStarted && remainingSeconds <= config.dimMinutes * 60;
}

// ─────────────────────────────────────────────────────────────────────────────
// Exports
// ─────────────────────────────────────────────────────────────────────────────

module.exports = {
  // Configuration
  loadConfig,
  getConfig,
  
  // Hue functions
  findHueBridge,
  registerHueBridge,
  getHueLights,
  getHueGroups,
  
  // Timer integration
  startSmartLightDim,
  updateSmartLightTick,
  invokeSmartLightOff,
  resetSmartLightState,
  shouldStartDim,
  
  // Testing
  testSmartLightConnection,
  
  // Direct control
  setHueLightState,
  setHueGroupState,
  invokeHttpLightAction
};
