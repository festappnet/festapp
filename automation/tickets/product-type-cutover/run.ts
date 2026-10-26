import {convert,candidates} from './convert.ts';
const [mode,input,output,orgString]=Deno.args;
const org=Number(orgString);
if(!['inventory','dry-run','apply','verify'].includes(mode)||!input||!output||!Number.isSafeInteger(org)||org<1)throw new Error('run.ts inventory|dry-run|apply|verify input.json output organization');
const rows=JSON.parse(await Deno.readTextFile(input));
if(!Array.isArray(rows)||rows.some(r=>r.organization!==org||!Number.isSafeInteger(r.id)||!/^[a-f0-9]{32}$/.test(r.features_hash)))throw new Error('Invalid scoped inventory');
if(mode==='inventory'){await Deno.writeTextFile(output,JSON.stringify(rows.map(r=>({id:r.id,candidates:candidates(r),schema:r.features.find((f:any)=>f.code==='ticket')?.layout?.schemaVersion??null})),null,2));}
if(mode==='dry-run') {
 const manifest:any[]=[],unresolved:any[]=[];
 for(const row of rows)try{manifest.push({...row,layout:await convert(row)});}catch(error){unresolved.push({id:row.id,error:String(error)});}
 await Deno.writeTextFile(output,JSON.stringify(manifest,null,2));await Deno.writeTextFile(output+'.unresolved.json',JSON.stringify(unresolved,null,2));
 if(unresolved.length)throw new Error('Unresolved rows: '+unresolved.length);
}
if(mode==='apply') {
 const quote=(v:unknown)=>"'"+JSON.stringify(v).replaceAll("'","''")+"'::jsonb";
 const sql=await Deno.readTextFile(new URL('./apply.sql',import.meta.url));
 const definitions=(await Deno.readTextFile(new URL('../../../supabase/migrations/20261013160000_ticket_product_type_cutover.sql',import.meta.url))).replace(/^BEGIN;$/m,'').replace(/^COMMIT;$/m,'');
 await Deno.writeTextFile(output,`BEGIN;\n${definitions}\n${sql}\nSELECT public.apply_ticket_product_cutover_20261013(${org},${quote(rows)});\nDROP FUNCTION public.apply_ticket_product_cutover_20261013(bigint,jsonb);\nINSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20261013160000','ticket_product_type_cutover',ARRAY[${"'"+definitions.replaceAll("'","''")+"'"}]) ON CONFLICT(version) DO NOTHING;\nCOMMIT;\n`);
}
if(mode==='verify') {
 const canonical=(v:any):string=>JSON.stringify(v,(_,value)=>value&&typeof value==='object'&&!Array.isArray(value)?Object.fromEntries(Object.entries(value).sort(([a],[b])=>a.localeCompare(b))):value);
 const manifest=JSON.parse(await Deno.readTextFile(output));
 if(manifest.length!==rows.length||rows.some(row=>canonical(row.features.find((f:any)=>f.code==='ticket')?.layout)!==canonical(manifest.find((m:any)=>m.id===row.id)?.layout)))throw new Error('Cutover readback differs');
}
console.log(`${mode}: ${rows.length} scoped configurations`);
