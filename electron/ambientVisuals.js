// Ambient Visuals: canvas-rendered backgrounds during wind-down.
// Fireplace, rain, starfield, aurora. Makes the experience cinematic.

// Each visual is a render function that draws one frame.
// The engine calls the active visual at ~30fps via requestAnimationFrame.

let canvas = null;
let ctx = null;
let activeVisual = null;
let animFrame = null;
let particles = [];
let W = 0;
let H = 0;

const VISUALS = {
  fireplace: { label: 'Fireplace', icon: '\u{1F525}' },
  rain: { label: 'Rain on Glass', icon: '\u{1F327}' },
  starfield: { label: 'Starfield', icon: '\u{2B50}' },
  aurora: { label: 'Aurora', icon: '\u{1F3A4}' },
  off: { label: 'Off', icon: '\u274C' }
};

function init(canvasEl) {
  canvas = canvasEl;
  ctx = canvas.getContext('2d');
  resize();
  window.addEventListener('resize', resize);
}

function resize() {
  if (!canvas) return;
  const rect = canvas.parentElement?.getBoundingClientRect() || { width: 520, height: 760 };
  W = canvas.width = rect.width;
  H = canvas.height = rect.height;
}

function start(visualName) {
  stop();
  if (!canvas || visualName === 'off') return;
  activeVisual = visualName;
  particles = [];
  initParticles(visualName);
  tick();
}

function stop() {
  if (animFrame) { cancelAnimationFrame(animFrame); animFrame = null; }
  activeVisual = null;
  if (ctx && canvas) ctx.clearRect(0, 0, W, H);
}

function tick() {
  if (!activeVisual || !ctx) return;
  ctx.clearRect(0, 0, W, H);

  switch (activeVisual) {
    case 'fireplace': drawFireplace(); break;
    case 'rain': drawRain(); break;
    case 'starfield': drawStarfield(); break;
    case 'aurora': drawAurora(); break;
  }

  animFrame = requestAnimationFrame(tick);
}

