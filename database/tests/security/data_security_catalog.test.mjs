import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import pg from '../../../web_client/node_modules/pg/lib/index.js';
const url = new URL(process.env.DATABASE_URL ?? 'missing:');
assert.equal(url.hostname,'127.0.0.1');
assert(['55462','56922'].includes(url.port));
const root = new URL('../../../',import.meta.url);
const read = p=>fs.readFileSync(new URL(p,root),'utf8');
const manifest=JSON.parse(read('database/functions/security/server_security_acl_manifest.json'));
const db=new pg.Client({connectionString:url.href});
await db.connect();
assert(['festapp-data-security-20261018','festapp-data-security-e2e-20261018'].includes((await db.query('select project from festapp_test_support.disposable_environment')).rows[0].project));
test.after(()=>db.end());
test('effective ACLs match data-security entrypoint contracts',async()=>{
 const mismatches=[];
 for(const [signature,roles] of Object.entries(manifest.entrypoints)) {
  if(['public.update_spot_assignments(jsonb)','public.add_sync_map(text,bigint,bigint,text,bigint,bigint)'].includes(signature))continue;
  for(const [role,allowed] of Object.entries(roles)) {
   const r=await db.query('select has_function_privilege($1,$2,\'EXECUTE\') allowed',[role,signature]);
   if(r.rows[0].allowed!==allowed)mismatches.push(role+' '+signature+': '+r.rows[0].allowed);
  }
 }
 assert.deepEqual(mismatches,[]);
});
test('runtime audit passes and detects grant, policy and default drift',async()=>{
 const audit=read('automation/hetzner-supabase/runtime/audit-data-security-state.sql');
 await db.query('BEGIN READ ONLY');
 try {await db.query(audit);} finally {await db.query('ROLLBACK');}
 for(const drift of [
   'GRANT SELECT ON public.email_templates TO authenticated',
   'CREATE POLICY injected_data_security_leak ON public.user_groups FOR SELECT TO authenticated USING(true)',
   'ALTER DEFAULT PRIVILEGES FOR ROLE postgres GRANT EXECUTE ON FUNCTIONS TO PUBLIC',
 ]) {
  await db.query('BEGIN');
  try {await db.query(drift);await assert.rejects(db.query(audit),/drift/);} finally {await db.query('ROLLBACK');}
 }
});
