/** Offline distribution fixtures. All shaping goes through the production owner.
 * Input requests are exported by the package's core/template API. */
import {fontCatalog,fontFamilyCatalog,fontMetrics} from '../supabase/functions/_shared/ticketFonts.ts';
import {prepareLayoutTextResources} from '../supabase/functions/_shared/layoutTextResources.ts';
const [requestPath,outputDirectory]=Deno.args;
if(!requestPath||!outputDirectory)throw new Error('Expected REQUESTS_JSON OUTPUT_DIRECTORY');
const requests=JSON.parse(await Deno.readTextFile(requestPath));
const family=fontFamilyCatalog.find(f=>f.family==='Roboto')!;
const resolve=async(id:string)=>{
 const asset=fontCatalog.find(a=>a.id===id)!;
 const bytes=await Deno.readFile(asset.source==='bundled'?new URL(`../supabase/functions/_shared/ticket-assets/${asset.file}`,import.meta.url):new URL(`../supabase/.temp/blueprint-typography/${asset.sha256}.ttf`,import.meta.url));
 return {...asset,bytes,metrics:fontMetrics(bytes)};
};
const numericFaces=[...new Map([{fontFamilyId:family.id,fontFaceId:family.faces['400:normal']},...requests.map((r:Record<string,unknown>)=>({fontFamilyId:r.fontFamilyId,fontFaceId:r.fontFaceId}))].map(r=>[r.fontFaceId,r])).values()];
const result={protocol:2,fontFamilies:{},textLayouts:{},numberSymbols:{}};
for(let i=0;i<requests.length;i+=32){
 const batch=await prepareLayoutTextResources({requests:requests.slice(i,i+32),numericFaces:i===0?numericFaces:[]},resolve);
 Object.assign(result.fontFamilies,batch.fontFamilies);Object.assign(result.textLayouts,batch.textLayouts);Object.assign(result.numberSymbols,batch.numberSymbols);
}
await Deno.writeTextFile(`${outputDirectory}/fixtures.json`,JSON.stringify(result)+'\n');
const fixtures=[];
for(const [variant,id] of Object.entries(family.faces)){
 const asset=await resolve(id),file=`Roboto-${variant.replace(':','-')}.ttf`;
 await Deno.writeFile(`${outputDirectory}/${file}`,asset.bytes);
 fixtures.push({id,file,sha256:asset.sha256,license:'Roboto-OFL.txt',family:family.family,variant});
}
await Deno.writeTextFile(`${outputDirectory}/manifest.json`,JSON.stringify({protocol:2,fontFamilies:result.fontFamilies,fixtures},null,2)+'\n');
console.log(`Prepared ${requests.length} template paragraphs with the canonical engine`);
