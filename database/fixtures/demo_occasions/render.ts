// Offline evidence uses the same renderer and bundled font bytes as ticket delivery.
// deno run --allow-read --allow-write database/fixtures/demo_occasions/render.ts
import {generateTicketPdf} from '../../../supabase/functions/_shared/ticketGeneration.ts';
import {normalizeTicketData} from '../../../supabase/functions/_shared/ticketRenderData.ts';
import {validateLayout} from '../../../supabase/functions/_shared/ticketLayout.ts';
import {fontMetrics} from '../../../supabase/functions/_shared/ticketFonts.ts';

const output = new URL('../../../docs/plans/demo-occasions-evidence-2026-10-14/',import.meta.url);
await Deno.mkdir(output,{recursive:true});
const font = await Deno.readFile(new URL('../../../supabase/functions/_shared/ticket-assets/font.ttf',import.meta.url));

const report = [];
for (const [key,title,price] of [['ball','Ples pod hvězdami',450],['concert','Večer živé hudby',590]] as const) {
  const layout = JSON.parse(await Deno.readTextFile(new URL(`./${key}-layout.json`,import.meta.url)));
  validateLayout(layout);
  const template = layout.templates.wide;
  const resources = {font,metrics:fontMetrics(font),background:await Deno.readFile(new URL(`./assets/${key}-ticket-v1.jpg`,import.meta.url))};
  const catalog={types:new Map([[1,{id:1,occasion:1,title:'Vstupné',offered:true,referenced:true,example:null}]]),products:new Map([[1,{id:1,product_type:1,title:'Základní vstupné',price,currency_code:'CZK'}]])};
  for(const copy of [false,true]) {
    const data = normalizeTicketData({ticket_symbol:'DEMO-7K6M8R',occasion:1,
      price,currency_code:'CZK',order_product_ticket:[{id:1,product:1,spot_group_title:key==='ball'?'12':null}]},
      {id:1,title,start_time:key==='ball'?'2027-02-20T18:30:00Z':'2027-03-06T18:00:00Z',end_time:key==='ball'?'2027-02-21T01:00:00Z':'2027-03-06T22:00:00Z',
        data:{place_name:'Společenský sál'},demo_read_only:!copy},
      {name:'Kateřina Šťastná',surname:'Nováková-Černá'},catalog,template);
    const result = await generateTicketPdf(data,resources,template,'wide');
    if(result.warnings.length) throw new Error(`${key}: text does not fit: ${result.warnings}`);
    const file = `${key}${copy?'-copy':''}.pdf`;
    await Deno.writeFile(new URL(file,output),result.bytes);
    report.push({file,warnings:result.warnings,qr:'DEMO-7K6M8R'});
  }
}
await Deno.writeTextFile(new URL('pdf-render.json',output),JSON.stringify(report,null,2)+'\n');
console.log('Rendered 4 PDFs with the shared ticket renderer; no text warnings');
