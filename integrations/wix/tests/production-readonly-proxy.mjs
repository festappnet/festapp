// Readonly public production diagnostic, using the owned browser DNS fence.
import fs from 'node:fs';
import {permitsProductionRead, PUBLIC_FORM} from './production-readonly-policy.mjs';
const [cdpFile,receiptFile,...extra]=process.argv.slice(2);
if (!cdpFile||!receiptFile||extra.length) throw Error('Usage: production-readonly-proxy.mjs <cdp-file> <private-receipt>');
const endpoint = fs.readFileSync(cdpFile, 'utf8').trim();
if (!/^ws:\/\/127\.0\.0\.1:\d+\/devtools\/browser\/[a-zA-Z0-9-]+$/.test(endpoint)) throw Error('Loopback CDP required');
const receipt = {productionReadOnly:true, publicForm:PUBLIC_FORM, htmlAdapted:false,
  authAdapted:false, corsAdapted:false, requests:[], networkFenceProbes:[]};
const persist = () => fs.writeFileSync(receiptFile, JSON.stringify(receipt, null, 2) + '\n', {mode:0o600});
const ws = new WebSocket(endpoint);
await new Promise((resolve, reject) => { ws.addEventListener('open', resolve, {once:true}); ws.addEventListener('error', reject, {once:true}); });
let nextId = 0, ownsBrowser = false, stopping = false, interceptionEnabled = false;
const pending = new Map(), setups = new Map(), probeRequests = new Map(), probeErrors = new Map();
const destroyedTargets = new Set(), closingTargets = new Map();
function waitForTargetClose(targetId) {
  if (destroyedTargets.has(targetId)) return Promise.resolve();
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => { closingTargets.delete(targetId); reject(Error('Owned startup tab did not close')); }, 10000);
    closingTargets.set(targetId, () => { clearTimeout(timer); closingTargets.delete(targetId); resolve(); });
  });
}
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
  ]}, sessionId);
  await call('Target.setAutoAttach', {autoAttach:true, waitForDebuggerOnStart:true, flatten:true,
    filter:[{type:'page'}, {type:'iframe'}]}, sessionId);
  await call('Runtime.runIfWaitingForDebugger', {}, sessionId);
}
async function intercept({requestId, request}, sessionId) {
  const path = new URL(request.url).pathname;
  if (!permitsProductionRead(request)) {
    receipt.requests.push({method:request.method,path,blocked:true}); persist();
    await call('Fetch.failRequest',{requestId,errorReason:'BlockedByClient'},sessionId); return;
  }
  try {
    const headers = new Headers(request.headers);
    for (const name of ['host','content-length','accept-encoding']) headers.delete(name);
    const response = await fetch(request.url, {method:request.method,headers,
      body:request.method==='POST'?request.postData:undefined,
      redirect:'manual',signal:AbortSignal.timeout(30000)});
    const bytes=Buffer.from(await response.arrayBuffer());
    let applicationCode;
    try {applicationCode=JSON.parse(bytes.toString()).code;} catch {}
    // Node fetch decompresses the body. Do not alter auth or any CORS header.
    const responseHeaders=Array.from(response.headers,([name,value])=>({name,value}))
      .filter(h=>!['content-encoding','content-length','transfer-encoding'].includes(h.name));
    receipt.requests.push({method:request.method,path,status:response.status,applicationCode,requestOrigin:headers.get('origin'),
      cors:{origin:response.headers.get('access-control-allow-origin'),
        methods:response.headers.get('access-control-allow-methods'),
        headers:response.headers.get('access-control-allow-headers')}}); persist();
    await call('Fetch.fulfillRequest',{requestId,responseCode:response.status,responseHeaders,body:bytes.toString('base64')},sessionId);
  } catch {
    receipt.requests.push({method:request.method,path,transportFailed:true});persist();
    await call('Fetch.failRequest',{requestId,errorReason:'Failed'},sessionId);
  }
}
ws.addEventListener('message', event => {
  const data = JSON.parse(event.data);
  if (data.id) {
    const item = pending.get(data.id); pending.delete(data.id); clearTimeout(item?.timer);
    if (data.error) item?.reject(Error(data.error.message)); else item?.resolve(data.result);
    return;
  }
  if (data.method === 'Target.targetDestroyed') {
    destroyedTargets.add(data.params.targetId);
    closingTargets.get(data.params.targetId)?.();
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
  if (args.includes('--disable-web-security') || args.some(a => a.startsWith('--disable-features=') && a.includes('OutOfBlinkCors'))) throw Error('CORS bypass flags refused');
  receipt.corsEnforcementBypassAbsent = true;
  ownsBrowser = true;
  await call('Target.setDiscoverTargets', {discover:true});
  let {targetInfos} = await call('Target.getTargets');
  const startupClosures = targetInfos.filter(t => t.url === 'chrome://newtab/' || t.url.startsWith('chrome-untrusted://new-tab-page/')).map(t => waitForTargetClose(t.targetId));
  for (const target of targetInfos.filter(t => t.type === 'page' && t.url === 'chrome://newtab/')) {
    await call('Target.closeTarget', {targetId:target.targetId});
  }
  await Promise.all(startupClosures);
  ({targetInfos} = await call('Target.getTargets'));
  const pages = targetInfos.filter(t => ['page', 'iframe'].includes(t.type));
  if (pages.length !== 1 || pages[0].type !== 'page' || pages[0].url !== 'about:blank') {
    throw Error('Start with one owned about:blank tab before installing the test transport; found ' + JSON.stringify(pages.map(t => ({type:t.type,url:t.url.split('?')[0]}))));
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
