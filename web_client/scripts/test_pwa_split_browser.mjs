// Generated production worker with a deliberately small simulated Flutter
// payload. The separate seat browser gate covers the real form and SQL.
import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { createServer } from 'node:http';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { promisify } from 'node:util';
import { createRequire } from 'node:module';
import { build as bundle } from 'esbuild';
import QRCode from 'qrcode';
import { qrDecoderAsset } from '../src/components/scan/scanner_codes.js';

const execute = promisify(execFile);
const projectRoot = path.resolve(import.meta.dirname, '../..');
const version = '1.2.3+4';
const flutterCore = ['/flutter.html', '/flutter.js', '/flutter_bootstrap.js', '/main.dart.1.2.3-4.js',
    '/main.dart.1.2.3-4.js_1.part.js'];
const flutterPaths = [...flutterCore, '/canvaskit/canvaskit.wasm', '/assets/FontManifest.json'];
const publicHtml = `<!doctype html><meta charset="utf-8"><title>Přihláška</title>
<form><label>Jméno <input name="jmeno"></label></form><p id="state">načítání</p>
<script src="/web-assets/public.js"></script>`;
const publicJs = `window.fixtureQuery = (runtime, type = 'FESTAPP_QUERY_BUILD_VERSION') => new Promise(resolve => {
  const channel = new MessageChannel();
  channel.port1.onmessage = event => resolve(event.data);
  navigator.serviceWorker.controller.postMessage({type, runtime, version:${JSON.stringify(version)}}, [channel.port2]);
});
navigator.serviceWorker.register('/festapp_service_worker.js', {scope:'/'}).then(async () => {
  await navigator.serviceWorker.ready;
  if (!navigator.serviceWorker.controller) await new Promise(resolve => navigator.serviceWorker.addEventListener('controllerchange', resolve, {once:true}));
  document.getElementById('state').textContent='připraveno';
});`;
const flutterHtml = `<!doctype html><meta charset="utf-8"><title>Ukázka aplikace</title>
<p id="state">aplikace</p><script src="/flutter_bootstrap.js"></script><script src="/main.dart.1.2.3-4.js"></script><script src="/main.dart.1.2.3-4.js_1.part.js"></script>`;

