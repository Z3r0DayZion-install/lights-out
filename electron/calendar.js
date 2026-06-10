// Calendar Module for Lights Out Electron
// Ported from PowerShell LightsOut.Calendar.psm1
// Parses iCalendar (.ics) files for scheduled shutdowns

const https = require('https');
const http = require('http');

// ─────────────────────────────────────────────────────────────────────────────
// ICS Line Processing
// ─────────────────────────────────────────────────────────────────────────────

function expandIcsLines(lines) {
  const out = [];
  for (const line of lines) {
    if (line.match(/^[ \t]/) && out.length > 0) {
      out[out.length - 1] = out[out.length - 1] + line.trimStart();
    } else if (line.trim()) {
      out.push(line.trim());
    }
  }
  return out;
}

// ─────────────────────────────────────────────────────────────────────────────
// ICS Date/Time Parsing
// ─────────────────────────────────────────────────────────────────────────────

function convertFromIcsDateTime(value, propLine = '') {
  if (!value) return null;
  value = value.trim();
  
  // Check for TZID in property line (best-effort local time handling)
  const tzidMatch = propLine.match(/TZID=([^:;]+)/);
  
  // Date-only format: 20240115
  if (value.match(/^\d{8}$/)) {
    const year = parseInt(value.substring(0, 4), 10);
    const month = parseInt(value.substring(4, 6), 10);
    const day = parseInt(value.substring(6, 8), 10);
    const date = new Date(year, month - 1, day, 0, 0, 0);
    return isNaN(date.getTime()) ? null : date;
  }
  
  // Remove trailing Z for UTC parsing
  const isUTC = value.endsWith('Z');
  const v = value.replace(/Z$/, '');
  
  const formats = [
    { regex: /^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})$/, indices: [1, 2, 3, 4, 5, 6] },
    { regex: /^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})$/, indices: [1, 2, 3, 4, 5] },
    { regex: /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})$/, indices: [1, 2, 3, 4, 5, 6] },
    { regex: /^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})$/, indices: [1, 2, 3, 4, 5, 6] },
    { regex: /^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2})$/, indices: [1, 2, 3, 4, 5] }
  ];
  
  for (const fmt of formats) {
    const match = v.match(fmt.regex);
    if (match) {
      const year = parseInt(match[fmt.indices[0]], 10);
      const month = parseInt(match[fmt.indices[1]], 10) - 1;
      const day = parseInt(match[fmt.indices[2]], 10);
      const hour = parseInt(match[fmt.indices[3]], 10);
      const minute = fmt.indices[4] ? parseInt(match[fmt.indices[4]], 10) : 0;
      const second = fmt.indices[5] && match[fmt.indices[5]] ? parseInt(match[fmt.indices[5]], 10) : 0;
      
      let date;
      if (isUTC) {
        date = new Date(Date.UTC(year, month, day, hour, minute, second));
        // Convert to local time
        date = new Date(date.getTime() - (date.getTimezoneOffset() * 60000));
      } else {
        date = new Date(year, month, day, hour, minute, second);
      }
      
      if (!isNaN(date.getTime())) return date;
    }
  }
  
  // Fallback to native parsing
  try {
    const date = new Date(value);
    return isNaN(date.getTime()) ? null : date;
  } catch {
    return null;
  }
}

function readIcsPropertyValue(line) {
  const colon = line.indexOf(':');
  if (colon < 0) return null;
  return line.substring(colon + 1).trim();
}

function getIcsPropertyName(line) {
  const colon = line.indexOf(':');
  if (colon < 0) return line.toUpperCase();
  const head = line.substring(0, colon);
  return head.split(';')[0].toUpperCase();
}

// ─────────────────────────────────────────────────────────────────────────────
// ICS Content Parsing
// ─────────────────────────────────────────────────────────────────────────────

function parseIcsContent(text) {
  if (!text) return [];
  
  const lines = expandIcsLines(text.split(/\r?\n/));
  const events = [];
  let inEvent = false;
  let currentEvent = { uid: '', summary: 'Event', start: null, end: null, location: '' };
  
  for (const line of lines) {
    const name = getIcsPropertyName(line);
    
    switch (name) {
      case 'BEGIN': {
        if (readIcsPropertyValue(line) === 'VEVENT') {
          inEvent = true;
          currentEvent = { uid: '', summary: 'Event', start: null, end: null, location: '' };
        }
        break;
      }
      case 'END': {
        if (inEvent && readIcsPropertyValue(line) === 'VEVENT') {
          if (currentEvent.start) {
            const event = {
              uid: currentEvent.uid || generateUid(),
              summary: currentEvent.summary || 'Event',
              start: currentEvent.start,
              end: currentEvent.end || new Date(currentEvent.start.getTime() + 60 * 60 * 1000),
              location: currentEvent.location || ''
            };
            events.push(event);
          }
          inEvent = false;
          currentEvent = { uid: '', summary: 'Event', start: null, end: null, location: '' };
        }
        break;
      }
      default: {
        if (!inEvent) continue;
        const value = readIcsPropertyValue(line);
        if (!value) continue;
        
        if (name === 'UID') {
          currentEvent.uid = value;
        } else if (name === 'SUMMARY') {
          currentEvent.summary = value.replace(/\\n/g, ' ').replace(/\\,/g, ',');
        } else if (name === 'LOCATION') {
          currentEvent.location = value.replace(/\\,/g, ',');
        } else if (name === 'DTSTART' || name === 'DTSTART;VALUE=DATE') {
          currentEvent.start = convertFromIcsDateTime(value, line);
        } else if (name === 'DTEND') {
          currentEvent.end = convertFromIcsDateTime(value, line);
        }
        break;
      }
    }
  }
  
  return events;
}

