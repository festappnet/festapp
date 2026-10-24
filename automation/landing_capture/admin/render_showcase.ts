// Offline production renderer. Run Deno --cached-only --allow-read --allow-write.
import {ticketGallery,galleryBackgrounds,galleryBackground} from '../../../supabase/functions/_shared/ticketGallery.ts';
import {fontCatalog,fontMetrics,type TicketFont} from '../../../supabase/functions/_shared/ticketFonts.ts';
import {generateTicketPdf} from '../../../supabase/functions/_shared/ticketGeneration.ts';
import {sampleData} from '../../../supabase/functions/_shared/ticketRenderData.ts';
const output=Deno.args[0];if(!output)throw Error('Output directory required');await Deno.mkdir(output,{recursive:true});
const gallery=ticketGallery();const manifest=[];
const keys=Deno.args.slice(1);
for(const key of keys.length ? keys : ['festival_poster','boarding_pass','cinema_strip','sports_arena','workshop_card','gallery_square']){
 const t=gallery[key];const ids=new Set([t.fontId,...t.elements.map(e=>e.style.fontId)].filter((x):x is string=>!!x));const fonts:Record<string,TicketFont>={};
 for(const id of ids){const a=fontCatalog.find(a=>a.id===id)!;const bytes=await Deno.readFile(new URL('../../../supabase/functions/_shared/ticket-assets/'+(a.file||`gallery-fonts/${a.sha256}.ttf`),import.meta.url));fonts[id]={id,bytes,metrics:fontMetrics(bytes),family:a.family,weight:a.weight};}
 const font=fonts[t.fontId!];const data=sampleData('normal',{id:6,organization:1,title:key==='festival_poster'?'Letní festival':key==='workshop_card'?'Tvůrčí dílna':'Ples pod hvězdami',start_time:'2027-02-20T18:00:00Z',end_time:'2027-02-21T01:00:00Z',data:{place_name:key==='gala_invitation'?'':'Kulturní dům'}},undefined,t);
 const bytes=await generateTicketPdf(data,{font:font.bytes,metrics:font.metrics,fonts,background:await galleryBackground(galleryBackgrounds[key]!)},t,'named',true);
 await Deno.writeFile(`${output}/${key}.pdf`,bytes.bytes);manifest.push({key,widthPt:t.page.width,heightPt:t.page.height,source:'supabase/functions/_shared/ticketGallery.ts',background:galleryBackgrounds[key]});
}
await Deno.writeTextFile(`${output}/provenance.json`,JSON.stringify(manifest,null,2));console.log(`Rendered ${manifest.length} canonical templates offline`);
