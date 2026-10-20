/** Wave-0 evidence only. No RPCs, credentials or production access.
 * deno run --allow-read --allow-write=supabase/.temp/blueprint-typography,docs/plans/evidence/blueprint-typography-20261020 --allow-net=fonts.gstatic.com --allow-run=hb-shape automation/blueprint_typography_probe.ts
 */
import * as fontkit from 'npm:fontkit@2.0.4';
import * as hb from 'npm:harfbuzzjs@1.6.3';
import {LayoutTextFace} from '../supabase/functions/_shared/layoutTextShaper.ts';
import {prepareLayoutText} from '../supabase/functions/_shared/layoutTextPreparation.ts';
import {extractFaceVariants} from './generate_ticket_font_catalog.mjs';
import {fontCatalog,TicketFontResolver,digest} from '../supabase/functions/_shared/ticketFonts.ts';

const cache=new URL('../supabase/.temp/blueprint-typography/',import.meta.url);
await Deno.mkdir(cache,{recursive:true});
const configUrl=new URL('../.dart_tool/package_config.json',import.meta.url);
const config=JSON.parse(await Deno.readTextFile(configUrl));
const pkg=config.packages.find((p:{name:string})=>p.name==='google_fonts');
const pkgRoot=new URL(pkg.rootUri.endsWith('/')?pkg.rootUri:pkg.rootUri+'/',configUrl);
const all=await Deno.readTextFile(new URL('lib/src/google_fonts_all_parts.dart',pkgRoot));
const assets=[];
for(const family of ['Roboto','Amiri','Tiro Devanagari Hindi']){
 const match=[...all.matchAll(/'([^']+)': Part([A-Z]).(\w+),/g)].find(m=>m[1]===family)!;
 const source=await Deno.readTextFile(new URL(`lib/src/google_fonts_parts/part_${match[2].toLowerCase()}.dart`,pkgRoot));
 for(const v of extractFaceVariants(source,match[3]).filter((v:{weight:number})=>[400,700].includes(v.weight))){
  assets.push({...v,id:`gf:${v.sha256}`,family,source:'google',extension:'ttf'});
 }
}
const resolver=new TicketFontResolver({
 store:{read:async key=>{try{return await Deno.readFile(new URL(key.split('/')[1],cache));}catch(e){if(e instanceof Deno.errors.NotFound)return null;throw e;}},create:async(key,bytes)=>{await Deno.writeFile(new URL(key.split('/')[1],cache),bytes);return true;}},
 fetch,bundled:async()=>null,lookup:async id=>assets.find(a=>a.id===id)??null,
});
const fixtureFaces=[];
for(const asset of assets){
 const font=await resolver.resolve(asset.id); // Includes immutable hash, format, metrics and PDF admission.
 if(await digest(font.bytes)!==asset.sha256)throw Error('Unexpected face bytes');
 const parsed=fontkit.create(font.bytes);
 const actualWeight=parsed['OS/2']?.usWeightClass,italicAngle=parsed.italicAngle,actualItalic=parsed['OS/2']?.fsSelection?.italic;
 if(actualWeight!==asset.weight||(asset.style==='italic')!==actualItalic)throw Error(`Face metadata mismatch: ${asset.family} ${asset.weight} ${asset.style}`);
 fixtureFaces.push({...asset,actualWeight,actualItalic,italicAngle,postscriptName:parsed.postscriptName,path:new URL(`${asset.sha256}.ttf`,cache).pathname});
}
const regular=(family:string)=>fixtureFaces.find(f=>f.family===family&&f.weight===400&&f.style==='normal')!;
const cases=[
 ...['AV','To','Wa','office ffi fi','Příliš žluťoučký kůň úpěl ďábelské ódy.','Ľúbim mäkký chlieb. Zażółć gęślą jaźń. Grüße Straße € ×','A\u0301 z\u030c a\u0323\u0301','jÁ Ť'].map(text=>({family:'Roboto',text,script:'latn',language:'und',direction:'ltr',features:''})),
 {family:'Roboto',text:'office ffi fi AV',script:'latn',language:'und',direction:'ltr',features:'liga=0,kern=0'},
 {family:'Amiri',text:'السَّلَامُ عَلَيْكُمْ',script:'arab',language:'ar',direction:'rtl',features:''},
 {family:'Amiri',text:'سلام',script:'arab',language:'ar',direction:'rtl',features:''},
 {family:'Tiro Devanagari Hindi',text:'नमस्ते हिन्दी क्षि',script:'deva',language:'hi',direction:'ltr',features:''},
];
const oracleVersion=new TextDecoder().decode((await new Deno.Command('hb-shape',{args:['--version']}).output()).stdout).trim();
if(!oracleVersion.startsWith('hb-shape (HarfBuzz) 14.4.0'))throw Error(`Oracle version changed: ${oracleVersion}`);
const results=[];
for(const c of cases){
 const face=regular(c.family),bytes=await Deno.readFile(face.path);
 const flags=[face.path,c.text,'--output-format=json','--no-glyph-names','--utf8-clusters','--cluster-level=0',`--direction=${c.direction}`,`--script=${c.script}`,`--language=${c.language}`];
 if(c.features)flags.push(`--features=${c.features}`);
 const oracleReply=await new Deno.Command('hb-shape',{args:flags}).output();
 if(!oracleReply.success)throw Error(new TextDecoder().decode(oracleReply.stderr));
 const oracle=JSON.parse(new TextDecoder().decode(oracleReply.stdout));
 const font=new hb.Font(new hb.Face(new hb.Blob(bytes.buffer)));
 const buffer=new hb.Buffer();buffer.addText(c.text);buffer.setDirection(c.direction==='rtl'?hb.Direction.RTL:hb.Direction.LTR);buffer.setScript(c.script);buffer.setLanguage(c.language);buffer.setClusterLevel(hb.ClusterLevel.MONOTONE_GRAPHEMES);
 hb.shape(font,buffer,c.features?c.features.split(',').map(x=>hb.Feature.fromString(x)!):undefined);
 const infos=buffer.getGlyphInfos(),positions=buffer.getGlyphPositions();
 const utf8=new Map<number,number>();let u16=0,u8=0;for(const cp of c.text){utf8.set(u16,u8);u16+=cp.length;u8+=new TextEncoder().encode(cp).length;}utf8.set(u16,u8);
 const shaped=infos.map((g,i)=>({g:g.codepoint,cl:utf8.get(g.cluster),dx:positions[i].xOffset,dy:positions[i].yOffset,ax:positions[i].xAdvance,ay:positions[i].yAdvance}));
 const canonicalFace=await LayoutTextFace.fromTicketFont(await resolver.resolve(face.id));
 const canonical=c.features?undefined:canonicalFace.shape(c.text,{direction:c.direction as 'ltr'|'rtl',script:c.script,language:c.language}).map(g=>({g:g.glyphId,cl:g.cluster,dx:g.xOffset,dy:g.yOffset,ax:g.xAdvance,ay:g.yAdvance}));
 if(canonical&&JSON.stringify(canonical)!==JSON.stringify(oracle))throw Error('Canonical shaper differs from oracle');
 const fk=fontkit.create(bytes);const features=Object.fromEntries(c.features.split(',').filter(Boolean).map(v=>{const [k,x]=v.split('=');return [k,x!=='0'];}));
 const run=fk.layout(c.text,features,c.script,c.language,c.direction);
 const fkGlyphs=run.glyphs.map((g:{id:number},i:number)=>({g:g.id,dx:run.positions[i].xOffset,dy:run.positions[i].yOffset,ax:run.positions[i].xAdvance,ay:run.positions[i].yAdvance}));
 const numeric=(glyphs:typeof shaped)=>glyphs.map(({g,dx,dy,ax,ay})=>({g,dx,dy,ax,ay}));
 results.push({...c,fontId:face.id,oracle,harfbuzz:shaped,fontkit:fkGlyphs,harfbuzzEqual:JSON.stringify(shaped)===JSON.stringify(oracle),fontkitEqual:JSON.stringify(fkGlyphs)===JSON.stringify(numeric(oracle))});
}
const preparation=[];
for(const c of [
 {family:'Roboto',text:'Příliš žluťoučký kůň. AV office ffi fi.',width:130,direction:'auto',language:'cs'},
 {family:'Amiri',text:'مرحبا Latin 123 (سلام) العربية',width:130,direction:'auto',language:'ar'},
 {family:'Amiri',text:'Latin 123 سلام 456 Arabic',width:100,direction:'ltr',language:'und'},
 {family:'Tiro Devanagari Hindi',text:'नमस्ते हिन्दी क्षि नमस्ते हिन्दी',width:100,direction:'auto',language:'hi'},
]){
 const asset=regular(c.family),face=await LayoutTextFace.fromTicketFont(await resolver.resolve(asset.id));
 const result=await prepareLayoutText(face,{text:c.text,role:'text',fontFamilyId:'probe:'+c.family,fontFaceId:asset.id,size:24,language:c.language,direction:c.direction as 'auto'|'ltr',lineHeight:1.2,align:'left',box:{x:0,y:0,width:c.width,height:400},fit:'wrap'});
 const utf8=new TextEncoder().encode(c.text);let runCount=0;
 for(const line of result.lines){
  const grouped=Map.groupBy(line.glyphs,g=>`${g.runStart}:${g.runEnd}:${g.direction}:${g.script}`);
  for(const glyphs of grouped.values()){
   const g=glyphs[0],text=new TextDecoder().decode(utf8.slice(g.runStart as number,g.runEnd as number));
   const args=[asset.path,text,'--output-format=json','--no-glyph-names','--utf8-clusters','--cluster-level=0',`--direction=${g.direction}`,`--script=${g.script}`,`--language=${c.language}`];
   const reply=await new Deno.Command('hb-shape',{args}).output();if(!reply.success)throw Error(new TextDecoder().decode(reply.stderr));
   const oracle=JSON.parse(new TextDecoder().decode(reply.stdout));
   const actual=glyphs.map(g=>({g:g.glyphId,cl:(g.cluster as number)-(g.runStart as number),dx:g.xOffset,dy:g.yOffset,ax:g.xAdvance,ay:g.yAdvance}));
   if(JSON.stringify(actual)!==JSON.stringify(oracle))throw Error('Final line oracle mismatch: '+text);
   runCount++;
  }
 }
 preparation.push({family:c.family,text:c.text,fontId:asset.id,lines:result.lines.length,oracleRuns:runCount,oracleEqual:true,result});
}
// Batch CPU preparation only, with font parse included in cold measurements.
const bytes=await Deno.readFile(regular('Roboto').path),warmFont=new hb.Font(new hb.Face(new hb.Blob(bytes.buffer)));
const sample=cases.slice(0,8).map(c=>c.text);const latency:Record<string,number[]>={cold:[],warm:[]};
for(const mode of ['cold','warm'])for(let i=0;i<60;i++){
 const start=performance.now();const font=mode==='cold'?new hb.Font(new hb.Face(new hb.Blob(bytes.slice().buffer))):warmFont;
 for(const text of sample){const b=new hb.Buffer();b.addText(text);b.guessSegmentProperties();hb.shape(font,b);for(const g of b.getGlyphInfos())font.glyphToJson(g.codepoint);}
 latency[mode].push(performance.now()-start);
}
const report={scope:'local Deno only; Edge, network and full layout latency measured separately',oracleVersion,harfbuzzjs:'1.6.3',harfbuzz:hb.versionString(),fontkit:'2.0.4',fixtureFaces,results,preparation,latency:Object.fromEntries(Object.entries(latency).map(([k,v])=>{v.sort((a,b)=>a-b);return [k,{batchLabels:sample.length,samples:v.length,p50ms:v[29],p95ms:v[56]}];}))};
await Deno.writeTextFile(new URL('../docs/plans/evidence/blueprint-typography-20261020/engine-probe.json',import.meta.url),JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify({faces:fixtureFaces.length,cases:results.length,fontkitFailures:results.filter(r=>!r.fontkitEqual).map(r=>r.text),harfbuzzFailures:results.filter(r=>!r.harfbuzzEqual).map(r=>r.text),latency:report.latency}));
if(results.some(r=>!r.harfbuzzEqual))Deno.exit(1);
