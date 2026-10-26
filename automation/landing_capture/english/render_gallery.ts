/** Gallery stills use the same preset, data and PDF renderer as the real editor. */
import {ticketGallery,galleryBackgrounds} from '../../../supabase/functions/_shared/ticketGallery.ts';
import {sampleData} from '../../../supabase/functions/_shared/ticketRenderData.ts';
import {loadLayoutResources,generateTicketPdf} from '../../../supabase/functions/_shared/ticketGeneration.ts';
const out=Deno.args[0];if(!out)throw Error('Output directory required');await Deno.mkdir(out,{recursive:true});
const occasion={id:20,organization:900001,locale:'en',title:'Evening under the stars',start_time:'2026-11-22T18:00:00Z',end_time:'2026-11-22T23:00:00Z',data:{place_name:'Starlight Hall',timezone:'Europe/Prague'}};
for(const key of ['ball_silk','concert_stub','theatre_program','boarding_pass','cinema_strip','gallery_square','sports_arena','workshop_card']){
const t=ticketGallery()[key];const feature={code:'ticket',ticket_type:'wide',background:galleryBackgrounds[key],layout:{schemaVersion:3,templates:{wide:t}}};const r=await loadLayoutResources({...occasion,features:[feature]});const pdf=await generateTicketPdf(sampleData('normal',occasion,undefined,t),r,t,'wide',true);await Deno.writeFile(`${out}/${key}.pdf`,pdf.bytes);
}console.log('Rendered eight English presets through canonical ticket renderer');
