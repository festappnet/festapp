import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,mkdir,writeFile,readFile,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import path from 'node:path';
import vm from 'node:vm';
import {fileURLToPath} from 'node:url';
import {execFileSync} from 'node:child_process';
import {collectPwaShellManifest} from '../lib/pwa_shell_manifest.mjs';

async function fixture(t) {
  const root=await mkdtemp(path.join(tmpdir(),'festapp-split-shell-'));
  t.after(()=>rm(root,{recursive:true,force:true}));
  const resources={'flutter':'<html>Flutter app</html>',webclient:'<html>Public form</html>',
    'main.dart.js':'main','main.dart.js_1.part.js':'deferred','flutter.js':'loader',
    'flutter_bootstrap.js':'bootstrap','festapp_update_prompt.js':'recovery',
    'festapp-version.json':JSON.stringify({version:'1.2.3+4',main:'main.dart.1.2.3-4.js'}),
    'main.dart.1.2.3-4.js':'main','main.dart.1.2.3-4.js_1.part.js':'deferred',
    'web-assets/form.js':'form', 'canvaskit/canvaskit.wasm':'wasm'};
  for(const [name,value] of Object.entries(resources)) {
    await mkdir(path.dirname(path.join(root,name)),{recursive:true}); await writeFile(path.join(root,name),value);
  }
  execFileSync(process.execPath,[fileURLToPath(new URL('../generate_pwa_service_worker.mjs',import.meta.url)),root,'1.2.3+4'],{stdio:'pipe'});
  const source=await readFile(path.join(root,'festapp_service_worker.js'),'utf8');
  const handlers={}, stores=new Map(), requests=[], batches=[];
  let offline=false, failPart=false;
  const origin='https://app.test';
  const key=value=>new URL(typeof value==='string'?value:value.url,origin).href;
  const network=async value=>{
    const url=new URL(key(value)); requests.push(url.pathname);
    if(offline || (failPart && url.pathname.endsWith('_1.part.js'))) throw Error('simulated network failure');
    const body=resources[url.pathname.slice(1)];
    return body===undefined?new Response('missing',{status:404}):new Response(body);
  };
  const caches={keys:async()=>[...stores.keys()],delete:async name=>stores.delete(name),open:async name=>{
    if(!stores.has(name)) stores.set(name,new Map()); const data=stores.get(name);
    return {
      match:async(request,options={})=>{const requested=key(request);for(const [url,response] of data){
        if(url===requested || (options.ignoreSearch && url.split('?')[0]===requested.split('?')[0])) return response.clone();}},
      put:async(request,response)=>data.set(key(request),response.clone()),
      addAll:async items=>{batches.push(items.map(item=>new URL(key(item)).pathname));
        const responses=await Promise.all(items.map(network));
        if(responses.some(response=>!response.ok)) throw Error('non-successful atomic batch');
        items.forEach((item,index)=>data.set(key(item),responses[index].clone()));},
      delete:async request=>data.delete(key(request))};
  }};
  const clients=new Map();
  let skipWaiting=0,claimed=0;
  const self={location:new URL(origin+'/festapp_service_worker.js'),addEventListener:(type,fn)=>handlers[type]=fn,
    clients:{matchAll:async()=>[...clients.values()],get:async id=>clients.get(id),claim:async()=>{claimed++;}},skipWaiting:async()=>{skipWaiting++;}};
  vm.runInNewContext(source,{self,caches,fetch:network,Request,Response,URL,console,setTimeout,clearTimeout});
  const lifecycle=async type=>{let promise;handlers[type]({waitUntil:value=>promise=value});await promise;};
  const message=async (data,url='/form/a',id='client')=>{let promise,reply;handlers.message({data,source:{id,url:origin+url},
    ports:[{postMessage:value=>reply=value}],waitUntil:value=>promise=value});await promise;return reply;};
  const navigate=async pathname=>{let response,pending;const request=new Request(origin+pathname);
    Object.defineProperty(request,'mode',{value:'navigate'});
    handlers.fetch({request,clientId:'',resultingClientId:'new-page',respondWith:value=>response=value,waitUntil:value=>pending=value});
    const result=await response;await pending;return result;};
  return {manifest:await collectPwaShellManifest(root),requests,batches,stores,clients,lifecycle,message,navigate,
    activation:()=>({skipWaiting,claimed}),
    offline:value=>offline=value,failPart:value=>failPart=value,
    cached:()=>[...stores.get('festapp-app-shell-1.2.3+4').keys()].map(url=>new URL(url).pathname)};
}
const flutter=url=>/main\.dart|^\/flutter|^\/canvaskit/.test(url);

