import test from 'node:test';
import {readHistoricalSql} from '../../../automation/lib/historical_sql.mjs';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {readFileSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
const require=createRequire(new URL('../../../web_client/package.json',import.meta.url));
const {Client}=require('pg');
const connectionString=process.env.DATABASE_URL;
assert.equal(new URL(connectionString).hostname,'127.0.0.1');
assert.equal(new URL(connectionString).port,'55562');
const root=new URL('../../../',import.meta.url);
const read=p=>readFileSync(new URL(p,root),'utf8');
const manifest=JSON.parse(read('database/functions/security/server_security_acl_manifest.json'));
const db=new Client({connectionString});
await db.connect();
const q=(s,p=[])=>db.query(s,p);
const one=async(s,p=[]) => (await q(s,p)).rows[0];
let ids;
async function role(name,actor,fn){
 await q("SELECT set_config('request.jwt.claim.sub',$1,true),set_config('request.jwt.claim.role',$2,true),set_config('request.jwt.claims',$3,true)",[actor||'',name,JSON.stringify({role:name,...(actor?{sub:actor}:{})})]);
 await q(`SET LOCAL ROLE ${name}`);
 try{return await fn();}finally{await q('RESET ROLE').catch(()=>{});}
}
async function denied(fn,code='42501'){
 await q('SAVEPOINT denied');
 let error;
 try{await fn();}catch(e){error=e;}finally{await q('ROLLBACK TO SAVEPOINT denied');}
 assert.equal(error?.code,code,error?.message||'operation unexpectedly succeeded');
}
try{
 await q('BEGIN');
 assert.match((await one('SHOW server_version')).server_version,/^17\./);
 assert.match((await one('SELECT project FROM festapp_test_support.disposable_environment')).project,/^festapp-security-/);
 ids={actor:(await one('SELECT gen_random_uuid() AS id')).id,outsider:(await one('SELECT gen_random_uuid() AS id')).id,org:[],occ:[],pool:[],ctx:[],res:[],slot:[],spot:[]};
 for(let i=0;i<2;i++){
  ids.org.push((await one("INSERT INTO public.organizations(title) VALUES('Security fixture') RETURNING id")).id);
  const unit=(await one("INSERT INTO public.units(title,organization) VALUES('Fixture',$1) RETURNING id",[ids.org[i]])).id;
  ids.occ.push((await one("INSERT INTO public.occasions(title,link,organization,unit,start_time,end_time) VALUES('Fixture',gen_random_uuid()::text,$1,$2,now(),now()+interval '1 day') RETURNING id",[ids.org[i],unit])).id);
  ids.pool.push((await one("INSERT INTO public.inventory_pools(title,occasion) VALUES('Fixture',$1) RETURNING id",[ids.occ[i]])).id);
  ids.ctx.push((await one('INSERT INTO public.inventory_contexts(inventory_pool) VALUES($1) RETURNING id',[ids.pool[i]])).id);
  ids.res.push((await one("INSERT INTO public.resources(title,inventory_pool,occasion,capacity) VALUES('Fixture',$1,$2,1) RETURNING id",[ids.pool[i],ids.occ[i]])).id);
  ids.slot.push((await one('INSERT INTO public.resource_slots(resource) VALUES($1) RETURNING id',[ids.res[i]])).id);
  ids.spot.push((await one('INSERT INTO eshop.spots(occasion,inventory_context) VALUES($1,$2) RETURNING id',[ids.occ[i],ids.ctx[i]])).id);
 }
 for(const actor of [ids.actor,ids.outsider]){
  await q("INSERT INTO auth.users(id,email) VALUES($1::uuid,$1::text||'@fixture.invalid')",[actor]);
  await q("INSERT INTO public.user_info(id,name,organization,email_readonly) VALUES($1::uuid,'Fixture',$2,$1::text||'@fixture.invalid')",[actor,ids.org[0]]);
 }
 await q('INSERT INTO public.occasion_users(occasion,"user",is_editor_order) VALUES($1,$2,true)',[ids.occ[0],ids.actor]);
 const change=(i=0,extra={})=>({resource_id:ids.res[i],resource_slot_id:ids.slot[i],inventory_context_id:ids.ctx[i],new_spot_id:ids.spot[i],...extra});
 const assign=changes=>q('SELECT public.update_spot_assignments($1::jsonb)',[JSON.stringify(changes)]);
 await test('pre-fix batch reproduces cross-tenant write, then rolls back',async()=>{
  await q('SAVEPOINT old_body');
  const old=execFileSync('git',['show','a95067e26d7b1d17009fa6100145708750833133:database/functions/inventory/update_spots_assignments.sql'],{cwd:new URL('../../../',import.meta.url),encoding:'utf8'});
  await q(old);
  await role('authenticated',ids.actor,()=>assign([change(),change(1)]));
  assert.equal((await one('SELECT count(*)::int n FROM eshop.spots WHERE id=ANY($1) AND resource IS NOT NULL',[ids.spot])).n,2);
  await q('ROLLBACK TO SAVEPOINT old_body');
 });
 await test('NULL permission result fails closed',async()=>{
  await q('SAVEPOINT null_permission');
  await q('CREATE OR REPLACE FUNCTION public.get_is_editor_order_on_occasion(oc bigint) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$ SELECT NULL::boolean $$');
  await denied(()=>role('authenticated',ids.actor,()=>assign([change()])));
  await q('ROLLBACK TO SAVEPOINT null_permission');
 });
 await test('legacy RPCs and sender absent, including all overloads',async()=>{
  assert.equal((await one("SELECT count(*)::int n FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname=ANY($1)",[manifest.retired_rpc_names])).n,0);
 });
 await test('containment closes PUBLIC inheritance on legacy definitions before retirement',async()=>{
  await q('SAVEPOINT pre');
  const baseline=readHistoricalSql('supabase/baseline/20260805230000_production_schema.sql');
  for(const name of ['migrate_users_to_org','update_spot','apply_allocations_claim_only']){
   const start=baseline.indexOf(`CREATE OR REPLACE FUNCTION "public"."${name}"(`);
   assert(start>=0,name);
   const end=baseline.indexOf('$$;',start)+3;
   await q(baseline.slice(start,end));
   const args=name==='update_spot'?'jsonb':'bigint';
   await q(`GRANT EXECUTE ON FUNCTION public.${name}(${args}) TO PUBLIC,anon,authenticated`);
   assert.equal((await one("SELECT has_function_privilege('anon',$1,'EXECUTE') allowed",[`public.${name}(${args})`])).allowed,true);
  }
  await q(read('supabase/migrations/20261016170000_server_security_containment.sql'));
  for(const name of ['migrate_users_to_org','update_spot','apply_allocations_claim_only']){
   const arg=name==='update_spot'?"'{}'::jsonb":'0::bigint';
   for(const r of ['anon','authenticated']) await denied(()=>role(r,null,()=>q(`SELECT public.${name}(${arg})`)));
  }
  await q('ROLLBACK TO SAVEPOINT pre');
 });
 await test('anon, NULL subject and outsider denied without writes',async()=>{
  for(const [r,u] of [['anon',null],['authenticated',null],['authenticated',ids.outsider]]) await denied(()=>role(r,u,()=>assign([change()])));
  assert.equal((await one('SELECT resource FROM eshop.spots WHERE id=$1',[ids.spot[0]])).resource,null);
 });
 await test('every batch resource, spot, context and slot checked; mixed batch rolls back',async()=>{
  for(const changes of [[change(),change(1)],[change(0,{new_spot_id:ids.spot[1]})],[change(0,{old_spot_id:ids.spot[1]})],[change(0,{inventory_context_id:ids.ctx[1]})],[change(0,{inventory_context_id:null})],[change(0,{resource_slot_id:ids.slot[1]})],[change(0,{resource_id:null})]]){
   await denied(()=>role('authenticated',ids.actor,()=>assign(changes)));
   assert.equal((await one('SELECT count(*)::int n FROM eshop.spots WHERE id=ANY($1) AND resource IS NOT NULL',[ids.spot])).n,0);
  }
 });
 await test('authorized assignment and unassignment preserve scope',async()=>{
  await role('authenticated',ids.actor,()=>assign([change()]));
  assert.equal((await one('SELECT resource FROM eshop.spots WHERE id=$1',[ids.spot[0]])).resource,ids.res[0]);
  await role('authenticated',ids.actor,()=>assign([change(0,{old_spot_id:ids.spot[0],new_spot_id:null})]));
  assert.equal((await one('SELECT resource FROM eshop.spots WHERE id=$1',[ids.spot[0]])).resource,null);
 });
 await test('capacity rejection rolls back preceding writes',async()=>{
  const extra=(await one('INSERT INTO eshop.spots(occasion,inventory_context) VALUES($1,$2) RETURNING id',[ids.occ[0],ids.ctx[0]])).id;
  await denied(()=>role('authenticated',ids.actor,()=>assign([change(),change(0,{new_spot_id:extra})])),'23514');
  assert.equal((await one('SELECT count(*)::int n FROM eshop.spots WHERE resource=$1',[ids.res[0]])).n,0);
 });
 await test('sync client CRUD denied for every table, service upserts work',async()=>{
  for(const table of manifest.sync_tables){
   for(const r of ['anon','authenticated']){
    for(const sql of [`SELECT * FROM public.${table}`,`DELETE FROM public.${table}`,`UPDATE public.${table} SET source_name=source_name`,`INSERT INTO public.${table} DEFAULT VALUES`]) await denied(()=>role(r,ids.actor,()=>q(sql)));
    assert.equal((await one("SELECT has_table_privilege($1,$2,'TRUNCATE') allowed",[r,`public.${table}`])).allowed,false);
   }
  }
  for(const table of manifest.sync_tables) assert.equal((await one("SELECT has_table_privilege('service_role',$1,'TRUNCATE') allowed",['public.'+table])).allowed,false);
  await role('service_role',null,async()=>{
   await q("INSERT INTO public.external_sync_sources(source_name,supabase_url,anon_key) VALUES('security-test','https://example.invalid','fixture') ON CONFLICT(source_name) DO UPDATE SET anon_key=excluded.anon_key");
   await q("INSERT INTO public.external_sync_maps(source_name,target_org_id,target_unit_id,remote_link_base) VALUES('security-test',$1,0,'fixture')",[ids.org[0]]);
   await q("INSERT INTO public.external_occasions_cache(source_name,external_id,link) VALUES('security-test',1,'security-fixture') ON CONFLICT(source_name,external_id) DO UPDATE SET last_synced_at=now()");
  });
 });
 await test('live catalog drift gate rejects PUBLIC grant despite unchanged ledger',async()=>{
  await q(read('automation/hetzner-supabase/runtime/audit-security-state.sql'));
  await q('SAVEPOINT drift');
  await q('GRANT SELECT ON public.external_sync_sources TO PUBLIC');
  await denied(()=>q(read('automation/hetzner-supabase/runtime/audit-security-state.sql')),'P0001');
  await q('ROLLBACK TO SAVEPOINT drift');
 });
}finally{await q('ROLLBACK');await db.end();}
