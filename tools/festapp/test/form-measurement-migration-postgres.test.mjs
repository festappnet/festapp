import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from '../../../automation/lib/migration_inputs_async.mjs';
import {options,setup,create} from './form-fixtures.mjs';
const sql=name=>readFile(new URL('../../../'+name,import.meta.url),'utf8');
const migration=await sql('supabase/migrations/20261106100000_form_measurement_policy.sql');

test('legacy PR upgrades into one Unit configuration default-off, relocates private tables and reapplies safely',options,async t=>{
 const {db,f}=await setup(t);const made=await create(db,f);
 const old={gtm_container:'GTM-AB12',scripts:'<script>LEGACY_MEASUREMENT_733</script>',enhanced_conversions:false};
 await db.query('update forms set data=$1 where id=$2',[{analytics:old},made.formId]);
 // Exercise an installation at the original PR, inside the rollback fixture.
 await db.query('drop table analytics.conversion_facts');await db.query('drop table analytics.unit_runtime');await db.query('drop table analytics.organization_policy');
 await db.query('drop function public.form_measurement_write_rule(boolean,boolean)');
 await db.query(await sql('supabase/migrations/20261106090000_form_measurement.sql'));
 for(let pass=0;pass<2;pass++){
  await db.query(migration);
  const row=(await db.query('select data,form_measurement_status_internal(id) status,get_effective_form_data(id) runtime from forms where id=$1',[made.formId])).rows[0];
  assert.deepEqual(row.data.analytics,{enabled:false});assert.equal(row.status.requested_enabled,false);assert.equal(row.status.eligible,false);assert.equal(row.status.runtime_supported,false);
  const unit=(await db.query('select data from units where id=$1',[f.unit])).rows[0].data;
  assert.equal(unit.measurement_gtm_container,old.gtm_container);assert.equal(unit.measurement_scripts,old.scripts);assert.notEqual(unit.measurement_enabled,true);
  assert(!JSON.stringify(row.runtime).includes('LEGACY_MEASUREMENT_733'));assert(!JSON.stringify(row.runtime).includes('GTM-AB12'));
  assert.equal((await db.query('select count(*)::int n from analytics.conversion_facts')).rows[0].n,0);
  assert.equal((await db.query("select to_regclass('public.form_measurement_organization_policy') is null retired")).rows[0].retired,true);
  for(const role of ['anon','authenticated','service_role'])assert.equal((await db.query("select has_schema_privilege($1,'analytics','USAGE') allowed",[role])).rows[0].allowed,false);
 }
});

test('ambiguous Unit migration fails atomically and preserves every original configuration',options,async t=>{
 const {db,f}=await setup(t),first=await create(db,f),second=await create(db,f);
 await db.query("update forms set data=jsonb_build_object('analytics',jsonb_build_object('gtm_container',case when id=$1 then 'GTM-AAAA' else 'GTM-BBBB' end)) where id=any($2)",[first.formId,[first.formId,second.formId]]);
 const before=(await db.query('select id,data from forms where id=any($1) order by id',[[first.formId,second.formId]])).rows;
 await db.query('SAVEPOINT preflight');await assert.rejects(db.query(migration),error=>error.message.includes('Conflicting legacy measurement destinations'));
 await db.query('ROLLBACK TO SAVEPOINT preflight');
 assert.deepEqual((await db.query('select id,data from forms where id=any($1) order by id',[[first.formId,second.formId]])).rows,before);
 assert.equal((await db.query('select data from units where id=$1',[f.unit])).rows[0].data?.measurement_gtm_container,undefined);
});

test('legacy enhanced preparation requires reconciliation rather than silent deletion',options,async t=>{
 const {db,f:scope}=await setup(t);const made=await create(db,scope);const f={id:made.formId};
await db.query("update forms set data='{\"analytics\":{\"enhanced_conversions\":true}}' where id=$1",[f.id]);
 await db.query('SAVEPOINT preflight');await assert.rejects(db.query(migration),error=>error.message.includes('enhanced-conversion preparation'));
 await db.query('ROLLBACK TO SAVEPOINT preflight');
 assert.equal((await db.query('select data from forms where id=$1',[f.id])).rows[0].data.analytics.enhanced_conversions,true);
});

// A missing version row is a real version zero, not permission to overwrite the move.
test('legacy Unit snapshot at version zero cannot erase migrated destination',options,async t=>{
 const {db,f}=await setup(t);const made=await create(db,f);
 const oldUnit=(await db.query('select data from units where id=$1',[f.unit])).rows[0].data;
 await db.query("delete from client_aggregate_versions where aggregate_type='unit' and scope_id=$1",[f.unit]);
 await db.query("update forms set data='{\"analytics\":{\"gtm_container\":\"GTM-AB12\"}}' where id=$1",[made.formId]);
 await db.query(migration);
 const result=(await db.query("select save_unit_client_sync_v1($1,gen_random_uuid(),0,$2) value",[f.unit,{id:f.unit,data:oldUnit||{}}])).rows[0].value;
 assert.equal(result.code,409,JSON.stringify(result));
 assert.equal((await db.query('select data from units where id=$1',[f.unit])).rows[0].data.measurement_gtm_container,'GTM-AB12');
});

