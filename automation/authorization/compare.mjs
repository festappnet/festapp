import { createHash } from 'node:crypto';
// Alternating paired measurements with identical transaction-local fixtures.
import { readFile, writeFile } from 'node:fs/promises';
import { connect,fixture,measure,executionContract } from './benchmark.mjs';
const root=new URL('../../',import.meta.url);
const folder=new URL('docs/plans/evidence/canonical-authorization-20261020/',root);
const before=await readFile(new URL('baseline.sql',folder),'utf8');
const migrationFile=await readFile(new URL('supabase/migrations/20261021100000_canonical_authorization.sql',root),'utf8');
const after=migrationFile.replace(/^BEGIN;$/m,'').replace(/^COMMIT;$/m,'');
const output=process.argv[2]??'performance-final.json';
if(!/^[a-z0-9-]+\.json$/.test(output)) throw new Error('Invalid output name');
const sampleCount=Number(process.env.AUTHZ_PERF_SAMPLES??25);
if(!Number.isInteger(sampleCount)||sampleCount<20||sampleCount>1000) throw new Error('Invalid sample count');
const selected=process.env.AUTHZ_PERF_WORKLOADS?.split(',');
const hash=s=>createHash('sha256').update(s).digest('hex');
const db=await connect();const result={sampleCount,executionContracts:{},selectedWorkloads:selected??'all',baselineSha256:hash(before),migrationFileSha256:hash(migrationFile),transactionSqlSha256:hash(after),harnessSha256:hash(await readFile(new URL('automation/authorization/benchmark.mjs',root),'utf8')),fixtureBoundary:'identical transaction-local actor, resource IDs, rows and statistics across A/B pairs',coldBoundary:'fresh SQL function/connection state only; OS/shared-buffer caches are not flushed',sourceHead:'ce77a1e40057841bff9abe9f28ba0a4f0c4510dd',server:(await db.query('select version()')).rows[0].version,blocks:[]};
try {for(const n of [8,1000]) {
    await db.query('BEGIN');
    const bankCount=n===8?4:50;
    const f=await fixture(db,n,bankCount);
    // Reuse the exact actor, resource IDs, rows and statistics in every A/B
    // pair. Only function/policy definitions change inside the savepoint.
    try {for(let round=0;round<4;round++) for(const variant of round%2?['after','before']:['before','after']) {
        await db.query('SAVEPOINT variant');
        await db.query(variant==='before'?before:after);
        if(!result.executionContracts[variant]) result.executionContracts[variant]=await executionContract(db);
        result.blocks.push({round,variant,occasions:n,places:50,unitMemberships:1,occasionMemberships:n,bankMemberships:bankCount,results:await measure(db,f,sampleCount,selected)});
        await db.query('ROLLBACK TO SAVEPOINT variant');
        await db.query('RELEASE SAVEPOINT variant');
        await writeFile(new URL(output,folder),JSON.stringify(result,null,2)+'\n');
        console.log(`${n} occasions, round ${round+1}, ${variant} measured`);
    }} finally {await db.query('ROLLBACK');}
}} finally {await db.end();}
