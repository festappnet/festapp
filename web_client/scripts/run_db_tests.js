import pg from 'pg';
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import {globSync} from 'glob';
import {selectSqlTests} from './db_test_selection.mjs';
import {runWorkers} from './sql_worker_pool.mjs';
import {timed,emitTiming} from './test_timings.mjs';
import {assertLocalDatabaseUrl,assertDisposableDatabase} from '../tests/database/disposable_database.js';

const ROOT=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..');
const args=process.argv.slice(2);
// Explicit CLI filters and groups use the same canonical workspace owner as CI.
if (!process.env.DATABASE_URL) {
  const result=spawnSync('python3',[path.join(ROOT,'automation/local_db/runtime.py'),'exec','--',process.execPath,fileURLToPath(import.meta.url),...args],{stdio:'inherit',env:process.env});
  process.exit(result.status??1);
}
assertLocalDatabaseUrl(process.env.DATABASE_URL);
const contract=JSON.parse(fs.readFileSync(path.join(ROOT,'automation/ci/checks.json'),'utf8'));
let filters=[];
for(let i=0;i<args.length;i++) {
  if(args[i]==='--group') {
    const name=args[++i];
    if(!contract.sqlGroups?.[name]) throw new Error('Unknown SQL group: '+name);
    filters.push(...contract.sqlGroups[name].filters);
  } else if(!args[i].startsWith('--')) filters.push(args[i]);
  else if(!['--list','--diagnostic-retry'].includes(args[i])) throw new Error('Unknown SQL option: '+args[i]);
}
const files=selectSqlTests(globSync(path.join(ROOT,'database/tests/**/*_test.sql')),filters,ROOT).sort();
const testId=file=>path.relative(ROOT,file);
const concurrency=Number(process.env.FESTAPP_SQL_CONCURRENCY??'2');
if(!Number.isInteger(concurrency)||concurrency<1||concurrency>8) throw new Error('SQL concurrency must be an integer 1-8');
emitTiming('sql.inventory',performance.now(),{testIds:files.map(testId),filters,node:process.version,concurrency});
if(!files.length) {console.error('SQL selection is empty');process.exit(1);}
if(args.includes('--list')) {console.log(files.map(testId).join('\n'));process.exit(0);}
const pool=new pg.Pool({connectionString:process.env.DATABASE_URL,ssl:false,max:concurrency,
  connectionTimeoutMillis:5000,lock_timeout:5000,statement_timeout:30000,query_timeout:35000});
const read=relative=>fs.readFileSync(path.join(ROOT,relative),'utf8');
const assertionSource=read('database/tests/helpers/assertions.sql');
const sessionBlock=/-- session-setup-start\n([\s\S]*?)-- session-setup-end\n/;
const sessionAssertions=assertionSource.match(sessionBlock)?.[1];
if(!sessionAssertions) throw new Error('Missing session assertion helper boundary');
const assertions=assertionSource.replace(sessionBlock,'');
const scanning=read('database/tests/scanning/fixture.sql');
const setups=new Map(files.map(file=>[file,[...read(testId(file)).matchAll(/^-- test-setup: (database\/[\w./-]+\.sql)$/gm)].map(match=>match[1])]));
const sharedSetups=new Set(contract.sqlSharedSetups);
let poolFailure=false;
pool.on('error',error=>{poolFailure=true;console.error('Idle SQL connection failed: '+error.message);});

