#!/usr/bin/env node
/** Real disposable HTTP/PG qualification. Never accepts a remote target. */
import fs from 'node:fs/promises';
import crypto from 'node:crypto';
import os from 'node:os';
import {performance} from 'node:perf_hooks';
import pg from 'pg';

const project = 'festapp-blueprint-1000-e2e-20261020';
const backend = `/Users/miakh/source/${project}`;
const output = process.argv[2] || `${backend}/blueprint-1000-profile.json`;
const pool = new pg.Pool({host:'127.0.0.1',port:59722,database:'postgres',user:'postgres',password:'postgres',max:20,statement_timeout:30000});
const p95 = values => values.length ? [...values].sort((a,b)=>a-b)[Math.ceil(values.length*.95)-1] : null;
const summarize = rows => ({count:rows.length,p95Ms:p95(rows.map(row=>row.ms)),outcomes:Object.fromEntries([...new Set(rows.map(row=>row.category))].map(key=>[key,rows.filter(row=>row.category===key).length]))});
const classify = (code, reason='') => code === 200 ? 'accepted' : /deadlock/i.test(reason) ? 'deadlock' : /timeout|timed out/i.test(reason) ? 'timeout' : code === 429 || /rate|quota|limit/i.test(reason) ? 'policy_limit' : [400,403,404,409].includes(code) ? 'expected_conflict' : 'internal_error';
async function mapLimit(values, concurrency, action) {
    let cursor=0;
    const results=new Array(values.length);
    await Promise.all(Array.from({length:Math.min(concurrency,values.length)},async()=> {
        while(cursor<values.length) { const index=cursor++; results[index]=await action(values[index],index); }
    }));
    return results;
}

