import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {readFile,writeFile,mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {execFileSync} from 'node:child_process';
import {createRequire} from 'node:module';
import {assertLocalDatabaseUrl,assertDisposableDatabase} from '../../../web_client/tests/database/disposable_database.js';
const require=createRequire(new URL('../../../web_client/package.json',import.meta.url));
const {Client}=require('pg');
const url=process.env.DATABASE_URL;
assertLocalDatabaseUrl(url);
const cloneName=`festapp_seating_race_${randomUUID().replaceAll('-','')}`;
async function connect(connectionString){const c=new Client({connectionString});await c.connect();return c;}
async function identity(c,actor){await c.query("SELECT set_config('request.jwt.claim.sub',$1,false),set_config('request.jwt.claim.role','authenticated',false)",[actor]);}
async function blocked(admin,pid){for(let n=0;n<150;n++){const r=await admin.query('SELECT wait_event_type FROM pg_stat_activity WHERE pid=$1',[pid]);if(r.rows[0]?.wait_event_type==='Lock')return;await new Promise(r=>setTimeout(r,20));}throw Error('second connection never reached lock wait');}
const row=async(c,sql,args=[])=>(await c.query(sql,args)).rows[0];
const rpc=async(c,sql,args=[])=>(await row(c,sql,args)).result;

test('seating public commands: actual two-connection serial outcomes and permission revocation',{timeout:60000},async t=>{
 const admin=await connect(url);await assertDisposableDatabase(admin);
 const cloneUrl=new URL(url);cloneUrl.pathname=`/${cloneName}`;
 let db,left,right;
 const kit=await mkdtemp(`${tmpdir()}/festapp-seating-race-`);
 try{
  // Clone checked dependencies, never reset the shared database or bootstrap a server.
  execFileSync('pg_dump',[url,'--no-owner','--exclude-schema=cron','--file',`${kit}/snapshot.sql`],{stdio:'pipe'});
  await writeFile(`${kit}/snapshot.sql`,(await readFile(`${kit}/snapshot.sql`,'utf8')).replace(/^SET transaction_timeout = 0;$/m,'').replace(/^CREATE EXTENSION IF NOT EXISTS pg_cron\b[^;]*;$/gm,'').replace(/^COMMENT ON EXTENSION pg_cron\b[^;]*;$/gm,'').replace(/^(?:REVOKE|GRANT).*ON FUNCTION graphql_public\.graphql\(.*$/gm,'').replace(/^(?:ALTER DEFAULT PRIVILEGES|REVOKE|GRANT).*\bcron\b.*$/gm,''));
  await admin.query(`CREATE DATABASE ${cloneName} TEMPLATE template0`);
  const restoreUrl=new URL(cloneUrl);restoreUrl.username='supabase_admin';
  execFileSync('psql',[restoreUrl.href,'-v','ON_ERROR_STOP=1','-q','-f',`${kit}/snapshot.sql`],{stdio:'pipe'});
  execFileSync('psql',[restoreUrl.href,'-v','ON_ERROR_STOP=1','-q','-c',`GRANT ALL ON ALL TABLES IN SCHEMA public,eshop TO postgres; GRANT ALL ON ALL SEQUENCES IN SCHEMA public,eshop TO postgres; DO $fix$ DECLARE r record; BEGIN FOR r IN SELECT p.oid::regprocedure f FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.prokind IN ('f','w') AND NOT EXISTS(SELECT 1 FROM pg_depend d WHERE d.classid='pg_proc'::regclass AND d.objid=p.oid AND d.deptype='e') LOOP EXECUTE format('ALTER FUNCTION %s OWNER TO postgres',r.f); END LOOP; END $fix$;`],{stdio:'pipe'});
  [db,left,right]=await Promise.all([connect(cloneUrl.href),connect(cloneUrl.href),connect(cloneUrl.href)]);
  for(const source of ['database/tests/helpers/assertions.sql','database/tests/blueprint/fixtures.sql','database/tests/blueprint/seating_fixture.sql'])await db.query(await readFile(new URL(`../../../${source}`,import.meta.url),'utf8'));
  await right.query('SET ROLE authenticated');
  await t.test('clean predecessor upgrade and final canonical source parity',async()=>{
   const program=`import runpy,sys,subprocess
from pathlib import Path
sys.path.insert(0,'automation')
from generate_canonical_source_contract import definitions
assembly=runpy.run_path('automation/assemble-seating-transition-migration.py')
sources=assembly['SOURCES']
predecessor=assembly['PREDECESSOR']
commands=['BEGIN; SET LOCAL ROLE postgres;']
old_sources=[]
for source in sources:
 current=dict(definitions(Path('database/functions',source).read_text()))
 old=subprocess.run(['git','show',predecessor+':database/functions/'+source],capture_output=True,text=True)
 previous=dict(definitions(old.stdout)) if old.returncode==0 else {}
 for signature,body in current.items():
  if body is not None and signature not in previous:commands.append('DROP FUNCTION IF EXISTS '+signature+' CASCADE;')
 if old.returncode==0:old_sources.append(old.stdout)
commands.append('DROP TABLE public.form_seating_transitions CASCADE;')
# The clone contains unrelated retained old fixtures. This upgrade proof uses
# an empty layout store; production data conversion has its own guarded proof.
commands.append('TRUNCATE eshop.blueprints CASCADE;')
commands.append('RESET ROLE; ALTER TABLE eshop.blueprints OWNER TO postgres; SET LOCAL ROLE postgres;')
commands.append('ALTER TABLE eshop.blueprints DROP CONSTRAINT IF EXISTS blueprints_canonical_layout_check, DROP CONSTRAINT IF EXISTS blueprints_retired_geometry_empty_check;')
commands+=old_sources
commands.append(Path('supabase/migrations/20261031223000_blueprint_feature_independent_capacity.sql').read_text())
commands.append(Path('supabase/migrations/20261101120000_blueprint_existing_admission_seating.sql').read_text())
commands.append(Path('supabase/migrations/20261101121500_occasion_copy_deletion.sql').read_text())
commands.append(Path('supabase/migrations/20261101160000_blueprint_canonical_storage_cutover.sql').read_text())
commands.append(Path('supabase/migrations/20261101173000_seating_compatibility_admissions.sql').read_text())
commands.append("RESET ROLE; DELETE FROM supabase_migrations.schema_migrations WHERE version='20261101120000'; INSERT INTO supabase_migrations.schema_migrations(version,name) VALUES('20261101120000','blueprint_existing_admission_seating'); COMMIT;")
print(chr(10).join(commands))`;
   const upgrade=execFileSync('python3',['-c',program],{cwd:new URL('../../../',import.meta.url),encoding:'utf8'});
   try { execFileSync('psql',[restoreUrl.href,'-v','ON_ERROR_STOP=1','-q'],{input:upgrade,stdio:['pipe','pipe','pipe']}); }
   catch(error) { throw new Error(error.stderr?.toString() || error.message); }
   await db.query(await readFile(new URL('../canonical_mutation_source_parity_test.sql',import.meta.url),'utf8'));
  });
  const fixture=async(n=2,w=0)=>rpc(db,'SELECT public.seating_test_fixture_internal($1,$2) result',[n,w]);
  const prepare=async(c,f,m)=>rpc(c,'SELECT public.preview_ticket_seat_assignment($1,$2::jsonb) result',[f.transition,JSON.stringify(m)]).then(r=>r.data);
  const assign=async(c,f,m,p)=>rpc(c,'SELECT public.set_ticket_seat_assignments($1,$2::jsonb,$3,$4) result',[f.transition,JSON.stringify(m),p.fingerprint,randomUUID()]);
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
  await t.test('publication first; stale visible-product checkout rejected by actual materializer',async()=>{
   const f=await fixture(0);await Promise.all([identity(left,f.actor),identity(right,f.actor)]);
   const p=(await rpc(left,'SELECT public.preview_seating_publication($1) result',[f.transition])).data;
   await left.query('BEGIN');await left.query('SELECT public.lock_blueprint_scope_internal(ARRAY[$1::bigint])',[f.occasion]);
   const checkout={form:f.formKey,email:'seating@example.invalid',ticket:[{fields:[{product_type:f.product}]}]};
   const competing=rpc(right,'SELECT public.create_ticket_order_client_sync_v1($1::jsonb,$2,$3) result',[JSON.stringify(checkout),randomUUID(),randomUUID()]);await waitRight();
   const published=await rpc(left,'SELECT public.publish_seating_transitions($1,$2::uuid[],$3,$4) result',[f.transition,p.transitionIds,p.fingerprint,randomUUID()]);
   assert.equal(published.status,'applied');await left.query('COMMIT');
   const rejected=await competing;assert.notEqual(rejected.status,'applied');
   assert.equal((await row(db,"SELECT count(*)::int n FROM eshop.orders WHERE occasion=$1 AND state NOT IN ('storno','waitlisted','stock')",[f.occasion])).n,0);
  });

  await t.test('layout save first; waiting publication must review new saved revision',async()=>{
   const f=await fixture(0);await Promise.all([identity(left,f.actor),identity(right,f.actor)]);
   const p=(await rpc(right,'SELECT public.preview_seating_publication($1) result',[f.transition])).data;
   const b=(await row(db,'SELECT to_jsonb(b) b FROM eshop.blueprints b WHERE id=$1',[f.blueprint])).b;
   await left.query('BEGIN');await left.query('SELECT public.lock_blueprint_scope_internal(ARRAY[$1::bigint])',[f.occasion]);
   const competing=rpc(right,'SELECT public.publish_seating_transitions($1,$2::uuid[],$3,$4) result',[f.transition,p.transitionIds,p.fingerprint,randomUUID()]);await waitRight();
   const payload={id:b.id,occasion:b.occasion,organization:b.organization,title:'Revised saved plan',expected_layout_revision:b.layout_revision,layout:b.layout,textResourceIds:[],seatChanges:[],groupProductChanges:[],areaBindingChanges:[]};
   const saved=await rpc(left,'SELECT public.update_blueprint_client_sync_v1($1::jsonb,$2) result',[JSON.stringify(payload),randomUUID()]);
   assert.equal(saved.status,'applied',JSON.stringify(saved));await left.query('COMMIT');
   assert.equal((await competing).status,'conflict');
  });
  await t.test('provider completion first; publication rechecks paid facts and keeps exact placement',async()=>{
   const f=await fixture(1);await Promise.all([identity(left,f.actor),identity(right,f.actor)]);
   await assign(left,f,f.mappings,await prepare(left,f,f.mappings));
   const parent=await row(db,'SELECT o.id,o.organization,o.unit FROM public.occasions o WHERE id=$1',[f.occasion]);
   const order=(await row(db,'SELECT "order" id FROM eshop.order_product_ticket WHERE id=$1',[f.mappings[0].admissionItemId])).id;
   const account='acct_'+randomUUID().replaceAll('-','');
   const connection=(await row(db,"INSERT INTO eshop.stripe_connections(organization_id,unit_id,account_id,livemode,state,paused) VALUES($1,$2,$3,false,'connected',false) RETURNING id",[parent.organization,parent.unit,account])).id;
   const payment=(await row(db,"INSERT INTO eshop.payment_info(amount,paid,currency_code,payment_method,stripe_connection_id) VALUES(42,0,'CZK','stripe',$1) RETURNING id",[connection])).id;
   await db.query('UPDATE eshop.orders SET payment_info=$1 WHERE id=$2',[payment,order]);
   const lease=randomUUID();
   const attempt=(await row(db,"INSERT INTO eshop.stripe_checkout_attempts(order_id,payment_info_id,organization_id,unit_id,connection_id,livemode,amount_minor,currency,order_revision,idempotency_key,reservation_expires_at,state,lease_token,lease_expires_at) VALUES($1,$2,$3,$4,$5,false,4200,'CZK',1,$6,clock_timestamp()+interval '1 hour','open',$7,clock_timestamp()+interval '5 minutes') RETURNING id",[order,payment,parent.organization,parent.unit,connection,'seating:'+randomUUID(),lease])).id;
   const p=(await rpc(right,'SELECT public.preview_seating_publication($1) result',[f.transition])).data;
   await left.query('BEGIN');await left.query('SELECT public.lock_order_capacity_scope_internal(ARRAY[$1::bigint])',[order]);
   const competing=rpc(right,'SELECT public.publish_seating_transitions($1,$2::uuid[],$3,$4) result',[f.transition,p.transitionIds,p.fingerprint,randomUUID()]);await waitRight();
   await left.query("SELECT set_config('request.jwt.claim.role','service_role',true)");
   await left.query("SELECT set_config('request.jwt.claim.sub','',true)");
   const now=Math.floor(Date.now()/1000),intent='pi_'+randomUUID().replaceAll('-','');
   const event={id:'evt_'+randomUUID().replaceAll('-',''),bodyHash:'f'.repeat(64),accountId:account,livemode:false,type:'checkout.session.completed',created:now};
   const facts={observedAt:new Date().toISOString(),sessionId:'cs_'+randomUUID().replaceAll('-',''),paymentIntentId:intent,sessionStatus:'complete',movements:[{kind:'payment',providerId:intent,amountMinor:4200,currency:'CZK',occurredAt:now}],disputes:[]};
   const paid=await rpc(left,'SELECT public.ingest_stripe_payment_internal($1,$2,$3::jsonb,$4::jsonb) result',[attempt,lease,JSON.stringify(event),JSON.stringify(facts)]);
   assert.equal(paid.status,'applied',JSON.stringify(paid));await left.query('COMMIT');
   assert.equal((await competing).status,'conflict');
   assert.equal((await row(db,'SELECT order_product_ticket FROM eshop.spots WHERE id=$1',[f.mappings[0].targetSpotId])).order_product_ticket,String(f.mappings[0].admissionItemId));
  });
  await t.test('offer acceptance first; stable accepted ticket enters worklist before publication',async()=>{
   const f=await fixture(0,2);await Promise.all([identity(left,f.actor),identity(right,f.actor)]);
   await db.query('UPDATE eshop.products SET price=0 WHERE id=$1',[f.product]);
   const person=await row(db,'SELECT t.id,x."order" FROM eshop.tickets t JOIN eshop.order_product_ticket x ON x.ticket=t.id JOIN eshop.orders o ON o.id=x."order" WHERE o.occasion=$1',[f.occasion]);
   await db.query('UPDATE eshop.order_product_ticket SET \"order\"=$1 WHERE \"order\" IN(SELECT id FROM eshop.orders WHERE occasion=$2)',[person.order,f.occasion]);
   await db.query("UPDATE eshop.orders SET data=jsonb_set(data,'{tickets}',(SELECT jsonb_agg(tj) FROM eshop.orders sibling CROSS JOIN LATERAL jsonb_array_elements(sibling.data->'tickets') tj WHERE sibling.occasion=$2)) WHERE id=$1",[person.order,f.occasion]);
   const offer=(await row(db,"INSERT INTO eshop.waitlist_offers(order_id,form_id,created_by,expires_at,revision) VALUES($1,$2,$3,clock_timestamp()+interval '1 hour',0) RETURNING id",[person.order,f.form,f.actor])).id;
   await db.query('INSERT INTO eshop.waitlist_offer_slots(offer_id,ticket_id,form_id) VALUES($1,$2,$3)',[offer,person.id,f.form]);
   const p=(await rpc(right,'SELECT public.preview_seating_publication($1) result',[f.transition])).data;
   await left.query('BEGIN');await left.query('SELECT public.lock_blueprint_scope_internal(ARRAY[$1::bigint])',[f.occasion]);
   const competing=rpc(right,'SELECT public.publish_seating_transitions($1,$2::uuid[],$3,$4) result',[f.transition,p.transitionIds,p.fingerprint,randomUUID()]);await waitRight();
   await left.query("SELECT set_config('request.jwt.claim.role','service_role',true)");
   const payload={offerId:offer,ticketIds:[person.id],orderDetails:{form:f.formKey,email:'seating@example.invalid',ticket:[{ticketId:person.id,fields:[{product_type:f.product}]}]}};
   const accepted=await rpc(left,"SELECT public.execute_waitlist_command_client_sync_v1('accept',$1::jsonb,$2,$3,$4) result",[JSON.stringify(payload),randomUUID(),randomUUID(),f.actor]);
   assert.equal(accepted.status,'applied',JSON.stringify(accepted));await left.query('COMMIT');
   assert.equal((await competing).status,'conflict');
   const context=(await rpc(right,'SELECT public.get_seating_transition_context($1) result',[f.transition])).data;
   assert.equal(context.counts.unassigned,1);assert.equal(context.counts.waiting,1);assert.ok(context.items.some(i=>i.ticketId===Number(person.id)&&i.category==='unassigned'));
   const ownership=await row(db,'SELECT \"order\" FROM eshop.order_product_ticket WHERE ticket=$1',[person.id]);assert.notEqual(ownership.order,person.order,'partial acceptance split retains current ticket identity');
  });
 }finally{
  await Promise.allSettled([left,right,db].filter(Boolean).map(async c=>{await c.query('ROLLBACK');await c.end();}));
  await admin.query(`DROP DATABASE IF EXISTS ${cloneName} WITH (FORCE)`);await admin.end();await rm(kit,{recursive:true,force:true});
 }
});
