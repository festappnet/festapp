import { access, readdir, stat } from 'node:fs/promises';
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
]);

export function shouldPrecache(relativePath) {
  const name = path.posix.basename(relativePath);
  if (excludedNames.has(name)) return false;
  if (name === 'NOTICES' || name.endsWith('.map') || name.endsWith('.symbols')) {
    return false;
  }
  return !(/^main\.dart\..+\.js$/.test(name) &&
    !/^main\.dart\.js_\d+\.part\.js$/.test(name));
}

export function deploymentUrl(url) {
  if (url === '/flutter') return '/flutter?pwa-cache=1';
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
  const files = await collectFiles(buildDir);
  const byUrl = new Map();
  for (const file of files) {
    const existing = byUrl.get(file.url);
    byUrl.set(file.url, existing ? {...existing, bytes: existing.bytes + file.bytes} : file);
  }

  const knownResources = [...byUrl.keys()];
  const standaloneDocuments = knownResources.filter((url) =>
    url !== '/' && url.endsWith('/'));
  const standaloneDocumentSet = new Set(standaloneDocuments);
  const installCriticalNames = new Set([
    '/flutter.js', '/flutter_bootstrap.js', '/main.dart.js',
    '/festapp_update_prompt.js', '/festapp_pwa_bridge.js',
    '/festapp-version.json', '/manifest.json', '/manifest.webmanifest',
    '/AssetManifest.json', '/FontManifest.json',
  ]);
  const coreResources = knownResources.filter((url) =>
    url === flutterEntry || url === webClientEntry ||
    standaloneDocumentSet.has(url) ||
    installCriticalNames.has(url.split('?')[0]) ||
    /^\/main\.dart\.js_\d+\.part\.js$/.test(url.split('?')[0]));
  const total = (resources) => resources.reduce(
    (sum, url) => sum + (byUrl.get(url)?.bytes ?? 0), 0);

  return {
    flutterEntry,
    webClientEntry,
    standaloneDocuments,
    coreResources,
    knownResources,
    coreBytes: total(coreResources),
    knownBytes: total(knownResources),
  };
}
