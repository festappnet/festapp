// Local synthetic evidence; never sends tickets or contacts a backend.
// deno run --frozen --lock=supabase/functions/deno.lock --allow-read --allow-write --allow-env --allow-run=sips automation/tickets/verify-preview-fidelity.ts /absolute/evidence
import {ticketGallery,galleryBackgrounds} from '../../supabase/functions/_shared/ticketGallery.ts';
import {effectiveFontId} from '../../supabase/functions/_shared/ticketLayout.ts';
import {loadLayoutResources,generateTicketPdf} from '../../supabase/functions/_shared/ticketGeneration.ts';
import {sampleData} from '../../supabase/functions/_shared/ticketRenderData.ts';
const out=Deno.args[0];if(!out?.startsWith('/'))throw Error('Absolute evidence directory required');
await Deno.mkdir(out,{recursive:true});
const occasion={id:7,organization:1,title:'Příliš žluťoučký kůň - Slavnostní večer',start_time:'2026-10-22T18:00:00Z',data:{place_name:'Kulturní dům, Žďár'}};
const products={types:new Map(),products:new Map()};
const cases=[];
for(const [key,template] of Object.entries(ticketGallery())){
 const background=galleryBackgrounds[key]??null;
 const resources=await loadLayoutResources(occasion,{ticket_type:'wide',layout:{schemaVersion:3,templates:{wide:template}},background});
 for(const scenario of key==='classic'?['normal','long','missing']:['normal']){
  const name=`${key}-${scenario}`;
  const data=sampleData(scenario,occasion,products,template);
  const pdf=await generateTicketPdf(data,resources,template,'wide',true);
  await Deno.writeFile(`${out}/${name}.pdf`,pdf.bytes);
  const result=await new Deno.Command('sips',{args:['-s','format','png',`${out}/${name}.pdf`,'--out',`${out}/${name}-pdf.png`],stdout:'null',stderr:'piped'}).output();
  if(!result.success)throw Error(new TextDecoder().decode(result.stderr));
  cases.push({name,scenario,reply:{resourceProtocol:3,template,preset:template,
   fontIds:[...new Set([effectiveFontId(template),...template.elements.filter(e=>e.visible&&!['qr','logo'].includes(e.binding)).map(e=>effectiveFontId(template,e))])],
   backgroundUrl:background,logoUrl:null,catalog:[],
   scenarios:Object.fromEntries(['normal','long','missing'].map(s=>[s,sampleData(s,occasion,products)]))}});
 }
}
await Deno.writeTextFile(`${out}/contexts.json`,JSON.stringify(cases));
console.log(`PDF and metadata evidence: ${cases.length} scenes`);
