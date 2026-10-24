import http from 'node:http';
import fs from 'node:fs/promises';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
const root=process.env.FESTAPP_PWA_PROBE_ROOT || import.meta.dirname;
const projectRoot=process.env.FESTAPP_REPO_ROOT || path.resolve(import.meta.dirname, '../../..');
const versions={v1:'1.0.0+1',v2:'2.0.0+2'};
let current='v1'; const requests=[];
for(const [key,version] of Object.entries(versions)){
 const html=`<!doctype html><meta charset="utf-8"><title>PWA deferred audit ${key}</title><body><p>${key}</p>
<script>
window.auditVersion=${JSON.stringify(version)};
function report(){navigator.serviceWorker.controller?.postMessage({type:'FESTAPP_CLIENT_VERSION',version:window.auditVersion});}
navigator.serviceWorker.addEventListener('message',e=>{if(e.data?.type==='FESTAPP_REPORT_VERSION')report();});
navigator.serviceWorker.addEventListener('controllerchange',report);
window.auditReady=(async()=>{await navigator.serviceWorker.register('/festapp_service_worker.js',{scope:'/',updateViaCache:'none'});await navigator.serviceWorker.ready;if(!navigator.serviceWorker.controller)await new Promise(r=>navigator.serviceWorker.addEventListener('controllerchange',r,{once:true}));report();return {version:window.auditVersion,caches:await caches.keys()};})();
window.auditUpdate=async()=>{const r=await navigator.serviceWorker.getRegistration('/');await r.update();let w=r.waiting||r.installing;if(!w)throw Error('no update');if(w.state!=='installed'&&w.state!=='activated')await new Promise((resolve,reject)=>{w.addEventListener('statechange',()=>{if(w.state==='installed'||w.state==='activated')resolve();if(w.state==='redundant')reject(Error('install failed'));});});const changed=new Promise(resolve=>navigator.serviceWorker.addEventListener('controllerchange',resolve,{once:true}));w.postMessage('SKIP_WAITING');await changed;report();return {oldPage:window.auditVersion,caches:await caches.keys()};};
</script><script src="/main.dart.js" defer></script></body>`;
 for(const name of ['flutter','webclient'])await fs.writeFile(path.join(root,key,name),html);
 await fs.writeFile(path.join(root,key,'festapp-version.json'),JSON.stringify({version}));
 const generated=spawnSync(process.execPath,[path.join(projectRoot,'automation/generate_pwa_service_worker.mjs'),path.join(root,key),version],{encoding:'utf8'});
 if(generated.status)throw Error(generated.stderr);
}
const server=http.createServer(async(req,res)=>{
 try{
 const url=new URL(req.url,'http://127.0.0.1');
 if(url.pathname==='/__switch'){if(versions[url.searchParams.get('version')])current=url.searchParams.get('version');res.setHeader('content-type','application/json');res.end(JSON.stringify({current}));return;}
 if(url.pathname==='/__requests'){res.setHeader('content-type','application/json');res.end(JSON.stringify(requests));return;}
 const name=url.pathname==='/'?'webclient':url.pathname.slice(1);
 if(name.includes('..')){res.writeHead(400).end();return;}
 requests.push({version:current,path:url.pathname});
 const bytes=await fs.readFile(path.join(root,current,name));
 res.setHeader('cache-control','no-store');
 res.setHeader('content-type',name.endsWith('.js')?'text/javascript':name.endsWith('.json')?'application/json':name==='webclient'||name==='flutter'?'text/html':'application/octet-stream');res.end(bytes);
 }catch(e){res.writeHead(404).end('missing');}
});
server.listen(4187,'127.0.0.1',()=>console.log('PWA deferred audit: http://127.0.0.1:4187'));
for(const signal of ['SIGTERM','SIGINT'])process.on(signal,()=>server.close(()=>process.exit(0)));