test('the ready-embed generation hands off on the next visit without reloading an open draft', async t => {
  const f=await fixture(t);
  const oldCache='festapp-app-shell-0.20.531+1042';
  const old=new Map([['https://app.test/web-assets/form.js',new Response('old draft code')]]);
  f.stores.set(oldCache,old);
  const navigations=[];
  f.clients.set('draft',{id:'draft',url:'https://app.test/form/a?embed=1',
    postMessage(){},navigate:url=>{navigations.push(url);return Promise.resolve();}});
  await f.message({type:'FESTAPP_CLIENT_VERSION',version:'0.20.531+1042'},'/form/a?embed=1','draft');
  await f.lifecycle('install');
  assert.equal(f.activation().skipWaiting,1,'old ready embeds cannot activate their successor themselves');
  await f.lifecycle('activate');
  assert.equal(f.activation().claimed,1);
  assert.deepEqual(navigations,[],'claim must leave an open draft untouched');
  assert.equal(await old.get('https://app.test/web-assets/form.js').clone().text(),'old draft code');
  assert.equal(f.stores.get(oldCache),old,'retain the open client generation');
  assert.equal(await (await f.navigate('/form/a?embed=1')).text(),'<html>Public form</html>');
  assert.equal(f.requests.some(flutter),false);
});

test('public install, query, repair, navigation and offline reload never fetch Flutter',async t=>{
  const f=await fixture(t);await f.lifecycle('install');
  assert.ok(f.requests.includes('/web-assets/form.js'));
  assert.equal(f.requests.some(flutter),false);
  assert.equal(f.manifest.webCoreResources.some(flutter),false);
  assert.ok(f.manifest.flutterCoreResources.includes('/main.dart.1.2.3-4.js_1.part.js'));
  assert.equal((await f.message({type:'FESTAPP_QUERY_BUILD_VERSION',runtime:'web'})).version,'1.2.3+4');
  for (const route of ['/form/a','/order','/']) {
    assert.equal((await f.message({type:'FESTAPP_QUERY_BUILD_VERSION'},route)).runtime,'web','legacy public queries stay web-only');
  }
  assert.equal((await f.message({type:'FESTAPP_REPAIR_APP_SHELL',runtime:'web',version:'1.2.3+4'})).ok,true);
  f.offline(true);assert.match(await (await f.navigate('/form/a')).text(),/Public form/);
  assert.equal(f.requests.some(flutter),false);assert.equal(f.cached().some(flutter),false);
});
test('Flutter preparation is atomic, retryable and shared by concurrent requests',async t=>{
  const f=await fixture(t);await f.lifecycle('install');f.failPart(true);
  assert.equal((await f.message({type:'FESTAPP_QUERY_BUILD_VERSION',runtime:'flutter'},'/flutter')).ready,false);
  assert.equal(f.cached().some(flutter),false,'failed batch must preserve public-only cache');
  f.failPart(false);const count=f.batches.length;
  const answers=await Promise.all([f.message({type:'FESTAPP_QUERY_BUILD_VERSION',runtime:'flutter'},'/flutter'),
    f.message({type:'FESTAPP_QUERY_BUILD_VERSION',runtime:'flutter'},'/flutter')]);
  assert.ok(answers.every(answer=>answer.ready && answer.version==='1.2.3+4'));
  assert.equal(f.batches.length,count+1,'one atomic download for concurrent callers');
  assert.ok(f.cached().includes('/main.dart.1.2.3-4.js_1.part.js'));
  f.offline(true);assert.match(await (await f.navigate('/event/news')).text(),/Flutter app/);
  assert.match(await (await f.navigate('/form/a')).text(),/Public form/);
});
test('first Flutter navigation prepares the shell without a prior query',async t=>{
  const f=await fixture(t);await f.lifecycle('install');
  assert.match(await (await f.navigate('/event/news')).text(),/Flutter app/);
  assert.ok(f.cached().includes('/main.dart.1.2.3-4.js'));
  f.offline(true);assert.match(await (await f.navigate('/event/news')).text(),/Flutter app/);
});
