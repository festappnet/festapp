import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import {fixture} from '../../../automation/authorization/benchmark.mjs';
import {openDisposableDatabase} from './postgres.mjs';
import {Operations} from '../src/operations/catalog.mjs';
const connection=process.env.FESTAPP_MCP_TEST_DATABASE_URL;
const options={skip:!connection};
async function install(db){
 for(const file of ['forms/email_address_is_valid.sql','eshop_orders/repair_order_email_client_sync_v1.sql','eshop_forms/duplicate_form_to_occasion.sql'])
  await db.query(await readFile(new URL('../../../database/functions/'+file,import.meta.url),'utf8'));
 for(const file of ['schema','order_context','temporal_feed','app_activity','core','orders','capacity','email','maintenance','bank','form_availability']){
  let sql=await readFile(new URL('../../../database/functions/notification_center/'+file+'.sql',import.meta.url),'utf8');
  if(file==='schema'&&(await db.query("select to_regclass('public.notification_center_events') present")).rows[0].present){
   // This shared disposable cache has the newer activation table. Add only the
   // missing canonical predecessor dependency inside this test transaction.
   if(!(await db.query("select to_regclass('public.notification_center_organizations') present")).rows[0].present)
    await db.query(sql.slice(0,sql.indexOf('CREATE TABLE public.notification_center_events')));
   await db.query('alter table public.notification_center_source_state add column if not exists next_evaluation_at timestamptz');
   continue;
  }
  if(file==='maintenance'&&(await db.query("select to_regclass('public.notification_center_maintenance') present")).rows[0].present)sql=sql.slice(sql.indexOf('CREATE OR REPLACE FUNCTION'));
  await db.query(sql);
 }
 await db.query(await readFile(new URL('../../../supabase/migrations/20261026190000_form_authoring.sql',import.meta.url),'utf8'));
 await db.query(await readFile(new URL('../../../supabase/migrations/20261026200000_form_authoring_settings.sql',import.meta.url),'utf8'));
 await db.query(await readFile(new URL('../../../supabase/migrations/20261026210000_form_administration_completion.sql',import.meta.url),'utf8'));
 await db.query(await readFile(new URL('../../../supabase/migrations/20261029130000_form_design_background_mode.sql',import.meta.url),'utf8'));
 await db.query(await readFile(new URL('../../../supabase/migrations/20261031120000_form_design_theme_mode.sql',import.meta.url),'utf8'));
}
async function setup(t){const db=await openDisposableDatabase(connection);await db.query('BEGIN');t.after(async()=>{await db.query('ROLLBACK');await db.end();});await install(db);const f=await fixture(db,2);return{db,f};}
function executor(db,f){const calls=[];const client={rpc:async(name,args)=>{await db.query('SAVEPOINT rpc');try{const names=Object.keys(args),values=Object.values(args);const data=(await db.query('select '+name+'('+names.map((n,i)=>n+'=> $'+(i+1)).join(',')+') value',values)).rows[0].value;await db.query('RELEASE SAVEPOINT rpc');calls.push({name,bytes:Buffer.byteLength(JSON.stringify(data))});return{data,error:null};}catch(error){await db.query('ROLLBACK TO SAVEPOINT rpc');await db.query('RELEASE SAVEPOINT rpc');return{data:null,error};}}};
 const owner={profile:{name:'fixture',tenantId:'fixture',organizationId:f.org},root:'/tmp/form-authoring',allowedOperations:['forms.list','forms.inspect','forms.paymentOptions','forms.publicLink','forms.setPublicLink','forms.previewOrder','forms.createOrder','waitlist.proposal','waitlist.detail','waitlist.send','waitlist.cancel','waitlist.withdraw','forms.create','forms.save','forms.duplicate','forms.delete'],delegatedContext:async()=>({organizationId:f.org,unitId:f.unit}),authorized:action=>action(client,{userId:f.actor})};return{ops:new Operations(owner),calls};}
async function create(db,f,title='Synthetic form'){const result=(await db.query("select manage_form($1,$2,$3,'create',$4,$5) value",[f.occasion,f.org,f.unit,{title},randomUUID()])).rows[0].value;assert.equal(result.code,200,JSON.stringify(result));return result.data;}
function formPatch(state,patch={}){return{id:state.form.id,expected_aggregate_version:state.form.aggregate_version,expected_product_versions:state.productVersions,expected_product_type_versions:state.productTypeVersions,...patch};}
async function save(db,f,payload,commandId=randomUUID()){return(await db.query("select manage_form($1,$2,$3,'save',$4,$5) value",[f.occasion,f.org,f.unit,payload,commandId])).rows[0].value;}
async function denied(db,sql,args,code='42501'){await db.query('SAVEPOINT denied');await assert.rejects(db.query(sql,args),e=>e.code===code);await db.query('ROLLBACK TO SAVEPOINT denied');await db.query('RELEASE SAVEPOINT denied');}


export {connection,options,install,setup,executor,create,formPatch,save,denied};
