import {evidenceDirectory} from './evidence.mjs';
// First domain request on a fresh PostgreSQL backend, sequential and four-way.
// Only the marker-verified local DB; OS/shared buffers deliberately stay warm.
import {readFile,writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {performance} from 'node:perf_hooks';
import assert from 'node:assert/strict';
import {connect,fixture,executionContract} from './benchmark.mjs';
const root=new URL('../../',import.meta.url),folder=await evidenceDirectory('baseline.sql');
const baseline=await readFile(new URL('baseline.sql',folder),'utf8');
const migration=await readFile(new URL('supabase/migrations/20261021100000_canonical_authorization.sql',root),'utf8');
const after=migration.replace(/^BEGIN;$/m,'').replace(/^COMMIT;$/m,'');
const hash=s=>createHash('sha256').update(s).digest('hex');
const filename=process.argv[2]??'performance-first-request-controlled.json';
if(!/^[a-z0-9-]+\.json$/.test(filename))throw new Error('Invalid evidence filename');
const output={boundary:'Exactly one first domain request per fresh PostgreSQL connection; identity/role setup and marker probes precede it; shared buffers and OS cache are warm',
 baselineSha256:hash(baseline),migrationSha256:hash(migration),harnessSha256:hash(await readFile(new URL('automation/authorization/cold.mjs',root),'utf8')),executionContracts:{},blocks:[]};
const admin=await connect();
async function first(f,ready=null) {
 const db=await connect();
 try {
  await db.query('BEGIN');
  await db.query("select set_config('request.jwt.claim.sub',$1,true),set_config('request.jwt.claim.role','authenticated',true)",[f.actor]);
  await db.query('SET LOCAL ROLE authenticated');
  if(ready) await ready();
  const start=performance.now();
  const response=await db.query('select public.get_app_config_v218($1::jsonb) result',[JSON.stringify({organization:f.org,link:f.link,platform:{platform:'web'}})]);
  const elapsed=performance.now()-start;assert.equal(response.rows[0].result.code,200);
  return elapsed;
 }finally{await db.query('ROLLBACK');await db.end();}
}
try {
 for(const size of [8,1000]) {
  await admin.query('BEGIN');const f=await fixture(admin,size,size===8?4:50);await admin.query('COMMIT');
  for(let round=0;round<6;round++) for(const variant of round%2?['after','before']:['before','after']) {
   await admin.query('BEGIN');await admin.query(variant==='before'?baseline:after);await admin.query('COMMIT');
   const index=(await admin.query("select to_regclass('public.occasions_unit_start_time_authorization_idx') is not null present")).rows[0].present;
   assert.equal(index,variant==='after','Before must not inherit the new index');
   if(!output.executionContracts[variant])output.executionContracts[variant]=await executionContract(admin);
   const sequential=[];for(let i=0;i<16;i++)sequential.push(await first(f));
   const concurrent=[];
   for(let wave=0;wave<4;wave++) {
    let arrivals=0,release;const gate=new Promise(resolve=>{release=resolve;});
    const ready=()=>{if(++arrivals===4)release();return gate;};
    concurrent.push(...await Promise.all(Array.from({length:4},()=>first(f,ready))));
   }
   output.blocks.push({size,round,variant,indexPresent:index,sequentialMs:sequential,concurrentMs:concurrent,rpcCount:1});
   await writeFile(new URL(filename,folder),JSON.stringify(output,null,2)+'\n');
   console.log(`${size} occasions, round ${round+1}, ${variant}: first requests measured`);
  }
 }
}finally{await admin.query('ROLLBACK');await admin.query(after);await admin.end();}
