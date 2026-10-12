import test from 'node:test';import assert from 'node:assert/strict';import fs from 'node:fs';import {createRequire} from 'node:module';
const require=createRequire(new URL('../../web_client/package.json',import.meta.url));const {Client}=require('pg');const operation=fs.readFileSync(new URL('../../database/operations/canonical_mutation_editor_pause.sql',import.meta.url),'utf8');const reopen=fs.readFileSync(new URL('../../database/operations/canonical_mutation_editor_reopen.sql',import.meta.url),'utf8');const manifest=JSON.parse(fs.readFileSync(new URL('../../docs/plans/evidence/canonical-mutation-editor-pause-manifest.json',import.meta.url),'utf8'));
test('shared pause and reopening keep old/direct writers denied and preserve readers, service and registry',async()=>{
 const url=new URL(process.env.DATABASE_URL);assert.equal(url.hostname,'127.0.0.1');assert.equal(url.port,'55452');assert.equal(url.pathname,'/postgres');const c=new Client({connectionString:url.href});await c.connect();
 try {assert.equal((await c.query('SELECT project FROM festapp_test_support.disposable_environment WHERE singleton')).rows[0].project,'festapp-canonical-mutation-pg15');await c.query('BEGIN');
 const snapshot=async()=> (await c.query(`SELECT jsonb_build_object('registry',(SELECT jsonb_agg(to_jsonb(s) ORDER BY component,source_relation) FROM public.client_sync_component_sources s),'functions',(SELECT jsonb_agg(jsonb_build_object('signature',s,'body',md5(p.prosrc),'service',has_function_privilege('service_role',p.oid,'EXECUTE'))) FROM unnest($1::text[]) s JOIN pg_proc p ON p.oid=to_regprocedure('public.'||s)),'tables',(SELECT jsonb_agg(jsonb_build_object('table',t,'serviceInsert',has_table_privilege('service_role','public.'||t,'INSERT'),'serviceDelete',has_table_privilege('service_role','public.'||t,'DELETE'),'serviceUpdate',has_table_privilege('service_role','public.'||t,'UPDATE'),'read',has_table_privilege('authenticated','public.'||t,'SELECT'))) FROM unnest($2::text[]) t)) value`,[[...manifest.legacySignatures,...manifest.pausedCanonicalSignatures],manifest.tables])).rows[0].value;
 const before=await snapshot();
 await c.query('SAVEPOINT premature_reopen');await assert.rejects(c.query(reopen),/expected paused CSM build-620 gate/);await c.query('ROLLBACK TO SAVEPOINT premature_reopen');
 await c.query('CREATE ROLE festapp_disposable_pause_inherited');await c.query('GRANT festapp_disposable_pause_inherited TO anon,authenticated');
 for(const table of manifest.tables) await c.query('GRANT INSERT,UPDATE,DELETE,TRUNCATE ON public.'+table+' TO festapp_disposable_pause_inherited');
 for(const signature of [...manifest.legacySignatures,...manifest.pausedCanonicalSignatures]) await c.query('GRANT EXECUTE ON FUNCTION public.'+signature+' TO festapp_disposable_pause_inherited');
 await c.query(operation);
 await c.query('SAVEPOINT unsafe_reopen');await c.query('GRANT EXECUTE ON FUNCTION public.save_activity_history(bigint,jsonb,text,bigint,text) TO authenticated');await assert.rejects(c.query(reopen),/old writer still reachable/);await c.query('ROLLBACK TO SAVEPOINT unsafe_reopen');
 assert.deepEqual(await snapshot(),before);
 for(const role of ['anon','authenticated']) {
  for(const signature of [...manifest.legacySignatures,...manifest.pausedCanonicalSignatures]) assert.equal((await c.query("SELECT has_function_privilege($1,to_regprocedure('public.'||$2),'EXECUTE') ok",[role,signature])).rows[0].ok,false,role+' '+signature);
  assert.equal((await c.query("SELECT has_function_privilege($1,'public.update_activities(bigint)','EXECUTE') ok",[role])).rows[0].ok,(await c.query("SELECT true ok")).rows[0].ok);
  for(const table of manifest.tables) {assert.equal((await c.query("SELECT has_table_privilege($1,'public.'||$2,'INSERT,UPDATE,DELETE,TRUNCATE') OR has_any_column_privilege($1,'public.'||$2,'INSERT,UPDATE') ok",[role,table])).rows[0].ok,false);
   await c.query('SAVEPOINT denied');await c.query('SET LOCAL ROLE '+role);await assert.rejects(c.query('DELETE FROM public.'+table+' WHERE false'),e=>e.code==='42501');await c.query('ROLLBACK TO SAVEPOINT denied');
  }
  await c.query('SAVEPOINT rpc_denied');await c.query('SET LOCAL ROLE '+role);await assert.rejects(c.query('SELECT public.save_activity_history(NULL,NULL,NULL,NULL,NULL)'),e=>e.code==='42501'&&e.message.includes('function'));await c.query('ROLLBACK TO SAVEPOINT rpc_denied');
 }
 await c.query(reopen);
 for(const signature of manifest.pausedCanonicalSignatures) assert.equal((await c.query("SELECT has_function_privilege('authenticated',to_regprocedure('public.'||$1),'EXECUTE') ok",[signature])).rows[0].ok,true);
 for(const signature of manifest.legacySignatures) assert.equal((await c.query("SELECT has_function_privilege('authenticated',to_regprocedure('public.'||$1),'EXECUTE') ok",[signature])).rows[0].ok,false);
 assert.equal((await c.query('SELECT paused FROM public.canonical_mutation_write_release_gate WHERE singleton')).rows[0].paused,false);
 assert.deepEqual(await snapshot(),before);
 }finally{await c.query('ROLLBACK');await c.end();}
});
