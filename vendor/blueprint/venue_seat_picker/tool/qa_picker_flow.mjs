/** Real Flutter/JS paired-unit and standing flow from the identical exported bundle. */
import {createRequire} from 'node:module';
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {createServer} from 'node:http';
import {resolve,join,extname} from 'node:path';
import assert from 'node:assert/strict';
import {button as control,activate,enableEditor,importPortable,download} from './qa_editor_flows.mjs';
const require=createRequire(new URL('../web/package.json',import.meta.url)),{chromium}=require('playwright');
const root=resolve(new URL('..',import.meta.url).pathname),out=resolve(process.argv[2]||'build/qa/browser/final-picker');await mkdir(out,{recursive:true});
const server=createServer(async(req,res)=>{try{const path=new URL(req.url,'http://localhost').pathname;let file=path.startsWith('/flutter/')?join(root,'build/demo',path):join(root,path);if(file.endsWith('/'))file+='index.html';res.setHeader('Content-Type',({'.html':'text/html','.js':'text/javascript','.json':'application/json','.wasm':'application/wasm'}[extname(file)]||'application/octet-stream'));res.end(await readFile(file));}catch{res.statusCode=404;res.end();}});await new Promise(r=>server.listen(0,'127.0.0.1',r));const base=`http://127.0.0.1:${server.address().port}`,browser=await chromium.launch({headless:true,args:['--mute-audio']}),external=[];let result={pass:false,externalRequests:external};
try{const c=await browser.newContext({viewport:{width:1440,height:1000},acceptDownloads:true});await c.route('**/*',r=>r.request().url().startsWith(base)||r.request().url().startsWith('data:')?r.continue():(external.push(r.request().url()),r.abort()));const p=await c.newPage();p.setDefaultTimeout(10000);const button=name=>p.getByRole('button',{name:new RegExp('^'+name+'(?: '+name+')?$')});try{
 await p.goto(`${base}/flutter/?demo=1`);await enableEditor(p);
 const fixture=JSON.parse(await readFile(join(root,'build/qa/browser-fixtures/lounge.json'),'utf8'));
 await importPortable(p,fixture);
 const portable=await download(p),bytes=Buffer.from(JSON.stringify(portable));
 assert.equal(portable.version,2);assert.equal(portable.layout.schemaVersion,2);
 assert.equal(portable.layout.selectionUnits.length,6);
 assert.equal(portable.layout.nodes.filter(n=>n.kind==='seat').length,12);
 await writeFile(join(out,'lounge-portable.json'),bytes);
 await activate(p,control(p,'Náhled'));await activate(p,control(p,'Seznam míst'));
 await p.getByRole('button',{name:/250 CZK/}).first().click();
 await p.getByText('2 selected seats - 0 standing selected',{exact:true}).waitFor();
 await activate(p,control(p,'Seznam míst'));
 await p.getByRole('button',{name:/Místa ke stání.*Volné/}).click();
 await activate(p,control(p,'Přidat'));
 await activate(p,control(p,'Potvrdit počet'));
 await p.getByText('2 selected seats - 2 standing selected',{exact:true}).waitFor();
 await p.screenshot({path:join(out,'flutter-paired-standing.png')});
 const js=await c.newPage();await js.goto(`${base}/web/demo/`);
 await js.waitForFunction(()=>!!window.venueDemo?.document);
 await js.locator('#import').setInputFiles({name:'lounge-portable.json',mimeType:'application/json',buffer:bytes});
 await js.waitForFunction(d=>JSON.stringify(window.venueDemo.document)===JSON.stringify(d),portable.layout);
 const pair=portable.layout.selectionUnits[0].nodeIds;
 await js.locator(`svg [data-node-id="${pair[0]}"]`).first().click();
 await js.waitForFunction(()=>window.venueDemo.selected.length===2);
 assert.deepEqual(new Set(await js.evaluate(()=>window.venueDemo.selected)),new Set(pair));
 const area=portable.layout.nodes.find(n=>n.kind==='capacityArea');
 const areaBounds=await js.locator(`svg [data-node-id="${area.id}"]`).first().boundingBox();
 assert.ok(areaBounds,'Standing area must be visible');
 await js.mouse.click(areaBounds.x+areaBounds.width*.2,areaBounds.y+areaBounds.height*.5);
 await js.locator('#picker').getByRole('spinbutton').fill('2');
 await js.getByRole('button',{name:'Confirm quantity',exact:true}).click();
 await js.locator('#selected').filter({hasText:'2 seats selected; 2 standing selected'}).waitFor();
 await js.screenshot({path:join(out,'js-paired-standing.png')});
 result={...result,pass:external.length===0,checks:['same exported version2 12seat6pair20capacity document in both hosts','Flutter accessible list chooses atomic pair','Flutter standing quantity2 remains independent','JS import selects same pair IDs','JS confirms quantity2 of capacity20'],browser:browser.version()};
 }catch(e){result.error=e.stack;await p.screenshot({path:join(out,'failure.png')}).catch(()=>{});await writeFile(join(out,'failure.aria.txt'),await p.locator('body').ariaSnapshot().catch(()=>''));}finally{await c.close();}}
finally{await browser.close();await new Promise(r=>server.close(r));}
await writeFile(join(out,'result.json'),JSON.stringify(result,null,2));console.log(`DA03 actual Flutter/JS pair+quantity: ${result.pass?'PASS':'FAIL'} ${result.error||''}`);if(!result.pass)process.exitCode=1;
