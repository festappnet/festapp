#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '../..');
const manifestValue = process.env.FESTAPP_RELEASE_MANIFEST?.trim();
if (!manifestValue) {
  throw new Error('Set FESTAPP_RELEASE_MANIFEST to the private release config.json');
}
const manifestPath = fs.realpathSync(manifestValue);
const listingRoot = path.dirname(manifestPath);
const releaseConfig = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
const googlePlay = releaseConfig.googlePlay;
if (!releaseConfig.androidPackage || !googlePlay?.locale || !googlePlay?.metadataDirectory ||
    !googlePlay?.artworkDirectory || !googlePlay?.screenshotManifest || !googlePlay?.screenshotSets) {
  throw new Error('Release manifest lacks the Google Play publishing contract');
}
const listingPath = (relative) => {
  const resolved = path.resolve(listingRoot, relative);
  if (resolved !== listingRoot && !resolved.startsWith(`${listingRoot}${path.sep}`)) {
    throw new Error(`Release path escapes listing root: ${relative}`);
  }
  return resolved;
};
const listing = listingPath(googlePlay.metadataDirectory);
const playAssets = listingPath(googlePlay.artworkDirectory);
const locale = googlePlay.locale;
const target = path.join(root, 'build/release/google-play-metadata', locale);
const manifest = JSON.parse(fs.readFileSync(listingPath(googlePlay.screenshotManifest), 'utf8'));

function pngSize(file) {
  const data = fs.readFileSync(file);
  if (data.toString('ascii', 1, 4) !== 'PNG') throw new Error(`Not PNG: ${file}`);
  return [data.readUInt32BE(16), data.readUInt32BE(20)];
}

function pngColorType(file) {
  const data = fs.readFileSync(file);
  if (data.toString('ascii', 1, 4) !== 'PNG') throw new Error(`Not PNG: ${file}`);
  return data.readUInt8(25);
}

function sha256(file) {
  return crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
}

function stageSet(name, config) {
  const set = manifest.sets[name];
  if (!set || !config?.sourceDirectory || !Array.isArray(config.destinationDirectories)) {
    throw new Error(`Incomplete Google Play screenshot set: ${name}`);
  }
  const sourceDir = listingPath(config.sourceDirectory);
  const actual = fs.readdirSync(sourceDir).filter(f => f.endsWith('.png')).sort();
  if (JSON.stringify(actual) !== JSON.stringify(set.files)) throw new Error(`${name}: file list differs from manifest`);
  for (const file of set.files) {
    const input = path.join(sourceDir, file);
    if (JSON.stringify(pngSize(input)) !== JSON.stringify(set.size)) throw new Error(`${name}/${file}: unexpected dimensions`);
    for (const dir of config.destinationDirectories) {
      fs.mkdirSync(path.join(target, 'images', dir), { recursive: true });
      fs.copyFileSync(input, path.join(target, 'images', dir, file));
    }
  }
}

fs.rmSync(target, { recursive: true, force: true });
fs.mkdirSync(target, { recursive: true });
for (const file of ['title.txt', 'short_description.txt', 'full_description.txt']) {
  const input = path.join(listing, file);
  fs.copyFileSync(input, path.join(target, file));
}
const changelogSource = path.join(listing, 'changelogs');
const changelogTarget = path.join(target, 'changelogs');
fs.mkdirSync(changelogTarget, { recursive: true });
for (const file of fs.readdirSync(changelogSource).filter(file => file.endsWith('.txt'))) {
  fs.copyFileSync(path.join(changelogSource, file), path.join(changelogTarget, file));
}

const icon = path.join(playAssets, 'icon.png');
if (JSON.stringify(pngSize(icon)) !== JSON.stringify([512, 512])) throw new Error('Play icon must be 512x512');
if (pngColorType(icon) !== 2) throw new Error('Play icon must be RGB without an alpha channel');
const featureGraphic = path.join(playAssets, 'featureGraphic.png');
if (JSON.stringify(pngSize(featureGraphic)) !== JSON.stringify([1024, 500])) throw new Error('Play feature graphic must be 1024x500');
if (pngColorType(featureGraphic) !== 2) throw new Error('Play feature graphic must be RGB without an alpha channel');
fs.mkdirSync(path.join(target, 'images'), { recursive: true });
fs.copyFileSync(icon, path.join(target, 'images/icon.png'));
fs.copyFileSync(featureGraphic, path.join(target, 'images/featureGraphic.png'));
for (const [name, config] of Object.entries(googlePlay.screenshotSets)) stageSet(name, config);

const evidence = [];
for (const file of fs.readdirSync(target, { recursive: true }).sort()) {
  const absolute = path.join(target, file);
  if (fs.statSync(absolute).isFile()) evidence.push({ path: file.replaceAll('\\', '/'), sha256: sha256(absolute) });
}
fs.writeFileSync(path.join(target, 'staging-manifest.json'), `${JSON.stringify({ packageName: releaseConfig.androidPackage, files: evidence }, null, 2)}\n`);
console.log(`Staged ${releaseConfig.androidPackage} metadata for ${locale}.`);