function generateUid() {
  return Date.now().toString(36) + Math.random().toString(36).substring(2, 9);
}

// ─────────────────────────────────────────────────────────────────────────────
// File Import
// ─────────────────────────────────────────────────────────────────────────────

function importIcsFromText(text, sourceName = 'Imported') {
  if (!text || !text.includes('BEGIN:VCALENDAR')) {
    throw new Error('Invalid iCalendar file: missing VCALENDAR header');
  }
  
  const events = parseIcsContent(text);
  return {
    source: sourceName,
    events: events,
    count: events.length
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// URL Import
// ─────────────────────────────────────────────────────────────────────────────

function testCalendarFeedUrl(url) {
  if (!url) return false;
  const u = url.trim();
  if (!u.startsWith('https://')) return false;
  if (u.includes(' ')) return false;
  return true;
}

async function importIcsFromUrl(url, timeoutMs = 45000) {
  if (!testCalendarFeedUrl(url)) {
    throw new Error('Calendar feed must be an https URL (Google Calendar secret iCal link or hosted .ics)');
  }
  
  return new Promise((resolve, reject) => {
    const urlObj = new URL(url.trim());
    const client = urlObj.protocol === 'https:' ? https : http;
    
    const options = {
      hostname: urlObj.hostname,
      path: urlObj.pathname + urlObj.search,
      method: 'GET',
      timeout: timeoutMs,
      headers: {
        'User-Agent': 'LightsOut/5.3 CalendarSync'
      }
    };
    
    const req = client.request(options, (res) => {
      if (res.statusCode !== 200) {
        reject(new Error(`HTTP ${res.statusCode}: Failed to fetch calendar`));
        return;
      }
      
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        if (!data || !data.includes('BEGIN:VCALENDAR')) {
          reject(new Error('Downloaded feed is not a valid iCalendar file'));
          return;
        }
        
        try {
          const events = parseIcsContent(data);
          resolve({
            source: url.trim(),
            events: events,
            count: events.length
          });
        } catch (error) {
          reject(error);
        }
      });
    });
    
    req.on('error', reject);
    req.on('timeout', () => {
      req.destroy();
      reject(new Error('Request timeout'));
    });
    
    req.end();
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Event Filtering & Utilities
// ─────────────────────────────────────────────────────────────────────────────

function getUpcomingEvents(events, from = new Date(), withinDays = 90, maxCount = 50) {
  const cutoff = new Date(from.getTime() + withinDays * 24 * 60 * 60 * 1000);
  
  return events
    .filter(e => e.start && e.start > from && e.start <= cutoff)
    .sort((a, b) => a.start - b.start)
    .slice(0, maxCount);
}

function getNextEvent(events, from = new Date()) {
  const upcoming = getUpcomingEvents(events, from, 365, 1);
  return upcoming.length > 0 ? upcoming[0] : null;
}

function formatEventTime(date) {
  if (!date) return 'Unknown';
  const now = new Date();
  const isToday = date.toDateString() === now.toDateString();
  const isTomorrow = new Date(now.getTime() + 24 * 60 * 60 * 1000).toDateString() === date.toDateString();
  
  const timeStr = date.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' });
  
  if (isToday) return `Today at ${timeStr}`;
  if (isTomorrow) return `Tomorrow at ${timeStr}`;
  
  const dateStr = date.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
  return `${dateStr} at ${timeStr}`;
}

function calculateDurationToEvent(event, from = new Date()) {
  if (!event || !event.start) return null;
  const diffMs = event.start.getTime() - from.getTime();
  const seconds = Math.max(0, Math.round(diffMs / 1000));
  return seconds;
}

// ─────────────────────────────────────────────────────────────────────────────
// Timer Profile Generation
// ─────────────────────────────────────────────────────────────────────────────

function createTimerFromEvent(event, action = 'shutdown', options = {}) {
  if (!event || !event.start) {
    return { success: false, error: 'Invalid event' };
  }
  
  const from = options.from || new Date();
  const durationSeconds = calculateDurationToEvent(event, from);
  
  if (durationSeconds <= 0) {
    return { success: false, error: 'Event has already started or passed' };
  }
  
  return {
    success: true,
    timerOptions: {
      durationSeconds,
      action,
      endsAt: event.start.toISOString(),
      dryRun: options.dryRun || false,
      forceShutdown: options.forceShutdown || false,
      muteSystem: options.muteSystem || false,
      gracePeriod: options.gracePeriod || 2
    },
    event: {
      uid: event.uid,
      summary: event.summary,
      start: event.start.toISOString(),
      end: event.end ? event.end.toISOString() : null,
      location: event.location
    }
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// Exports
// ─────────────────────────────────────────────────────────────────────────────

module.exports = {
  // Parsing
  parseIcsContent,
  importIcsFromText,
  
  // URL import
  testCalendarFeedUrl,
  importIcsFromUrl,
  
  // Filtering
  getUpcomingEvents,
  getNextEvent,
  
  // Utilities
  formatEventTime,
  calculateDurationToEvent,
  createTimerFromEvent,
  
  // Internal helpers (exposed for testing)
  convertFromIcsDateTime,
  expandIcsLines
};
