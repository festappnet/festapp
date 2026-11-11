import assert from 'node:assert/strict';
import {readFile} from '../../../automation/lib/migration_inputs_async.mjs';

const root=new URL('../../../',import.meta.url);
const sources=new Map();
async function source(file){
 assert(!file.includes('..')&&file.endsWith('.sql'));
 if(!sources.has(file))sources.set(file,readFile(new URL('database/functions/'+file,root),'utf8'));
 return sources.get(file);
}
// Call inside the fixture transaction, after historical migrations. Source bodies
// and grants stay canonical; only local routine ownership is aligned to production.
export async function installCurrentSql(db,files){
 const declared=new Set();
 for(const file of files){
  const sql=await source(file);await db.query(sql);
  for(const [,name] of sql.matchAll(/CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+public\.(\w+)\s*\(/gi))declared.add(name);
 }
 for(const row of(await db.query("select format('ALTER FUNCTION %s OWNER TO postgres',oid::regprocedure) statement from pg_proc where pronamespace='public'::regnamespace and proname=any($1)",[[...declared]])).rows)await db.query(row.statement);
}
export async function installCurrentCheckout(db){
 await installCurrentSql(db,[
  'eshop_payment_references/schema.sql','eshop_payment_references/identity.sql','eshop_payment_references/allocation.sql',
  'eshop_orders/ensure_order_payment_instructions.sql','eshop_orders/checkout_origin.sql','emails/order_checkout_email_kind.sql','emails/queue_payment_reminders.sql',
  'blueprint/seating_transition_schema.sql','user_permissions/seating_transition_operations.sql','blueprint/seating_transition_lifecycle.sql','blueprint/seating_publication.sql',
  'eshop_forms/primary_product_guard.sql','eshop_forms/form_availability.sql',
  'sale_opening_notifications/schema.sql','sale_opening_notifications/settings.sql',
  'eshop/materialize_ticket_products_internal_v1.sql','eshop/create_ticket_order.sql','eshop/finalize_ticket_order.sql',
  'eshop_orders/recalculate_order_payment_status.sql',
 ]);
 for(const table of ['sale_opening_campaigns','sale_opening_subscriptions','sale_opening_capabilities'])await db.query('ALTER TABLE public.'+table+' OWNER TO postgres');
}
export async function installCurrentLayoutContract(db){
 const files=JSON.parse(await readFile(new URL('automation/tickets/ticket-layout-write-contract-sources.json',root),'utf8'));
 await installCurrentSql(db,[...files,'others/get_ticket_layout_write_contract_v1.sql']);
}

let canonicalOwners;
export async function installCurrentMigrationOwners(db,migrations){
 if(!canonicalOwners)canonicalOwners=(async()=>{
  const files=JSON.parse(await readFile(new URL('automation/canonical-operation-sources.json',root),'utf8')).sources;
  return Promise.all(files.map(async file=>({file,names:new Set([...String(await source(file)).matchAll(/CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+public\.(\w+)\s*\(/gi)].map(m=>m[1]))})));
 })();
 const requested=new Set();
 for(const migration of migrations){
  const sql=await readFile(new URL('supabase/migrations/'+migration,root),'utf8');
  for(const [,name] of sql.matchAll(/CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+public\.(\w+)\s*\(/gi))requested.add(name);
 }
 await installCurrentSql(db,['users/member_visibility.sql','notification_center/subject_visibility.sql']);
 const files=(await canonicalOwners).filter(entry=>[...entry.names].some(name=>requested.has(name))).map(entry=>entry.file);
 assert(files.length>0,'Historical migration must resolve to current canonical SQL owners');
 await installCurrentSql(db,files);
}
