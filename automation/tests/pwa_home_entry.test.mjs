import assert from 'node:assert/strict';
import {mkdtemp,writeFile,readFile,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import vm from 'node:vm';
const root=await mkdtemp(path.join(tmpdir(),'festapp-home-shell-'));
try {
  for(const [name,text] of [['flutter','flutter shell'],['webclient','web client shell'],['main.dart.js','main']]) await writeFile(path.join(root,name),text);
  for(const forced of ['', 'forced-event']) {
    const generated=spawnSync(process.execPath,['automation/generate_pwa_service_worker.mjs',root,'1.2.3+4',forced],{encoding:'utf8'});
    assert.equal(generated.status,0,generated.stderr);
    const source=await readFile(path.join(root,'festapp_service_worker.js'),'utf8');
    const handlers={};
    const cache={match:async(request)=>{
      const url=typeof request==='string'?request:request.url;
      if(url==='https://app.test/' || url==='/index.html') return new Response('stale Flutter root shell');
      if(url.includes('/webclient?pwa-cache=1')) return new Response('web client shell');
      if(url.includes('/flutter?pwa-cache=1')) return new Response('flutter shell');
    }};
    const context=vm.createContext({URL,Request,Response,Headers,Promise,setTimeout,clearTimeout,console,
      caches:{open:async()=>cache},fetch:async()=>{throw Error('offline');},
      self:{location:{origin:'https://app.test'},addEventListener:(name,fn)=>{handlers[name]=fn;},clients:{get:async()=>null}}});
    vm.runInContext(source,context);
    const request=new Request('https://app.test/');Object.defineProperty(request,'mode',{value:'navigate'});
    let response;handlers.fetch({request,clientId:'',resultingClientId:'new-tab',respondWith:p=>{response=p;},waitUntil:()=>{}});
    assert.equal(await (await response).text(),forced?'flutter shell':'web client shell',
      'Opening the domain must use its configured entry even with a stale Flutter root in cache');
  }
  console.log('PWA home entry tests passed');
} finally {await rm(root,{recursive:true,force:true});}
