import {assert,assertEquals,assertRejects,assertThrows} from 'jsr:@std/assert@1';
import {TicketFontResolver,TicketFontError,fontCatalog,digest,fontMetrics,legacyNamedFontId,legacyNamedId,legacyWideId,futuraId,type FontDependencies,type FontAsset} from './ticketFonts.ts';
import {PDFDocument,PDFName,PDFRawStream,PDFDict} from 'npm:pdf-lib';
import {inflateSync} from 'node:zlib';
import {generateTicketPdf,prepareTicketRenderer} from './ticketGeneration.ts';
import {preset,parseLayout,pdfBox} from './ticketLayout.ts';
import {sampleData} from './ticketRenderData.ts';
import {fitText} from './ticketText.ts';
const families=['Roboto','Roboto Slab','Russo One'];
const assets=families.map(f=>fontCatalog.find(a=>a.family===f)!);
const local=new Map<string,Uint8Array>();
for(const a of assets)local.set(a.id,await Deno.readFile(`test/fixtures/ticket_fonts/${a.family.replaceAll(' ','-')}.ttf`));
function setup(shared=new Map<string,Uint8Array>()) {
  const counts={fetch:0,read:0,create:0,inspect:0,active:0,maximum:0};let now=100;
  const deps:FontDependencies={
    store:{read:async k=>{counts.read++;return shared.get(k)?.slice()??null;},create:async(k,b)=>{counts.create++;if(shared.has(k))return false;shared.set(k,b.slice());return true;}},
    bundled:async()=>null,now:()=>now,
    fetch:async url=>{counts.fetch++;counts.active++;counts.maximum=Math.max(counts.maximum,counts.active);await new Promise(r=>setTimeout(r,1));counts.active--;const a=assets.find(a=>String(url).includes(a.sha256))!;return new Response(local.get(a.id)!.slice());},
    inspect:async b=>{counts.inspect++;return fontMetrics(b);}
  };
  return {deps,counts,shared,advance:()=>now+=6000,resolver:new TicketFontResolver(deps)};
}
Deno.test('20 concurrent selections deduplicate, 100 renders stay warm, restart reads persistent bytes',async()=>{
  const s=setup();const fonts=await Promise.all(Array.from({length:20},()=>s.resolver.resolve(assets[0].id)));
  assertEquals([s.counts.fetch,s.counts.create,s.counts.inspect],[1,1,1]);
  const t=preset('named');t.fontId=assets[0].id;
  const resource=fonts[0];
  const render=await prepareTicketRenderer({id:7,features:[{code:'ticket',ticket_type:'named',layout:{schemaVersion:2,templates:{named:t}}}]},{},{},{
    load:async()=>({fonts:{[resource.id]:resource},font:resource.bytes,metrics:resource.metrics}),products:async()=>({})
  });
  for(let i=0;i<100;i++){await s.resolver.resolve(resource.id);await render({ticket_symbol:'12341A2C3E'});}
  assertEquals(s.counts.fetch,1);
  const cold=setup(s.shared);assertEquals(await digest((await cold.resolver.resolve(resource.id)).bytes),await digest(resource.bytes));assertEquals([cold.counts.fetch,cold.counts.read],[0,1]);
  fonts[0].bytes.fill(0);assertEquals(await digest((await s.resolver.resolve(resource.id)).bytes),assets[0].sha256);
});
Deno.test('isolate create conflict verifies the winner, LRU evicts, failures retry after bounded backoff',async()=>{
  const store=new Map<string,Uint8Array>();const a=setup(store),b=setup(store);
  const result=await Promise.all([a.resolver.resolve(assets[0].id),b.resolver.resolve(assets[0].id)]);
  assertEquals(await digest(result[0].bytes),await digest(result[1].bytes));assertEquals(store.size,1);
  const s=setup();const resolver=new TicketFontResolver(s.deps,{count:1,bytes:24000000,parallel:1,timeout:8000,cap:8388608});
  await Promise.all(assets.map(a=>resolver.resolve(a.id)));assertEquals(s.counts.maximum,1);
  const before=s.counts.read;await resolver.resolve(assets[0].id);assertEquals(s.counts.read,before+1);assertEquals(s.counts.fetch,3);
  const failed=setup();failed.deps.fetch=async()=>{failed.counts.fetch++;throw Error('offline');};
  await assertRejects(()=>failed.resolver.resolve(assets[0].id),TicketFontError,'font_provider');
  await assertRejects(()=>failed.resolver.resolve(assets[0].id),TicketFontError,'font_retry_backoff');assertEquals(failed.counts.fetch,1);
  failed.advance();await assertRejects(()=>failed.resolver.resolve(assets[0].id));assertEquals(failed.counts.fetch,2);
});
Deno.test('unknown IDs, storage errors/corruption, provider failures, hash mismatch, empty/HTML/oversize are visible',async()=>{
  await assertRejects(()=>setup().resolver.resolve('https://evil.invalid/font.ttf'),TicketFontError,'font_unknown');
  for(const status of [403,500]){
    const s=setup();s.deps.store.read=async()=>{throw new TicketFontError(`storage_${status}`);};
    await assertRejects(()=>s.resolver.resolve(assets[0].id));assertEquals(s.counts.fetch,0);
  }
  const corrupt=setup();corrupt.shared.set(`sha256/${assets[0].sha256}.ttf`,new Uint8Array(20));await assertRejects(()=>corrupt.resolver.resolve(assets[0].id));assertEquals(corrupt.counts.fetch,0);
  for(const response of [()=>new Response('',{status:404}),()=>new Response('',{status:302}),()=>new Response('<html>error</html>'),()=>new Response(new Uint8Array()),()=>new Response(new Uint8Array(9*1024*1024)),()=>new Response(local.get(assets[1].id)!.slice().buffer)]) {
    const s=setup();s.deps.fetch=async()=>response();await assertRejects(()=>s.resolver.resolve(assets[0].id));assertEquals(s.counts.create,0);
  }
  const s=setup();s.deps.inspect=async()=>{throw new TicketFontError('font_unsupported');};await assertRejects(()=>s.resolver.resolve(assets[0].id));assertEquals(s.counts.create,0);
});
Deno.test('timeout aborts provider, redirects disabled, corrupt parse fails even with valid digest',async()=>{
  const s=setup();s.deps.fetch=(_url,options)=>new Promise((_r,reject)=>{
    assertEquals(options?.redirect,'error');options?.signal?.addEventListener('abort',()=>reject(Error('aborted')));
  });
  const resolver=new TicketFontResolver(s.deps,{count:32,bytes:24000000,parallel:4,timeout:5,cap:8388608});
  await assertRejects(()=>resolver.resolve(assets[0].id),TicketFontError,'font_timeout');
  const bytes=Uint8Array.from([0,1,0,0,1,2,3]);const hash=await digest(bytes);const id=`gf:${hash}`;
  const bad=setup();delete bad.deps.inspect;bad.deps.lookup=async()=>({...assets[0],id,sha256:hash,byteLength:bytes.length});bad.deps.fetch=async()=>new Response(bytes);
  await assertRejects(()=>bad.resolver.resolve(id),TicketFontError,'font_unsupported');
});
Deno.test('bundled legacy defaults preserve exact identities, aliases never fetch arbitrary URL',async()=>{
 const s=setup();delete s.deps.inspect;s.deps.bundled=async a=>a.file?await Deno.readFile(new URL(`./ticket-assets/${a.file}`,import.meta.url)):null;
 for(const id of [futuraId,legacyWideId,legacyNamedId]){const font=await s.resolver.resolve(id);assertEquals(await digest(font.bytes),id.split(':').at(-1));}
 assertEquals([s.counts.fetch,s.counts.read],[0,0]);
 assertEquals(legacyNamedFontId(''),legacyNamedId);assertEquals(legacyNamedFontId('https://fonts.cdnfonts.com/s/12165/Roboto-Regular.woff'),legacyNamedId);
 assertThrows(()=>legacyNamedFontId('http://127.0.0.1/font'),TicketFontError,'legacy_font_alias_unknown');
});
Deno.test('three real families and mixed template embed exact resolved files; metrics and baseline are document independent',async()=>{
  const s=setup();delete s.deps.inspect;
  const fonts=Object.fromEntries(await Promise.all(assets.map(async a=>[a.id,await s.resolver.resolve(a.id)])));
  const t=preset('named');t.fontId=assets[0].id;
  t.elements.find(e=>e.binding==='occasionTitle')!.style.fontId=assets[1].id;
  t.elements.find(e=>e.binding==='orderName')!.style.fontId=assets[2].id;
  parseLayout({schemaVersion:2,templates:{named:t}});
  const data={...sampleData(),occasionTitle:'Příliš žluťoučký kůň',orderName:'Ľščťžýáíé, 0123456789 Kč €'};
  const r={fonts,font:fonts[assets[0].id].bytes,metrics:fonts[assets[0].id].metrics};
  const output=await generateTicketPdf(data,r,t,'named');const doc=await PDFDocument.load(output.bytes);
  const embedded=doc.context.enumerateIndirectObjects().filter(([,o])=>o instanceof PDFDict).map(([,o])=>o as PDFDict).filter(o=>o.has(PDFName.of('FontFile2'))||o.has(PDFName.of('FontFile3'))).map(o=>doc.context.lookup(o.get(PDFName.of('FontFile2'))??o.get(PDFName.of('FontFile3'))) as PDFRawStream);
  const hashes=await Promise.all(embedded.map(o=>digest(o.dict.get(PDFName.of('Filter'))?.toString()==='/FlateDecode'?inflateSync(o.getContents()):o.getContents())));
  assertEquals(new Set(hashes),new Set(assets.map(a=>a.sha256)));
  const ops=doc.context.enumerateIndirectObjects().filter(([,o])=>o instanceof PDFRawStream).map(([,o])=>o as PDFRawStream).filter(o=>!o.dict.get(PDFName.of('Length1'))&&o.dict.get(PDFName.of('Filter'))?.toString()==='/FlateDecode').map(o=>new TextDecoder().decode(inflateSync(o.getContents()))).join('\n');
  for(const e of t.elements.filter(e=>['occasionTitle','orderName'].includes(e.binding))) {
    const m=fonts[e.style.fontId!].metrics;const fit=fitText(data[e.binding]!,e,m);assert(!fit.replaced);
    assert(fit.widths.every(w=>w<=e.box.width));const y=t.page.height-t.ticketArea.y-e.box.y-m.ascent*fit.size;
    assert(ops.includes(`${y} Tm`),'PDF baseline uses the preview metrics');
    assertEquals(pdfBox(t,e.box).height,e.box.height);
  }
  assertEquals(s.counts.fetch,3);
});

