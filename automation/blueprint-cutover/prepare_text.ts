import {prepareLayoutTextResources} from '../../supabase/functions/_shared/layoutTextResources.ts';
import {TicketFontResolver} from '../../supabase/functions/_shared/ticketFonts.ts';
const directory=Deno.args[0];
if(!directory)throw Error('Explicit protected input directory required');
const root=new URL('../../',import.meta.url);
const resolver=new TicketFontResolver({
 store:{read:async()=>null,create:async()=>{throw Error('Migration never creates font assets');}},
 fetch:async()=>{throw Error('Network font fallback forbidden');},
 bundled:async asset=>{if(!asset.file)throw Error('Only registered bundled faces accepted');return Deno.readFile(new URL('supabase/functions/_shared/ticket-assets/'+asset.file,root));},
});
const proposals=JSON.parse(await Deno.readTextFile(directory+'/proposals.json'));
let total=0;
for(const p of proposals){
 const prepared:any={protocol:2,fontFamilies:{},textLayouts:{},numberSymbols:{}};
 const requests=[...new Map(p.requests.map((r:any)=>[JSON.stringify(r),r])).values()];
 const batches=Math.max(1,Math.ceil(requests.length/32));
 for(let i=0;i<batches;i++){
  const next=await prepareLayoutTextResources({requests:requests.slice(i*32,(i+1)*32),numericFaces:i===0?p.numericFaces:[]},id=>resolver.resolve(id));
  for(const key of ['fontFamilies','textLayouts','numberSymbols'])Object.assign(prepared[key],(next as any)[key]);
 }
 p.prepared=prepared;total+=Object.keys(prepared.textLayouts).length;delete p.requests;delete p.numericFaces;
}
await Deno.writeTextFile(directory+'/prepared-proposals.json',JSON.stringify(proposals));
console.log(`Prepared exact bundled-font glyphs for ${proposals.length} plans (${total} text resources).`);
