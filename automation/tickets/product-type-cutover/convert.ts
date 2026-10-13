// One-time offline conversion. Not a dependency of any application entry point.
import {importTicketTemplate} from './legacy-import.ts';
import {validateLayout as validateLegacy,positionedElements} from './legacy-layout.ts';
import {legacyNamedFontId,legacyFontIds} from '../../../supabase/functions/_shared/ticketFonts.ts';
import {validateLayout,preset} from '../../../supabase/functions/_shared/ticketLayout.ts';
import {resolveTicketFont} from '../../../supabase/functions/_shared/ticketFontStorage.ts';
import {loadLayoutResources} from '../../../supabase/functions/_shared/ticketGeneration.ts';
export function candidates(row:any):number[] {
  return (row.product_types??[]).filter((t:any)=>t.type==='food'&&(t.form_references>0||t.ordered_count>0)).map((t:any)=>t.id);
}
export async function convert(row:any,load=loadLayoutResources) {
  const ticket=row.features.find((f:any)=>f.code==='ticket');
  if(!ticket)throw new Error('ticket_feature_missing');
  if(ticket.layout?.schemaVersion===3){validateLayout(ticket.layout);return ticket.layout;}
  if(ticket.layout)validateLegacy(ticket.layout);
  const ids=candidates(row);
  const templates:any={};
  for(const slot of ['wide','named']) {
    let template=ticket.layout?.templates?.[slot];
    if(!template&&slot!==(ticket.ticket_type==='named'?'named':'wide')) {
      // An absent, inactive slot has never printed. Use the same neutral
      // canonical preset as a new slot, without inventing a historical field.
      templates[slot]=preset(slot as 'wide'|'named');
      continue;
    }
    if(!template){const source={...row,features:row.features.map((f:any)=>f.code==='ticket'?{...f,layout:undefined,ticket_type:slot}:f)};const resources=await load(source);const fontId=slot==='named'?legacyNamedFontId(row.data?.font):ticket.background?legacyFontIds.robotoSlab:legacyFontIds.futura;const original=await resolveTicketFont(fontId);template=await importTicketTemplate(source,{...resources,font:original.bytes,metrics:original.metrics});}
    template=structuredClone(template);
    if(ids.length>1&&template.elements.some((e:any)=>e.binding==='food'))throw new Error('ambiguous_form_or_historical_product_types:'+ids.join(','));
    const removed=template.elements.filter((e:any)=>e.binding==='food'&&!ids.length);
    if(removed.length) {
      // Only the permanently absent row is materialized. Retain compaction of
      // other optional rows so historical note/spot combinations keep geometry.
      let shift=0;
      for(const binding of template.flow??[]) {
        const e=template.elements.find((e:any)=>e.binding===binding);
        if(!e)throw new Error('invalid_legacy_flow');
        if(e.binding==='food')shift+=template.flowStep??e.box.height;
        else e.box.y-=shift;
      }
      template.elements=template.elements.filter((e:any)=>e.binding!=='food');
      if(template.flow)template.flow=template.flow.filter((binding:string)=>binding!=='food');
    }
    for(const e of template.elements)if(e.binding==='food'){e.binding='productType';e.productTypeId=ids[0];e.label='Večeře';}
    if(template.flow)template.flow=template.flow.map((binding:string)=>template.elements.find((e:any)=>e.binding===binding||(binding==='food'&&e.binding==='productType'))?.id);
    template.fontId??=legacyFontIds[template.font as keyof typeof legacyFontIds]??legacyFontIds.futura;
    delete template.font;
    templates[slot]=template;
  }
  const layout={schemaVersion:3 as const,templates};validateLayout(layout);return layout;
}