async function runTest(file,attempt=1) {
  const id=testId(file);const started=performance.now();let client;let success=false;let dirty=false;
  const notice=msg=>{
    if(msg.message.startsWith('TEST_TIMING ')) {
      try {emitTiming('sql.server-phase',performance.now(),{testId:id,...JSON.parse(msg.message.slice(12))});} catch {console.error('Malformed test timing notice: '+id);}
    } else if(process.env.FESTAPP_SQL_NOTICES==='1') console.log('  [NOTICE] '+msg.message);
  };
  try {
    client=await timed('sql.connection',()=>pool.connect(),{testId:id,attempt});
    client.on('notice',notice);
    await client.query("SELECT set_config('application_name',$1,false)",[id]);
    await client.query("SET statement_timeout='30s'; SET lock_timeout='5s'");
    if(id.startsWith('database/tests/notification_center/')) {
      await timed('sql.advisory-lock',()=>client.query('SELECT pg_advisory_lock(5831290471284)'),{testId:id,attempt});
    }
    await client.query('BEGIN');
    await timed('sql.fixture',async()=>{
      await client.query(sessionAssertions);
      for(const source of setups.get(file)) {
        if(!path.resolve(ROOT,source).startsWith(path.join(ROOT,'database')+path.sep)) throw new Error('SQL setup escaped database directory');
        if(!sharedSetups.has(source)) await client.query(read(source));
      }
    },{testId:id,attempt});
    // Sample server waits without recording query text. Includes monolithic DO fixtures.
    let observing=false;const waits={};const blockers={};
    const sample=async()=>{
      if(observing) return;observing=true;
      try {
        // A spare observer connection is intentionally separate from the worker pool.
        const rows=await observer.query('SELECT wait_event_type,wait_event,pg_blocking_pids(pid) blockers FROM pg_stat_activity WHERE pid=$1',[client.processID]);
        const row=rows.rows[0];const key=row?.wait_event_type?(row.wait_event_type+':'+row.wait_event):'executing';
        waits[key]=(waits[key]??0)+1;
        if(row?.blockers?.length) {
          const names=await observer.query('SELECT application_name FROM pg_stat_activity WHERE pid=ANY($1)',[row.blockers]);
          for(const blocker of names.rows) blockers[blocker.application_name]=(blockers[blocker.application_name]??0)+1;
        }
      } catch { /* The final query/connection verdict remains authoritative. */ }
      finally {observing=false;}
    };
    const interval=setInterval(sample,100);
    try {await timed('sql.body',()=>client.query(read(id)),{testId:id,attempt});}
    finally {clearInterval(interval);emitTiming('sql.wait-samples',performance.now(),{testId:id,attempt,sampleIntervalMs:100,samples:waits,blockers});}
    success=true;
  } catch(error) {
    dirty=true;
    console.error(`FAIL ${id}: ${error.message}`);
    if(error.where) console.error(error.where);
  } finally {
    if(client) {
      try {
        await timed('sql.session-cleanup',async()=>{
          await client.query('ROLLBACK');
          await client.query('RESET ROLE; RESET SESSION AUTHORIZATION');
          await client.query('DISCARD ALL');
        },{testId:id,attempt});
      } catch(error) {dirty=true;success=false;console.error('SQL session cleanup failed: '+id+': '+error.message);}
      client.removeListener('notice',notice);
      client.release(dirty);
    }
    emitTiming('sql.file',started,{testId:id,attempt,success});
  }
  if(success) console.log(`PASS ${id} (${Math.round(performance.now()-started)} ms)`);
  return {file,success,attempt};
}
const observer=new pg.Client({connectionString:process.env.DATABASE_URL,connectionTimeoutMillis:5000,statement_timeout:1000,query_timeout:2000});
const resource=file=>[...new Set([
  ...Object.entries(contract.sqlSerialResources).filter(([prefix])=>testId(file).startsWith(prefix)).map(([,claim])=>claim),
  ...Object.entries(contract.sqlSetupResources).filter(([prefix])=>setups.get(file).some(source=>source.startsWith(prefix))).map(([,claim])=>claim),
])];
async function main() {
  const started=performance.now();let results=[];const retries=[];
  try {
    await observer.connect();
    const setup=await pool.connect();
    try {
      await assertDisposableDatabase(setup);
      await timed('sql.shared-helpers',()=>setup.query(assertions+'\n'+scanning));
      for(const source of sharedSetups) {
        if([...setups.values()].some(paths=>paths.includes(source))) await timed('sql.shared-setup',()=>setup.query(read(source)),{source});
      }
      await timed('sql.sequence-maintenance',()=>setup.query(read('database/tests/helpers/reset_owned_sequences.sql')));
    } finally {setup.release();}
    console.log(`SQL inventory: ${files.length} files, ${concurrency} workers`);
    results=await runWorkers(files,concurrency,file=>runTest(file),resource,file=>contract.sqlExclusiveTests.includes(testId(file)));
    if(args.includes('--diagnostic-retry')) {
      for(const {file} of results.filter(result=>!result.success)) retries.push(await runTest(file,2));
    }
    const failures=results.filter(result=>!result.success).map(({file})=>testId(file));
    emitTiming('sql.result',started,{testIds:files.map(testId),firstAttemptFailures:failures,
      diagnosticRetries:retries.map(result=>({testId:testId(result.file),success:result.success})),success:!failures.length&&!poolFailure});
    console.log(`SUMMARY: ${results.length-failures.length} Passed, ${failures.length} Failed (first attempt)`);
    return failures.length||poolFailure?1:0;
  } finally {await pool.end();await observer.end();}
}
try {process.exitCode=await main();} catch(error) {console.error(error.message);process.exitCode=1;}
