// Renders assets/icon.svg into multi-resolution PNGs and a Windows .ico,
// plus a high-res brand PNG. Run with: node scripts/make-icons.js
const fs = require('fs');
const path = require('path');
const sharp = require('sharp');

const root = path.join(__dirname, '..');
const assets = path.join(root, 'assets');
const iconSvg = path.join(assets, 'icon.svg');
const logoSvg = path.join(assets, 'logo.svg');

const icoSizes = [16, 24, 32, 48, 64, 128, 256];

async function render(svgPath, size) {
  return sharp(svgPath, { density: 384 })
    .resize(size, size, { fit: 'contain', background: { r: 0, g: 0, b: 0, alpha: 0 } })
    .png()
    .toBuffer();
}

(async () => {
  const pngToIco = (await import('png-to-ico')).default;
  const svg = fs.readFileSync(iconSvg);

  // Multi-size PNG buffers for the ICO.
  const pngBuffers = [];
  for (const size of icoSizes) {
    pngBuffers.push(await render(iconSvg, size));
  }
  const ico = await pngToIco(pngBuffers);
  fs.writeFileSync(path.join(assets, 'icon.ico'), ico);
  console.log('Wrote assets/icon.ico');

  // App / store icon PNG.
  await sharp(svg, { density: 384 }).resize(512, 512).png().toFile(path.join(assets, 'icon-512.png'));
  console.log('Wrote assets/icon-512.png');

  // Transparent brand logo PNG for the UI.
  await sharp(fs.readFileSync(logoSvg), { density: 384 })
    .resize(512, 512, { fit: 'contain', background: { r: 0, g: 0, b: 0, alpha: 0 } })
    .png()
    .toFile(path.join(assets, 'logo-512.png'));
  console.log('Wrote assets/logo-512.png');
})().catch(err => {
  console.error(err);
  process.exit(1);
});