function initParticles(name) {
  particles = [];
  switch (name) {
    case 'fireplace':
      for (let i = 0; i < 80; i++) particles.push(makeFireParticle());
      break;
    case 'rain':
      for (let i = 0; i < 120; i++) particles.push(makeRainDrop());
      break;
    case 'starfield':
      for (let i = 0; i < 200; i++) particles.push({ x: Math.random() * W, y: Math.random() * H, size: Math.random() * 2 + 0.5, alpha: Math.random(), speed: Math.random() * 0.02 + 0.005, phase: Math.random() * Math.PI * 2 });
      break;
    case 'aurora':
      for (let i = 0; i < 5; i++) particles.push({ offset: Math.random() * 100, speed: 0.3 + Math.random() * 0.5, hue: 120 + Math.random() * 80, amp: 20 + Math.random() * 40, y: H * 0.15 + Math.random() * H * 0.3 });
      break;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Fireplace
// ─────────────────────────────────────────────────────────────────────────────

function makeFireParticle() {
  return {
    x: W * 0.3 + Math.random() * W * 0.4,
    y: H * 0.85 + Math.random() * H * 0.15,
    vx: (Math.random() - 0.5) * 1.5,
    vy: -(1 + Math.random() * 3),
    life: 1,
    decay: 0.008 + Math.random() * 0.015,
    size: 2 + Math.random() * 6
  };
}

function drawFireplace() {
  // Base glow.
  const grad = ctx.createRadialGradient(W * 0.5, H * 0.85, 10, W * 0.5, H * 0.85, W * 0.5);
  grad.addColorStop(0, 'rgba(255, 100, 20, 0.15)');
  grad.addColorStop(0.5, 'rgba(180, 40, 0, 0.05)');
  grad.addColorStop(1, 'rgba(0,0,0,0)');
  ctx.fillStyle = grad;
  ctx.fillRect(0, 0, W, H);

  for (let i = particles.length - 1; i >= 0; i--) {
    const p = particles[i];
    p.x += p.vx + (Math.random() - 0.5) * 0.5;
    p.y += p.vy;
    p.life -= p.decay;
    if (p.life <= 0) { particles[i] = makeFireParticle(); continue; }

    const alpha = p.life * 0.8;
    const r = 255;
    const g = Math.floor(100 + p.life * 100);
    const b = Math.floor(p.life * 30);
    ctx.beginPath();
    ctx.arc(p.x, p.y, p.size * p.life, 0, Math.PI * 2);
    ctx.fillStyle = `rgba(${r},${g},${b},${alpha})`;
    ctx.fill();
  }

  // Ember glow at bottom.
  const ember = ctx.createLinearGradient(0, H * 0.85, 0, H);
  ember.addColorStop(0, 'rgba(255, 80, 0, 0.1)');
  ember.addColorStop(1, 'rgba(255, 30, 0, 0.05)');
  ctx.fillStyle = ember;
  ctx.fillRect(W * 0.2, H * 0.85, W * 0.6, H * 0.15);
}

// ─────────────────────────────────────────────────────────────────────────────
// Rain on Glass
// ─────────────────────────────────────────────────────────────────────────────

function makeRainDrop() {
  return {
    x: Math.random() * W,
    y: Math.random() * H,
    len: 8 + Math.random() * 20,
    speed: 4 + Math.random() * 8,
    alpha: 0.15 + Math.random() * 0.3,
    drift: (Math.random() - 0.5) * 0.3
  };
}

function drawRain() {
  // Dark blue-gray background.
  ctx.fillStyle = 'rgba(10, 15, 30, 0.03)';
  ctx.fillRect(0, 0, W, H);

  for (let i = particles.length - 1; i >= 0; i--) {
    const p = particles[i];
    p.y += p.speed;
    p.x += p.drift;
    if (p.y > H) { particles[i] = makeRainDrop(); particles[i].y = -p.len; continue; }

    ctx.beginPath();
    ctx.moveTo(p.x, p.y);
    ctx.lineTo(p.x + p.drift * 2, p.y + p.len);
    ctx.strokeStyle = `rgba(150, 180, 220, ${p.alpha})`;
    ctx.lineWidth = 1;
    ctx.stroke();

    // Tiny splash at bottom.
    if (p.y + p.len > H - 5) {
      ctx.beginPath();
      ctx.arc(p.x, H - 2, 2, 0, Math.PI, true);
      ctx.strokeStyle = `rgba(150, 180, 220, ${p.alpha * 0.5})`;
      ctx.stroke();
    }
  }

  // Fog overlay.
  ctx.fillStyle = 'rgba(100, 120, 150, 0.01)';
  ctx.fillRect(0, 0, W, H);
}

// ─────────────────────────────────────────────────────────────────────────────
// Starfield
// ─────────────────────────────────────────────────────────────────────────────

let starTime = 0;
function drawStarfield() {
  ctx.fillStyle = 'rgba(5, 5, 20, 0.05)';
  ctx.fillRect(0, 0, W, H);
  starTime += 0.016;

  for (const p of particles) {
    p.phase += p.speed;
    const alpha = 0.3 + Math.sin(p.phase) * 0.4;
    ctx.beginPath();
    ctx.arc(p.x, p.y, p.size, 0, Math.PI * 2);
    ctx.fillStyle = `rgba(220, 230, 255, ${alpha})`;
    ctx.fill();

    // Tiny cross sparkle on bright stars.
    if (p.size > 1.5 && alpha > 0.5) {
      ctx.strokeStyle = `rgba(220, 230, 255, ${alpha * 0.3})`;
      ctx.lineWidth = 0.5;
      ctx.beginPath(); ctx.moveTo(p.x - 4, p.y); ctx.lineTo(p.x + 4, p.y); ctx.stroke();
      ctx.beginPath(); ctx.moveTo(p.x, p.y - 4); ctx.lineTo(p.x, p.y + 4); ctx.stroke();
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Aurora
// ─────────────────────────────────────────────────────────────────────────────

let auroraTime = 0;
function drawAurora() {
  auroraTime += 0.01;
  ctx.fillStyle = 'rgba(5, 5, 20, 0.04)';
  ctx.fillRect(0, 0, W, H);

  for (const band of particles) {
    band.offset += band.speed;
    ctx.beginPath();
    ctx.moveTo(0, band.y);
    for (let x = 0; x <= W; x += 4) {
      const wave = Math.sin((x + band.offset) * 0.01) * band.amp +
                   Math.sin((x + band.offset * 0.7) * 0.02) * band.amp * 0.5;
      ctx.lineTo(x, band.y + wave);
    }
    ctx.lineTo(W, band.y + band.amp + 30);
    ctx.lineTo(0, band.y + band.amp + 30);
    ctx.closePath();

    const grad = ctx.createLinearGradient(0, band.y - band.amp, 0, band.y + band.amp + 30);
    const hueShift = Math.sin(auroraTime + band.offset * 0.01) * 20;
    grad.addColorStop(0, `hsla(${band.hue + hueShift}, 80%, 60%, 0)`);
    grad.addColorStop(0.4, `hsla(${band.hue + hueShift}, 80%, 50%, 0.06)`);
    grad.addColorStop(0.7, `hsla(${band.hue + hueShift + 30}, 70%, 40%, 0.04)`);
    grad.addColorStop(1, `hsla(${band.hue + hueShift + 60}, 60%, 30%, 0)`);
    ctx.fillStyle = grad;
    ctx.fill();
  }
}

function isActive() { return !!activeVisual; }
function getActive() { return activeVisual; }

module.exports = { init, start, stop, isActive, getActive, VISUALS };
