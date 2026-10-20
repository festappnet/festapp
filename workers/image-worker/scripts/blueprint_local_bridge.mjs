// Owned local test transport. Real Worker/R2/Images execution; no remote binding.
import { Miniflare, convertV4MiniflareOptions } from 'miniflare';
import { build } from 'esbuild';
import { createServer } from 'node:http';
import { Readable } from 'node:stream';
import { readFileSync, mkdirSync, statSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
const args=Object.fromEntries(process.argv.slice(2).reduce((pairs,value,index,all)=>index%2===0?[...pairs,[value.replace(/^--/,''),all[index+1]]]:pairs,[]));
assert(args['env-file'] && args['state-dir'],'--env-file and --state-dir are required');
assert.equal(statSync(args['env-file']).mode&0o077,0,'private env file must not be group/world readable');
const api=new URL(args.api??'http://127.0.0.1:59721');assert.equal(api.origin,'http://127.0.0.1:59721','only owned E2E API59721 is allowed');
const port=Number(args.port??59725);assert.equal(port,59725,'owned bridge port59725 required');
const vars=Object.fromEntries(readFileSync(args['env-file'],'utf8').split(/\r?\n/).filter(x=>x&&!x.startsWith('#')).map(line=>{const at=line.indexOf('=');return [line.slice(0,at),line.slice(at+1).replace(/^['"]|['"]$/g,'')];}));
assert(vars.IMAGE_PROCESSING_SERVICE_SECRET?.length>=32 && vars.SUPABASE_ANON_KEY,'local manifest secret + anon key required');
const state=resolve(args['state-dir']);assert(state.includes('blueprint'),'task-specific state directory required');mkdirSync(state,{recursive:true,mode:0o700});
await build({entryPoints:[resolve(root,'src/index.ts')],bundle:true,format:'esm',platform:'browser',target:'es2022',outfile:resolve(state,'worker.mjs')});
const mf=new Miniflare(convertV4MiniflareOptions({modules:true,script:readFileSync(resolve(state,'worker.mjs'),'utf8'),compatibilityDate:'2025-01-01',port:0,
 r2Buckets:{IMAGES_BUCKET:'blueprint-local-public',IMAGES_PRIVATE_BUCKET:'blueprint-local-private',IMAGES_BUCKET_AKHWEB:'blueprint-local-akh'},resourcePersistencePath:resolve(state,'resources'),
 images:{binding:'IMAGES'},ratelimits:{IMAGE_READ_MISS_BUDGET:{namespace_id:'1001',simple:{limit:1000,period:60}}},
 bindings:{...vars,SUPABASE_URL:'https://api.festapp.net',SUPABASE_URL_A:'https://api.festapp.net',SUPABASE_ANON_KEY_A:vars.SUPABASE_ANON_KEY,
  SUPABASE_URL_SLUNOVRAT:'https://api.festapp.net',SUPABASE_ANON_KEY_SLUNOVRAT:vars.SUPABASE_ANON_KEY},
 outboundService:async request=>{
  const url=new URL(request.url);
  if(url.origin!=='https://api.festapp.net'||!url.pathname.startsWith('/rest/v1/rpc/'))return new Response('External network forbidden in owned fixture',{status:502});
  const target=new URL(url.pathname+url.search,api);return fetch(target,{method:request.method,headers:request.headers,body:request.body,duplex:'half',redirect:'error'});
 }}));
await mf.ready;
const server=createServer(async(req,res)=>{
 try{
  const local=new URL(req.url,'http://127.0.0.1:59725');
  if(local.pathname==='/health'){res.writeHead(200,{'Content-Type':'application/json'});res.end('{"project":"festapp-blueprint-1000-image-local","processor":"miniflare-images","remote":false}');return;}
  if(!['GET','HEAD','POST','PUT','OPTIONS'].includes(req.method)){res.writeHead(405);res.end();return;}
  const origin=req.headers.origin;
  if(origin&&!/^http:\/\/(localhost|127\.0\.0\.1):\d+$/.test(origin)){res.writeHead(403);res.end();return;}
  const publicRead=local.pathname.startsWith('/public/');
  const fontService=local.pathname.startsWith('/service/ticket-fonts/');
  if(fontService&&origin){res.writeHead(403);res.end();return;}
  if(!publicRead&&!fontService&&!['/upload','/delete'].includes(local.pathname)){res.writeHead(404);res.end();return;}
  const cors=origin?{'Access-Control-Allow-Origin':origin,Vary:'Origin'}:{};
  if(req.method==='OPTIONS'){res.writeHead(204,{...cors,'Access-Control-Allow-Methods':'GET,HEAD,POST,OPTIONS','Access-Control-Allow-Headers':'authorization,content-type'});res.end();return;}
  const path=publicRead?local.pathname.slice('/public'.length):local.pathname;
  const canonical=`https://${publicRead?'img.festapp.net':'image-api.festapp.net'}${path}${local.search}`;
  const headers=new Headers(Object.entries(req.headers).flatMap(([k,v])=>v===undefined?[]:[[k,Array.isArray(v)?v.join(','):v]]));headers.delete('host');
  const result=await mf.dispatchFetch(canonical,{method:req.method,headers,...(['POST','PUT'].includes(req.method)?{body:Readable.toWeb(req),duplex:'half'}:{})});
  const responseHeaders=new Headers(result.headers);for(const [name,value] of Object.entries(cors))responseHeaders.set(name,value);
  res.writeHead(result.status,Object.fromEntries(responseHeaders));if(result.body)Readable.fromWeb(result.body).pipe(res);else res.end();
 }catch{res.writeHead(500,{'Content-Type':'application/json'});res.end('{"error":"owned local image bridge failed"}');}
});
await new Promise(resolve=>server.listen(port,args.host??'127.0.0.1',resolve));console.log('READY owned image bridge127.0.0.1:59725; real local Images/R2; all non-owned outbound network blocked');
for(const signal of ['SIGINT','SIGTERM'])process.on(signal,async()=>{server.close();await mf.dispose();process.exit(0);});
