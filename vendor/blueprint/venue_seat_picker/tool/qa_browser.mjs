/** Deterministic isolated browser gate; no application controller hooks. */
import {createRequire} from 'node:module';
import {readFile,mkdir,writeFile} from 'node:fs/promises';
import {createServer} from 'node:http';
import {resolve,extname,join} from 'node:path';
import {cpus,totalmem,platform,arch} from 'node:os';
import {gzipSync} from 'node:zlib';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import assert from 'node:assert/strict';
import {runEditorFlows} from './qa_editor_flows.mjs';
const require=createRequire(new URL('../web/package.json',import.meta.url));
const {chromium}=require('playwright');
const phase=process.env.QA_PHASE||'all';
const root=resolve(new URL('..',import.meta.url).pathname),fixtures=resolve(process.argv[2]||'build/qa/fixtures');
const kernelAtStart=await readFile(join(root,'web/dist/venue_layout_kernel.js'));
const manifest=await readFile(join(root,'web/dist/manifest.json'),'utf8').then(JSON.parse).catch(()=>({toolchain:execFileSync('fvm',['flutter','--version','--machine'],{cwd:root,encoding:'utf8'}),sourceRevision:execFileSync('git',['rev-parse','HEAD'],{cwd:root,encoding:'utf8'}).trim(),sourceDigest:'Full build manifest not yet generated; exact kernel hash recorded separately.'}));
const out=resolve(process.argv[3]||'build/qa/browser');await mkdir(out,{recursive:true});
const report={environment:{platform:platform(),arch:arch(),cpu:cpus()[0]?.model,cpuCount:cpus().length,ramBytes:totalmem(),toolchain:manifest.toolchain,sourceRevision:manifest.sourceRevision,sourceDigest:manifest.sourceDigest},parity:[],corpusParity:[],performance:[],gestures:[],raster:[],failures:[],externalRequests:[]};
const server=createServer(async(req,res)=>{if(req.url==='/qa-blank'){res.setHeader('Content-Type','text/html');res.end('<!doctype html><body><script src="/web/dist/venue_layout_kernel.js"></script>');return;}try{const url=decodeURIComponent(new URL(req.url,'http://localhost').pathname);let file=url.startsWith('/fixtures/')?join(fixtures,url.slice(10)):url.startsWith('/flutter/')?join(root,'build/demo',url):join(root,url);if(!file.startsWith(root)&&!file.startsWith(fixtures))throw Error('path');if(file.endsWith('/'))file+='index.html';res.setHeader('Content-Type',({'.js':'text/javascript','.json':'application/json','.html':'text/html','.png':'image/png','.wasm':'application/wasm'}[extname(file)]||'application/octet-stream'));res.end(await readFile(file));}catch{res.statusCode=404;res.end('not found');}});
await new Promise(r=>server.listen(0,'127.0.0.1',r));const base=`http://127.0.0.1:${server.address().port}`;
const browser=await chromium.launch({headless:true,args:['--mute-audio']});report.environment.browser=browser.version();
const guarded=async opts=>{const c=await browser.newContext(opts);await c.route('**/*',route=>{const url=route.request().url();if(url.startsWith(base)||url.startsWith('data:')||url.startsWith('blob:'))return route.continue();report.externalRequests.push(url);return route.abort();});return c;};
const attempt=async(name,fn)=>{try{await fn();}catch(e){console.error(`${name}: ${e.message}`);report.failures.push({name,error:e.stack});}};
try{
 if(phase!=='ui'){
 const context=await guarded({viewport:{width:1440,height:900}}),page=await context.newPage();
 await page.goto(`${base}/qa-blank`);await page.waitForFunction(()=>!!globalThis.VenueLayoutKernel);
 const fixture=JSON.parse(await readFile(join(fixtures,'report.json'),'utf8'));
 if(phase!=='performance')for(const f of fixture.fixtures){await attempt(`parity ${f.name}`,async()=>{
  const actual=await page.evaluate(({f,resources})=>{const k=globalThis.VenueLayoutKernel,j=JSON.stringify(f.document);return {scene:JSON.parse(k.compileScene(j,JSON.stringify(resources),JSON.stringify(f.presentation||{}))),hits:f.hits.map(h=>k.hitTest(j,h.x,h.y)),motion:f.motion.map(m=>({document:JSON.parse(k.interpolate(j,JSON.stringify(f.toDocument),m.t)),scene:JSON.parse(k.compileScene(JSON.stringify(m.document),JSON.stringify(resources),JSON.stringify(f.presentation||{})))}))};},{f,resources:fixture.resources});
  assert.deepEqual(actual.scene,f.scene);assert.deepEqual(actual.hits,f.hits.map(h=>h.id));
  for(let i=0;i<f.motion.length;i++){assert.deepEqual(actual.motion[i].document,f.motion[i].document);assert.deepEqual(actual.motion[i].scene,f.motion[i].scene);}
  report.parity.push({fixture:f.name,scene:'exact',hits:f.hits.length,motionSamples:f.motion.length});console.log(`Exact fixture ${f.name}: scene/hit/motion passed`);
 });}
 for(const corpus of fixture.corpus){await attempt(`corpus ${corpus.count}`,async()=>{
  const document=corpus.document||JSON.parse(await readFile(join(fixtures,`corpus-${corpus.count}.document.json`),'utf8'));
  if(phase!=='performance'){
  const expected=JSON.parse(await readFile(join(fixtures,`corpus-${corpus.count}.scene.json`),'utf8'));
  const actual=await page.evaluate(({document,resources})=>JSON.parse(VenueLayoutKernel.compileScene(JSON.stringify(document),JSON.stringify(resources),'{}')),{document,resources:fixture.resources});assert.deepEqual(actual,expected);report.corpusParity.push({count:corpus.count,exact:true,sceneBytes:corpus.sceneBytes});if(phase==='parity')return;
  }
  const perf=await page.evaluate(async({document,resources})=>{
    const {mount}=await import('/web/src/index.js');const host=window.document.createElement('div');host.style.cssText='width:1400px;height:800px';window.document.body.replaceChildren(host);
    const before=performance.memory?.usedJSHeapSize??null,start=performance.now();const viewer=mount(host,{document,resources});const init=performance.now()-start;
    await new Promise(requestAnimationFrame);const raf=[],patch=[],camera=[],id=document.nodes.find(n=>n.kind==='seat').id;
    for(let i=0;i<36;i++){
      const frameStart=performance.now();let start=frameStart;viewer.update({seatPresentation:{[id]:{selected:i%2===0}}});patch.push(performance.now()-start);
      start=performance.now();viewer.svg.dispatchEvent(new WheelEvent('wheel',{deltaY:i%2?5:-5,clientX:400,clientY:300,bubbles:true,cancelable:true}));camera.push(performance.now()-start);
      start=performance.now();await new Promise(requestAnimationFrame);raf.push(performance.now()-frameStart);
    }
    const after=performance.memory?.usedJSHeapSize??null;const issues=viewer.scene.issues;window.__qaViewer=viewer;const p95=a=>a.sort((a,b)=>a-b)[Math.floor(a.length*.95)];
    return{initMs:init,patchCpuP95Ms:p95(patch),cameraCpuP95Ms:p95(camera),frameP95Ms:p95(raf),heapBefore:before,heapAfter:after,issues,frameMethod:'36 RAF intervals after real wheel handler and single-node presentation update; CPU patch and wheel-handler timings separately reported; no physical phone claim'};
  },{document,resources:fixture.resources});
  const cdp=await context.newCDPSession(page);perf.warmV8Heap=await cdp.send('Runtime.getHeapUsage');await cdp.detach();await page.evaluate(()=>{window.__qaViewer.dispose();window.__qaViewer=null;});
  const coldContext=await guarded({viewport:{width:1440,height:900}}),coldPage=await coldContext.newPage();let coldInitMs,coldV8Heap,coldResourceTimings;
  try{const coldStart=Date.now();await coldPage.goto(`${base}/qa-blank`);await coldPage.evaluate(async count=>{const [{mount},document,resources]=await Promise.all([import('/web/src/index.js'),fetch(`/fixtures/corpus-${count}.document.json`).then(r=>r.json()),fetch('/assets/layout_fonts/fixtures.json').then(r=>r.json())]);const host=window.document.createElement('div');host.style.cssText='width:1400px;height:800px';window.document.body.append(host);window.viewer=mount(host,{document,resources});await new Promise(requestAnimationFrame);await new Promise(requestAnimationFrame);},corpus.count);coldInitMs=Date.now()-coldStart;coldResourceTimings=await coldPage.evaluate(()=>performance.getEntriesByType('resource').map(e=>({name:new URL(e.name).pathname,durationMs:e.duration,encodedBytes:e.encodedBodySize,decodedBytes:e.decodedBodySize,transferBytes:e.transferSize})));const coldCdp=await coldContext.newCDPSession(coldPage);coldV8Heap=await coldCdp.send('Runtime.getHeapUsage');await coldCdp.detach();}finally{await coldContext.close();}
  console.log(`Corpus ${corpus.count}: cold ${coldInitMs}ms, frame p95 ${perf.frameP95Ms.toFixed(2)}ms, patch CPU p95 ${perf.patchCpuP95Ms.toFixed(2)}ms`);
  report.performance.push({...corpus,document:undefined,...perf,coldInitMs,coldV8Heap,coldResourceTimings,desktopFrameTarget:corpus.count===5000?perf.frameP95Ms<=16.7:null,initTarget:corpus.count===5000?coldInitMs<=2000:null});
 });}
 const fontFixtures=await readFile(join(root,'assets/layout_fonts/fixtures.json'));report.fontFixtures={bytes:fontFixtures.length,gzipBytes:gzipSync(fontFixtures).length,catalog:'Protocol-2 prepared paragraphs and number symbols; measured separately from kernel.'};
 const kernel=kernelAtStart;const kernelAtEnd=await readFile(join(root,'web/dist/venue_layout_kernel.js'));report.sourceChangedDuringRun=!kernel.equals(kernelAtEnd);if(report.sourceChangedDuringRun)report.failures.push({name:'source provenance',error:'Kernel artifact changed during verification; repeat after final source freeze.'});report.kernel={sha256:createHash('sha256').update(kernel).digest('hex'),bytes:kernel.length,gzipBytes:gzipSync(kernel).length,targetBytes:512000,pass:gzipSync(kernel).length<=512000};
 await context.close();
 }
 if(phase!=='kernel'&&phase!=='parity'&&phase!=='performance'){
 await runEditorFlows({root,out,base,guarded,report,attempt});

 }
}finally{await browser.close();await new Promise(r=>server.close(r));}
report.goalFailures=report.performance.filter(p=>p.desktopFrameTarget===false||p.initTarget===false).map(p=>({count:p.count,desktopFrameTarget:p.desktopFrameTarget,initTarget:p.initTarget}));
await writeFile(join(out,'result.json'),JSON.stringify(report,null,2));await writeFile(join(out,'index.html'),`<!doctype html><meta charset="utf-8"><title>Blueprint QA</title><h1>Blueprint QA evidence</h1><pre>${JSON.stringify(report,null,2).replaceAll('&','&amp;').replaceAll('<','&lt;')}</pre>`);console.log(`QA browser: ${report.parity.length} exact fixtures, ${report.corpusParity.length} exact corpus, ${report.gestures.length} gesture flows; ${report.failures.length} failures, ${report.goalFailures.length} measured target misses; ${out}/index.html`);if(report.failures.length||report.goalFailures.length||report.externalRequests.length||(phase!=='ui'&&!report.kernel?.pass))process.exitCode=1;
