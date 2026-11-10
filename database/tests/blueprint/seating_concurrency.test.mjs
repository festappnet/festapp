import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {execFileSync} from 'node:child_process';
import {createRequire} from 'node:module';
import {createTestWorkspace} from '../../../web_client/tests/database/runtime_workspace.js';
import {assertLocalDatabaseUrl,assertDisposableDatabase} from '../../../web_client/tests/database/disposable_database.js';
const require=createRequire(new URL('../../../web_client/package.json',import.meta.url));
const {Client}=require('pg');
const url=process.env.DATABASE_URL;
assertLocalDatabaseUrl(url);
async function connect(connectionString){const c=new Client({connectionString});await c.connect();return c;}
async function identity(c,actor){await c.query("SELECT set_config('request.jwt.claim.sub',$1,false),set_config('request.jwt.claim.role','authenticated',false)",[actor]);}
async function blocked(admin,pid){for(let n=0;n<150;n++){const r=await admin.query('SELECT wait_event_type FROM pg_stat_activity WHERE pid=$1',[pid]);if(r.rows[0]?.wait_event_type==='Lock')return;await new Promise(r=>setTimeout(r,20));}throw Error('second connection never reached lock wait');}
const row=async(c,sql,args=[])=>(await c.query(sql,args)).rows[0];
const rpc=async(c,sql,args=[])=>(await row(c,sql,args)).result;

