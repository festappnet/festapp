#!/usr/bin/env node

import http from 'node:http';
import { mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';

const projectRoot = path.resolve(import.meta.dirname, '../..');
const generator = path.join(projectRoot, 'automation/generate_pwa_service_worker.mjs');
const fixtureRoot = await mkdtemp(path.join(tmpdir(), 'festapp-browser-pwa-'));
const versions = ['1.0.0+1', '2.0.0+2'];
const workers = new Map();
let currentVersion = versions[0];

for (const version of versions) {
  const root = path.join(fixtureRoot, version.replace('+', '-'));
  await mkdir(root);
  await writeFile(path.join(root, 'flutter'), 'fixture');
  await writeFile(path.join(root, 'webclient'), 'fixture');
  await writeFile(path.join(root, 'main.dart.js'), `self.fixtureBuild=${JSON.stringify(version)};`);
  const result = spawnSync(process.execPath, [generator, root, version], { encoding: 'utf8' });
  if (result.status !== 0) throw new Error(result.stderr);
  workers.set(version, await readFile(path.join(root, 'festapp_service_worker.js'), 'utf8'));
}

function fixtureHtml(version) {
  return `<!doctype html>
<html><head><meta charset="utf-8"><title>Festapp PWA ${version}</title></head>
<body><h1>Festapp PWA fixture ${version}</h1><p id="status">starting</p>
<script>
const FIXTURE_VERSION=${JSON.stringify(version)};
window.__fixtureVersion=FIXTURE_VERSION;
function reportVersion(){navigator.serviceWorker.controller?.postMessage({type:'FESTAPP_CLIENT_VERSION',version:FIXTURE_VERSION});}
function workerRequest(type){return new Promise((resolve)=>{const channel=new MessageChannel();channel.port1.onmessage=(event)=>resolve(event.data);navigator.serviceWorker.controller.postMessage({type},[channel.port2]);});}
window.fixtureInspect=()=>workerRequest('FESTAPP_INSPECT_SHELLS');
window.fixturePrune=()=>workerRequest('FESTAPP_PRUNE_UNUSED_SHELLS');
window.fixtureCaches=()=>caches.keys();
window.fixtureUpdate=async()=>{
  const registration=await navigator.serviceWorker.getRegistration('/');
  await registration.update();
  let candidate=registration.waiting||registration.installing;
  if(candidate&&candidate.state!=='installed') await new Promise((resolve)=>candidate.addEventListener('statechange',()=>{if(candidate.state==='installed')resolve();}));
  candidate=registration.waiting||candidate;
  if(!candidate) throw new Error('updated worker did not install');
  const changed=new Promise((resolve)=>navigator.serviceWorker.addEventListener('controllerchange',resolve,{once:true}));
  candidate.postMessage('SKIP_WAITING');
  await changed;
  location.reload();
};
navigator.serviceWorker.addEventListener('message',(event)=>{if(event.data?.type==='FESTAPP_REPORT_VERSION')reportVersion();});
navigator.serviceWorker.addEventListener('controllerchange',reportVersion);
window.addEventListener('focus',reportVersion);
navigator.serviceWorker.register('/festapp_service_worker.js',{scope:'/',updateViaCache:'none'}).then(async()=>{
  await navigator.serviceWorker.ready;
  reportVersion();
  window.__fixtureReady=true;
  document.querySelector('#status').textContent='ready '+FIXTURE_VERSION;
});
</script></body></html>`;
}

const server = http.createServer((request, response) => {
  const url = new URL(request.url, 'http://127.0.0.1');
  if (url.pathname === '/__switch') {
    const requested = url.searchParams.get('version');
    if (!versions.includes(requested)) {
      response.writeHead(400).end('unknown version');
      return;
    }
    currentVersion = requested;
    response.writeHead(200, { 'content-type': 'application/json', 'cache-control': 'no-store' });
    response.end(JSON.stringify({ version: currentVersion }));
    return;
  }
  if (url.pathname === '/__state') {
    response.writeHead(200, { 'content-type': 'application/json', 'cache-control': 'no-store' });
    response.end(JSON.stringify({ version: currentVersion }));
    return;
  }
  response.setHeader('cache-control', 'no-store');
  if (url.pathname === '/festapp_service_worker.js') {
    response.setHeader('content-type', 'text/javascript');
    response.end(workers.get(currentVersion));
  } else if (url.pathname === '/main.dart.js') {
    response.setHeader('content-type', 'text/javascript');
    response.end(`self.fixtureBuild=${JSON.stringify(currentVersion)};`);
  } else if (url.pathname === '/' || url.pathname === '/webclient' || url.pathname === '/flutter') {
    response.setHeader('content-type', 'text/html; charset=utf-8');
    response.end(fixtureHtml(currentVersion));
  } else {
    response.writeHead(404).end('not found');
  }
});

const port = Number(process.argv[2] || 4179);
server.listen(port, '127.0.0.1', () => {
  console.log(`pwa-browser-fixture http://127.0.0.1:${port}`);
});

async function close() {
  server.close();
  await rm(fixtureRoot, { recursive: true, force: true });
}
process.on('SIGINT', () => close().finally(() => process.exit(0)));
process.on('SIGTERM', () => close().finally(() => process.exit(0)));