export async function testPwaSplitBrowser({ owner, session, temporary }) {
    const build = path.join(temporary, 'pwa-build');
    await mkdir(path.join(build, 'web-assets'), {recursive:true});
    await mkdir(path.join(build, 'canvaskit'), {recursive:true});
    await mkdir(path.join(build, 'assets'), {recursive:true});
    const files = {
        '/index.html': publicHtml,
        '/web-assets/public.js': publicJs,
        '/flutter.html': flutterHtml,
        '/flutter.js': 'window.fixtureFlutterLoader=true;',
        '/flutter_bootstrap.js': 'window.fixtureFlutterBootstrap=true;',
        '/main.dart.1.2.3-4.js': `window.fixtureFlutterMain=true; Promise.all([fetch('/canvaskit/canvaskit.wasm'),fetch('/assets/FontManifest.json')]).then(r=>{if(r.every(x=>x.ok))window.fixtureFlutterAssets=true});`,
        '/main.dart.1.2.3-4.js_1.part.js': 'window.fixtureFlutterPart=true;',
        '/festapp-version.json': JSON.stringify({version,main:'main.dart.1.2.3-4.js'}),
        '/canvaskit/canvaskit.wasm': 'fixture-canvas-engine',
        '/assets/FontManifest.json': '[]',
    };
    const decoder=await bundle({entryPoints:[path.join(projectRoot,'web_client/src/components/scan/scanner_decoder_worker.js')],bundle:true,format:'iife',platform:'browser',write:false,target:'es2022'});
    files['/web-assets/scanner-reader.js']=decoder.outputFiles[0].text;
    files[qrDecoderAsset]=await readFile(createRequire(import.meta.url).resolve('zxing-wasm/reader/zxing_reader.wasm'));
    for (const [name, content] of Object.entries(files)) await writeFile(path.join(build, name.slice(1)), content);
    await execute(process.execPath, [path.join(projectRoot, 'automation/generate_pwa_service_worker.mjs'), build, version], {cwd:projectRoot});
    const worker = await readFile(path.join(build, 'festapp_service_worker.js'));
    let rejectPart = false;
    const requests = [];
    const server = createServer((req, res) => {
        const url = new URL(req.url, 'http://127.0.0.1');
        requests.push(url.pathname);
        if (url.pathname === '/__browser_startup') return res.end('<!doctype html><title>Browser startup</title>');
        if (url.pathname === '/festapp_service_worker.js') { res.setHeader('content-type', 'text/javascript'); return res.end(worker); }
        if (rejectPart && url.pathname === '/main.dart.1.2.3-4.js_1.part.js') { res.statusCode=503; return res.end('temporary fixture failure'); }
        const name = url.pathname === '/' || url.pathname.startsWith('/form/') ? '/index.html' : url.pathname;
        const content = files[name];
        if (content === undefined) { res.statusCode=404; return res.end('not found'); }
        res.setHeader('cache-control','no-store');
        res.setHeader('content-type', name.endsWith('.html') ? 'text/html; charset=utf-8' : name.endsWith('.js') ? 'text/javascript' : name.endsWith('.wasm') ? 'application/wasm' : 'application/octet-stream');
        res.end(content);
    });
    await new Promise((resolve, reject) => { server.once('error', reject); server.listen(0, '127.0.0.1', resolve); });
    const origin = `http://127.0.0.1:${server.address().port}`;
    owner.allow(origin);
    const evalResult = code => session.page.evaluate(code);
    const cachePaths = () => evalResult(`(async () => {const c=await caches.open(${JSON.stringify('festapp-app-shell-'+version)}); return (await c.keys()).map(r=>new URL(r.url).pathname)})()`);
    const query = (runtime, type) => evalResult(`window.fixtureQuery(${JSON.stringify(runtime)},${JSON.stringify(type || 'FESTAPP_QUERY_BUILD_VERSION')})`);
    try {
        await session.open(`${origin}/form/prihlaska`);
        await session.page.waitForFunction('document.getElementById("state").textContent === "připraveno"');
        assert.deepEqual(await query('web'), {version, runtime:'web', ready:true});
        assert.deepEqual(await query('web', 'FESTAPP_REPAIR_APP_SHELL'), {ok:true, version});
        assert.deepEqual(await query(undefined), {version, runtime:'web', ready:true});
        await session.page.goto(`${origin}/`);
        await session.page.waitForFunction('document.getElementById("state").textContent === "připraveno"');
        assert.deepEqual(await query(undefined), {version, runtime:'web', ready:true});
        const publicFlutterRequests = requests.filter(p => /^\/(?:main\.dart(?:\.|$)|flutter(?:\.html|\.js|_bootstrap\.js)|canvaskit\/|assets\/(?!translations\/))/.test(p));
        const publicCache = await cachePaths();
        assert.deepEqual(publicFlutterRequests, [], 'public install and repair must not download Flutter');
        assert.deepEqual(publicCache.filter(p => flutterPaths.includes(p)), [], 'public cache must not eagerly hold Flutter');
        await session.context.setOffline(true);
        await session.page.goto(`${origin}/form/offline`);
        await session.page.locator('input[name=jmeno]').waitFor();
        await session.page.locator('input[name=jmeno]').fill('Jana Nováková');
        assert.equal((await session.page.locator('input[name=jmeno]').inputValue()), 'Jana Nováková');
        // A fresh worker must load its engine from the installed shell while offline.
        assert.ok(publicCache.includes(qrDecoderAsset),'WASM reader must be part of the web shell');
        const qr=QRCode.create('OFFLINE-SCANNER');
        const decoded=await evalResult(`new Promise((resolve,reject)=>{
          const worker=new Worker('/web-assets/scanner-reader.js',{type:'module'}),width=240,height=240,scale=6;
          const pixels=new Uint8ClampedArray(width*height*4).fill(255),modules=${JSON.stringify(Array.from(qr.modules.data))},size=${qr.modules.size};
          for(let y=0;y<size;y++)for(let x=0;x<size;x++)if(modules[y*size+x])for(let dy=0;dy<scale;dy++)for(let dx=0;dx<scale;dx++){
            const i=((y*scale+dy+40)*width+x*scale+dx+40)*4;pixels[i]=pixels[i+1]=pixels[i+2]=0;
          }
          const timer=setTimeout(()=>{worker.terminate();reject(new Error('offline reader timeout'));},10000);
          worker.onerror=()=>{clearTimeout(timer);worker.terminate();reject(new Error('offline reader failed'));};
          worker.onmessage=event=>{clearTimeout(timer);worker.terminate();event.data.error?reject(new Error(event.data.error)):resolve(event.data.codes.map(code=>code.value));};
          worker.postMessage({pixels,width,height},[pixels.buffer]);
        })`);
        assert.deepEqual(decoded,['OFFLINE-SCANNER'],'offline must decode through a new real WASM worker');
        await session.context.setOffline(false);
        await session.page.waitForFunction('!!navigator.serviceWorker.controller && !!window.fixtureQuery');
        const webCacheBeforeFailure = await cachePaths();
        rejectPart = true;
        assert.deepEqual(await query('flutter'), {version:null, runtime:'flutter', ready:false});
        const afterFailure = await cachePaths();
        assert.deepEqual(afterFailure.filter(p => flutterPaths.includes(p)), [], 'failed Flutter batch must not commit partial entries');
        for (const resource of webCacheBeforeFailure) assert.ok(afterFailure.includes(resource), `failed preparation removed web resource ${resource}`);
        rejectPart = false;
        assert.deepEqual(await query('flutter'), {version, runtime:'flutter', ready:true});
        const cached = await cachePaths();
        for (const resource of flutterCore) assert.ok(cached.includes(resource), `missing prepared Flutter resource ${resource}`);
        await session.page.goto(`${origin}/app/fixture`);
        await session.page.waitForFunction('window.fixtureFlutterMain === true && window.fixtureFlutterPart === true && window.fixtureFlutterAssets === true');
        await session.context.setOffline(true);
        await session.page.goto(`${origin}/app/offline`);
        await session.page.waitForFunction('window.fixtureFlutterMain === true && window.fixtureFlutterPart === true && window.fixtureFlutterAssets === true');
        // A direct Flutter navigation also prepares a missing executable set.
        await session.context.setOffline(false);
        await session.page.goto(`${origin}/form/prihlaska`);
        await session.page.waitForFunction('!!navigator.serviceWorker.controller');
        await evalResult(`(async () => {const c=await caches.open(${JSON.stringify('festapp-app-shell-'+version)}); for(const p of ${JSON.stringify(flutterCore)}) await c.delete(p); return true})()`);
        await session.page.goto(`${origin}/app/direct`);
        await session.page.waitForFunction('window.fixtureFlutterMain === true && window.fixtureFlutterPart === true && window.fixtureFlutterAssets === true');
        const directCache = await cachePaths();
        for (const resource of flutterCore) assert.ok(directCache.includes(resource), `direct navigation omitted ${resource}`);
        console.log(`PASS: public install and web repair: ${publicFlutterRequests.length} Flutter requests, ${publicCache.length} public cache entries; failed batch: 0 Flutter entries; successful query and direct navigation: ${flutterCore.length}/${flutterCore.length} Flutter core entries; offline public form fixture and simulated app entry`);
    } catch (error) {
        console.error('PWA fixture requests:', requests);
        console.error('PWA fixture browser errors:', session.errors);
        throw error;
    } finally {
        await session.context?.setOffline(false).catch(()=>{});
        await session.close().catch(()=>{});
        await new Promise(resolve => server.close(resolve));
    }
}
