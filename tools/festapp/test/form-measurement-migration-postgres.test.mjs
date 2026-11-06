import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
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