Deno.test('default global concurrency is four and byte-budget eviction uses persistent cache',async()=>{
 const s=setup();let active=0,maximum=0;
 const data=new Map<string,Uint8Array>(),metadata=new Map<string,FontAsset>();
 for(let i=0;i<16;i++){const bytes=Uint8Array.from([0,1,0,0,i]);const hash=await digest(bytes);const id=`gf:${hash}`;data.set(hash,bytes);metadata.set(id,{...assets[0],id,sha256:hash,byteLength:bytes.length});}
 s.deps.lookup=async id=>metadata.get(id)??null;
 s.deps.inspect=async()=>({advances:{'?':1},ascent:1,descent:0});
 s.deps.fetch=async url=>{active++;maximum=Math.max(maximum,active);await new Promise(r=>setTimeout(r,2));active--;return new Response(data.get(String(url).split('/').at(-1)!.split('.')[0])!.slice().buffer);};
 const resolver=new TicketFontResolver(s.deps);await Promise.all([...metadata.keys()].map(id=>resolver.resolve(id)));assertEquals(maximum,4);
 const bounded=new TicketFontResolver(s.deps,{count:32,bytes:70,parallel:4,timeout:8000,cap:8388608});
 const ids=[...metadata.keys()];await bounded.resolve(ids[0]);await bounded.resolve(ids[1]);const reads=s.counts.read;await bounded.resolve(ids[0]);assertEquals(s.counts.read,reads+1);
});
Deno.test('persistent writes are awaited; write errors and corrupt race winners fail closed',async()=>{
 const s=setup();let release!:()=>void;const gate=new Promise<void>(r=>release=r);let done=false;
 s.deps.store.create=async()=>{await gate;return true;};const pending=s.resolver.resolve(assets[0].id).then(()=>done=true);
 await new Promise(r=>setTimeout(r,5));assertEquals(done,false);release();await pending;assertEquals(done,true);
 const failed=setup();failed.deps.store.create=async()=>{throw new TicketFontError('font_storage_write');};await assertRejects(()=>failed.resolver.resolve(assets[0].id),TicketFontError,'font_storage_write');
 const conflict=setup();let reads=0;conflict.deps.store.read=async()=>++reads===1?null:new Uint8Array(12);conflict.deps.store.create=async()=>false;
 await assertRejects(()=>conflict.resolver.resolve(assets[0].id),TicketFontError,'font_integrity');
});
Deno.test('new variable fonts cannot bypass the historical bundled exception',async()=>{
 const bytes=await Deno.readFile('test/fixtures/ticket_fonts/Roboto-Slab-variable.ttf');const hash=await digest(bytes);const id=`gf:${hash}`;
 const s=setup();delete s.deps.inspect;s.deps.lookup=async()=>({...assets[1],id,sha256:hash,byteLength:bytes.length});s.deps.fetch=async()=>new Response(bytes.slice().buffer);
 await assertRejects(()=>s.resolver.resolve(id),TicketFontError,'font_unsupported');assertEquals(s.counts.create,0);
});
