// Run in the owned local runtime at the predecessor revision. The database
// lease is disposable and must be released after this fixture commits.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {readFileSync} from 'node:fs';
import {createRequire} from 'node:module';
import {setTimeout as sleep} from 'node:timers/promises';
import {assertDisposableDatabase,assertLocalDatabaseUrl} from '../../../web_client/tests/database/disposable_database.js';

const require=createRequire(new URL('../../../web_client/package.json',import.meta.url));
const {Client}=require('pg');
const read=path=>readFileSync(new URL('../../../'+path,import.meta.url),'utf8');
const url=process.env.DATABASE_URL;
assert(url,'Run with an owned predecessor database lease');
assertLocalDatabaseUrl(url);

const primary=new Client({connectionString:url,application_name:'publisher-rehearsal'});
const contender=new Client({connectionString:url,application_name:'publisher-rehearsal-contender'});
const scalar=async (text,args=[],client=primary)=>(await client.query(text,args)).rows[0]?.value;
const state=order=>scalar(`SELECT jsonb_build_object(
  'facts',(SELECT jsonb_agg(to_jsonb(f) ORDER BY kind) FROM analytics.conversion_facts f WHERE f."order"=o.id),
  'delivery',(SELECT jsonb_build_object('status',status,'revision',connector_revision,
     'consent',consent_snapshot,'attempts',attempts) FROM analytics.meta_purchase_deliveries WHERE order_id=o.id)
 ) value FROM eshop.orders o WHERE o.id=$1`,[order]);

