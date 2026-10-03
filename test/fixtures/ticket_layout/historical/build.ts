// Regenerate local reference layouts with the production geometry contract.
// Run: deno run --allow-read --allow-write test/fixtures/ticket_layout/historical/build.ts
import { preset, portraitPreset, validateLayout } from '../../../../supabase/functions/_shared/ticketLayout.ts';
const url = new URL('./catalog.json', import.meta.url);
const catalog = JSON.parse(await Deno.readTextFile(url)).filter((item:any)=>item.id!=='portrait');
for (const item of catalog) {
  const template = preset('wide', item.width, item.height);
  for (const element of template.elements) {
    if (element.binding !== 'qr') element.style.color = item.textColor;
  }
  validateLayout({ schemaVersion: 1, templates: { wide: template } });
  item.template = template;
}
catalog.push({id:'portrait',label:'Jmenná na výšku',image:null,width:200,height:375,template:portraitPreset()});
await Deno.writeTextFile(url, JSON.stringify(catalog, null, 2) + '\n');
