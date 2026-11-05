/** Supported Czech demo journeys, through public semantics, files and pointers. */
import assert from 'node:assert/strict';
import {readFile,writeFile} from 'node:fs/promises';
import {join} from 'node:path';

export const button=(page,name)=>page.getByRole('button',{name,exact:true});
export async function activate(page,target){await target.focus();await page.keyboard.press('Enter');}
async function save(page){
 await activate(page,button(page,'Uložit plánek'));
 const saving=page.getByRole('button',{name:/^Ukládání/});
 await saving.waitFor({state:'visible'});await saving.waitFor({state:'hidden'});
 await button(page,'Uložit plánek').waitFor();
}
export async function enableEditor(page){
 await page.waitForSelector('flutter-view',{timeout:45000});
 const semantics=page.locator('flt-semantics-placeholder');
 if(await semantics.count())await semantics.dispatchEvent('click');
 const blank=page.getByRole('button',{name:/^Prázdný sál /});
 await Promise.race([blank.waitFor(),button(page,'Náhled').waitFor()]);
 if(await blank.count())await blank.click();
 await button(page,'Náhled').waitFor();
}
export async function replaceIfAsked(page){
 const replace=button(page,'Nahradit');
 // Dialog is created asynchronously by file reading/validation.
 await Promise.race([replace.waitFor(),page.getByText('Plánek načtený ze souboru',{exact:true}).waitFor()]).catch(()=>{});
 if(await replace.count())await activate(page,replace);
}
export async function menu(page,name){
 const item=page.getByRole('menuitem',{name,exact:true});
 await activate(page,button(page,'Soubory a další možnosti'));
 await activate(page,item);
 await page.waitForTimeout(300);
 if(await item.isVisible()){await page.mouse.click(100,300);await item.waitFor({state:'hidden'});}
}
export async function download(page,name='Exportovat plánek včetně podkladů'){
 const pending=page.waitForEvent('download',{timeout:20000});pending.catch(()=>{});
 await menu(page,name);const file=await pending;
 return JSON.parse(await readFile(await file.path(),'utf8'));
}
export async function upload(page,name,file,bytes,mimeType='application/json'){
 const pending=page.waitForEvent('filechooser');pending.catch(()=>{});
 await menu(page,name);await(await pending).setFiles({name:file,mimeType,buffer:bytes});
}
export async function importPortable(page,value){
 await upload(page,'Otevřít plánek ze souboru','portable.json',Buffer.from(JSON.stringify(value)));
 await replaceIfAsked(page);
 for(let attempt=0;attempt<10;attempt++){const current=await download(page);if(JSON.stringify(current.layout)===JSON.stringify(value.layout))return;await new Promise(r=>setTimeout(r,50));}
 throw Error('Imported portable document did not become the exported draft');
}
export async function insert(page,kind,width){
 if(width<900)await activate(page,button(page,'Vložit'));
 const search=page.getByRole('textbox',{name:'Hledat objekt',exact:true});
 if(width>=900 && !await search.count()){
  await page.mouse.click(100,300);
  await search.waitFor({state:'visible'});
 }
 if(await search.count()){
  const bounds=await search.boundingBox();assert.ok(bounds);
  for(let attempt=0;attempt<3;attempt++){
   await page.mouse.click(bounds.x+bounds.width/2,bounds.y+bounds.height/2);
   await page.waitForTimeout(250);
   await page.keyboard.press('End');for(let i=0;i<32;i++)await page.keyboard.press('Backspace');
   await page.keyboard.type(kind,{delay:25});
   if(await button(page,`Vložit: ${kind}`).waitFor({state:'visible',timeout:1500}).then(()=>true).catch(()=>false))break;
  }
 }
 const item=button(page,`Vložit: ${kind}`);await item.waitFor();
 const itemBounds=await item.boundingBox();assert.ok(itemBounds);
 await page.mouse.click(itemBounds.x+itemBounds.width/2,itemBounds.y+itemBounds.height/2);
 if(width>=900){
  const canvas=await page.getByRole('group',{name:/^Plátno plánku/}).first().boundingBox();
  assert.ok(canvas,'Canvas must be pointer reachable');
  await page.mouse.click(canvas.x+canvas.width*.5,canvas.y+canvas.height*.5);
 }
}
async function editField(page,name,value){
 const field=page.getByRole('textbox',{name,exact:true});
 await field.scrollIntoViewIfNeeded();
 let focused=false;
 for(let attempt=0;attempt<3;attempt++){
  const bounds=await field.boundingBox();assert.ok(bounds);
  await page.mouse.click(bounds.x+bounds.width/2,bounds.y+bounds.height/2);
  focused=await page.waitForFunction(label=>['INPUT','TEXTAREA'].includes(document.activeElement?.tagName)&&document.activeElement?.getAttribute('aria-label')===label,name,{timeout:1000}).then(()=>true).catch(()=>false);
  if(focused)break;
  await page.mouse.move(1300,700);await page.mouse.wheel(0,150);await page.waitForTimeout(250);
 }
 assert.ok(focused,`Native field ${name} must receive focus`);
 await page.waitForTimeout(500);
 await page.keyboard.press(process.platform==='darwin'?'Meta+A':'Control+A');if(name==='Text')await page.keyboard.insertText(value);else await page.keyboard.type(value,{delay:30});
 assert.equal(await page.evaluate(()=>document.activeElement?.value),value,`${name} native value`);
 await page.keyboard.press('Tab');await page.waitForTimeout(500);
}
export async function runEditorFlows({root,out,base,guarded,report,attempt}){
 if(process.env.QA_UI_SCOPE!=='journey')for(const width of process.env.QA_UI_WIDTH?[Number(process.env.QA_UI_WIDTH)]:[360,900,1440])for(const dpr of process.env.QA_UI_DPR?[Number(process.env.QA_UI_DPR)]:[1,2])await attempt(`gestures ${width}@${dpr}`,async()=>{
  const context=await guarded({viewport:{width,height:900},deviceScaleFactor:dpr,hasTouch:width===360,reducedMotion:'reduce',acceptDownloads:true});
  const page=await context.newPage();page.setDefaultTimeout(12000);
  try{
   await page.goto(`${base}/flutter/?demo=1`);await enableEditor(page);
   await insert(page,'Stůl',width);
   const created=await download(page,'Exportovat pouze geometrii');
   assert.equal(created.schemaVersion,2);
   assert.equal(created.nodes.filter(n=>n.kind==='table').length,1,'Insert one table');
   await activate(page,button(page,'Zpět'));
   assert.equal((await download(page,'Exportovat pouze geometrii')).nodes.filter(n=>n.kind==='table').length,0,'Undo insertion');
   await activate(page,button(page,'Znovu'));
   assert.deepEqual(await download(page,'Exportovat pouze geometrii'),created,'Redo exact document');
   await activate(page,button(page,'Uložit plánek'));
   await page.getByRole('button',{name:/^Ukládání/}).waitFor({timeout:1000}).catch(()=>{});
   await button(page,'Uložit plánek').waitFor();
   const saved=await download(page);
   assert.ok(saved.host.revision>=1,'Explicit save persisted a baseline revision');
   assert.deepEqual(saved.host.savedBaseline,saved.layout,'Saved baseline matches actual portable document');
   await activate(page,button(page,'Náhled'));await button(page,'Seznam míst').waitFor();
   await activate(page,button(page,'Zpět do editoru'));await button(page,'Náhled').waitFor();
   await page.screenshot({path:join(out,`editor-${width}-${dpr}.png`)});
   report.gestures.push({width,dpr,checks:['pointer insertion','version2 export','exact undo/redo','local save','preview and return','mobile host actions remain reachable']});
  }catch(error){await page.screenshot({path:join(out,`editor-failure-${width}-${dpr}.png`)}).catch(()=>{});await writeFile(join(out,`editor-failure-${width}-${dpr}.aria.txt`),await page.locator('body').ariaSnapshot().catch(()=>''));throw error;}
  finally{await context.close();}
 });
 if(process.env.QA_UI_SCOPE!=='basic')await attempt('current organizer journey',async()=>{
  const context=await guarded({viewport:{width:1440,height:1000},acceptDownloads:true});
  const page=await context.newPage();page.setDefaultTimeout(12000);
  try{
   await page.goto(`${base}/flutter/?demo=1`);await enableEditor(page);
   await menu(page,'Otevřít ukázkový sál (72 míst)');
   const original=await download(page,'Exportovat pouze geometrii');
   assert.equal(original.nodes.filter(n=>n.kind==='seat').length,72,'Sample action opens its advertised 72 seats');
   await insert(page,'Stůl',1440);
   const withTable=await download(page,'Exportovat pouze geometrii');
   assert.equal(withTable.nodes.filter(n=>n.kind==='table').length,original.nodes.filter(n=>n.kind==='table').length+1);
   const add=button(page,'Přidat židli');await add.scrollIntoViewIfNeeded();await activate(page,add);
   const withChair=await download(page,'Exportovat pouze geometrii');
   assert.equal(withChair.nodes.filter(n=>n.kind==='seat').length,withTable.nodes.filter(n=>n.kind==='seat').length+1);
   await insert(page,'Text',1440);
   await editField(page,'Text','Příliš žluťoučký kůň\nDruhý řádek');
   await save(page);
   await activate(page,button(page,'Poloha a velikost'));
   await activate(page,page.getByRole('button',{name:'Text',exact:true,description:/Rozbaleno/}));
   await editField(page,'Šířka','350');await editField(page,'Výška','130');await editField(page,'Úhel','37');
   await activate(page,page.getByRole('button',{name:'Text',exact:true,description:/Sbaleno/}));
   await activate(page,button(page,'Tučné'));await page.waitForTimeout(500);
   await activate(page,button(page,'Kurzíva'));await page.waitForTimeout(500);
   await activate(page,button(page,'Zpět'));await page.waitForTimeout(500);
   await activate(page,button(page,'Znovu'));await page.waitForTimeout(500);
   await save(page);
   const png=await page.evaluate(()=>{const c=document.createElement('canvas');c.width=4;c.height=3;const x=c.getContext('2d');x.fillStyle='#88aacc';x.fillRect(0,0,4,3);return c.toDataURL('image/png').split(',')[1];});
   await upload(page,'Nahrát podklad','background.png',Buffer.from(png,'base64'),'image/png');
   await page.getByText(/Local background embedded|Lokální podklad|Podklad/).first().waitFor();
   await save(page);
   const portable=await download(page),geometry=await download(page,'Exportovat pouze geometrii');
   assert.equal(portable.version,2);assert.equal(geometry.schemaVersion,2);assert.deepEqual(portable.layout,geometry);
   assert.ok(!('host' in geometry));assert.ok(geometry.background.assetRef);
   const text=geometry.nodes.find(n=>n.kind==='text'&&n.text?.includes('žluťoučký'));
   assert.ok(text,'Czech multiline label remains canonical');assert.equal(text.text,'Příliš žluťoučký kůň\nDruhý řádek');
   assert.ok(text.text.includes('\n'),'Text contains an actual line break');
   assert.equal(text.width,350);assert.equal(text.height,130);assert.equal(text.transform.rotation,37);
   assert.equal(text.style.label.weight,700);assert.equal(text.style.label.italic,true);
   await writeFile(join(out,'journey-portable.json'),JSON.stringify(portable));
   // Host prices cross the actual portable import boundary and retain undo.
   const priced=structuredClone(portable),seat=geometry.nodes.find(n=>n.kind==='seat');priced.host.prices[seat.id]=350;
   await importPortable(page,priced);assert.equal((await download(page)).host.prices[seat.id],350);
   await activate(page,button(page,'Zpět'));assert.deepEqual((await download(page)).host.prices,portable.host.prices);
   await activate(page,button(page,'Znovu'));assert.equal((await download(page)).host.prices[seat.id],350);
   await activate(page,button(page,'Uložit plánek'));const saved=await download(page);
   const js=await context.newPage();
   try{
    await js.goto(`${base}/web/demo/`);await js.waitForFunction(()=>!!window.venueDemo?.document);
    await js.locator('#import').setInputFiles({name:'portable.json',mimeType:'application/json',buffer:Buffer.from(JSON.stringify(saved))});
    await js.waitForFunction(doc=>JSON.stringify(window.venueDemo.document)===JSON.stringify(doc),saved.layout);
    assert.ok(await js.locator('#picker svg image').count(),'Embedded background reaches the public viewer');
    const seatBounds=await js.locator(`svg [data-node-id="${seat.id}"]`).first().boundingBox();assert.ok(seatBounds);
    await js.mouse.click(seatBounds.x+seatBounds.width/2,seatBounds.y+seatBounds.height/2);
    await js.waitForFunction(id=>window.venueDemo.selected.includes(id),seat.id);
   }finally{await js.close();}
   await upload(page,'Otevřít plánek ze souboru','bad.json',Buffer.from('{"format":"invalid"}'));
   await page.getByText(/Import rejected|Import odmítnut|Plánek se nepodařilo/).first().waitFor();
   assert.deepEqual((await download(page)).layout,saved.layout,'Invalid file preserves draft');
   await page.reload();await enableEditor(page);
   const restored=await download(page);assert.deepEqual(restored.layout,saved.layout);assert.deepEqual(restored.host.prices,saved.host.prices);
   await menu(page,'Diagnostika dema');
   await activate(page,button(page,'Simulate font race'));await page.getByText(/stale result ignored/).waitFor();
   for(const scenario of ['conflict','timeout','resource']){
    await activate(page,button(page,'success'));await page.getByRole('menuitem',{name:scenario,exact:true}).click();
    await activate(page,button(page,'Uložit plánek'));
    await page.getByText(scenario==='conflict'?/Demo conflict:/:scenario==='timeout'?/Demo request timed out/:/Demo resource unavailable/).waitFor();
    assert.deepEqual((await download(page)).layout,saved.layout);
    await activate(page,button(page,scenario));await page.getByRole('menuitem',{name:'success',exact:true}).click();
   }
   const full=page.getByRole('checkbox',{name:'Storage full',exact:true});await full.focus();await page.keyboard.press('Space');
   await activate(page,button(page,'Uložit plánek'));await page.getByText(/Save failed|Uložení se nezdařilo|Plánek se nepodařilo uložit/).first().waitFor();
   assert.deepEqual((await download(page)).layout,saved.layout);
   report.gestures.push({name:'organizer',checks:['72seat sample','table and extra chair','canonical multiline text/geometry/font style','undo/redo','embedded PNG','version2 portable/geometry exports','host price history','real JS import and selection','invalid file preserves draft','reload retains assets/prices','stale font resolve','conflict/timeout/resource/quota failures preserve draft']});
  }catch(error){await page.screenshot({path:join(out,'journey-failure.png')}).catch(()=>{});await writeFile(join(out,'journey-failure.aria.txt'),await page.locator('body').ariaSnapshot().catch(()=>''));throw error;}
  finally{await context.close();}
 });
}
