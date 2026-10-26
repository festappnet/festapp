import { access, readFile, readdir, stat } from 'node:fs/promises';
import path from 'node:path';

const excludedNames = new Set([
  '.last_build_id',
  '_headers',
  '_redirects',
  '_worker.js',
  'backend-activation.json',
  'client-sync-config.json',
  'flutter_service_worker.js',
  'festapp_service_worker.js',
  'organizers-page',
  'organizer-pages.json',
  'platform-updates.json',
]);

export function shouldPrecache(relativePath) {
  // The vendored editor ships optional standalone example resources. Festapp
  // supplies its own layout resources and never loads this fixture bundle.
  // Keep it available online without spending users' offline cache budget.
  if (relativePath === 'assets/packages/venue_seat_picker/assets/layout_fonts/fixtures.json') return false;
  // Marketing demonstrations are streamed, not part of the offline app.
  if (relativePath.startsWith('napoveda/')) return false;
  if (relativePath.startsWith('organizers/') || relativePath.startsWith('organizers-media/') || /^web-assets\/landing-[^/]+\.js$/.test(relativePath)) return false;
  const name = path.posix.basename(relativePath);
  if (excludedNames.has(name)) return false;
  if (name === 'NOTICES' || name.endsWith('.map') || name.endsWith('.symbols')) {
    return false;
  }
  return !(/^main\.dart\..+\.js$/.test(name) &&
    !/^main\.dart\.(?:[0-9][0-9A-Za-z.+-]*\.)?js_\d+\.part\.js$/.test(name));
}

export function deploymentUrl(url) {
  if (url === '/flutter') return '/flutter?pwa-cache=1';
  if (url === '/organizers-page') return '/pro-poradatele';
  if (url === '/webclient') return '/webclient?pwa-cache=1';
  return url.endsWith('/index.html') ? url.slice(0, -'index.html'.length) : url;
}

async function collectFiles(directory, prefix = '') {
  const entries = await readdir(directory, { withFileTypes: true });
  const files = [];
  for (const entry of entries.sort((a, b) => a.name.localeCompare(b.name))) {
    const relativePath = path.posix.join(prefix, entry.name);
    const absolutePath = path.join(directory, entry.name);
    if (entry.isDirectory()) {
      files.push(...await collectFiles(absolutePath, relativePath));
    } else if (entry.isFile() && shouldPrecache(relativePath)) {
      files.push({
        relativePath,
        url: deploymentUrl(`/${relativePath}`),
        bytes: (await stat(absolutePath)).size,
      });
    }
  }
  return files;
}

async function firstExisting(buildDir, candidates) {
  for (const candidate of candidates) {
    try {
      await access(path.join(buildDir, candidate));
      return deploymentUrl(`/${candidate}`);
    } catch (_) {}
  }
  throw new Error(`Missing required entry point: ${candidates.join(' or ')}`);
}