try {
    const config = await fs.readFile(`${backend}/supabase/config.toml`,'utf8');
    const marker = await pool.query('SELECT project FROM festapp_test_support.disposable_environment WHERE singleton');
    const defines=JSON.parse(await fs.readFile(`${backend}/private-defines.json`,'utf8'));
    if(marker.rows[0]?.project!==project || !config.includes(`project_id = "${project}"`) || !config.includes('port = 59722') || !config.includes('port = 59721') || defines.FESTAPP_SUPABASE_URL!=='http://127.0.0.1:59721') throw new Error('Exact task-owned DB/HTTP identity required');
    const fences=await pool.query('SELECT (SELECT count(*) FROM public.email_capacity WHERE NOT paused OR worker_url IS NOT NULL)+(SELECT count(*) FROM cron.job WHERE active)+(SELECT count(*) FROM eshop.external_services) AS unsafe');
    if(Number(fences.rows[0].unsafe)!==0) throw new Error('Disposable delivery/provider fences required');
    const manifest=JSON.parse(await fs.readFile(`${backend}/blueprint-1000-fixtures.json`,'utf8'));
    if(manifest.project!==project || !manifest.complete || manifest.fixtures.length!==3) throw new Error('Three complete canonical fixtures required');
    const rpc=async(name,body) => {
        const started=performance.now();
        try {
            const response=await fetch(`http://127.0.0.1:59721/rest/v1/rpc/${name}`,{method:'POST',headers:{apikey:defines.FESTAPP_SUPABASE_ANON_KEY,Authorization:`Bearer ${defines.FESTAPP_SUPABASE_ANON_KEY}`,'Content-Type':'application/json'},body:JSON.stringify(body),signal:AbortSignal.timeout(30000)});
            const raw=await response.text();
            let data;try {data=JSON.parse(raw);} catch {data={code:response.status,message:'non-json response'};}
            const code=Number(data?.code ?? response.status);
            const reason=data?.reason||data?.message||data?.error||'';
            return {ms:performance.now()-started,code,reason,category:classify(code,reason),bytes:Buffer.byteLength(raw),data};
        } catch(error) { return {ms:performance.now()-started,category:classify(500,error.name==='TimeoutError'?'timeout':error.message),reason:error.message}; }
    };
    const sourceHashes={};
    for(const path of ['../../automation/blueprint_1000_fixture.py','./blueprint_1000_profile.mjs','../../database/functions/blueprint/save.sql','../../database/functions/eshop/select_spot.sql','../../database/functions/eshop/get_blueprint.sql']) {
        sourceHashes[path]=crypto.createHash('sha256').update(await fs.readFile(new URL(path,import.meta.url))).digest('hex');
    }
    const databaseVersion=(await pool.query('SELECT version() AS version')).rows[0].version;
    const results={project,schemaVersion:manifest.schemaVersion,sourceHashes,databaseVersion,profile:{openHttpBuyerSessions:100,concurrentMutations:20,wanLatencyInjected:false,antiAbuseModified:false,sessionDefinition:'100 distinct buyer UUIDs retained through public RPC reads; this is not 100 browser windows or 100 people'},machine:{platform:os.platform(),arch:os.arch(),cpus:os.cpus().length,node:process.version},fixtures:[],startedAt:new Date().toISOString()};
    for(const f of manifest.fixtures) {
        const sessions=Array.from({length:100},()=>crypto.randomUUID());
        // All 100 identities read the exact same persisted event through anon HTTP.
        const reads=await mapLimit(sessions,20,secret=>rpc('get_blueprint',{my_secret:secret,form_key:f.formKey,blueprint_id:f.blueprint}));
        const productRows=await pool.query('SELECT id,price,currency_code FROM eshop.products WHERE occasion=$1',[f.occasion]);
        const expectedPrices=new Map(productRows.rows.map(row=>[String(row.id),row]));
        const expected=new Map(f.bindings.map(b=>[b.nodeId,String(b.spotId)]));
        for(const read of reads.filter(read=>read.code===200)) {
            const actual=read.data.data;
            if(!actual?.layout || actual.seatBindings.length!==expected.size || actual.seatBindings.some(b=>expected.get(b.nodeId)!==String(b.spotId))) throw new Error('Public stable identity readback failed');
            if(!actual.products?.length) throw new Error('Public prices missing');
            if((actual.products||[]).some(product=>{const expected=expectedPrices.get(String(product.id));return !expected||Number(product.price)!==Number(expected.price)||product.currency_code!==expected.currency_code;})) throw new Error('Public price readback mismatch');
        }
        const eligible=f.bindings.filter(binding=>!binding.blocked&&!binding.selectionUnitId&&binding.productId!=null);
        if(eligible.length<110) throw new Error('Not enough independent available fixture seats');
        // Separate successful independent seats from deliberate single-seat contention.
        const independent=await mapLimit(sessions.slice(0,20),20,(secret,index)=>rpc('select_spot',{form_key:f.formKey,secret_id:secret,spot_id:eligible[index+40].spotId,selecting:true}));
        const contested=await mapLimit(sessions.slice(20,40),20,secret=>rpc('select_spot',{form_key:f.formKey,secret_id:secret,spot_id:eligible[80].spotId,selecting:true}));
        // Release only holds actually accepted under the same buyer identity.
        const releases=[];
        for(let i=0;i<independent.length;i++) if(independent[i].code===200) releases.push([sessions[i],eligible[i+40].spotId]);
        for(let i=0;i<contested.length;i++) if(contested[i].code===200) releases.push([sessions[i+20],eligible[80].spotId]);
        const cleanup=await mapLimit(releases,20,([secret,spot])=>rpc('select_spot',{form_key:f.formKey,secret_id:secret,spot_id:spot,selecting:false}));
        const policy=await pool.query("SELECT public.abuse_effective_rules_v1('spot.hold',unit,organization) AS hold, public.abuse_effective_rules_v1('hold.duration',unit,organization) AS duration FROM public.occasions WHERE id=$1",[f.occasion]);
        const sqlSamples=[];
        for(let i=0;i<5;i++) {
            const connection=await pool.connect();
            try {
                await connection.query('BEGIN');
                await connection.query("SELECT set_config('request.jwt.claim.role','anon',true)");
                await connection.query('SET LOCAL ROLE anon');
                const probeSecret=crypto.randomUUID();
                const start=performance.now();
                const explain=await connection.query('EXPLAIN (ANALYZE, FORMAT JSON) SELECT public.select_spot($1::uuid,$2::uuid,$3::bigint,true)',[f.formKey,probeSecret,eligible[100+i].spotId]);
                const plan=explain.rows[0]['QUERY PLAN'][0];
                const pgMs=performance.now()-start;
                await connection.query('SET LOCAL ROLE postgres');
                const held=await connection.query('SELECT secret=$1::uuid AS owned FROM eshop.spots WHERE id=$2',[probeSecret,eligible[100+i].spotId]);
                if(held.rows[0]?.owned!==true) throw new Error('SQL probe was rejected instead of acquiring a hold');
                sqlSamples.push({clientPgMs:pgMs,sqlExecutionMs:plan['Execution Time'],sqlPlanningMs:plan['Planning Time']});
            } finally { await connection.query('ROLLBACK'); connection.release(); }
        }
        const summary={schemaVersion:2,fontBoundary:'actual immutable font whole-text resources; browser qualification separate',effectivePolicy:policy.rows[0],kind:f.kind,blueprint:f.blueprint,seats:f.seatCount,publicRead:summarize(reads),independentHolds:summarize(independent),contendedHolds:summarize(contested),cleanup:summarize(cleanup),readBytes:reads[0]?.bytes,sqlHold:{count:sqlSamples.length,p95ExecutionMs:p95(sqlSamples.map(s=>s.sqlExecutionMs)),p95PgRoundtripMs:p95(sqlSamples.map(s=>s.clientPgMs)),samples:sqlSamples},saveReopenPsqlMs:f.saveReopenCommandPsqlMs,stableIdentityReads:reads.filter(row=>row.code===200).length,detail:[...independent,...contested].map(({data,...row})=>row)};
        results.fixtures.push(summary);
    }
    results.finishedAt=new Date().toISOString();
    results.limitations=['HTTP timings include server+transport; no unmeasured subtraction claimed.','EXPLAIN SQL samples are separate rollback probes, not per-request SQL tracing.','Psql save timing includes command startup, SQL and JSON transfer.','Render usability, touch, JS interaction latency and Flutter timings require the separate real UI qualification.'];
    results.gates={allIndependentAccepted:results.fixtures.every(f=>(f.independentHolds.outcomes.accepted??0)===20),identity:results.fixtures.every(f=>f.stableIdentityReads===100),holdP95Under1s:results.fixtures.every(f=>(f.independentHolds.p95Ms??Infinity)<1000),noUnexpectedFailures:results.fixtures.every(f=>[f.publicRead,f.independentHolds,f.contendedHolds].every(s=>!s.outcomes.timeout&&!s.outcomes.deadlock&&!s.outcomes.internal_error)),singleContendedWinner:results.fixtures.every(f=>(f.contendedHolds.outcomes.accepted??0)===1)};
    await fs.writeFile(output,JSON.stringify(results,null,2),{mode:0o600});
    console.log(JSON.stringify({output,gates:results.gates,fixtures:results.fixtures.map(f=>({kind:f.kind,holds:f.independentHolds,contended:f.contendedHolds,sql:f.sqlHold.p95ExecutionMs}))}));
    if(Object.values(results.gates).some(value=>!value)) process.exitCode=1;
} finally {await pool.end();}