test('seating public commands: actual two-connection serial outcomes and permission revocation',{timeout:60000},async t=>{
 const admin=await connect(url);await assertDisposableDatabase(admin);
 const workspace=await createTestWorkspace();const cloneUrl=new URL(workspace.databaseUrl);const restoreUrl=new URL(cloneUrl);restoreUrl.username='supabase_admin';
 let db,left,right;
 try{
  [db,left,right]=await Promise.all([connect(cloneUrl.href),connect(cloneUrl.href),connect(cloneUrl.href)]);
  for(const source of ['database/tests/helpers/assertions.sql','database/tests/blueprint/fixtures.sql','database/tests/blueprint/seating_fixture.sql'])await db.query(await readFile(new URL(`../../../${source}`,import.meta.url),'utf8'));
  await right.query('SET ROLE authenticated');
  const fixture=async(n=2,w=0)=>rpc(db,'SELECT public.seating_test_fixture_internal($1,$2) result',[n,w]);
  const prepare=async(c,f,m)=>rpc(c,'SELECT public.preview_ticket_seat_assignment($1,$2::jsonb) result',[f.blueprint,JSON.stringify(m)]).then(r=>r.data);
  const assign=async(c,f,m,p)=>rpc(c,'SELECT public.set_ticket_seat_assignments($1,$2::jsonb,$3,$4) result',[f.blueprint,JSON.stringify(m),p.fingerprint,randomUUID()]);
  const waitRight=async()=>blocked(db,right.processID);
  t.afterEach(async()=>{await left.query('ROLLBACK');await right.query('ROLLBACK');});
  await t.test('two organizers target one seat; exactly one placement',async()=>{
   const f=await fixture();await Promise.all([identity(left,f.actor),identity(right,f.actor)]);
   const first=[f.mappings[0]],second=[{...f.mappings[1],targetSpotId:first[0].targetSpotId}];
   const [p,q]=await Promise.all([prepare(left,f,first),prepare(right,f,second)]);
   await left.query('BEGIN');await left.query('SELECT public.lock_blueprint_scope_internal(ARRAY[$1::bigint])',[f.occasion]);
   const competing=assign(right,f,second,q);await waitRight();
   const won=await assign(left,f,first,p);assert.equal(won.status,'applied');await left.query('COMMIT');
   const lost=await competing;assert.equal(lost.status,'conflict');assert.equal(lost.data.reason,'SEAT_UNAVAILABLE');
   assert.equal((await row(db,'SELECT count(*)::int n FROM eshop.spots WHERE id=$1 AND order_product_ticket IS NOT NULL',[first[0].targetSpotId])).n,1);
  });
  await t.test('cancel source while assignment waits; no placement on cancelled ticket',async()=>{
   const f=await fixture(1);await Promise.all([identity(left,f.actor),identity(right,f.actor)]);const p=await prepare(right,f,f.mappings);
   await left.query('BEGIN');await left.query('SELECT public.lock_blueprint_scope_internal(ARRAY[$1::bigint])',[f.occasion]);
   const competing=assign(right,f,f.mappings,p);await waitRight();
   const cancelled=await rpc(left,'SELECT public.storno_tickets_client_sync_v1($1::bigint[],$2) result',[[f.mappings[0].ticketId],randomUUID()]);
   assert.equal(cancelled.status,'applied');await left.query('COMMIT');
   assert.equal((await competing).status,'conflict');
   assert.equal((await row(db,'SELECT order_product_ticket FROM eshop.spots WHERE id=$1',[f.mappings[0].targetSpotId])).order_product_ticket,null);
  });
  await t.test('revoked writer after advisory wait gets denial and no receipt',async()=>{
   const f=await fixture(1);await identity(right,f.actor);const p=await prepare(right,f,f.mappings);
   await left.query('BEGIN');await left.query('SELECT public.lock_blueprint_scope_internal(ARRAY[$1::bigint])',[f.occasion]);
   const competing=assign(right,f,f.mappings,p).then(value=>({value}),error=>({error}));await waitRight();
   await left.query('UPDATE public.occasion_users SET is_editor_order=false WHERE occasion=$1 AND "user"=$2',[f.occasion,f.actor]);await left.query('COMMIT');
   const outcome=await competing;assert.equal(outcome.error?.code,'42501');
   assert.equal((await row(db,"SELECT count(*)::int n FROM public.client_mutation_receipts WHERE occasion=$1 AND command_name='seating.assignment.set'",[f.occasion])).n,0);
  });
  await t.test('scan/use wins source parent lock; assignment observes used state',async()=>{
   const f=await fixture(1);await Promise.all([identity(left,f.actor),identity(right,f.actor)]);const p=await prepare(right,f,f.mappings);
   await left.query('BEGIN');await left.query('SELECT public.scanner_lock_ticket_internal($1)',[f.mappings[0].ticketId]);
   const competing=assign(right,f,f.mappings,p);await waitRight();
   await left.query('SELECT public.scanner_admit_ticket_internal($1)',[f.mappings[0].ticketId]);await left.query('COMMIT');
   const r=await competing;assert.equal(r.status,'conflict');assert.equal(r.data.reason,'USED_TICKET_PROTECTED');
  });
  await t.test('layout save invalidates a waiting assignment preview',async()=>{
   const f=await fixture(1);await Promise.all([identity(left,f.actor),identity(right,f.actor)]);
   const p=await prepare(right,f,f.mappings);
   const b=(await row(db,'SELECT to_jsonb(b) b FROM eshop.blueprints b WHERE id=$1',[f.blueprint])).b;
   await left.query('BEGIN');await left.query('SELECT public.lock_blueprint_scope_internal(ARRAY[$1::bigint])',[f.occasion]);
   const competing=assign(right,f,f.mappings,p);await waitRight();
   const payload={id:b.id,occasion:b.occasion,organization:b.organization,title:'Revised saved plan',expected_layout_revision:b.layout_revision,layout:b.layout,textResourceIds:[],seatChanges:[],groupProductChanges:[],areaBindingChanges:[]};
   const saved=await rpc(left,'SELECT public.update_blueprint_client_sync_v1($1::jsonb,$2) result',[JSON.stringify(payload),randomUUID()]);
   assert.equal(saved.status,'applied',JSON.stringify(saved));await left.query('COMMIT');
   assert.equal((await competing).status,'conflict');
  });
  await t.test('forward cutover connects an existing configuration without changing orders or seats',async()=>{
   const f=await fixture(1);await identity(right,f.actor);
   const generic=await fixture(2,1);
   const p=await prepare(right,f,f.mappings);assert.equal((await assign(right,f,f.mappings,p)).status,'applied');
   const old=await readFile(new URL('../../../supabase/migrations/20261101120000_blueprint_existing_admission_seating.sql',import.meta.url),'utf8');
   const start=old.indexOf('-- Source: database/functions/blueprint/seating_transition_schema.sql');
   const end=old.indexOf('-- Source:',start+10);
   assert.ok(start>=0 && end>start);
   await db.query('BEGIN');
   try {
    await db.query(old.slice(start,end));
    await db.query('INSERT INTO public.form_seating_transitions(occasion,form,blueprint,started_by) VALUES($1,$2,$3,$4)',[f.occasion,f.form,f.blueprint,f.actor]);
    await db.query("INSERT INTO public.client_sync_component_sources(registry_version,component,source_relation,scope_resolver,tracked_columns,canonical_writers,legacy_writers,disposition,test_factory,cutover_ready) VALUES(1,'private_inventory','public.form_seating_transitions'::regclass,'form_seating_transitions.occasion',ARRAY['form'],ARRAY['set_ticket_seat_assignments'],ARRAY[]::text[],'migrate','fixture',true)");
    await db.query("INSERT INTO public.form_fields(form,type,is_ticket_field,is_hidden) VALUES($1,'spot',true,false)",[f.form]);
    await db.query('UPDATE public.forms SET blueprint=NULL,is_open=false WHERE id=$1',[f.form]);
    await db.query('INSERT INTO public.form_seating_transitions(occasion,form,blueprint,started_by) VALUES($1,$2,$3,$4)',[generic.occasion,generic.form,generic.blueprint,generic.actor]);
    await db.query('UPDATE public.forms SET blueprint=NULL,participant_capacity=10,waitlist_enabled=true,waitlist_offer_duration_seconds=3600 WHERE id=$1',[generic.form]);
    const genericBefore=await row(db,'SELECT to_jsonb(f) value FROM public.forms f WHERE id=$1',[generic.form]);
    const before=await row(db,"SELECT (SELECT jsonb_agg(to_jsonb(o) ORDER BY id) FROM eshop.orders o WHERE occasion=$1) orders,(SELECT jsonb_agg(to_jsonb(s) ORDER BY id) FROM eshop.spots s WHERE occasion=$1) spots",[f.occasion]);
    await db.query(await readFile(new URL('../../../supabase/migrations/20261110220000_automatic_form_blueprints.sql',import.meta.url),'utf8'));
    const after=await row(db,"SELECT (SELECT jsonb_agg(to_jsonb(o) ORDER BY id) FROM eshop.orders o WHERE occasion=$1) orders,(SELECT jsonb_agg(to_jsonb(s) ORDER BY id) FROM eshop.spots s WHERE occasion=$1) spots",[f.occasion]);
    assert.deepEqual(after,before);
    assert.deepEqual(await row(db,'SELECT to_jsonb(f) value FROM public.forms f WHERE id=$1',[generic.form]),genericBefore);
    await identity(db,generic.actor);
    const genericContext=(await rpc(db,'SELECT public.get_blueprint_seating_context($1) result',[generic.blueprint])).data;
    assert.equal(genericContext.counts.unassigned,2);
    assert.equal(genericContext.counts.waiting,1);
    assert.equal((await row(db,'SELECT blueprint,is_open FROM public.forms WHERE id=$1',[f.form])).blueprint,String(f.blueprint));
    assert.equal((await row(db,'SELECT is_open FROM public.forms WHERE id=$1',[f.form])).is_open,false);
    assert.equal((await row(db,"SELECT to_regclass('public.form_seating_transitions') retired")).retired,null);
    assert.equal((await row(db,'SELECT count(*)::int n FROM public.client_sync_component_sources t WHERE NOT EXISTS(SELECT FROM pg_class c WHERE c.oid=t.source_relation)')).n,0);
    await db.query('COMMIT');
   } catch(error) {await db.query('ROLLBACK');throw error;}
  });
 }finally{
  await Promise.allSettled([left,right,db].filter(Boolean).map(async c=>{await c.query('ROLLBACK');await c.end();}));
  await admin.end();await workspace.release();
 }
});
