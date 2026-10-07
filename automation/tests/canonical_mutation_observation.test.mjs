import assert from 'node:assert/strict';
import test from 'node:test';
import fs from 'node:fs';
import {createRequire} from 'node:module';
import {MutationObservationSummary} from '../client-sync/summarize_mutation_observation.mjs';
const requestId='12345678-1234-1234-1234-123456789abc';
const actor='87654321-4321-4321-4321-cba987654321';
const observe=value=>'2026-10-07 LOG: FESTAPP_MUTATION_OBSERVATION '+JSON.stringify(value);
const operation=fs.readFileSync(new URL('../../database/operations/canonical_mutation_observation.sql',import.meta.url),'utf8');
async function disposable() {
 const url=new URL(process.env.DATABASE_URL);
 assert.equal(url.hostname,'127.0.0.1');assert.equal(url.port,'55452');assert.equal(url.pathname,'/postgres');
 const require=createRequire(new URL('../../web_client/package.json',import.meta.url));
 const client=new (require('pg').Client)({connectionString:process.env.DATABASE_URL});
 await client.connect();
 try {
  assert.equal((await client.query('SELECT project FROM festapp_test_support.disposable_environment WHERE singleton')).rows[0].project,'festapp-canonical-mutation-pg15');
  await client.query('BEGIN');return client;
 } catch(error) {await client.end();throw error;}
}
test('observation export excludes tokens, bodies, query strings and raw actor IDs',()=>{
 const s=new MutationObservationSummary();
 s.consume(observe({schemaVersion:1,event:'request',requestId,pid:42,actor,role:'authenticated',method:'POST',path:'/rpc/save_user_group_client_sync_v1',declaredBuild:'619',declaredVersion:'0.20.135',declaredPlatform:'web',authorization:'secret-token',body:'private-body'}));
 s.consume(observe({schemaVersion:1,event:'scope',requestId,pid:42,occasion:12}));
 s.consume(JSON.stringify({ts:123,status:204,request:{uri:'/rest/v1/rpc/delete_occasion_user_ws?user=secret-user',method:'POST',headers:{Authorization:'secret-token'},body:'private-body'}}));
 s.consume('LOG: AUDIT: SESSION,1,1,WRITE,INSERT,TABLE,public.activity_history,private-body,secret-token');
 const result=s.result(),output=JSON.stringify(result);
 for(const forbidden of ['secret-token','private-body','secret-user',actor])assert.ok(!output.includes(forbidden));
 assert.equal(result.gateway.legacySuccesses,1);
 assert.equal(result.database.scopes[0].occasion,12);
 assert.match(result.database.requests[0].actorSha256,/^[a-f0-9]{64}$/);
 assert.equal(result.database.auditRecords,1);
 assert.equal(result.g3Satisfied,false);
});
test('unknown metadata and incomplete retention never become zero-traffic proof',()=>{
 const s=new MutationObservationSummary();
 s.consume(observe({schemaVersion:1,event:'request',requestId,pid:42,actor,role:'authenticated',method:'POST',path:'/activity_history?token=private',declaredBuild:'619\nforged',declaredVersion:'private',declaredPlatform:'private'}));
 s.consume('FESTAPP_MUTATION_OBSERVATION malformed-secret');
 const result=s.result();
 assert.equal(result.database.unidentifiableWrites,1);
 assert.equal(result.database.rejectedObservationRecords,1);
 assert.equal(result.database.requests[0].path,'unidentified');
 assert.equal(result.coverageComplete,false);
 assert.ok(!JSON.stringify(result).includes('private'));
});
test('observation activates redacted logging without changing registry or effective ACL',{skip:!process.env.DATABASE_URL},async()=>{
 const client=await disposable();
 try {
  const snapshot=async()=> (await client.query(`SELECT jsonb_build_object(
   'registry',(SELECT jsonb_agg(to_jsonb(s) ORDER BY component,source_relation) FROM public.client_sync_component_sources s),
   'acl',(SELECT jsonb_agg(jsonb_build_object('table',c.oid::regclass::text,'acl',c.relacl) ORDER BY c.oid) FROM pg_class c WHERE c.oid=ANY(ARRAY['public.activity_history','public.user_groups','public.places']::regclass[]))) value`)).rows[0].value;
  const before=await snapshot();await client.query(operation);
  const settings=(await client.query("SELECT c FROM pg_db_role_setting s CROSS JOIN LATERAL unnest(s.setconfig) c WHERE s.setrole='authenticator'::regrole AND s.setdatabase=(SELECT oid FROM pg_database WHERE datname=current_database())")).rows.map(r=>r.c);
  assert.ok(settings.includes('pgrst.db_pre_request=public.log_canonical_mutation_request_v1'));
  assert.ok(settings.includes('pgaudit.log_statement=off'));
  assert.equal((await client.query("SELECT current_setting('pgaudit.log_parameter') value")).rows[0].value,'off');
  assert.deepEqual(await snapshot(),before);
 } finally {await client.query('ROLLBACK');await client.end();}
});
test('observation fails closed instead of replacing an existing request hook',{skip:!process.env.DATABASE_URL},async()=>{
 const client=await disposable();
 try {
  await client.query("ALTER ROLE authenticator IN DATABASE postgres SET pgrst.db_pre_request TO 'public.existing_security_hook'");
  await client.query('SAVEPOINT existing_hook');
  await assert.rejects(client.query(operation),/existing pre-request hook/);
  await client.query('ROLLBACK TO SAVEPOINT existing_hook');
  const rows=(await client.query("SELECT c FROM pg_db_role_setting s CROSS JOIN LATERAL unnest(s.setconfig) c WHERE s.setrole='authenticator'::regrole AND s.setdatabase=(SELECT oid FROM pg_database WHERE datname=current_database()) AND c LIKE 'pgrst.db_pre_request=%'")).rows;
  assert.equal(rows[0].c,'pgrst.db_pre_request=public.existing_security_hook');
 } finally {await client.query('ROLLBACK');await client.end();}
});