await primary.connect();
await contender.connect();
try {
  await assertDisposableDatabase(primary);
  await assertDisposableDatabase(contender);
  await primary.query("SET statement_timeout='30s'; SET festapp.email_wake='scheduled'");
  await contender.query("SET statement_timeout='15s'");
  await primary.query(read('database/tests/helpers/assertions.sql'));
  await primary.query(read('database/tests/helpers/form_measurement_fixture.sql'));
  assert.equal(await scalar("SELECT to_regprocedure('public.publish_form_measurement_event_internal(text,bigint)') value"),null);
  const x=await scalar('SELECT pg_temp.fixture(NULL) value');
  await primary.query("SELECT public.reserve_public_link_internal('occasion',$1,$2,true)",[x.occasion,x.link]);
  await primary.query("SELECT public.reserve_public_link_internal('form',$1,$2,true)",[x.form,x.link]);
  await primary.query(`UPDATE public.organizations SET data=data||'{"DEFAULT_URL":"https://tickets.example"}' WHERE id=$1`,[x.organization]);
  await primary.query(`UPDATE public.units SET data=data||'{"measurement_consent_bridge":true,"measurement_websites":["https://tickets.example"]}' WHERE id=$1`,[x.unit]);
  await primary.query(`UPDATE public.forms SET is_open=true,data=data||'{"analytics":{"enabled":true}}' WHERE id=$1`,[x.form]);
  await primary.query(`INSERT INTO analytics.organization_policy(organization,meta_capi_enabled,enabled,revision,operator,reason)
    VALUES($1,true,true,1,'fixture','publisher rehearsal')`,[x.organization]);
  await primary.query(`INSERT INTO analytics.meta_purchase_connectors(unit,dataset,vault_secret,website_origin,enabled)
    VALUES($1,'123456',vault.create_secret(repeat('t',40)),'https://tickets.example',true)`,[x.unit]);
  await primary.query('INSERT INTO analytics.meta_purchase_forms(form,unit) VALUES($1,$2)',[x.form,x.unit]);
  await primary.query("SELECT public.purge_meta_purchase_data_internal()");
  await primary.query("SELECT set_config('request.jwt.claim.sub','',false)");
  const snapshot=await scalar(`SELECT jsonb_build_object('source','klaro',
    'websiteOrigin','https://tickets.example','consentRevision',public.unit_measurement_consent_scope_internal($1)->>'consentRevision',
    'revision',public.get_meta_purchase_consent($2)->>'revision','userAgent','Publisher rehearsal',
    'timestamp',statement_timestamp(),
    'ad_storage',true,'ad_user_data',true,'ad_personalization',true) value`,[x.unit,x.link]);
  assert(snapshot.revision,'predecessor exposes a consent revision');
  const createOrder=async label=>{
    const receipt=await scalar(`SELECT public.create_ticket_order_client_sync_v1(pg_temp.checkout($1::jsonb)||
      jsonb_build_object('metaPurchaseConsent',$2::jsonb,'email',$3::text),gen_random_uuid(),gen_random_uuid()) value`,
      [x,snapshot,label+'@example.invalid']);
    assert.equal(String(receipt.data?.code),'200');
    const id=receipt.data.order.id;
    assert((await state(id)).delivery,'predecessor captured consent');
    const txn=(await primary.query(`INSERT INTO eshop.transactions(bank_account_id,amount,currency,date,ingest_source)
      SELECT p.bank_account,100,'CZK',clock_timestamp(),'fio_api' FROM eshop.orders o
      JOIN eshop.payment_info p ON p.id=o.payment_info WHERE o.id=$1 RETURNING id,payment_info`,[id])).rows[0];
    await primary.query(`SELECT public.apply_transaction_pairing($1,(SELECT payment_info FROM eshop.orders WHERE id=$2),'manual_attach','user')`,[txn.id,id]);
    return id;
  };
  const pending=await createOrder('publisher-pending');
  const sent=await createOrder('publisher-sent');
  await primary.query("SELECT set_config('request.jwt.claim.role','service_role',false)");
  const leases=(await primary.query('SELECT * FROM public.claim_meta_purchase_deliveries(20)')).rows;
  const sentLease=leases.find(row=>String(row.order_id)===String(sent))?.lease;
  assert(sentLease);
  const prepared=await scalar('SELECT public.prepare_meta_purchase_delivery($1,$2) value',[sent,sentLease]);
  assert(prepared?.eventId);
  assert(await scalar("SELECT public.finish_meta_purchase_delivery($1,$2,'sent') value",[sent,sentLease]));
  // An interrupted worker may resume only after its prior lease has expired.
  await primary.query('UPDATE analytics.meta_purchase_deliveries SET lease_until=clock_timestamp() WHERE order_id=$1',[pending]);
  const oldPending=await state(pending);
  const oldSent=await state(sent);
  assert.equal(oldPending.delivery.status,'pending');
  assert.equal(oldSent.delivery.status,'sent');

  const legacy=await scalar(`INSERT INTO eshop.orders(occasion,price,state,data,order_symbol,order_sequence)
    VALUES($1,0,'used',jsonb_build_object('form',$2::text),public.generate_order_symbol(),public.next_order_sequence($1)) RETURNING id value`,
    [x.occasion,x.key]);
  await primary.query('UPDATE public.user_info SET organization=$1 WHERE id=$2',[x.organization,x.actor]);
  await primary.query('INSERT INTO public.occasion_users(occasion,"user",is_editor_view) VALUES($1,$2,true) ON CONFLICT(occasion,"user") DO UPDATE SET is_editor_view=true',[x.occasion,x.actor]);
  await primary.query("SELECT set_config('request.jwt.claim.sub',$1,false),set_config('request.jwt.claim.role','authenticated',false)",[x.actor]);
  const link=await scalar('SELECT link value FROM public.occasions WHERE id=$1',[x.occasion]);
  const stats=async()=>scalar("SELECT f->'stats' value FROM jsonb_array_elements(public.get_forms_by_link($1)) f WHERE f->>'id'=$2",[link,String(x.form)]);
  const before=await stats();
  const readers=['public.get_forms_by_link(text)','public.get_all_viewable_forms_for_copying()',
    'public.get_all_forms(text)','public.get_all_occasions_for_edit_v182(bigint)',
    'public.get_form_catalog_rows_internal(bigint,bigint,integer)'];
  const rollback=(await primary.query('SELECT pg_get_functiondef(signature::regprocedure) ddl FROM unnest($1::text[]) signature',[readers])).rows;
  const catalogMigration=read('supabase/migrations/20261121101000_order_catalog_counts.sql');
  const catalogPreflight=execFileSync('python3',[
    fileURLToPath(new URL('../../../automation/form_catalog_preflight.py',import.meta.url)),
  ],{encoding:'utf8'});
  const catalogAudit=async()=>(await primary.query(catalogPreflight)).rows[0];
  await primary.query('BEGIN READ ONLY');
  assert.deepEqual(await catalogAudit(),{legacy_missing:'1',conflicts:'0'});
  await primary.query('ROLLBACK');

  await primary.query(read('supabase/migrations/20261121020000_self_service_meta_capi.sql'));
  await primary.query(read('supabase/migrations/20261121100000_form_measurement_publisher.sql'));
  assert.deepEqual(await state(pending),oldPending);
  assert.deepEqual(await state(sent),oldSent);
  assert.equal(await scalar("SELECT to_regprocedure('public.record_form_paid_conversion_internal(bigint)') value"),null);
  for(const signature of ['bigint','bigint,boolean']) {
    assert.equal(await scalar("SELECT to_regprocedure('public.record_form_conversion_internal('||$1||')') value",[signature]),null);
  }

  // Reconciliation blocks a conflicting non-null relation, without affecting the rest of the upgrade.
  await primary.query('BEGIN');
  await primary.query('SAVEPOINT conflicting_catalog_fixture');
  const otherForm=await scalar("INSERT INTO public.forms(occasion,title) VALUES($1,'Other form') RETURNING id value",[x.occasion]);
  await primary.query('UPDATE eshop.orders SET form=$2 WHERE id=$1',[legacy,otherForm]);
  assert.deepEqual(await catalogAudit(),{legacy_missing:'0',conflicts:'1'});
  await assert.rejects(primary.query(catalogMigration),/requires reconciliation of 1 order\/form conflicts/);
  await primary.query('ROLLBACK TO SAVEPOINT conflicting_catalog_fixture');
  await primary.query("INSERT INTO public.forms(occasion,key,title) VALUES($1,$2,'Ambiguous in the same occasion')",[x.occasion,x.key]);
  await assert.rejects(primary.query(catalogMigration),/requires reconciliation of 3 order\/form conflicts/);
  await primary.query('ROLLBACK TO SAVEPOINT conflicting_catalog_fixture');
  await primary.query("UPDATE eshop.orders SET data=jsonb_build_object('form',gen_random_uuid()) WHERE id=$1",[legacy]);
  await assert.rejects(primary.query(catalogMigration),/requires reconciliation of 1 order\/form conflicts/);
  await primary.query('ROLLBACK TO SAVEPOINT conflicting_catalog_fixture');
  const otherOccasion=await scalar(`INSERT INTO public.occasions(organization,unit,title,start_time,end_time,link)
    VALUES($1,$2,'Different scope',now(),now(),'publisher-rehearsal-other') RETURNING id value`,[x.organization,x.unit]);
  await primary.query("INSERT INTO public.forms(occasion,key,title) VALUES($1,$2,'Same UUID in a different occasion')",[otherOccasion,x.key]);
  await primary.query(catalogMigration);
  await primary.query('COMMIT');
  assert.equal(String(await scalar('SELECT form value FROM eshop.orders WHERE id=$1',[legacy])),String(x.form));
  assert.deepEqual(await catalogAudit(),{legacy_missing:'0',conflicts:'0'});
  assert.deepEqual(await stats(),before);
  for(const row of rollback)await primary.query(row.ddl);
  assert.deepEqual(await stats(),before);
  assert.deepEqual(await state(sent),oldSent);
  assert.deepEqual(await state(pending),oldPending);
  await primary.query(catalogMigration);
  assert.deepEqual(await stats(),before);
  await primary.query("SELECT set_config('request.jwt.claim.sub','',false),set_config('request.jwt.claim.role','service_role',false)");
  const next=(await primary.query('SELECT * FROM public.claim_meta_purchase_deliveries(20)')).rows;
  assert(!next.some(row=>String(row.order_id)===String(sent)),'sent delivery stays terminal after report rollback');
  const nextLease=next.find(row=>String(row.order_id)===String(pending))?.lease;
  assert(nextLease);
  const again=await scalar('SELECT public.prepare_meta_purchase_delivery($1,$2) value',[pending,nextLease]);
  assert.equal(again?.eventId,oldPending.facts.find(f=>f.kind==='order_fully_paid').event_id);

  const query="SELECT public.publish_form_measurement_event_internal('checkout_finalized',$1) value";
  await primary.query('BEGIN');
  const id=await scalar(query,[legacy]);
  assert(id);
  const race=scalar(query,[legacy],contender);
  // Observe the second transaction waiting on the real unique index, not a serial replay.
  let blocked=false;
  for(let attempt=0;attempt<100&&!blocked;attempt++){
    blocked=await scalar(`SELECT coalesce(bool_or(wait_event_type='Lock'),false) value
      FROM pg_stat_activity WHERE application_name='publisher-rehearsal-contender' AND datname=current_database()`);
    if(!blocked)await sleep(25);
  }
  await primary.query('COMMIT');
  assert.equal(await race,id);
  assert(blocked,'the contender must reach the insert before the first transaction commits');
  assert.equal(await scalar('SELECT count(*)::int value FROM analytics.conversion_facts WHERE "order"=$1',[legacy]),1);
  console.log('PASS predecessor upgrade, stable identities and terminal delivery, historical repair, reader rollback, concurrent replay');
} finally {
  await primary.query('ROLLBACK').catch(()=>{});
  await primary.end();
  await contender.end();
}
