/** Build a reviewed, tenant-scoped, forward-only SQL plan. No database writes.
 * Input rows: id, organization, features, data (font only), features_hash.
 * Execute the resulting SQL through the approved Access SQL workflow after review.
 */
import {loadLayoutResources,resolveTicketTemplate} from '../../supabase/functions/_shared/ticketGeneration.ts';
const [input,output,organizationValue]=Deno.args;
const organization=Number(organizationValue);
if(!input||!output||!Number.isSafeInteger(organization)||organization<1)throw new Error('usage: import-layouts.ts inventory.json plan.sql organization');
const rows=JSON.parse(await Deno.readTextFile(input));
const quote=(v:unknown)=>"'"+JSON.stringify(v).replaceAll("'","''")+"'::jsonb";
const plans:string[]=[],blocked:{id:number,error:string}[]=[];
for(const row of rows){
 if(row.organization!==organization||!Number.isSafeInteger(row.id)||!/^[0-9a-f]{32}$/.test(row.features_hash))throw new Error('Invalid inventory identity');
 const feature=row.features?.find((f:any)=>f.code==='ticket');
 if(!feature||feature.layout||(!feature.background&&feature.ticket_type!=='named'))continue;
 try{
  const resources=await loadLayoutResources(row);
  const type=feature.ticket_type==='named'?'named':'wide';
  const template=await resolveTicketTemplate(row,resources);
  const layout={schemaVersion:1,templates:{[type]:template}};
  plans.push(`
DO $import$ BEGIN
  PERFORM public.validate_ticket_layout(${quote(layout)});
  UPDATE public.occasions o SET features=(SELECT jsonb_agg(CASE WHEN f->>'code'='ticket' THEN f||jsonb_build_object('layout',${quote(layout)}) ELSE f END ORDER BY ord) FROM jsonb_array_elements(o.features) WITH ORDINALITY AS items(f,ord))
  WHERE o.id=${row.id} AND o.organization=${organization}
    AND md5(o.features::text)='${row.features_hash}'
    AND COALESCE(o.data->'font','null'::jsonb)=${quote(row.data?.font??null)};
  IF NOT FOUND AND NOT EXISTS(SELECT 1 FROM public.occasions o CROSS JOIN LATERAL jsonb_array_elements(o.features) f WHERE o.id=${row.id} AND o.organization=${organization} AND f->>'code'='ticket' AND f->'layout'=${quote(layout)}) THEN
    RAISE EXCEPTION 'Ticket import conflict for occasion ${row.id}';
  END IF;
END $import$;`);
 }catch(error){blocked.push({id:row.id,error:String(error)});}
}
await Deno.writeTextFile(output,'BEGIN;\n'+plans.join('\n')+'\nCOMMIT;\n');
await Deno.writeTextFile(output+'.blocked.json',JSON.stringify(blocked,null,2)+'\n');
console.log(JSON.stringify({organization,planned:plans.length,blocked}));
