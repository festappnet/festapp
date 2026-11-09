import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import net from 'node:net';
import {chromium} from 'playwright';
import {createNativeBrowser} from '../../scripts/native_browser.mjs';

async function listen(server) {
  await new Promise((resolve,reject)=>{server.once('error',reject);server.listen(0,'127.0.0.1',resolve);});
  return `http://127.0.0.1:${server.address().port}`;
}

test('native contexts isolate state and proxy contains page, popup, websocket and service-worker egress', async () => {
  let forbiddenHits=0, allowedWs=0;
  const forbidden=http.createServer((_req,res)=>{forbiddenHits++;res.end('forbidden');});
  forbidden.on('upgrade',(_req,socket)=>{forbiddenHits++;socket.destroy();});
  const denied=await listen(forbidden);
  const allowed=http.createServer((req,res)=>{
    if(req.url==='/sw.js') {res.setHeader('content-type','text/javascript');res.end(`self.addEventListener('message',e=>{e.waitUntil(fetch(${JSON.stringify(denied+'/sw')},{mode:'no-cors'}).catch(()=>{}).then(()=>e.ports[0].postMessage('done')))});`);return;}
    res.setHeader('content-type','text/html');res.end('<!doctype html><title>fixture</title>');
  });
  allowed.on('upgrade',(_req,socket)=>{allowedWs++;socket.destroy();});
  const origin=await listen(allowed);
  const owner=await createNativeBrowser();owner.allow(origin);
  try {
    const ctx=await owner.context();const page=await ctx.newPage();await page.goto(origin);
    await page.evaluate(()=>localStorage.setItem('fixture','private'));
    assert.equal(await page.evaluate(url=>fetch(url).then(()=>null,e=>e.name),denied+'/page'),'SecurityError');
    assert.equal(await page.evaluate(url=>{try{new XMLHttpRequest().open('GET',url);return null}catch(error){return error.name}},denied+'/xhr'),'SecurityError');
    await page.evaluate(async urls=>{
      await navigator.serviceWorker.register('/sw.js');await navigator.serviceWorker.ready;
      const worker=(await navigator.serviceWorker.getRegistration()).active;
      await new Promise(resolve=>{const c=new MessageChannel();c.port1.onmessage=resolve;worker.postMessage('probe',[c.port2]);});
      await Promise.all(urls.map(url=>new Promise(resolve=>{const ws=new WebSocket(url);ws.onerror=resolve;ws.onclose=resolve;})));
    },[origin.replace('http:','ws:')+'/allowed',denied.replace('http:','ws:')+'/denied']);
    const popupPromise=page.waitForEvent('popup');await page.evaluate(url=>window.open(url),denied+'/popup');
    const popup=await popupPromise;await popup.waitForLoadState('domcontentloaded').catch(()=>{});await popup.close();
    assert.equal(allowedWs,1,'allowed WebSocket traverses the proxy');
    assert.equal(forbiddenHits,0,'denied page, SW, popup and WebSocket never reach the target');
    assert.ok(owner.deniedRequests>=3,'proxy observes non-page egress denials');
    await ctx.close();
    const fresh=await owner.context();const freshPage=await fresh.newPage();await freshPage.goto(origin);
    assert.equal(await freshPage.evaluate(()=>localStorage.getItem('fixture')),null);
    assert.equal(await freshPage.evaluate(async()=>!!await navigator.serviceWorker.getRegistration()),false);
    await fresh.close();
  } finally { await owner.close();await Promise.all([new Promise(r=>allowed.close(r)),new Promise(r=>forbidden.close(r))]); }
});

test('fixture origin registration rejects unowned network targets', async () => {
  const owner=await createNativeBrowser();
  try {
    for (const origin of ['https://example.invalid','http://example.invalid:80','http://127.0.0.1','http://127.0.0.1:1234/path','http://user@127.0.0.1:1234']) {
      assert.throws(() => owner.allow(origin));
    }
    owner.allow('http://127.0.0.1:1234');
  } finally { await owner.close(); }
});

test('external access requires an explicitly approved exact origin', async () => {
  await assert.rejects(createNativeBrowser({externalOrigins:['https://example.invalid']}), /unapproved external/);
});

test('owned contexts close independently and browser disposal closes remaining contexts', async () => {
  const owner=await createNativeBrowser();
  const first=await owner.context();const second=await owner.context();
  const firstPage=await first.newPage();const secondPage=await second.newPage();
  await first.close();
  assert.equal(firstPage.isClosed(),true);
  assert.equal(secondPage.isClosed(),false);
  await owner.close();
  assert.equal(secondPage.isClosed(),true);
});


test('context options cannot override isolation or egress policy', async () => {
  const owner=await createNativeBrowser();
  try {
    for(const options of [{proxy:{server:'http://example.invalid'}},{storageState:{}},{colorScheme:'dark'}])
      await assert.rejects(owner.context(options), /unsupported context options/);
  } finally { await owner.close(); }
});

test('registered IPv6 loopback reaches only its explicit fixture', async t => {
  const server=http.createServer((_req,res)=>res.end('ipv6'));
  try { await new Promise((resolve,reject)=>{server.once('error',reject);server.listen(0,'::1',resolve)}); }
  catch (error) { if (error.code==='EADDRNOTAVAIL') {t.skip('IPv6 loopback unavailable');return;} throw error; }
  const owner=await createNativeBrowser();
  try {
    const origin=`http://[::1]:${server.address().port}`;owner.allow(origin);
    const context=await owner.context();const page=await context.newPage();await page.goto(origin);
    assert.equal(await page.locator('body').innerText(),'ipv6');
  } finally { await owner.close();await new Promise(resolve=>server.close(resolve)); }
});

test('owner closes pending upstream sockets and cleanup is idempotent', async () => {
  let received;const incoming=new Promise(resolve=>{received=resolve});
  const server=http.createServer((req,res)=>{if(req.url==='/pending'){received();return;}res.end('fixture');});
  const origin=await listen(server);const owner=await createNativeBrowser();owner.allow(origin);
  try {
    const context=await owner.context();const page=await context.newPage();await page.goto(origin);
    await page.evaluate(()=>{fetch('/pending').catch(()=>{});});await incoming;
    const first=owner.close();const second=owner.close();assert.equal(first,second);await first;
  } finally {await owner.close();await new Promise(resolve=>server.close(resolve));}
});

test('failed browser launch closes the already-listening owned proxy', async t => {
  let socket,closed;
  t.mock.method(chromium,'launch',async options=>{
    const port=Number(new URL(options.proxy.server).port);
    socket=net.connect(port,'127.0.0.1');
    closed=new Promise(resolve=>socket.once('close',resolve));
    await new Promise((resolve,reject)=>{socket.once('connect',resolve);socket.once('error',reject)});
    throw new Error('synthetic launch failure');
  });
  await assert.rejects(createNativeBrowser(),/synthetic launch failure/);
  await closed;
});

test('a failing context close still closes browser and proxy', async t => {
  const owner=await createNativeBrowser();
  const context=await owner.context();const page=await context.newPage();
  t.mock.method(context,'close',async()=>{throw new Error('synthetic context close failure')});
  await assert.rejects(owner.close(),/Owned browser cleanup failed/);
  assert.equal(page.isClosed(),true);
});