export async function collectPwaShellManifest(buildDir) {
  const flutterEntry = await firstExisting(buildDir, ['flutter', 'flutter.html']);
  const webClientEntry = await firstExisting(buildDir, ['webclient', 'index.html']);
  let flutterMain = '/main.dart.js';
  try {
    const versionManifest = JSON.parse(await readFile(
      path.join(buildDir, 'festapp-version.json'), 'utf8'));
    if (!/^main\.dart\.[0-9][0-9A-Za-z.+-]*\.js$/.test(versionManifest.main)) {
      throw new Error('Invalid immutable Flutter entrypoint in festapp-version.json');
    }
    flutterMain = '/' + versionManifest.main;
  } catch (error) {
    if (error.code !== 'ENOENT') throw error;
  }
  let marketing = {enabled:false,pages:[]};
  try { marketing = JSON.parse(await readFile(path.join(buildDir,'organizer-pages.json'),'utf8')); }
  catch (error) { if (error.code !== 'ENOENT') throw error; }
  const marketingRoutes = Object.fromEntries(marketing.pages.map(page=>[page.path,page.asset]));
  for (const asset of Object.values(marketingRoutes)) await access(path.join(buildDir,asset));
  const organizerHomepage = marketing.enabled && Boolean(marketingRoutes['/']);
  const collected = await collectFiles(buildDir);
  let canvasKitOnly = false;
  try {
    const bootstrap = await readFile(path.join(buildDir, 'flutter_bootstrap.js'), 'utf8');
    const config = bootstrap.match(/^_flutter\.buildConfig\s*=\s*(\{.*\});\s*$/m)?.[1];
    const builds = config && JSON.parse(config).builds;
    canvasKitOnly = Array.isArray(builds) && builds.length > 0 &&
      builds.every(build => build.compileTarget === 'dart2js' && build.renderer === 'canvaskit');
  } catch (_) {
    // Unknown/older bootstrap formats retain the conservative complete set.
  }
  const filesWithImmutableChunks = new Set(collected.map(entry => entry.url));
  const files = collected.filter(entry => {
    // Flutter ships both engines even for a CanvasKit-only build. Skwasm and
    // Wimp cannot be selected by that build; retain every CanvasKit variant.
    if (canvasKitOnly && /^\/canvaskit\/(?:skwasm(?:_heavy)?|wimp)\.(?:js|wasm)$/.test(entry.url)) return false;
    if (!/^\/main\.dart\..*js_\d+\.part\.js$/.test(entry.url)) return true;
    // Keep only this release's chunk when its immutable alias exists.
    const suffix = entry.url.match(/js_(\d+\.part\.js)$/)[1];
    const immutable = `${flutterMain}_${suffix}`;
    return !filesWithImmutableChunks.has(immutable) || entry.url === immutable;
  });
  if (flutterMain !== '/main.dart.js') {
    // Flutter HTML requests the immutable name. Cache exactly that executable,
    // rather than an unused mutable copy with identical bytes.
    const file = path.join(buildDir, flutterMain.slice(1));
    const aliasIndex = files.findIndex((entry) => entry.url === '/main.dart.js');
    if (aliasIndex !== -1) files.splice(aliasIndex, 1);
    files.push({ url: flutterMain, bytes: (await stat(file)).size });
  }
  const updatePages=marketing.pages.filter(page=>page.type==='updates-index' || page.type==='update-detail');
  for (const page of updatePages) files.push({url:page.path,bytes:(await stat(path.join(buildDir,page.asset))).size});
  const byUrl = new Map();
  for (const file of files) {
    const existing = byUrl.get(file.url);
    byUrl.set(file.url, existing ? {...existing, bytes: existing.bytes + file.bytes} : file);
  }

  const knownResources = [...byUrl.keys()];
  const standaloneDocuments = knownResources.filter((url) =>
    url !== '/' && (url.endsWith('/') || url === '/pro-poradatele'));
  const standaloneDocumentSet = new Set(standaloneDocuments);
  const installCriticalNames = new Set([
    '/flutter.js', '/flutter_bootstrap.js', '/main.dart.js',
    '/festapp_update_prompt.js', '/festapp_pwa_bridge.js',
    '/festapp_flutter_bootstrap_guard.js',
    '/festapp-version.json', '/manifest.json', '/manifest.webmanifest',
    '/AssetManifest.json', '/FontManifest.json',
  ]);
  const coreResources = knownResources.filter((url) =>
    url === flutterEntry || url === webClientEntry ||
    // Every lazy web module belongs to the same immutable build. Open forms
    // must still open their seat selector after a newer deployment replaces assets.
    (url.startsWith('/web-assets/') && /\.(?:js|css)$/.test(url)) ||
    url.startsWith('/assets/translations/') ||
    standaloneDocumentSet.has(url) ||
    url === flutterMain ||
    installCriticalNames.has(url.split('?')[0]) ||
    /^\/festapp_(?:update_prompt|flutter_bootstrap_guard|pwa_bridge)\.[0-9][0-9A-Za-z.+-]*\.js$/.test(url) ||
    /^\/main\.dart\.(?:[0-9][0-9A-Za-z.+-]*\.)?js_\d+\.part\.js$/.test(url.split('?')[0]));
  const total = (resources) => resources.reduce(
    (sum, url) => sum + (byUrl.get(url)?.bytes ?? 0), 0);

  return {
    flutterEntry,
    organizerHomepage,
    marketingRoutes,
    publicUpdatePaths:updatePages.map(page=>page.path),
    publicFeeds:marketing.feeds ?? [],
    flutterMain,
    webClientEntry,
    standaloneDocuments,
    coreResources,
    knownResources,
    coreBytes: total(coreResources),
    knownBytes: total(knownResources),
  };
}
