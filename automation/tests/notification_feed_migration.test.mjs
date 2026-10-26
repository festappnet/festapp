import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync,mkdtempSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
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
