import assert from 'node:assert/strict';
import fs from 'node:fs';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import {performance,monitorEventLoopDelay} from 'node:perf_hooks';
import {createHash} from 'node:crypto';
const [mode,rootArg,previewPath]=process.argv.slice(2),root=resolve(rootArg);
const probeCount=Number(process.argv[5]??100),intervalMs=Number(process.argv[6]??1250);
assert(Number.isInteger(probeCount)&&probeCount>=1&&probeCount<=100&&intervalMs>=1250);
assert(['baseline','candidate'].includes(mode));
const source=relative=>pathToFileURL(resolve(root,relative));
const {setup,connect,apiRequest,httpRequest}=await import(source('tools/festapp/test/api-fixture.mjs'));
const {reply}=await import(source('tools/festapp/test/fixture.mjs'));
const {createRateLimiter}=await import(source('tools/festapp/src/remote/rate-limit.mjs'));
const rendered=JSON.parse(fs.readFileSync(previewPath));
const runtimeFiles=fs.readdirSync(resolve(root,'tools/festapp/src'),{recursive:true}).filter(f=>f.endsWith('.mjs')).sort();
const runtimeDigest=createHash('sha256').update(runtimeFiles.map(f=>f+'\0'+fs.readFileSync(resolve(root,'tools/festapp/src',f))).join('\0')).digest('hex');
const cleanup=[],t={after:fn=>cleanup.push(fn)};let virtualTime=0,variant=0;
const columns=['id','symbol','state','ticketCount','price','currency','paid'];
const rows=Array.from({length:50},(_,i)=>({id:i+1,symbol:String(i+1).padStart(10,'0'),state:'ordered',ticketCount:20,price:'10000.00',currency:'CZK',paid:'0.00'}));
const scopes=['festapp:ticket-layouts:read','festapp:ticket-artwork:preview','festapp:export-orders:read','festapp:orders:read'];
let peakRss=0;const timer=setInterval(()=>{peakRss=Math.max(peakRss,process.memoryUsage().rss);},10);
const lag=monitorEventLoopDelay({resolution:10});lag.enable();
try{
 const f=await setup(t,{api:mode==='candidate',rateLimiter:createRateLimiter({now:()=>performance.now()+virtualTime}),apiPolicy:mode==='candidate'?{allowedScopes:scopes,allowedOperations:['context.inspect','access.inspect','ticket_layouts.preview','exports.orders']}:undefined,
 previewFetch:(_url,init)=>{
  const body=JSON.parse(init.body);if(body.mode!=='pdf')return reply(rendered[body.mode]);
  const pdf=Buffer.concat([Buffer.from(rendered.pdf.file,'base64'),Buffer.from('\n% qualified benchmark variant '+variant+++'\n')]);
  return reply({...rendered.pdf,file:pdf.toString('base64')});
 },fetchImpl:async(url,init)=>{
  if(url.pathname.endsWith('/get_authoring_export_page'))return reply({columns,rows,nextCursor:null});
  if(url.pathname.endsWith('/authorize_authoring_export'))return reply(true);
 }});
 let mcp=(await connect(f,{clientId:'chatgpt-fixture',resources:[f.config.resource],scope:scopes.join(' ')})).tokens;
 const api=mode==='candidate'?(await connect(f,{scope:scopes.join(' ')})).tokens:null;
 const load=api??(await connect(f,{clientId:'chatgpt-fixture',resources:[f.config.resource],scope:scopes.join(' '),consentFields:{mode:'new',name:'Benchmark load'}})).tokens;
 const rpc=async(method,params,token=mcp)=>{
  const response=await fetch(f.issuer+'/mcp',{method:'POST',headers:{authorization:'Bearer '+token.access_token,'content-type':'application/json',accept:'application/json, text/event-stream','mcp-protocol-version':'2025-11-25'},body:JSON.stringify({jsonrpc:'2.0',id:1,method,params})});
  assert.equal(response.status,200,await response.clone().text());const text=await response.text();
  const body=JSON.parse(!text.trim().startsWith('{')?text.split('\n').find(line=>line.startsWith('data:')).slice(5):text);assert(!body.error,JSON.stringify(body.error));return body.result;
 };
 const invoke=async(id,args={},useApi=false)=>{
  if(useApi&&mode==='candidate'){const response=await apiRequest(f,api,id,args);assert.equal(response.status,200,await response.clone().text());return response.json();}
  const result=await rpc('tools/call',{name:'festapp_'+id.replaceAll('.','_'),arguments:args},useApi?load:mcp);assert(!result.isError,JSON.stringify(result.structuredContent));return result.structuredContent;
 };
 const artifact=async(uri,useApi)=>{
  if(useApi){const e=f.config.endpoints[0],headers={host:new URL(e.publicBase).host,'x-forwarded-host':new URL(e.publicBase).host,'x-festapp-endpoint':e.endpointId,'x-forwarded-proto':'https',authorization:'Bearer '+api.access_token,'content-type':'application/json'};
   const response=await httpRequest(f.issuer+'/integrations/v1/artifacts/read',{method:'POST',headers,body:JSON.stringify({uri})});assert.equal(response.status,200,await response.clone().text());return(await response.arrayBuffer()).byteLength;}
  const result=await rpc('resources/read',{uri});return Buffer.from(result.contents[0].blob,'base64').length;
 };
 for(let i=0;i<12;i++)await invoke('context.inspect');global.gc?.();const idle=process.memoryUsage(),mcpTimes=[];
 const readCpuBefore=fs.readFileSync('/sys/fs/cgroup/cpu.stat','utf8'),readCpuStart=process.cpuUsage(),readStarted=performance.now();
 // Equal MCP canary sample sizes. The baseline load is MCP; candidate load API.
 // 1 probe + 1 load per 1.25s respects both existing 60/min grant budgets and
 // shared client/org quotas, including warmup. No limiter is disabled.
 for(let i=0;i<probeCount;i++){
  const remaining=readStarted+i*intervalMs-performance.now();if(remaining>0)await new Promise(resolve=>setTimeout(resolve,remaining));
  const start=performance.now();let probeMs;
  await Promise.all([invoke('context.inspect').then(()=>probeMs=performance.now()-start),invoke('context.inspect',{},true)]);mcpTimes.push(probeMs);
 }
 const readCpuAfter=fs.readFileSync('/sys/fs/cgroup/cpu.stat','utf8'),readCpuUsage=process.cpuUsage(readCpuStart);
 const documents=[];
 for(let i=0;i<8;i++){
  const isPreview=i%2===1,isApi=mode==='candidate'&&i%3!==0,start=performance.now();
  const context=invoke('context.inspect');
  const result=await invoke(isPreview?'ticket_layouts.preview':'exports.orders',isPreview?{occasionId:7,type:'named',scenario:'long',layout:{schemaVersion:3,templates:{named:rendered.resolve.template}}}:{occasionId:7,columns,limit:50,separator:','},isApi);
  await context;const bytes=await artifact(isPreview?result.data.pdf.uri:result.data.file.uri,isApi);
  documents.push({kind:isPreview?'preview':'export',bytes,elapsedMs:performance.now()-start});
  global.gc?.();
 }
 const afterWork=process.memoryUsage();
 // Same provider refresh workload on both images; no limiter is disabled.
 for(let i=0;i<12;i++){
  const response=await fetch(f.issuer+'/token',{method:'POST',body:new URLSearchParams({client_id:'chatgpt-fixture',grant_type:'refresh_token',refresh_token:mcp.refresh_token,resource:f.config.resource})});
  assert.equal(response.status,200,await response.clone().text());mcp=await response.json();
 }
 virtualTime+=60001;await invoke('context.inspect');
 // Artifact expiration uses the real owning cache clock. It also purges old
 // replay/cache evidence on subsequent operations. Never retain a stale URI.
 const now=Date.now;try{Date.now=()=>now()+16*60000;
  // Access tokens expire earlier, so stale access is rejected before the cache.
  const response=await fetch(f.issuer+'/mcp',{method:'POST',headers:{authorization:'Bearer '+mcp.access_token,'content-type':'application/json'},body:'{}'});assert.equal(response.status,401);
 }finally{Date.now=now;}
 for(let i=0;i<3;i++){global.gc?.();await new Promise(resolve=>setTimeout(resolve,50));}
 const afterGc=process.memoryUsage(),cgroup={};for(const field of ['memory.peak','memory.max','cpu.max'])cgroup[field]=fs.readFileSync('/sys/fs/cgroup/'+field,'utf8').trim();
 console.log(JSON.stringify({ok:true,mode,runtimeDigest,node:process.version,limits:{heapMiB:192,cgroup},dataset:{rows:50,columns,preview:'canonical named long-scenario renderer PDF with 32 elements and near-limit text input; distinct trailing PDF comment per preview',previewFixtureSha256:createHash('sha256').update(fs.readFileSync(previewPath)).digest('hex')},probeCount,intervalMs,readCpuBefore,readCpuAfter,readCpuUsage,mcpSamples:mcpTimes,workload:'12 warm MCP reads, 100 measured MCP canaries + 100 equal background reads (baseline MCP, candidate API) at 1.25s cadence, 4 50-row exports and 4 distinct canonical PDF/raster previews each concurrent with MCP read and followed by authorized artifact read, 12 refreshes, expired-token rejection, GC recovery',documents,mcpP95Ms:mcpTimes.sort((a,b)=>a-b)[Math.ceil(mcpTimes.length*.95)-1],memory:{idle,afterWork,afterGc,peakRss},eventLoopP95Ms:lag.percentile(95)/1e6,limitations:['fixture backend/renderer response; production renderer/network/DB costs excluded','32-element near-input-limit text fixture; remote image-worker/network failure costs excluded','queue exhaustion and disconnect admission covered by targeted HTTP tests, not this timing sample']}));
}finally{clearInterval(timer);lag.disable();for(const fn of cleanup.reverse())await fn();}
