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
const browser=await chromium.launch({headless:true});report.environment.browser=browser.version();
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
 // All interaction goes through rendered semantics plus pointer/keyboard events.
 if(process.env.QA_UI_SCOPE!=='journey')for(const width of [360,900,1440])for(const dpr of [1,2])await attempt(`gestures ${width}@${dpr}`,async()=>{
  const c=await guarded({viewport:{width,height:900},deviceScaleFactor:dpr,hasTouch:width===360,reducedMotion:'reduce'});const p=await c.newPage();p.setDefaultTimeout(8000);try{
   await p.goto(`${base}/flutter/`);await p.waitForSelector('flutter-view',{timeout:45000});
   const semantics=p.locator('flt-semantics-placeholder');if(await semantics.count()){await semantics.focus();await p.keyboard.press('Enter');if(await semantics.count())await semantics.dispatchEvent('click');}
   const insert=p.getByRole('button',{name:'Insert',exact:true});await insert.waitFor({timeout:20000});
   await p.getByRole('button',{name:'Choose template',exact:true}).click();const blank=p.getByRole('button',{name:/^Blank layout /});for(let i=0;i<12;i++){const b=await blank.boundingBox().catch(()=>null);if(b&&b.y>=0&&b.y+b.height<850)break;await p.mouse.move(width/2,650);await p.mouse.wheel(0,350);await p.waitForTimeout(80);}await blank.click();const replace=p.getByRole('button',{name:'Replace plan',exact:true});await replace.click();await insert.click();
   await p.getByText('Table',{exact:true}).last().click();if(width===360)await p.touchscreen.tap(width*.48,480);else await p.mouse.click(width*.48,480);await p.waitForTimeout(350);
   await p.getByRole('button',{name:'Undo',exact:true}).click();await p.getByRole('button',{name:'Redo',exact:true}).click();
   await p.getByRole('button',{name:'Save local baseline',exact:true}).click();
   await p.getByRole('button',{name:'Customer preview',exact:true}).click();await p.waitForTimeout(350);await p.getByRole('button',{name:/^Return to editor/}).click();
   await p.screenshot({path:join(out,`editor-${width}-${dpr}.png`)});report.gestures.push({width,dpr,touch:width===360,reducedMotion:true,actions:['insert table by toolbar and canvas pointer','undo','redo','local save','preview and return']});
  }catch(e){await p.screenshot({path:join(out,`editor-failure-${width}-${dpr}.png`)}).catch(()=>{});await writeFile(join(out,`editor-failure-${width}-${dpr}.aria.txt`),await p.locator('body').ariaSnapshot().catch(()=>''));throw e;}finally{await c.close();}
 });
 if(process.env.QA_UI_SCOPE!=='basic')await attempt('DA02 DA04 detailed organizer journey',async()=>{
  const c=await guarded({viewport:{width:1440,height:1000},deviceScaleFactor:1,acceptDownloads:true});const p=await c.newPage();p.setDefaultTimeout(8000);const downloads=[];
  const button=name=>{const escaped=name.replace(/[.*+?^${}()|[\]\\]/g,'\\$&');return p.getByRole('button',{name:new RegExp('^'+escaped+'(?: '+escaped+')?$')});};
  const menu=async text=>{await button('Files and diagnostics').click();await p.getByRole('menuitem',{name:text,exact:true}).click();};
  const enable=async()=>{await p.waitForSelector('flutter-view',{timeout:45000});const s=p.locator('flt-semantics-placeholder');if(await s.count()){await s.focus();await p.keyboard.press('Enter');if(await s.count())await s.dispatchEvent('click');}await button('Insert').waitFor({timeout:20000});};
  const download=async text=>{const pending=p.waitForEvent('download',{timeout:15000});pending.catch(()=>{});await menu(text);const d=await pending;const data=await readFile(await d.path());downloads.push({menu:text,name:d.suggestedFilename(),bytes:data.length});return JSON.parse(data);};
  const upload=async(text,name,buffer,mimeType)=>{const pending=p.waitForEvent('filechooser',{timeout:15000});pending.catch(()=>{});await menu(text);await(await pending).setFiles({name,mimeType,buffer});};
  const inspect=async target=>{if(await target.count()&&await target.first().isVisible())return target.first();await p.mouse.move(1300,760);await p.mouse.wheel(0,-4000);await p.waitForTimeout(80);for(let i=0;i<15;i++){if(await target.count()&&await target.first().isVisible())return target.first();await p.mouse.wheel(0,230);await p.waitForTimeout(60);}return target.first();};
  const paletteInput=async()=>{for(let attempt=0;attempt<20;attempt++){for(const f of await p.getByRole('textbox',{name:'Find object',exact:true}).all()){const box=await f.boundingBox();if(box&&box.x<300&&box.width>20)return f;}await p.waitForTimeout(50);}throw Error('Palette search is not visible');};
  const type=async(target,value)=>{await target.click();await p.waitForTimeout(200);await target.fill(value);await p.waitForTimeout(200);console.log('Typed',value,await target.inputValue());};
  const field=async(name,value)=>{const target=await inspect(p.getByRole('textbox',{name,exact:true}));await type(target,value);await button(`Apply ${name}`).click();};
  try{
   await p.goto(`${base}/flutter/`);await enable();
   await button('Choose template').click();await p.getByRole('button',{name:/^Classic ball /}).click();await button('Replace plan').click();console.log('Journey: classic gallery confirmed');
   await button('Insert').click();await type(await paletteInput(),'Table');await p.getByText('Table',{exact:true}).last().click();
   const canvas=await p.getByRole('group',{name:/^Layout canvas/}).boundingBox();const scale=Math.min((canvas.width-32)/1600,(canvas.height-32)/1200);const point=(x,y)=>({x:canvas.x+(canvas.width-1600*scale)/2+x*scale,y:canvas.y+(canvas.height-1200*scale)/2+y*scale});
   console.log('Journey canvas',JSON.stringify(canvas),'scale',scale);const tablePoint=point(1680,1100);console.log('Journey table point',JSON.stringify(tablePoint));assert.ok(tablePoint.x<canvas.x+canvas.width&&tablePoint.y<canvas.y+canvas.height,'Free table point is visible beyond current document edge');await p.mouse.click(tablePoint.x,tablePoint.y);await p.waitForTimeout(350);await p.keyboard.press('Escape');await p.mouse.click(tablePoint.x,tablePoint.y);await p.waitForTimeout(350);console.log('Journey: new table selected');
   await writeFile(join(out,'debug-before-chair.json'),JSON.stringify(await download('Export geometry only')));await (await inspect(button('Add one seat'))).click();const afterChair=await download('Export geometry only');await writeFile(join(out,'debug-after-chair.json'),JSON.stringify(afterChair));assert.equal(afterChair.nodes.filter(n=>n.kind==='seat').length,79,'Add one seat succeeds without overlap');await (await inspect(p.getByText('350 CZK',{exact:true}))).click();console.log('Journey: seventh chair and sample price');
   if(!(await p.getByRole('textbox',{name:'Find object',exact:true}).count()))await button('Insert').click();await type(await paletteInput(),'Text');await p.getByText('Text',{exact:true}).last().click();const textPoint=point(1520,80);await p.mouse.click(textPoint.x,textPoint.y);await p.waitForTimeout(350);await p.keyboard.press('Escape');
   await field('Width','350');await field('Height','130');await field('Text','Příliš žluťoučký kůň\nDruhý řádek');
   await p.getByRole('button',{name:'Font fixture:sans',exact:true}).click();await p.getByRole('menuitem',{name:'fixture:serif',exact:true}).click();
   await field('Text color #RRGGBBAA','#224466CC');await field('Rotation °','37');console.log('Journey: multiline font/color/rotation edited');
   await button('Undo').click();await button('Redo').click();
   const png=await p.evaluate(()=>{const canvas=document.createElement('canvas');canvas.width=4;canvas.height=3;const ctx=canvas.getContext('2d');ctx.fillStyle='#88aacc';ctx.fillRect(0,0,4,3);return canvas.toDataURL('image/png').split(',')[1];});
   await upload('Import background image','qa-background.png',Buffer.from(png,'base64'),'image/png');await p.getByText(/Local background embedded/).waitFor();
   await button('Save local baseline').click();await p.getByText(/Saved local baseline/).waitFor();
   console.log('Journey: PNG embedded and saved');const portable=await download('Export portable demo'),geometry=await download('Export geometry only');await writeFile(join(out,'journey-portable.json'),JSON.stringify(portable));await writeFile(join(out,'journey-geometry.json'),JSON.stringify(geometry));assert.deepEqual(portable.layout,geometry);assert.equal(geometry.schemaVersion,1);assert.equal(geometry.nodes.filter(n=>n.kind==='seat').length,79);assert.ok(!('host'in geometry));assert.ok(portable.layout.background.assetRef);assert.ok(Object.keys(portable.host.prices).length);
   const resource=JSON.parse(Buffer.from(portable.resources[0].data,'base64'));assert.equal(Object.values(resource.assets)[0].mime,'image/png');assert.ok(Object.values(resource.assets)[0].data);
   const text=geometry.nodes.find(n=>n.kind==='text'&&n.text?.includes('žluťoučký'));assert.ok(text,'Edited Czech multiline text exported');assert.equal(text.fontId,'fixture:serif');assert.equal(text.color,'#224466CC');assert.equal(text.transform.rotation,37);
   const js=await c.newPage();try{await js.goto(`${base}/web/demo/`);await js.waitForFunction(()=>!!window.venueDemo?.document);await js.locator('#import').setInputFiles({name:'flutter-portable.json',mimeType:'application/json',buffer:Buffer.from(JSON.stringify(portable))});await js.waitForFunction(expected=>JSON.stringify(window.venueDemo.document)===JSON.stringify(expected),geometry);assert.deepEqual(await js.evaluate(()=>window.venueDemo.document),geometry);assert.ok(await js.locator('#picker svg image').count(),'Embedded PNG is rendered by JS consumer');const seat=geometry.nodes.find(n=>n.kind==='seat');await js.locator(`[data-node-id="${seat.id}"]`).last().click();await js.waitForFunction(id=>window.venueDemo.selected.includes(id),seat.id);await js.screenshot({path:join(out,'same-export-js.png')});}finally{await js.close();}
   await upload('Import portable demo','qa-portable.json',Buffer.from(JSON.stringify(portable)),'application/json');await p.getByText(/Imported portable draft/).waitFor();
   assert.deepEqual((await download('Export portable demo')).layout,portable.layout);
   await upload('Import portable demo','bad.json',Buffer.from('{"format":"invalid"}'),'application/json');await p.getByText(/Import rejected; draft unchanged/).waitFor();assert.deepEqual((await download('Export portable demo')).layout,portable.layout);
   await p.waitForTimeout(450);await p.reload();await enable();const restored=await download('Export portable demo');assert.deepEqual(restored.layout,portable.layout);assert.deepEqual(restored.host.prices,portable.host.prices);assert.deepEqual(JSON.parse(Buffer.from(restored.resources[0].data,'base64')).assets,resource.assets);
   await menu('Diagnostics');await p.waitForTimeout(300);await button('Simulate font race').focus();await p.keyboard.press('Enter');await p.getByText(/stale result ignored/).waitFor();
   for(const scenario of ['conflict','timeout','resource']){await button('success').focus();await p.keyboard.press('Enter');await p.getByRole('menuitem',{name:scenario,exact:true}).click();await button('Save local baseline').click();await p.getByText(scenario==='conflict'?/Demo conflict:/:scenario==='timeout'?/Demo request timed out/:/Demo resource unavailable/).waitFor();assert.deepEqual((await download('Export portable demo')).layout,portable.layout);await button(scenario).focus();await p.keyboard.press('Enter');await p.getByRole('menuitem',{name:'success',exact:true}).click();}
   await p.getByRole('checkbox',{name:'Storage full',exact:true}).focus();await p.keyboard.press('Space');await button('Save local baseline').click();await p.getByText(/Save failed. Draft is preserved/).waitFor();assert.deepEqual((await download('Export portable demo')).layout,portable.layout);
   await p.screenshot({path:join(out,'journey1440.png')});report.gestures.push({name:'DA02/DA04 organizer',width:1440,downloads,checks:['gallery classic','table and seventh chair','sample price','Czech multiline text, font, color, rotation','undo redo','PNG import embedded','portable and pure geometry download','same portable export renders and selects in actual JS picker','valid reopen','invalid import preserves','autosave reload retains background/prices','stale font resolve','conflict timeout preserve export','storage full preserves export']});
  }catch(e){await p.screenshot({path:join(out,'journey-failure.png')}).catch(()=>{});await writeFile(join(out,'journey-failure.aria.txt'),await p.locator('body').ariaSnapshot().catch(()=>''));throw e;}finally{await c.close();}
 });

 }
}finally{await browser.close();await new Promise(r=>server.close(r));}
report.goalFailures=report.performance.filter(p=>p.desktopFrameTarget===false||p.initTarget===false).map(p=>({count:p.count,desktopFrameTarget:p.desktopFrameTarget,initTarget:p.initTarget}));
await writeFile(join(out,'result.json'),JSON.stringify(report,null,2));await writeFile(join(out,'index.html'),`<!doctype html><meta charset="utf-8"><title>Blueprint QA</title><h1>Blueprint QA evidence</h1><pre>${JSON.stringify(report,null,2).replaceAll('&','&amp;').replaceAll('<','&lt;')}</pre>`);console.log(`QA browser: ${report.parity.length} exact fixtures, ${report.corpusParity.length} exact corpus, ${report.gestures.length} gesture flows; ${report.failures.length} failures, ${report.goalFailures.length} measured target misses; ${out}/index.html`);if(report.failures.length||report.goalFailures.length||report.externalRequests.length||(phase!=='ui'&&!report.kernel?.pass))process.exitCode=1;
