import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync,mkdtempSync,rmSync,mkdirSync,copyFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
const root=fileURLToPath(new URL('../../',import.meta.url));
import {spawnSync} from 'node:child_process';
const run=(...args)=>spawnSync('python3',['automation/assemble-notification-center-migration.py',...args],{encoding:'utf8',cwd:root});
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
  const manifest=JSON.parse(readFileSync(join(root,'automation/notification-center-feed-manifest.json'),'utf8'));
  const script='automation/assemble-notification-center-migration.py';
  const files=[script,'automation/notification-center-feed-manifest.json',manifest.output,
   ...manifest.prerequisites.map(name=>'supabase/migrations/'+name),
   ...manifest.sources.map(name=>'database/functions/'+name),
   'database/tables/tables.sql','database/functions/notification_center/schema.sql',
   'database/functions/notification_center/maintenance.sql'];
  for(const file of new Set(files)) {
   const target=join(dir,file);mkdirSync(dirname(target),{recursive:true});copyFileSync(join(root,file),target);
  }
  const source=join(dir,'database/functions/notification_center/center_policy.sql');
  writeFileSync(source,readFileSync(source,'utf8')+'\n-- Later source edit\n');
  const output=join(dir,manifest.output),before=readFileSync(output);
  const result=spawnSync('python3',[script],{cwd:dir,encoding:'utf8'});
  assert.notEqual(result.status,0);
  assert.match(result.stderr,/Refusing to overwrite an existing different output/);
  assert.deepEqual(readFileSync(output),before);
 } finally {rmSync(dir,{recursive:true});}
});
