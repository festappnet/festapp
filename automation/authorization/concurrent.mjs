import {evidenceDirectory} from './evidence.mjs';
// Paired four-client SQL load on committed synthetic fixtures in our own DB.
import {readFile,writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {performance} from 'node:perf_hooks';
import {connect,fixture,workloads,executionContract,verifyWorkload} from './benchmark.mjs';
const root=new URL('../../',import.meta.url);
const folder=await evidenceDirectory('baseline.sql');
const baseline=await readFile(new URL('baseline.sql',folder),'utf8');
const migration=await readFile(new URL('supabase/migrations/20261021100000_canonical_authorization.sql',root),'utf8');
const after=migration.replace(/^BEGIN;$/m,'').replace(/^COMMIT;$/m,'');
const hash=s=>createHash('sha256').update(s).digest('hex');
const sampleCount=Number(process.env.AUTHZ_PERF_SAMPLES??20);
if(!Number.isInteger(sampleCount)||sampleCount<20||sampleCount>1000) throw new Error('Invalid sample count');
const selected=process.env.AUTHZ_PERF_WORKLOADS?.split(',');
const output=process.env.AUTHZ_PERF_OUTPUT??'performance-concurrent.json';
if(!/^[a-z0-9-]+\.json$/.test(output)) throw new Error('Invalid output name');
const result={executionContracts:{},sampleCount,warmupSamples:3,selectedWorkloads:selected??'all',baselineSha256:hash(baseline),migrationFileSha256:hash(migration),clients:4,
    coldBoundary:'fresh client connections; shared buffers and OS cache are warm',blocks:[]};
const admin=await connect();
try {for(const n of [8,1000]) {
    const bankCount=n===8?4:50;
    await admin.query('BEGIN');const f=await fixture(admin,n,bankCount);await admin.query('COMMIT');
    for(let round=0;round<3;round++) for(const variant of round%2?['after','before']:['before','after']) {
        await admin.query('BEGIN');await admin.query(variant==='before'?baseline:after);await admin.query('COMMIT');
        if(!result.executionContracts[variant]) result.executionContracts[variant]=await executionContract(admin);
        const clients=await Promise.all(Array.from({length:4},()=>connect()));
        const block={round,variant,occasions:n,bankMemberships:bankCount,results:{}};
        try {
            await Promise.all(clients.map(async db=>{
                await db.query('BEGIN');
                await db.query("select set_config('request.jwt.claim.sub',$1,true),set_config('request.jwt.claim.role','authenticated',true),set_config('festapp.email_wake','scheduled',true)",[f.actor]);
                await db.query('SET LOCAL ROLE authenticated');
            }));
            for(const [i,[name]] of workloads(f).entries()) {
                if(selected&&!selected.includes(name)) continue;
                const coldConnectionSamplesMs=[];
                const start=performance.now();
                const samples=(await Promise.all(clients.map(async db=>{
                    const [,sql,args]=workloads(f)[i];const times=[];
                    for(let sample=0;sample<sampleCount+3;sample++) {
                        await db.query('SAVEPOINT workload');
                        const begin=performance.now();const response=await db.query(sql,args);const elapsed=performance.now()-begin;
                        verifyWorkload(name,response,f);
                        if(sample<3)coldConnectionSamplesMs.push(elapsed);else times.push(elapsed);
                        await db.query('ROLLBACK TO SAVEPOINT workload');await db.query('RELEASE SAVEPOINT workload');
                    }
                    return times;
                }))).flat();
                const elapsed=performance.now()-start,sorted=samples.toSorted((a,b)=>a-b);
                block.results[name]={coldConnectionSamplesMs,samplesMs:samples,p50:sorted[Math.floor(sorted.length*.5)],p95:sorted[Math.ceil(sorted.length*.95)-1],throughputPerSecond:1000*samples.length/elapsed,rpcCount:1};
            }
        } finally {await Promise.all(clients.map(async db=>{await db.query('ROLLBACK');await db.end();}));}
        result.blocks.push(block);
        await writeFile(new URL(output,folder),JSON.stringify(result,null,2)+'\n');
        console.log(`${n} occasions, round ${round+1}, ${variant}, four clients measured`);
    }
}} finally {
    // Always restore the current authored contract, including after failure.
    await admin.query('ROLLBACK');await admin.query(after);await admin.end();
}
