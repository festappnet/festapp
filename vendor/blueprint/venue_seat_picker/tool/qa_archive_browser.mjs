import {createRequire} from 'node:module';
import {readFile,writeFile} from 'node:fs/promises';
import {createServer} from 'node:http';
import {resolve,extname,join} from 'node:path';
import assert from 'node:assert/strict';
const require=createRequire(new URL('../web/package.json',import.meta.url)),{chromium}=require('playwright');
const [npm,flutter,templatesPath,out]=process.argv.slice(2).map(v=>resolve(v));
const templates=JSON.parse(await readFile(templatesPath,'utf8'));
const requests=[],failures=[];
const server=createServer(async(req,res)=>{try{const url=new URL(req.url,'http://localhost').pathname;if(url==='/blank.html'){res.setHeader('Content-Type','text/html');res.end('<!doctype html><html><body></body></html>');return;}let file=url.startsWith('/flutter/')?join(flutter,url.slice(9)):join(npm,url);if(url.endsWith('/'))file=join(file,'index.html');res.setHeader('Content-Type',({'.js':'text/javascript','.html':'text/html','.json':'application/json','.wasm':'application/wasm'}[extname(file)]||'application/octet-stream'));res.end(await readFile(file));}catch{res.statusCode=404;res.end();}});await new Promise(r=>server.listen(0,'127.0.0.1',r));const base=`http://127.0.0.1:${server.address().port}`;
const browser=await chromium.launch({headless:true});
try{const context=await browser.newContext({viewport:{width:900,height:900}});await context.route('**/*',r=>{const u=r.request().url();if(u.startsWith(base)||u.startsWith('data:')||u.startsWith('blob:'))return r.continue();requests.push(u);return r.abort();});const page=await context.newPage();page.on('pageerror',e=>failures.push(e.message));
// Start in a fresh origin page and exercise the public asset loader itself.
await page.goto(`${base}/blank.html`);
await page.evaluate(async()=>{const {loadKernel}=await import('/src/index.js');await Promise.all([loadKernel('/dist/venue_layout_kernel.js'),loadKernel('/dist/venue_layout_kernel.js')]);if(!globalThis.VenueLayoutKernel)throw Error('Packed kernel did not load');});
const result=await page.evaluate(async templates=>{const{mount}=await import('/src/index.js');const resources=await(await fetch('/assets/layout_fonts/fixtures.json')).json();const results=[];for(const t of templates){const host=document.createElement('div');document.body.replaceChildren(host);const viewer=mount(host,{document:t.document,resources});results.push({id:t.id,seats:Number(host.querySelector('[role=list] button')?.getAttribute('aria-setsize')||host.querySelectorAll('[role=list] button').length),issues:viewer.scene.issues});viewer.dispose();}return results;},templates);
for(let i=0;i<templates.length;i++){assert.equal(result[i].seats,templates[i].document.nodes.filter(n=>n.kind==='seat'||n.kind==='capacityArea').length);assert.deepEqual(result[i].issues,[]);}
// Resolve and render a real raster through the actual packed public asset API.
const raster=await page.evaluate(async document=>{
 const {loadLayoutAssets,mount}=await import('/src/index.js');
 const encoded='iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAEklEQVR4nGP4z8DwHwyBNBgAAEnICff5q7YNAAAAAElFTkSuQmCC';
 const hash='7f2538a6e81af23e034f8ca2efc2cb5f1d7d709f502fa30bdccfebe774e4ecab',ref=`image:${hash}`;
 const resources=await(await fetch('/assets/layout_fonts/fixtures.json')).json();
 resources.assets={[ref]:{hash,url:`data:image/png;base64,${encoded}`,width:2,height:2,mimeType:'image/png',byteLength:75}};
 const resolved=await loadLayoutAssets(resources);
 document.background={assetRef:ref,hash,x:100,y:100,width:2,height:2,rotation:0,scale:100,opacity:1,crop:{x:0,y:0,width:1,height:1}};
 const host=globalThis.document.createElement('div');globalThis.document.body.replaceChildren(host);
 const viewer=mount(host,{document,resources:resolved});
 const result={issues:viewer.scene.issues,raster:host.querySelector('image')?.getAttribute('href')===`data:image/png;base64,${encoded}`};
 viewer.dispose();return result;
},templates.find(t=>t.document.nodes.some(n=>n.kind==='seat')).document);
assert.deepEqual(raster,{issues:[],raster:true});
// Same packed renderer and browser: full load versus a one-state patch.
// Timing is diagnostic; retained item identity asserts the incremental contract.
const performanceEvidence=await page.evaluate(async()=>{
 const {mount}=await import('/src/index.js');const results=[];
 for(const count of [500,5000]){
  const nodes=Array.from({length:count},(_,i)=>({id:`00000000-0000-4000-8000-${String(i+1).padStart(12,'0')}`,kind:'seat',label:'',transform:{x:40+(i%50)*50,y:40+Math.floor(i/50)*50,rotation:0},width:36,height:36}));
  const document={schemaVersion:2,symbolSetVersion:1,canvas:{x:0,y:0,width:2600,height:Math.ceil(count/50)*50+80,fill:'#ffffffff'},styles:{},seatingDefaults:{},textPolicy:{language:'und',direction:'auto'},nodes,selectionUnits:[],sections:[],attachments:[],presets:[]};
  const host=globalThis.document.createElement('div');host.style.cssText='width:900px;height:600px';globalThis.document.body.replaceChildren(host);
  const start=performance.now(),viewer=mount(host,{document});const mountMs=performance.now()-start;
  const untouched=viewer.scene.items.find(item=>item.id===nodes[count-1].id),camera={...viewer.camera};
  if(!untouched)throw Error('Missing untouched scene item in performance fixture');
  const patch=performance.now();viewer.update({seatPresentation:{[nodes[0].id]:{status:'occupied',selectable:false}}});const patchMs=performance.now()-patch;
  const retained=viewer.scene.items.find(item=>item.id===nodes[count-1].id)===untouched;
  const stable=viewer.options.document===document&&JSON.stringify(camera)===JSON.stringify(viewer.camera);
  results.push({seats:count,mountMs,oneStatePatchMs:patchMs,retainedUntouchedItem:retained,stableDocumentAndCamera:stable,issues:viewer.scene.issues});viewer.dispose();
 }return results;
});
for(const row of performanceEvidence){assert.equal(row.retainedUntouchedItem,true);assert.equal(row.stableDocumentAndCamera,true);assert.deepEqual(row.issues,[]);}
// Actual packed public entry/kernel, with simulated async host callbacks.
const lifecycle=await page.evaluate(async()=>{
 const {mount}=await import('/src/index.js');
 const nodeId='00000000-0000-4000-8000-000000000001';
 const document={schemaVersion:2,symbolSetVersion:1,canvas:{x:0,y:0,width:800,height:600,fill:'#ffffffff'},styles:{},seatingDefaults:{},textPolicy:{language:'und',direction:'auto'},nodes:[{id:nodeId,kind:'seat',label:'',transform:{x:100,y:100,rotation:0},width:40,height:40}],selectionUnits:[],sections:[],attachments:[],presets:[]};
 const host=globalThis.document.createElement('div');globalThis.document.body.replaceChildren(host);
 let resolve;const viewer=mount(host,{document,onSelectionRequested:()=>new Promise(r=>resolve=r)});
 host.querySelector('[role=list] button').click();
 const camera={...viewer.camera};
 viewer.update({seatPresentation:{[nodeId]:{selected:false,status:'available'}}});
 if(!viewer.pending.has(nodeId)||!viewer.selected.has(nodeId))throw Error('Presentation reset pending selection');
 const retained=viewer.options.document===document&&JSON.stringify(camera)===JSON.stringify(viewer.camera);
 resolve({accepted:true});await new Promise(r=>setTimeout(r,0));
 const accepted=viewer.selected.has(nodeId)&&viewer.pending.size===0;
 host.querySelector('[role=list] button').click();
 viewer.update({document:structuredClone(document)});
 resolve({accepted:false,message:'stale'});await new Promise(r=>setTimeout(r,0));
 const fenced=viewer.pending.size===0&&viewer.selected.size===0&&!host.textContent.includes('stale');
 host.querySelector('[role=list] button').click();viewer.dispose();resolve({accepted:true});await new Promise(r=>setTimeout(r,0));
 return {retained,accepted,fenced,disposed:host.childElementCount===0};
});
assert.deepEqual(lifecycle,{retained:true,accepted:true,fenced:true,disposed:true});
await page.goto(`${base}/flutter/`);await page.waitForSelector('flutter-view',{timeout:45000});const semantics=page.locator('flt-semantics-placeholder');if(await semantics.count()){await semantics.focus();await page.keyboard.press('Enter');if(await semantics.count())await semantics.dispatchEvent('click');}await page.getByRole('button',{name:'Uložit plánek',exact:true}).waitFor({timeout:20000});await page.screenshot({path:join(out,'archive-flutter.png')});await context.close();assert.deepEqual(requests,[]);assert.deepEqual(failures,[]);await writeFile(join(out,'browser.json'),JSON.stringify({npmTemplates:result,packedPickerLifecycle:lifecycle,packedRaster:raster,performanceEvidence,flutterArchiveBoot:true,externalRequests:requests,failures},null,2));console.log(`Archive browser: ${templates.length} npm scenes and actual archived Flutter example booted offline.`);}
finally{await browser.close();await new Promise(r=>server.close(r));}
