#!/usr/bin/env node
/**
 * Render favicons + app icons from a single source SVG.
 *
 * Usage:
 *   node scripts/generate_icons.mjs <source.svg>
 *
 * Requires `sharp` (we reuse the copy in workers/image-worker/node_modules).
 */
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';

const __dirname = dirname(fileURLToPath(import.meta.url));
const projectRoot = resolve(__dirname, '..');

const sharpPath = resolve(projectRoot, 'workers/image-worker/node_modules/sharp/lib/index.js');
const { default: sharp } = await import(sharpPath);

const iconSvg = readFileSync(resolve(projectRoot, 'web/csmostrava-icon.svg'));
const logoSvg = readFileSync(resolve(projectRoot, 'web/csmostrava-logo.svg'));
const logoProgramSvg = readFileSync(resolve(projectRoot, 'web/csmostrava-logo-program.svg'));

// Square favicons / launcher icons → use the icon SVG (cloud only).
const iconTargets = [
  { path: 'web/favicon-96x96.png', size: 96 },
  { path: 'web/apple-touch-icon.png', size: 180 },
  { path: 'web/android-chrome-192x192.png', size: 192 },
  { path: 'web/android-chrome-512x512.png', size: 512 },
  { path: 'web/notification-icon-256x256.png', size: 256 },
  { path: 'web/web-app-manifest-192x192.png', size: 192 },
  { path: 'web/web-app-manifest-512x512.png', size: 512 },
  { path: 'assets/icons/fstappicon.png', size: 512 },
];

for (const { path, size } of iconTargets) {
  const out = resolve(projectRoot, path);
  mkdirSync(dirname(out), { recursive: true });
  await sharp(iconSvg, { density: 384 })
    .resize(size, size, {
      fit: 'contain',
      background: { r: 0, g: 0, b: 0, alpha: 0 },
    })
    .png()
    .toFile(out);
  console.log(`✓ ${path} (${size}×${size}) [icon-only]`);
}

// Header logo (cloud + text) — wide aspect, used by LogoWidget in the app.
// Two variants: default (blue cloud + orange text) and "program" (swap), used
// by schedule pages so they're visually distinct from the main app header.
const logoVariants = [
  { svg: logoSvg, targets: ['web/fstapplogo.png', 'assets/icons/fstapplogo.png'], label: 'logo+text' },
  { svg: logoProgramSvg, targets: ['assets/icons/fstapplogo_program.png'], label: 'logo+text program' },
];

for (const { svg, targets, label } of logoVariants) {
  for (const path of targets) {
    const out = resolve(projectRoot, path);
    mkdirSync(dirname(out), { recursive: true });
    await sharp(svg, { density: 384 })
      .resize({ width: 1024, fit: 'contain', background: { r: 0, g: 0, b: 0, alpha: 0 } })
      .png()
      .toFile(out);
    console.log(`✓ ${path} (1024w) [${label}]`);
  }
}

// Build a multi-resolution favicon.ico (16, 32, 48). Sharp can't write ICO,
// so concatenate the BMP/PNG payloads into the ICO container directly.
const icoSizes = [16, 32, 48];
const icoBuffers = await Promise.all(
  icoSizes.map((s) =>
    sharp(iconSvg, { density: 384 })
      .resize(s, s, { fit: 'contain', background: { r: 0, g: 0, b: 0, alpha: 0 } })
      .png()
      .toBuffer()
  )
);

function buildIco(images) {
  const header = Buffer.alloc(6);
  header.writeUInt16LE(0, 0); // reserved
  header.writeUInt16LE(1, 2); // type: icon
  header.writeUInt16LE(images.length, 4); // count

  const entries = [];
  const payloads = [];
  let offset = 6 + images.length * 16;
  for (let i = 0; i < images.length; i++) {
    const buf = images[i];
    const size = icoSizes[i];
    const entry = Buffer.alloc(16);
    entry.writeUInt8(size >= 256 ? 0 : size, 0); // width
    entry.writeUInt8(size >= 256 ? 0 : size, 1); // height
    entry.writeUInt8(0, 2); // palette
    entry.writeUInt8(0, 3); // reserved
    entry.writeUInt16LE(1, 4); // color planes
    entry.writeUInt16LE(32, 6); // bits per pixel
    entry.writeUInt32LE(buf.length, 8); // size of image data
    entry.writeUInt32LE(offset, 12); // offset
    entries.push(entry);
    payloads.push(buf);
    offset += buf.length;
  }
  return Buffer.concat([header, ...entries, ...payloads]);
}

const icoBuffer = buildIco(icoBuffers);
const icoOut = resolve(projectRoot, 'web/favicon.ico');
writeFileSync(icoOut, icoBuffer);
console.log(`✓ web/favicon.ico (${icoSizes.join('/')})`);
