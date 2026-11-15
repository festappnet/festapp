import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createRequire} from 'node:module';
import {assertLocalDatabaseUrl,assertDisposableDatabase} from '../../../web_client/tests/database/disposable_database.js';
const require=createRequire(new URL('../../../web_client/package.json',import.meta.url));
const {Client}=require('pg');
assertLocalDatabaseUrl(process.env.DATABASE_URL);
const clients=Array.from({length:2},()=>new Client({connectionString:process.env.DATABASE_URL}));
for(const c of clients){await c.connect();await assertDisposableDatabase(c);await c.query("SET request.jwt.claim.role='service_role'; SET lock_timeout='5s'");}
const [a,b]=clients;
const scalar=async(c,sql,params=[]) => (await c.query(sql,params)).rows[0].v;
let org,unit;
try {
 org=await scalar(a,"INSERT INTO public.organizations(title) VALUES('Consent concurrency') RETURNING id v");
 unit=await scalar(a,`INSERT INTO public.units(title,organization,data) VALUES('Consent concurrency',$1,'{"measurement_websites":["https://website.example"]}') RETURNING id v`,[org]);
 const actor=await scalar(a,'SELECT id v FROM auth.users ORDER BY id LIMIT 1');
 await a.query('INSERT INTO public.unit_users(unit,"user",is_manager) VALUES($1,$2,true)',[unit,actor]);
 for(const c of clients)await c.query("SELECT set_config('request.jwt.claim.sub',$1,false),set_config('request.jwt.claim.role','authenticated',false)",[actor]);
 const scope=await scalar(a,'SELECT public.get_unit_website_consent_bindings($1) v',[unit]);
 const save=(c,version,revision=scope.consentRevision)=>scalar(c,`SELECT public.save_unit_website_consent_binding($1,'https://website.example','wordpress','{"provider":"complianz","policyId":"42"}',$2,$3,true) v`,[unit,version,revision]);
 await test('concurrent confirmations serialize and cannot silently overwrite',async()=>{
  const results=await Promise.allSettled([save(a,0),save(b,0)]);
  assert.equal(results.filter(r=>r.status==='fulfilled').length,1);
  assert.equal(results.find(r=>r.status==='rejected').reason.code,'40001');
  const data=await scalar(a,'SELECT public.get_unit_website_consent_bindings($1) v',[unit]);
  assert.equal(data.bindings.length,1);assert.equal(data.bindings[0].version,1);
 });
 await test('provider cleanup preserves existing confirmed binding and scope',async()=>{
  const source=readFileSync(new URL('../../../supabase/migrations/20261115210000_website_consent_live_provider_state.sql',import.meta.url),'utf8');
  await a.query('BEGIN');
  try {
   await a.query(`UPDATE analytics.website_consent_bindings SET provider_config='{"provider":"complianz","policyId":"42","cbid":"obsolete","revision":42,"consentValidFrom":"2026-01-01T00:00:00.000Z","maxAgeSeconds":86400}' WHERE unit=$1`,[unit]);
   const before=await scalar(a,'SELECT to_jsonb(b) v FROM analytics.website_consent_bindings b WHERE unit=$1',[unit]);
   assert.equal(before.enabled,true);assert.equal(before.confirmed_revision,scope.consentRevision);
   assert.ok(before.confirmed_by);assert.ok(before.confirmed_at);
   await a.query(source);await a.query(source);
   const after=await scalar(a,'SELECT to_jsonb(b) v FROM analytics.website_consent_bindings b WHERE unit=$1',[unit]);
   assert.deepEqual(after,{...before,provider_config:{provider:'complianz'}});
   assert.equal((await scalar(a,'SELECT public.unit_measurement_consent_scope_internal($1) v',[unit])).consentRevision,scope.consentRevision);
  } finally {await a.query('ROLLBACK');}
 });
 await test('confirmation waits for Unit save and rejects the superseded semantic revision',async()=>{
  await a.query('BEGIN');
  await a.query(`UPDATE public.units SET data=data||'{"measurement_consent_version":2}' WHERE id=$1`,[unit]);
  let settled=false;
  const pending=save(b,1).then(()=>({ok:true}),error=>({error})).finally(()=>settled=true);
  await new Promise(r=>setTimeout(r,30));assert.equal(settled,false);
  await a.query('COMMIT');
  assert.equal((await pending).error.code,'40001');
 });
 await test('forward migration reapplies transactionally without changing existing binding or semantic revision',async()=>{
  const source=readFileSync(new URL('../../../supabase/migrations/20261114170000_website_consent_bindings.sql',import.meta.url),'utf8');
  assert.equal(source.split('\n')[1],'BEGIN;');assert.match(source,/COMMIT;\s*$/);
  const body=source.replace(/^BEGIN;\n/m,'').replace(/COMMIT;\s*$/,'');
  const snapshot=await scalar(a,'SELECT to_jsonb(b) v FROM analytics.website_consent_bindings b WHERE unit=$1',[unit]);
  const before=await scalar(a,'SELECT public.unit_measurement_consent_scope_internal($1) v',[unit]);
  await a.query('BEGIN');
  try {
   await a.query(body);await a.query(body);
   assert.deepEqual(await scalar(a,'SELECT to_jsonb(b) v FROM analytics.website_consent_bindings b WHERE unit=$1',[unit]),snapshot);
   assert.deepEqual(await scalar(a,'SELECT public.unit_measurement_consent_scope_internal($1) v',[unit]),before);
  } finally {await a.query('ROLLBACK');}
 });

} finally {
 await a.query('ROLLBACK');
 if(unit) {await a.query('DELETE FROM analytics.website_consent_bindings WHERE unit=$1',[unit]);await a.query('DELETE FROM public.unit_users WHERE unit=$1',[unit]);await a.query('DELETE FROM public.units WHERE id=$1',[unit]);}
 if(org)await a.query('DELETE FROM public.organizations WHERE id=$1',[org]);
 for(const c of clients)await c.end();
}
