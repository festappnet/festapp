// Test transport for the unchanged canonical image Worker and local GoTrue/SQL.
// No production egress, real R2 or provider credentials are used.
import {readFile} from 'node:fs/promises';
import {createServer} from 'node:http';
import {createRequire} from 'node:module';
import {dirname,resolve} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'../../..');
const worker=resolve(root,'workers/image-worker');
const status=JSON.parse(await readFile(process.argv[2],'utf8'));
const api=new URL(status.API_URL),database=new URL(status.DB_URL);
if(api.hostname!=='127.0.0.1'||api.port!=='56521'||database.hostname!=='127.0.0.1'||database.port!=='56522')throw new Error('Owned local copy E2E backend required');
const {Client}=createRequire(pathToFileURL(resolve(worker,'package.json')))('pg');
const db=new Client({connectionString:status.DB_URL});await db.connect();
try{
 const fixture=(await db.query("select exists(select 1 from auth.users where id='078e32bf-ae6b-4bc0-ba2f-918842e703e8') present")).rows[0].present;
 if(!fixture)throw new Error('Owned synthetic editor identity missing');
 await db.query('CREATE SCHEMA IF NOT EXISTS festapp_test_support');
 await db.query('CREATE TABLE IF NOT EXISTS festapp_test_support.disposable_environment(singleton boolean PRIMARY KEY CHECK(singleton),project text NOT NULL)');
 const rows=(await db.query('select project from festapp_test_support.disposable_environment')).rows;
 if(rows.some(row=>row.project!=='festapp-copy-e2e-20261110'))throw new Error('Different disposable owner');
 await db.query("insert into festapp_test_support.disposable_environment values(true,'festapp-copy-e2e-20261110') on conflict(singleton) do nothing");
}finally{await db.end();}
process.chdir(worker);
const {startLocalUploadRuntime}=await import(pathToFileURL(resolve(worker,'tests/integration/local-upload-runtime.ts')));
const originalFetch=globalThis.fetch;
globalThis.fetch=async(input,init)=>{
 const started=performance.now();
 try{
  const response=await originalFetch(input,init);
  const target=new URL(typeof input==='string'||input instanceof URL?input:input.url);
  if(target.origin===api.origin){
   let error;
   if(!response.ok){const body=await response.clone().json().catch(()=>({}));error={code:body.code,message:body.message};}
   console.log(JSON.stringify({rpc:target.pathname,status:response.status,milliseconds:Math.round(performance.now()-started),error}));
  }
  return response;
 }catch(error){console.log(JSON.stringify({transportError:error.name,milliseconds:Math.round(performance.now()-started)}));throw error;}
};
const runtime=await startLocalUploadRuntime(status.DB_URL,status.API_URL,status.ANON_KEY);
const origins=new Set(['http://localhost:56530','http://127.0.0.1:56530']);
const server=createServer(async(req,res)=>{
 const origin=req.headers.origin;
 if(origin&&!origins.has(origin)){res.writeHead(403).end();return;}
 const cors=origin?{'access-control-allow-origin':origin,'vary':'Origin','access-control-allow-methods':'POST,OPTIONS','access-control-allow-headers':'Authorization,Content-Type'}:{};
 if(req.method==='OPTIONS'){res.writeHead(204,cors).end();return;}
 if(req.url==='/health'){res.writeHead(200,{'content-type':'application/json',...cors}).end('{"localWorker":true}');return;}
 if(req.url!=='/occasion-lifecycle'||req.method!=='POST'){res.writeHead(404,cors).end();return;}
 try{
  const chunks=[];let length=0;
  for await(const chunk of req){length+=chunk.length;if(length>1048576)throw new Error('Request too large');chunks.push(chunk);}
  const headers=new Headers();for(const name of ['authorization','content-type'])if(req.headers[name])headers.set(name,req.headers[name]);
  const response=await runtime.fetch('https://image-api.festapp.net/occasion-lifecycle',{method:'POST',headers,body:Buffer.concat(chunks)});
  const body=Buffer.from(await response.arrayBuffer());
  res.writeHead(response.status,{'content-type':response.headers.get('content-type')??'application/json',...cors}).end(body);
  console.log(JSON.stringify({route:'/occasion-lifecycle',status:response.status}));
 }catch(error){res.writeHead(500,{'content-type':'application/json',...cors}).end('{"error":"local worker adapter failed"}');console.error(error.message);}
});
await new Promise(resolve=>server.listen(56540,'127.0.0.1',resolve));
console.log('Canonical local image Worker ready: http://127.0.0.1:56540');
let closing=false;
async function close(){if(closing)return;closing=true;server.close();await runtime.dispose();process.exit(0);}
process.on('SIGTERM',()=>void close());process.on('SIGINT',()=>void close());