test('protocol cutover changes saved-choice identity once without changing stored configuration or facts',options,async t=>{
 const {db,f}=await setup(t);const made=await create(db,f),formId=made.formId;
 await db.query("update organizations set data=coalesce(data,'{}')||'{\"FORM_MEASUREMENT_ENABLED\":true}'::jsonb where id=$1",[f.org]);
 await db.query("update units set data=coalesce(data,'{}')||'{\"measurement_enabled\":true,\"measurement_gtm_container\":\"GTM-AB12\"}'::jsonb where id=$1",[f.unit]);
 await db.query("update forms set is_open=true,data=coalesce(data,'{}')||'{\"analytics\":{\"enabled\":true}}'::jsonb where id=$1",[formId]);
 await db.query("insert into analytics.organization_policy(organization,enabled,revision,operator,reason) values($1,true,1,'fixture','protocol migration')",[f.org]);
 await db.query("insert into analytics.unit_runtime(unit,runtime_origin,runtime_profile,parent_origins,revision,operator,reason) values($1,'https://protocol-test.pages.dev','gtm-v1',ARRAY['https://tickets.example'],1,'fixture','protocol migration')",[f.unit]);
 const order=(await db.query("insert into eshop.orders(occasion,form,state,order_symbol,order_sequence,data) values($1,$2,'ordered',generate_order_symbol(),1,'{}') returning id",[f.occasion,formId])).rows[0].id;
 await db.query("insert into analytics.conversion_facts(\"order\",kind,payload) values($1,'purchase','{\"event\":\"purchase\",\"preserved\":true}')",[order]);
 const configuration=async()=>(await db.query(`select jsonb_build_object('organization',(select to_jsonb(o) from organizations o where id=$1),
  'unit',(select to_jsonb(u) from units u where id=$2),'form',(select to_jsonb(f) from forms f where id=$3),
  'registration',(select to_jsonb(r) from analytics.unit_runtime r where unit=$2),
  'permission',(select to_jsonb(p) from analytics.organization_policy p where organization=$1),
  'facts',(select jsonb_agg(to_jsonb(c)) from analytics.conversion_facts c where "order"=$4)) value`,[f.org,f.unit,formId,order])).rows[0].value;
 const read=async()=>(await db.query('select form_measurement_runtime_internal($1) value',[formId])).rows[0].value;
 await db.query(await sql('supabase/migrations/20261107130000_form_measurement_gtm_always.sql'));
 const before=await read(),state=await configuration();assert.equal(before.measurement_protocol,undefined);assert.equal(before.eligible,true);
 const forward=await sql('supabase/migrations/20261107170000_form_measurement_protocol.sql');
 await db.query(forward);const after=await read();assert.equal(after.measurement_protocol,3);assert.notEqual(after.processing_revision,before.processing_revision);
 const {processing_revision:oldHash,...oldPolicy}=before;
 const {processing_revision:newHash,measurement_protocol,...newPolicy}=after;
 assert.deepEqual(newPolicy,oldPolicy);assert.deepEqual(await configuration(),state);
 await db.query(forward);assert.deepEqual(await read(),after);assert.deepEqual(await configuration(),state);
 const bridgeForward=await sql('supabase/migrations/20261110200000_form_measurement_consent_bridge.sql');
 await db.query(bridgeForward);const bridgePolicy=await read();
 assert.equal(bridgePolicy.measurement_consent_bridge,false);
 assert.equal(bridgePolicy.processing_revision,after.processing_revision,'default-off upgrade preserves saved-choice identity');
 assert.deepEqual(await configuration(),state,'migration preserves existing configuration and conversion facts');
 await db.query(bridgeForward);assert.deepEqual(await read(),bridgePolicy);
 await db.query("update units set data=data||'{\"measurement_consent_bridge\":false}'::jsonb where id=$1",[f.unit]);
 assert.deepEqual(await read(),bridgePolicy,'explicit false preserves the pre-bridge policy fingerprint');
 await db.query(bridgeForward);assert.deepEqual(await read(),bridgePolicy,'reapply preserves explicit false');
 await db.query("update units set data=data||'{\"measurement_consent_bridge\":true}'::jsonb where id=$1",[f.unit]);
 const optedIn=await read();assert.equal(optedIn.measurement_consent_bridge,true);
 assert.notEqual(optedIn.processing_revision,bridgePolicy.processing_revision);
 await db.query(bridgeForward);assert.deepEqual(await read(),optedIn,'reapply preserves explicit organizer opt-in');
 await db.query("update organizations set data=data||'{\"FORM_MEASUREMENT_ENABLED\":false}'::jsonb where id=$1",[f.org]);
 const disabled=await configuration();await db.query(bridgeForward);assert.equal((await read()).eligible,false);assert.deepEqual(await configuration(),disabled);
});
