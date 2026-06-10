// Ported from PowerShell LightsOut.LastLight.psm1.
// Timer-zero finale copy and step timing (visual layer only).
// Dual-mode: usable via require() in Node/main and via <script> in the renderer.
(function (root, factory) {
  const mod = factory();
  if (typeof module !== 'undefined' && module.exports) module.exports = mod;
  if (root) root.LastLight = mod;
})(typeof window !== 'undefined' ? window : null, function () {
  const VALID_IDS = ['ClassicFade', 'ExitTheGrid', 'AntiAlgorithm', 'SignalSeverance'];

  function getCatalog() {
    return [
      { id: 'ClassicFade', name: 'Classic Fade', description: 'Calm fade before confirm' },
      { id: 'ExitTheGrid', name: 'Exit the Grid', description: 'Cyber unplug finale' },
      { id: 'AntiAlgorithm', name: 'Anti-Algorithm Protocol', description: 'Feed-resist shutdown ritual' },
      { id: 'SignalSeverance', name: 'Signal Severance', description: 'Premium severance checklist' }
    ];
  }

  function normalizeId(id) {
    if (!id) return 'ClassicFade';
    const raw = String(id).replace(/\s/g, '').replace(/_/g, '').toLowerCase();
    if (raw === 'classicfade') return 'ClassicFade';
    if (raw === 'exitthegrid') return 'ExitTheGrid';
    if (raw === 'antialgorithm' || raw === 'antialgorithmprotocol') return 'AntiAlgorithm';
    if (raw === 'signalseverance') return 'SignalSeverance';
    return 'ClassicFade';
  }

  function isValidId(id) {
    return VALID_IDS.indexOf(normalizeId(id)) !== -1;
  }

  function getMeta(sequenceId, dryRun) {
    const id = normalizeId(sequenceId);
    let finalLine;
    switch (id) {
      case 'ExitTheGrid': finalLine = 'You are no longer available to the system.'; break;
      case 'AntiAlgorithm': finalLine = 'The algorithm lost tonight.'; break;
      case 'SignalSeverance': finalLine = 'Signal severed. Night secured.'; break;
      default: finalLine = dryRun ? 'No power action will run.' : 'Night recovered.';
    }
    const sequenceLabel = {
      ExitTheGrid: 'EXIT THE GRID',
      AntiAlgorithm: 'ANTI-ALGORITHM PROTOCOL',
      SignalSeverance: 'SIGNAL SEVERANCE'
    }[id] || 'LAST LIGHT';
    return {
      id,
      finalLine,
      sequenceLabel,
      cinematicTitle: 'LAST LIGHT',
      stampLine: dryRun ? 'DRY RUN' : 'UNPLUGGED'
    };
  }

  function getSteps(sequenceId, dryRun) {
    const id = normalizeId(sequenceId);
    const meta = getMeta(id, dryRun);
    let lines;
    switch (id) {
      case 'ExitTheGrid':
        lines = [
          { headline: 'GRID HOLD WEAKENING', line: 'The feed is losing control.', dwellMs: 1800 },
          { headline: '', line: 'Breaking signal...', dwellMs: 1200 },
          { headline: '', line: 'Disconnecting feed...', dwellMs: 1200 },
          { headline: '', line: 'Exiting the grid...', dwellMs: 1500 },
          { headline: '', line: meta.finalLine, dwellMs: 2000 }
        ];
        break;
      case 'AntiAlgorithm':
        lines = [
          { headline: 'THE FEED WANTS ONE MORE CLICK', line: 'Lights Out says no.', dwellMs: 1800 },
          { headline: 'ANTI-ALGORITHM PROTOCOL', line: '', dwellMs: 1000 },
          { headline: '', line: 'Autoplay resisted.', dwellMs: 900 },
          { headline: '', line: 'Recommendations ignored.', dwellMs: 900 },
          { headline: '', line: 'Infinite scroll denied.', dwellMs: 900 },
          { headline: '', line: 'Session ending.', dwellMs: 1200 },
          { headline: '', line: meta.finalLine, dwellMs: 2000 }
        ];
        break;
      case 'SignalSeverance':
        lines = [
          { headline: 'SIGNAL SEVERANCE INITIATED', line: '', dwellMs: 1200 },
          { headline: '', line: 'Browser noise: muted', dwellMs: 900 },
          { headline: '', line: 'Video loop: severed', dwellMs: 900 },
          { headline: '', line: 'System glow: fading', dwellMs: 900 },
          { headline: '', line: 'Session: closing', dwellMs: 1200 },
          { headline: '', line: meta.finalLine, dwellMs: 2000 }
        ];
        break;
      default:
        lines = [
          { headline: 'LAST LIGHT', line: 'Your session is ending.', dwellMs: 2000 },
          { headline: meta.stampLine, line: meta.finalLine, dwellMs: 1800 }
        ];
    }
    if (dryRun) {
      lines = lines.map(s => ({ ...s, dwellMs: Math.max(400, Math.round(s.dwellMs * 0.35)) }));
    }
    return lines;
  }

  function getDurationMs(sequenceId, dryRun) {
    return getSteps(sequenceId, dryRun).reduce((sum, s) => sum + Number(s.dwellMs || 0), 0);
  }

  function getSoundCatalog() {
    return [
      { id: 'Off', name: 'Off' },
      { id: 'Soft', name: 'Soft tick' },
      { id: 'Silent', name: 'Silent' }
    ];
  }

  function normalizeSoundId(id) {
    const v = String(id || 'Off').toLowerCase();
    if (v === 'soft') return 'Soft';
    if (v === 'silent') return 'Silent';
    return 'Off';
  }

  return {
    VALID_IDS,
    getCatalog,
    normalizeId,
    isValidId,
    getMeta,
    getSteps,
    getDurationMs,
    getSoundCatalog,
    normalizeSoundId
  };
});
