// Test transport for an OWNED headless Chrome only. Never a production service.
import fs from 'node:fs';
import {createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';

const [cdpFile, statusFile, templateFile, receiptFile] = process.argv.slice(2);
if (![cdpFile, statusFile, templateFile, receiptFile].every(Boolean)) {
  throw Error('Usage: node tests/checkout-proxy.mjs <cdp-url-file> <local-backend-status> <production-html-template> <private-receipt>');
}
const status = JSON.parse(fs.readFileSync(statusFile, 'utf8'));
if (status.API_URL !== 'http://127.0.0.1:59821' || !status.ANON_KEY) throw Error('Disposable backend required');
const databaseGuard = execFileSync('docker', [
  'exec', 'supabase_db_festapp-vo-wordpress-20261023', 'psql', '-X', '-U', 'postgres', '-d', 'postgres', '-Atqc',
  "select count(*)=1 and min(title)='Test Organization' from public.organizations; select count(*)=1 from public.forms where link='wix-qa-20261025';",
], {encoding:'utf8'}).trim();
if (databaseGuard !== 't\nt') throw Error('Synthetic database guard failed');
const endpoint = fs.readFileSync(cdpFile, 'utf8').trim();
if (!/^ws:\/\/127\.0\.0\.1:\d+\/devtools\/browser\/[a-zA-Z0-9-]+$/.test(endpoint)) throw Error('Loopback CDP required');
const template = fs.readFileSync(templateFile);
const receipt = {
  backend: status.API_URL, syntheticBackendGuard: true,
  templateSha256: createHash('sha256').update(template).digest('hex'),
  clientVersion: /__FESTAPP_BUILD_VERSION__\s*=\s*"([^"]+)"/.exec(template.toString())?.[1],
  transportAdapted: true, productionCorsQualified: false, requests: [], networkFenceProbes: [],
};
const persist = () => fs.writeFileSync(receiptFile, JSON.stringify(receipt, null, 2) + '\n', {mode:0o600});
const ws = new WebSocket(endpoint);
await new Promise((resolve, reject) => { ws.addEventListener('open', resolve, {once:true}); ws.addEventListener('error', reject, {once:true}); });
let nextId = 0, ownsBrowser = false, stopping = false, interceptionEnabled = false;
const pending = new Map(), setups = new Map(), probeRequests = new Map(), probeErrors = new Map();
function call(method, params = {}, sessionId) {
  return new Promise((resolve, reject) => {
    const id = ++nextId;
    const timer = setTimeout(() => { pending.delete(id); reject(Error(`${method} timed out`)); }, 10000);
    pending.set(id, {resolve, reject, timer});
    ws.send(JSON.stringify({id, method, params, sessionId}));
  });
}
async function stop(error) {
  if (stopping) return;
  stopping = true;
  if (error) console.error(error.message);
  // Ownership and persistent network fencing are established before any Fetch setup.
  if (ownsBrowser && ws.readyState === WebSocket.OPEN) await call('Browser.close').catch(() => {});
  ws.close();
  process.exit(error ? 1 : 0);
}
process.on('SIGINT', () => void stop());
process.on('SIGTERM', () => void stop());
process.on('unhandledRejection', error => void stop(error instanceof Error ? error : Error(String(error))));
process.on('uncaughtException', error => void stop(error));
ws.addEventListener('error', () => void stop(Error('CDP connection failed; browser network fence remains active')));
ws.addEventListener('close', () => {
  if (!stopping) { persist(); console.error('CDP disconnected; browser launch DNS fence still blocks production backend access.'); }
});
async function configure(sessionId) {
  await call('Fetch.enable', {patterns:[
    {urlPattern:'https://api.festapp.net/*', requestStage:'Request'},
    {urlPattern:'https://*.supabase.co/*', requestStage:'Request'},
    {urlPattern:'https://vstupenky.online/form/wix-qa-20261025*', requestStage:'Request'},
  ]}, sessionId);
  await call('Target.setAutoAttach', {autoAttach:true, waitForDebuggerOnStart:true, flatten:true,
    filter:[{type:'page'}, {type:'iframe'}]}, sessionId);
  await call('Runtime.runIfWaitingForDebugger', {}, sessionId);
}
async function intercept({requestId, request}, sessionId) {
  const url = new URL(request.url);
  try {
    if (url.origin === 'https://vstupenky.online' && url.pathname === '/form/wix-qa-20261025') {
      await call('Fetch.fulfillRequest', {requestId, responseCode:200, responseHeaders:[
        {name:'Content-Type', value:'text/html; charset=utf-8'}, {name:'Cache-Control', value:'no-store'},
        {name:'X-Festapp-QA-Document', value:'production-template-disposable-backend'},
      ], body:template.toString('base64')}, sessionId);
      receipt.requests.push({method:request.method, path:url.pathname, status:200, documentAdapted:true});
      persist(); return;
    }
    if (url.origin !== 'https://api.festapp.net' || !/^\/(rest|auth|functions)\/v1\//.test(url.pathname)) {
      throw Error('Unexpected backend blocked');
    }
    const headers = new Headers(request.headers);
    for (const name of ['host', 'cookie', 'content-length', 'accept-encoding']) headers.delete(name);
    headers.set('apikey', status.ANON_KEY);
    headers.set('authorization', 'Bearer ' + status.ANON_KEY);
    headers.set('origin', 'http://127.0.0.1:59801');
    const response = await fetch(status.API_URL + url.pathname + url.search, {
      method:request.method, headers, body:['GET', 'HEAD'].includes(request.method) ? undefined : request.postData,
      redirect:'manual', signal:AbortSignal.timeout(30000),
    });
    const body = Buffer.from(await response.arrayBuffer()).toString('base64');
    const excluded = new Set(['content-encoding', 'content-length', 'transfer-encoding',
      'access-control-allow-origin', 'access-control-allow-headers', 'access-control-allow-methods']);
    const responseHeaders = Array.from(response.headers, ([name, value]) => ({name, value})).filter(h => !excluded.has(h.name));
    responseHeaders.push(
      {name:'Access-Control-Allow-Origin', value:'https://vstupenky.online'},
      {name:'Access-Control-Allow-Headers', value:headers.get('access-control-request-headers') ||
        'authorization,apikey,content-type,x-client-info,x-supabase-api-version,content-profile,accept-profile,prefer'},
      {name:'Access-Control-Allow-Methods', value:'GET,POST,PATCH,DELETE,OPTIONS'},
      {name:'X-Festapp-QA-Backend', value:'disposable-59821'},
    );
    await call('Fetch.fulfillRequest', {requestId, responseCode:response.status, responseHeaders, body}, sessionId);
    receipt.requests.push({method:request.method, path:url.pathname, status:response.status});
  } catch (error) {
    await call('Fetch.failRequest', {requestId, errorReason:'BlockedByClient'}, sessionId).catch(() => {});
    receipt.requests.push({method:request.method, path:url.pathname, blocked:true, error:error.message});
  }
  persist();
}
ws.addEventListener('message', event => {
  const data = JSON.parse(event.data);
  if (data.id) {
    const item = pending.get(data.id); pending.delete(data.id); clearTimeout(item?.timer);
    if (data.error) item?.reject(Error(data.error.message)); else item?.resolve(data.result);
    return;
  }
  if (data.method === 'Network.requestWillBeSent' && data.params.request.url.includes('wix-qa-proxy-probe=1')) {
    probeRequests.set(data.params.requestId, data.params.request.url);
  }
  if (data.method === 'Network.loadingFailed' && probeRequests.has(data.params.requestId)) {
    probeErrors.set(probeRequests.get(data.params.requestId), data.params.errorText);
  }
  if (data.method === 'Target.attachedToTarget' && interceptionEnabled) {
    const {sessionId, targetInfo} = data.params;
    const operation = ['page', 'iframe'].includes(targetInfo.type)
      ? configure(sessionId) : call('Runtime.runIfWaitingForDebugger', {}, sessionId);
    setups.set(targetInfo.targetId, operation);
    operation.catch(error => void stop(error));
  }
  if (data.method === 'Fetch.requestPaused') intercept(data.params, data.sessionId).catch(error => void stop(error));
});
try {
  const {arguments:args} = await call('Browser.getBrowserCommandLine');
  const dnsFence = '--host-resolver-rules=MAP api.festapp.net ~NOTFOUND, MAP *.supabase.co ~NOTFOUND';
  if (!args.includes('--festapp-wix-qa=20261025') || !args.some(a => /^--headless(?:=|$)/.test(a)) ||
      !args.includes('--no-proxy-server') || !args.includes(dnsFence) || args.some(a => a.startsWith('--proxy-server='))) {
    throw Error('Owned headless Wix browser with persistent backend DNS fencing required');
  }
  ownsBrowser = true;
  let {targetInfos} = await call('Target.getTargets');
  for (const target of targetInfos.filter(t => t.type === 'page' && t.url === 'chrome://newtab/')) {
    await call('Target.closeTarget', {targetId:target.targetId});
  }
  ({targetInfos} = await call('Target.getTargets'));
  const pages = targetInfos.filter(t => ['page', 'iframe'].includes(t.type));
  if (pages.length !== 1 || pages[0].type !== 'page' || pages[0].url !== 'about:blank') {
    throw Error('Start with one owned about:blank tab before installing the test transport');
  }
  const {sessionId} = await call('Target.attachToTarget', {targetId:pages[0].targetId, flatten:true});
  await call('Network.enable', {}, sessionId);
  for (const host of ['api.festapp.net', 'kjdpmixlnhntmxjedpxh.supabase.co']) {
    const url = `https://${host}/rest/v1/?wix-qa-proxy-probe=1`;
    const evaluation = await call('Runtime.evaluate', {expression:`fetch(${JSON.stringify(url)},{mode:'no-cors',cache:'no-store'}).then(()=>"unexpected-success",error=>error.message)`, awaitPromise:true, returnByValue:true}, sessionId);
    if (evaluation.exceptionDetails) throw Error('Network probe failed to execute: ' + evaluation.exceptionDetails.text);
    const errorText = probeErrors.get(url);
    receipt.networkFenceProbes.push({host, errorText}); persist();
    if (errorText !== 'net::ERR_NAME_NOT_RESOLVED') throw Error('Persistent network fence was not proven for ' + host);
  }
  await call('Target.detachFromTarget', {sessionId});
  interceptionEnabled = true;
  await call('Target.setAutoAttach', {autoAttach:true, waitForDebuggerOnStart:true, flatten:true,
    filter:[{type:'page'}, {type:'iframe'}]});
  const initial = pages.map(page => setups.get(page.targetId));
  if (initial.some(operation => !operation)) throw Error('Initial page was not attached');
  await Promise.all(initial);
  receipt.initialTargetsConfigured = initial.length; receipt.ready = true; persist();
  console.log('READY: owned browser fenced, backend probes blocked, all initial Fetch targets configured');
} catch (error) { await stop(error); }
