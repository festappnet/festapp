import test from 'node:test';
import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {randomUUID} from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import {fileURLToPath} from 'node:url';
import pg from 'pg';
import {assertLocalDatabaseUrl,assertDisposableDatabase} from './disposable_database.js';
const execute=promisify(execFile);
const root=fileURLToPath(new URL('../../../',import.meta.url));
const runner=path.join(root,'web_client/scripts/run_db_tests.js');

async function withProbe(run) {
  assert.ok(process.env.DATABASE_URL,'An owned disposable workspace is required');
  assertLocalDatabaseUrl(process.env.DATABASE_URL);
  const db=new pg.Client({connectionString:process.env.DATABASE_URL});await db.connect();
  const suffix=randomUUID().replaceAll('-','');const files=[];
  const directory=await fs.mkdtemp(path.join(os.tmpdir(),'festapp-sql-runner-'));
  async function source(index,sql) {
    const file=path.join(root,'database/tests',`runtime_${suffix}_${index}_test.sql`);
    await fs.writeFile(file,sql);files.push(file);return file;
  }
  try {await assertDisposableDatabase(db);await run({db,source,directory,suffix});}
  finally {await db.end();await Promise.all(files.map(file=>fs.rm(file,{force:true})));await fs.rm(directory,{recursive:true,force:true});}
}

test('SQL diagnostic retry retains first-attempt failure as a failing gate',async()=>withProbe(async({db,source,directory,suffix})=>{
 const sequence='festapp_test_support.retry_'+suffix;
 await db.query('CREATE SEQUENCE '+sequence);
 const file=await source(0,`DO $$ BEGIN IF nextval('${sequence}')=1 THEN RAISE EXCEPTION 'first attempt probe'; END IF; END $$;`);
 const trace=path.join(directory,'timings.jsonl');
 try {
  let failure;
  try {await execute(process.execPath,[runner,file,'--diagnostic-retry'],{cwd:root,env:{...process.env,FESTAPP_TIMINGS:trace,FESTAPP_SQL_CONCURRENCY:'1'}});}
  catch(error){failure=error;}
  assert.equal(failure?.code,1,'a recovered diagnostic retry must not turn the gate green');
  const events=(await fs.readFile(trace,'utf8')).trim().split('\n').map(JSON.parse);
  const attempts=events.filter(event=>event.name==='sql.file');
  assert.deepEqual(attempts.map(({attempt,success})=>({attempt,success})),[{attempt:1,success:false},{attempt:2,success:true}]);
 } finally {await db.query('DROP SEQUENCE '+sequence);}
}));

test('reused SQL connection resets role, session GUC, temp objects and advisory locks after COMMIT',async()=>withProbe(async({db,source,suffix})=>{
 const table='festapp_test_support.pool_'+suffix;await db.query('CREATE TABLE '+table+'(pid int)');
 const first=await source(0,`INSERT INTO ${table} VALUES(pg_backend_pid()); SELECT pg_advisory_lock(813789); CREATE TEMP TABLE runtime_pool_probe(id int); COMMIT; SET work_mem='11MB'; SET ROLE authenticated;`);
 const second=await source(1,`DO $$ BEGIN
 IF current_user<>'postgres' OR current_setting('work_mem')='11MB' OR to_regclass('pg_temp.runtime_pool_probe') IS NOT NULL
 OR EXISTS(SELECT 1 FROM pg_locks WHERE pid=pg_backend_pid() AND locktype='advisory')
 OR pg_backend_pid()<>(SELECT pid FROM ${table}) THEN RAISE EXCEPTION 'pool session was dirty or not reused'; END IF; END $$;`);
 try {
  const result=await execute(process.execPath,[runner,first,second],{cwd:root,env:{...process.env,FESTAPP_SQL_CONCURRENCY:'1'}});
  assert.match(result.stdout,/SUMMARY: 2 Passed, 0 Failed/);
 } finally {await db.query('DROP TABLE '+table);}
}));

test('unknown SQL selection fails instead of reporting an empty successful gate',async()=>{
 let failure;
 try {await execute(process.execPath,[runner,'database/tests/nonexistent-'+randomUUID()],{cwd:root,env:process.env});}
 catch(error){failure=error;}
 assert.equal(failure?.code,1);assert.match(failure.stderr,/selection is empty/);
});
