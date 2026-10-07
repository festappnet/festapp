import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {createRequire} from 'node:module';
const require=createRequire(new URL('../../web_client/package.json',import.meta.url));
const {Client}=require('pg');
const source=fs.readFileSync(new URL('../../database/registry/canonical_mutation_registry.sql',import.meta.url),'utf8');
async function disposable() {
 const target=new URL(process.env.DATABASE_URL??'http://missing');
 assert.equal(target.hostname,'127.0.0.1');assert.equal(target.port,'55452');assert.equal(target.pathname,'/postgres');
 const client=new Client({connectionString:target.href});await client.connect();
 assert.equal((await client.query('SELECT project FROM festapp_test_support.disposable_environment WHERE singleton')).rows[0].project,'festapp-canonical-mutation-pg15');
 await client.query('BEGIN');return client;
}
test('active shared readiness rejects the slice before changing registry rows',async()=>{
 const client=await disposable();
 try {
  await client.query("UPDATE public.client_sync_component_sources SET cutover_ready=true");
  await client.query("INSERT INTO public.occasions(organization,unit,title,link,start_time,end_time,data) SELECT organization,id,'Registry guard','registry-guard',now(),now()+interval '1 day','{\"client_sync_v1\":true}'::jsonb FROM public.units LIMIT 1");
  const before=(await client.query('SELECT jsonb_agg(to_jsonb(s) ORDER BY component,source_relation) rows FROM public.client_sync_component_sources s')).rows[0].rows;
  await client.query('SAVEPOINT active_guard');
  await assert.rejects(client.query(source),/active shared registry/);
  await client.query('ROLLBACK TO SAVEPOINT active_guard');
  const after=(await client.query('SELECT jsonb_agg(to_jsonb(s) ORDER BY component,source_relation) rows FROM public.client_sync_component_sources s')).rows[0].rows;
  assert.deepEqual(after,before);
 } finally {await client.query('ROLLBACK');await client.end();}
});
test('inactive baseline accepts additive metadata without enabling readiness',async()=>{
 const client=await disposable();
 try {
  await client.query("UPDATE public.occasions SET data=coalesce(data,'{}'::jsonb)||'{\"client_sync_v1\":false}'::jsonb");
  await client.query(source);
  assert.equal((await client.query("SELECT cutover_ready FROM public.client_sync_component_sources WHERE component='private_profile' AND source_relation='public.places'::regclass")).rows[0].cutover_ready,false);
 } finally {await client.query('ROLLBACK');await client.end();}
});
