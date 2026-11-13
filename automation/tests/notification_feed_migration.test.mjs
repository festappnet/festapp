import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync,mkdtempSync,rmSync,mkdirSync,copyFileSync} from '../lib/migration_inputs.mjs';
import {tmpdir} from 'node:os';
import {join,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
const root=fileURLToPath(new URL('../../',import.meta.url));
import {spawnSync} from 'node:child_process';
const run=(...args)=>spawnSync('python3',['automation/assemble-admin-notification-delivery-migration.py',...args],{encoding:'utf8',cwd:root});
test('forward assembler checks canonical tables without rewriting historical notification migration',()=>{
 const path=join(root,'supabase/migrations/20261024010000_organization_notification_center.sql'),before=readFileSync(path);
 assert.equal(run('--check').status,0);assert.deepEqual(readFileSync(path),before);
 const blocked=run('--output',path);assert.notEqual(blocked.status,0);assert.deepEqual(readFileSync(path),before);
});
test('explicit output refuses an existing different artifact',()=>{
 const dir=mkdtempSync(join(tmpdir(),'notification-feed-'));try{
  const path=join(dir,'migration.sql');writeFileSync(path,'foreign content');assert.notEqual(run('--output',path).status,0);assert.equal(readFileSync(path,'utf8'),'foreign content');
 }finally{rmSync(dir,{recursive:true});}
});
test('default output cannot rewrite a published migration after source changes',()=>{
 const dir=mkdtempSync(join(tmpdir(),'notification-default-'));
 try {
  const manifest=JSON.parse(readFileSync(join(root,'automation/admin-notification-delivery-manifest.json'),'utf8'));
  const script='automation/assemble-admin-notification-delivery-migration.py';
  const files=[script,'automation/migration-forward-owners.json','automation/migration_forward_owners.py','automation/generate_canonical_source_contract.py','automation/migration_inputs.py','automation/baseline.py','automation/historical_inputs.py','automation/admin-notification-delivery-manifest.json',manifest.output,
   ...manifest.prerequisites.map(name=>'supabase/migrations/'+name),
   ...manifest.sources.map(name=>'database/functions/'+name),
   'database/functions/abuse/seeds.sql',
   'database/tables/tables.sql','database/functions/notification_center/schema.sql',
   'database/functions/notification_center/maintenance.sql',
   'database/functions/notification_center/prepared_schema.sql'];
  const forwards=JSON.parse(readFileSync(join(root,'automation/migration-forward-owners.json'),'utf8')).migrations
   .filter(entry=>entry.migration>manifest.output.split('/').at(-1));
  for(const entry of forwards){
   if(entry.manifest)files.push('automation/'+entry.manifest);
   files.push('supabase/migrations/'+entry.migration);
  }
  for(const file of new Set(files)) {
   const target=join(dir,file);mkdirSync(dirname(target),{recursive:true});copyFileSync(join(root,file),target);
  }
  const source=join(dir,'database/functions/'+manifest.sources[0]);
  writeFileSync(source,readFileSync(source,'utf8')+'\n-- Later source edit\n');
  const output=join(dir,manifest.output),before=readFileSync(output);
  const ownership=join(dir,'automation/migration-forward-owners.json'),ownerBefore=readFileSync(ownership);
  const result=spawnSync('python3',[script],{cwd:dir,encoding:'utf8'});
  assert.notEqual(result.status,0);
  assert.match(result.stderr,/Refusing to overwrite a different migration/);
  assert.deepEqual(readFileSync(output),before);
  assert.deepEqual(readFileSync(ownership),ownerBefore);
 } finally {rmSync(dir,{recursive:true});}
});

test('assembled prerequisite rejects a missing canonical scope owner', {skip: !process.env.DATABASE_URL}, async()=>{
 const {createRequire}=await import('node:module');
 const {assertLocalDatabaseUrl,assertDisposableDatabase}=await import('../../web_client/tests/database/disposable_database.js');
 assertLocalDatabaseUrl(process.env.DATABASE_URL);
 const {Client}=createRequire(new URL('../../web_client/package.json',import.meta.url))('pg');
 const db=new Client({connectionString:process.env.DATABASE_URL});await db.connect();
 try{
  await assertDisposableDatabase(db);await db.query('BEGIN');
  const manifest=JSON.parse(readFileSync(join(root,'automation/admin-notification-delivery-manifest.json'),'utf8'));
  const guard=readFileSync(join(root,manifest.output),'utf8').match(/DO \$\$ BEGIN[\s\S]*?END \$\$;/)[0];
  await db.query('ALTER FUNCTION public.notification_center_prepared_scope(bigint,jsonb) RENAME TO notification_scope_missing_fixture');
  await assert.rejects(db.query(guard), /admin_notification_prerequisites_missing/);
 }finally{await db.query('ROLLBACK');await db.end();}
});
