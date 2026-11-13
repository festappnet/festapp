import { pathToFileURL } from 'node:url';
import { resolve } from 'node:path';
import { performance, monitorEventLoopDelay } from 'node:perf_hooks';
import fs from 'node:fs';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import assert from 'node:assert/strict';
const mode=process.argv[2],root=resolve(process.argv[3]??'../..'),paceMs=Number(process.argv[5]??0);
assert(['baseline','candidate'].includes(mode));
const {setup,connect,apiRequest}=await import(pathToFileURL(resolve(root,'tools/festapp/test/api-fixture.mjs')));
const sourceFiles=fs.readdirSync(resolve(root,'tools/festapp/src'),{recursive:true}).filter(f=>f.endsWith('.mjs')).sort();
const runtimeDigest=createHash('sha256').update(sourceFiles.map(f=>f+'\0'+fs.readFileSync(resolve(root,'tools/festapp/src',f))).join('\0')).digest('hex');
const sourceSha=process.argv[4]??execFileSync('git',['rev-parse','HEAD'],{cwd:root,encoding:'utf8'}).trim();
const cgroup = {};
for (const field of ['memory.peak','memory.max','cpu.max']) { try { cgroup[field] = fs.readFileSync('/sys/fs/cgroup/'+field,'utf8').trim(); } catch {} }
const cleanups=[],t={after:fn=>cleanups.push(fn)};
const delay=monitorEventLoopDelay({resolution:10});delay.enable();
let peakRss=0;const sample=setInterval(()=>{peakRss=Math.max(peakRss,process.memoryUsage().rss);},10);
try{
    const f=await setup(t,{api:mode==='candidate'});
    const mcp=await connect(f,{clientId:'chatgpt-fixture',resources:[f.config.resource]});
    const api=mode==='candidate'?await connect(f):null;
    const read=async(useApi)=>{
        const response=useApi?await apiRequest(f,api.tokens):await fetch(f.issuer+'/mcp',{method:'POST',headers:{authorization:'Bearer '+mcp.tokens.access_token,'content-type':'application/json',accept:'application/json, text/event-stream','mcp-protocol-version':'2025-11-25'},body:JSON.stringify({jsonrpc:'2.0',id:1,method:'tools/call',params:{name:'festapp_context_inspect',arguments:{}}})});
        assert.equal(response.status,200,await response.clone().text());
        const body=await response.text();assert(!body.includes('"ok":false'));
    };
    for(let i=0;i<12;i++)await read(false);
    global.gc?.();const idle=process.memoryUsage();
    const mcpTimes=[],allTimes=[];
    if(paceMs)await new Promise(resolve=>setTimeout(resolve,250));
    const workloadStarted=performance.now(),cpuStarted=process.cpuUsage();
    let cpuBefore;try{cpuBefore=fs.readFileSync('/sys/fs/cgroup/cpu.stat','utf8');}catch{}
    // Below existing admission quotas; exact same 32 business reads per source.
    for(let i=0;i<32;i++){
        if(paceMs){const wait=workloadStarted+i*paceMs-performance.now();if(wait>0)await new Promise(resolve=>setTimeout(resolve,wait));}
        const useApi=mode==='candidate'&&i%2===1,start=performance.now();await read(useApi);
        const elapsed=performance.now()-start;allTimes.push(elapsed);if(!useApi)mcpTimes.push(elapsed);
    }
    const cpuWorkloadMicros=process.cpuUsage(cpuStarted);let cpuAfter;try{cpuAfter=fs.readFileSync('/sys/fs/cgroup/cpu.stat','utf8');}catch{}
    global.gc?.();const after=process.memoryUsage();
    const p95=values=>values.sort((a,b)=>a-b)[Math.ceil(values.length*.95)-1];
    for (const field of Object.keys(cgroup)) cgroup[field]=fs.readFileSync('/sys/fs/cgroup/'+field,'utf8').trim();
    console.log(JSON.stringify({mode,sourceSha,runtimeDigest,cgroup,recordedAt:new Date().toISOString(),heapLimitMiB:192,paceMs,cpuWorkloadMicros,cpuBefore,cpuAfter,workload:'12 MCP warmups + 32 sequential context reads; candidate 16 API/16 MCP, baseline 32 MCP',totalOperations:44,
        memory:{idle,after,peakRss},mcpP95Ms:p95(mcpTimes),allP95Ms:p95(allTimes),eventLoopP95Ms:delay.percentile(95)/1e6,
        node:process.version,platform:process.platform,arch:process.arch,
        limitations:[cgroup['memory.max']?'container read slice only; full release workload not exercised':'native process slice; container/CPU limits not exercised','exports, preview, refresh and exhaustion require the full release workload','MCP p95 has a small sample and is diagnostic, not release approval']}));
}finally{
    clearInterval(sample);delay.disable();
    // Close the HTTP service before removing its source fixture directories.
    for(const cleanup of cleanups.reverse())await cleanup();
}
