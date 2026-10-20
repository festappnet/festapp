import {assertEquals,assert,assertRejects} from 'jsr:@std/assert@1';
import {prepareLayoutText,canonicalLayoutResourceJson,type LayoutTextRequest} from './layoutTextPreparation.ts';
import {LayoutTextFace} from './layoutTextShaper.ts';
import {fontCatalog,fontMetrics,TicketFontError} from './ticketFonts.ts';
async function face(){const a=fontCatalog.find(a=>a.file==='font.ttf')!,bytes=await Deno.readFile(new URL('./ticket-assets/font.ttf',import.meta.url));return LayoutTextFace.fromTicketFont({...a,bytes,metrics:fontMetrics(bytes)});}
function request(text:string,patch:Partial<LayoutTextRequest>={}):LayoutTextRequest{return {text,role:'text',fontFamilyId:'test:registered-futura',fontFaceId:fontCatalog.find(a=>a.file==='font.ttf')!.id,size:24,language:'und',direction:'auto',lineHeight:1.2,align:'left',box:{x:-200,y:-100,width:400,height:200},fit:'wrap',...patch};}
Deno.test('whole text preparation is immutable, deterministic and preserves original source and clusters',async()=>{
 const f=await face(),r=request('Příliš žluťoučký kůň.');
 const pending=prepareLayoutText(f,r);r.text='later draft';r.box.width=1000;
 const prepared=await pending;
 assertEquals(prepared.descriptor.request.text,'Příliš žluťoučký kůň.');
 assertEquals(prepared.descriptor.request.box.width,400);
 assertEquals(await prepareLayoutText(f,request('Příliš žluťoučký kůň.')),prepared);
 assert(prepared.path.length>0);assertEquals(prepared.lines.length,1);
 assertEquals(prepared.lines[0].start,0);assertEquals(prepared.lines[0].end,new TextEncoder().encode('Příliš žluťoučký kůň.').length);
});
Deno.test('final wrapped lines reshape in context and long tokens clip without changing original text',async()=>{
 const f=await face(),text='AV AV AV AV AV';
 const prepared=await prepareLayoutText(f,request(text,{box:{x:0,y:0,width:70,height:200}}));
 assert(prepared.lines.length>1);
 assertEquals(prepared.lines.at(-1)!.end,text.length);
 for(let i=1;i<prepared.lines.length;i++)assertEquals(prepared.lines[i-1].end,prepared.lines[i].start);
 const long=await prepareLayoutText(f,request('AV'.repeat(100),{box:{x:0,y:0,width:20,height:30}}));
 assertEquals(long.lines.length,1);assert(long.advanceBounds.width>20);assertEquals(long.clip.width,20);assertEquals(long.fitScale,1);
});
Deno.test('table label shrink preserves physical box, full source and contains vector ink',async()=>{
 const f=await face(),r=request('Velmi dlouhý název stolu',{role:'label',fit:'shrink',align:'center',box:{x:-20,y:-10,width:40,height:20}}),prepared=await prepareLayoutText(f,r);
 assert(prepared.fitScale<1);assertEquals(prepared.descriptor.request,r);assertEquals(prepared.clip,r.box);
 assert(prepared.advanceBounds.width<=40.000001);assert(prepared.advanceBounds.height<=20.000001);
 for(const command of prepared.path)for(let i=1;i<command.length;i+=2){assert((command[i] as number)>=-20.001&&(command[i] as number)<=20.001);assert((command[i+1] as number)>=-10.001&&(command[i+1] as number)<=10.001);}
});
Deno.test('CRLF, trailing newline, NBSP and empty lines retain original byte mappings',async()=>{
 const f=await face(),r=request('Židle\r\n\r\nStůl\n'),prepared=await prepareLayoutText(f,r);
 assertEquals(prepared.descriptor.request.text,r.text);assertEquals(prepared.lines.length,4);
 assertEquals(prepared.lines.map(l=>[l.start,l.end]),[[0,6],[8,8],[10,15],[16,16]]);
 const nbsp=await prepareLayoutText(f,request('A\u00a0V',{box:{x:0,y:0,width:1,height:20}}));assertEquals(nbsp.lines.length,1);
 const empty=await prepareLayoutText(f,request(''));assertEquals(empty.path,[]);assertEquals(empty.lines.length,1);
});
Deno.test('closed request rejects foreign face, world state, invalid dimensions and missing glyphs',async()=>{
 const f=await face();
 for(const r of [request('AV',{fontFaceId:'foreign'}),request('AV',{box:{x:0,y:0,width:0,height:20}}),{...request('AV'),camera:{x:1}}])await assertRejects(()=>prepareLayoutText(f,r as LayoutTextRequest),TicketFontError,'layout_text_request');
 await assertRejects(()=>prepareLayoutText(f,request('😀')),TicketFontError,'layout_glyph_unavailable');
 assertEquals(canonicalLayoutResourceJson({b:2,a:{d:4,c:3}}),'{"a":{"c":3,"d":4},"b":2}');
});
Deno.test('resource codec has identical Dart and Deno numeric canonical form and hashes',async()=>{
 const fixtures=JSON.parse(await Deno.readTextFile(new URL('./testdata/layout-resource-codec.json',import.meta.url)));
 for(const fixture of fixtures){const encoded=canonicalLayoutResourceJson(fixture.value);assertEquals(encoded,fixture.canonical);const hash=new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(encoded)));assertEquals([...hash].map(x=>x.toString(16).padStart(2,'0')).join(''),fixture.sha256);}
});
