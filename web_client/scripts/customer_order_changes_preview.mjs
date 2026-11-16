// Developer-only E2E: actual product renderer -> production Edge handler ->
// local PostgREST -> a verified disposable SQL database. Mail stays in the sink.
import {createServer as createHttpServer,request as proxyRequest} from 'node:http';
import {createServer as createViteServer} from 'vite';
import {readFileSync,writeFileSync,mkdtempSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {resolve} from 'node:path';
import {spawn,execFileSync} from 'node:child_process';
import {randomBytes,createHmac,createDecipheriv} from 'node:crypto';
import pg from 'pg';
import {createTestWorkspace} from '../tests/database/runtime_workspace.js';
import {assertDisposableDatabase} from '../tests/database/disposable_database.js';
const root=resolve(import.meta.dirname,'../..'),port=Number(process.env.CUSTOMER_PREVIEW_PORT??57986),restPort=port+1,edgePort=port+2;
const lease=await createTestWorkspace();const db=new pg.Client({connectionString:lease.databaseUrl});await db.connect();await assertDisposableDatabase(db);
const temporary=mkdtempSync(resolve(tmpdir(),'festapp-customer-e2e-'));const container='festapp-customer-e2e-'+process.pid;
const jwtSecret=randomBytes(32).toString('base64'),emailKey=randomBytes(32),origin=`http://127.0.0.1:${port}`;
const jwt=role=>{const h=Buffer.from(JSON.stringify({alg:'HS256',typ:'JWT'})).toString('base64url'),p=Buffer.from(JSON.stringify({role,iss:'supabase',iat:Math.floor(Date.now()/1000)-10,exp:Math.floor(Date.now()/1000)+7200})).toString('base64url');return `${h}.${p}.${createHmac('sha256',jwtSecret).update(h+'.'+p).digest('base64url')}`;};
const anonKey=jwt('anon'),serviceKey=jwt('service_role');
let vite,edge,server;let cleaned=false;
async function cleanup(){if(cleaned)return;cleaned=true;edge?.kill('SIGTERM');await vite?.close();await new Promise(resolve=>server?server.close(resolve):resolve());try{execFileSync('docker',['rm','-f',container],{stdio:'ignore'});}catch{}await db.end();await lease.release();rmSync(temporary,{recursive:true,force:true});}
for(const signal of ['SIGINT','SIGTERM'])process.on(signal,()=>cleanup().then(()=>process.exit(0)));
try{
 await db.query(readFileSync(resolve(root,'database/tests/helpers/assertions.sql'),'utf8'));
 await db.query(readFileSync(resolve(root,'database/tests/helpers/payment_lifecycle_fixture.sql'),'utf8'));
 await db.query(readFileSync(resolve(root,'database/tests/customer_order_changes/fixture.sql'),'utf8'));
 const fixtures=[];
 for(const locale of ['cs','en']){
  const x=(await db.query('SELECT pg_temp.customer_two_fixture() x')).rows[0].x;
  await db.query("SELECT set_config('request.jwt.claim.sub',$1,false),set_config('request.jwt.claim.role','authenticated',false)",[x.actor]);
  const title=locale==='cs'?'Taneční večer v kulturním domě':'Dance evening at the town hall';
  await db.query('UPDATE public.organizations SET title=$1,data=$2 WHERE id=$3',[locale==='cs'?'Spolek Přátelé tance':'Friends of Dance Association',{DEFAULT_URL:origin,DEFAULT_LANGUAGE:locale},x.organization]);
  await db.query('UPDATE public.occasions SET title=$1 WHERE id=$2',[title,x.occasion]);
  await db.query('UPDATE public.units SET title=$1 WHERE id=(SELECT unit FROM public.occasions WHERE id=$2)',[locale==='cs'?'Spolek Přátelé tance':'Friends of Dance Association',x.occasion]);
  await db.query('UPDATE public.forms SET title=$1 WHERE id=$2',[title,x.form]);
  await db.query('UPDATE public.form_fields SET title=$1 WHERE id=$2',[locale==='cs'?'Telefon':'Phone',x.field]);
  await db.query('UPDATE eshop.products SET title=$1 WHERE id=$2',[locale==='cs'?'Vstup na taneční večer':'Dance evening admission',x.product]);
  await db.query('UPDATE eshop.product_types SET title=$1 WHERE id=(SELECT product_type FROM eshop.products WHERE id=$2)',[locale==='cs'?'Vstupné':'Admission',x.product]);
  await db.query('UPDATE eshop.orders SET data=data||$1::jsonb WHERE id=$2',[{name:locale==='cs'?'Jana':'Jane',surname:locale==='cs'?'Nováková':'Novak',email:`buyer-${locale}@example.test`},x.order]);
  let policy=(await db.query('SELECT public.customer_order_policy_internal($1) p',[x.form])).rows[0].p.policy;
  policy.cancel={...policy.cancel,mode:process.env.CUSTOMER_PREVIEW_CANCEL_MODE==='automatic'?'automatic':'approval_required',reason_required:true,refund_mode:'manual'};
  await db.query('SELECT public.save_customer_order_policy_internal($1,$2)',[x.form,policy]);
  await db.query("UPDATE eshop.orders SET data=jsonb_set(jsonb_set(data,'{tickets,0,products,0,title}',$1::jsonb),'{tickets,0,products,0,type_title}',$2::jsonb) WHERE id=$3",[JSON.stringify(locale==='cs'?'Vstup na taneční večer':'Dance evening admission'),JSON.stringify(locale==='cs'?'Vstupné':'Admission'),x.order]);
  policy.move={enabled:false,targets:[]};
  await db.query('SELECT public.save_customer_order_policy_internal($1,$2)',[x.form,policy]);
  if(process.env.CUSTOMER_PREVIEW_SEATS==='1') {
    const seated=(await db.query('SELECT pg_temp.payment_attach_spot($1) x',[x])).rows[0].x;
    await db.query("UPDATE eshop.spots SET title='12' WHERE id=$1",[seated.spot]);
    await db.query('UPDATE eshop.blueprints SET title=$1 WHERE id=(SELECT blueprint FROM eshop.spots WHERE id=$2)',[locale==='cs'?'Taneční sál':'Dance hall',seated.spot]);
    const spot=(await db.query("INSERT INTO eshop.spots(occasion,blueprint,product,order_product_ticket,title) SELECT $1,s.blueprint,$2,opt.id,'13' FROM eshop.spots s CROSS JOIN eshop.order_product_ticket opt WHERE s.id=$3 AND opt.\"order\"=$4 AND opt.ticket=$5 RETURNING id",[x.occasion,x.product,seated.spot,x.order,x.otherTicket])).rows[0].id;
    await db.query("UPDATE eshop.orders SET data=jsonb_set(jsonb_set(data,'{tickets,0,products,0,spot_title}','\"12\"'::jsonb),'{tickets,1,products,0}',data#>'{tickets,1,products,0}'||jsonb_build_object('spot_id',$1::bigint,'spot_title','13')) WHERE id=$2",[spot,x.order]);
  }
  await db.query("UPDATE eshop.orders SET data=jsonb_set(data,'{tickets}',(SELECT jsonb_agg(jsonb_set(ticket,'{products}',(SELECT jsonb_agg(product||jsonb_build_object('title',$1::text,'type_title',$2::text)) FROM jsonb_array_elements(ticket->'products') product))) FROM jsonb_array_elements(data->'tickets') ticket)) WHERE id=$3",[locale==='cs'?'Vstup na taneční večer':'Dance evening admission',locale==='cs'?'Vstupné':'Admission',x.order]);
  fixtures.push({...x,locale,url:origin+`/order?order_id=${x.order}&token=${x.readToken}`});
 }
 // Quota bypasses and successful RPC injections are deliberately absent. Only
 // external queue wake is disabled in this disposable environment.
 await db.query("CREATE FUNCTION public.customer_e2e_pre_request() RETURNS void LANGUAGE sql SET search_path=public,extensions AS $$ SELECT pg_catalog.set_config('festapp.email_wake','scheduled',true) $$");
 await db.query('REVOKE ALL ON FUNCTION public.customer_e2e_pre_request() FROM PUBLIC; GRANT EXECUTE ON FUNCTION public.customer_e2e_pre_request() TO anon,authenticated,service_role');
 const dbUrl=new URL(lease.databaseUrl);dbUrl.hostname='host.docker.internal';
 const envFile=resolve(temporary,'rest.env');writeFileSync(envFile,`PGRST_DB_URI=${dbUrl}\nPGRST_DB_SCHEMAS=public\nPGRST_DB_ANON_ROLE=anon\nPGRST_JWT_SECRET=${jwtSecret}\nPGRST_DB_PRE_REQUEST=public.customer_e2e_pre_request\n`,{mode:0o600});
 execFileSync('docker',['run','-d','--rm','--name',container,'--env-file',envFile,'-p',`127.0.0.1:${restPort}:3000`,'public.ecr.aws/supabase/postgrest:v14.15'],{stdio:'ignore'});
 const wrapper=resolve(temporary,'edge.ts');writeFileSync(wrapper,`const serve=Deno.serve;Deno.serve=((handler)=>serve({hostname:'127.0.0.1',port:${edgePort}},handler)) as typeof Deno.serve;await import(${JSON.stringify('file://'+resolve(root,'supabase/functions/customer-order-changes/index.ts'))});`);
 edge=spawn('deno',['run','--allow-env','--allow-read','--allow-net',wrapper],{env:{...process.env,SUPABASE_URL:origin,SUPABASE_SERVICE_ROLE_KEY:serviceKey,EMAIL_PAYLOAD_KEY:emailKey.toString('base64'),DEFAULT_EMAIL:'support@example.test'},stdio:['ignore','ignore','pipe']});edge.stderr.on('data',chunk=>{const message=String(chunk);if(!message.includes('Listening'))process.stderr.write(message);});
 vite=await createViteServer({configFile:false,root:resolve(root,'web_client'),server:{middlewareMode:true,fs:{allow:[root]}},appType:'custom',logLevel:'error'});
 const bootstrap=readFileSync(resolve(root,'web_client/index.html'),'utf8').match(/<script>([\s\S]*?)<\/script>/)[1];
 const forward=(request,response,targetPort,path)=>{const proxied=proxyRequest({hostname:'127.0.0.1',port:targetPort,path,method:request.method,headers:{...request.headers,host:`127.0.0.1:${targetPort}`}},r=>{response.writeHead(r.statusCode??500,r.headers);r.pipe(response);});proxied.on('error',()=>{response.writeHead(503);response.end();});request.pipe(proxied);};
 server=createHttpServer(async(request,response)=>{
  const url=new URL(request.url,origin);
  if(url.pathname.startsWith('/rest/v1/'))return forward(request,response,restPort,url.pathname.slice('/rest/v1'.length)+url.search);
  if(url.pathname==='/functions/v1/customer-order-changes')return forward(request,response,edgePort,'/');
  if(url.pathname.startsWith('/fixture/translations/')){const locale=url.pathname.endsWith('/en')?'en':'cs';response.setHeader('content-type','application/json');return response.end(readFileSync(resolve(root,`assets/translations/${locale}.json`)));}
  if(url.pathname==='/fixture/mail'){
   const selected=fixtures.find(x=>String(x.order)===url.searchParams.get('order_id'));if(!selected){response.writeHead(404);return response.end();}
   const row=(await db.query("SELECT prepared FROM public.email_messages WHERE recipient=$1 AND code='CUSTOMER_ORDER_CHANGE' ORDER BY id DESC LIMIT 1",[`buyer-${selected.locale}@example.test`])).rows[0];
   if(!row){response.writeHead(404);return response.end('No confirmation email yet');}
   const value=row.prepared,encrypted=Buffer.from(value.ciphertext,'base64'),decipher=createDecipheriv('aes-256-gcm',emailKey,Buffer.from(value.iv,'base64'));decipher.setAuthTag(encrypted.subarray(-16));const prepared=JSON.parse(Buffer.concat([decipher.update(encrypted.subarray(0,-16)),decipher.final()]).toString());
   response.setHeader('content-type','text/html; charset=utf-8');response.setHeader('cache-control','no-store');return response.end(`<!doctype html><html lang="${selected.locale}"><meta name="referrer" content="no-referrer"><body style="color-scheme:light;background:white;color:#172b4d;font:18px system-ui;max-width:700px;margin:40px auto"><h1>${prepared.subject}</h1>${prepared.html}</body></html>`);
  }
  if(url.pathname==='/order'){
   const selected=fixtures.find(x=>String(x.order)===url.searchParams.get('order_id'));if(!selected){response.writeHead(404);return response.end();}
   const html=`<!doctype html><html lang="${selected.locale}"><head><script>${bootstrap}</script><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="referrer" content="no-referrer"><style>html{color-scheme:light}body{font-family:system-ui;background:#fff;color:#172b4d;margin:0;padding:20px}main{max-width:850px;margin:auto}button{font:inherit}h1,h2,h3{line-height:1.25}p{line-height:1.5}</style></head><body><main></main><script>window.customerFixture=${JSON.stringify({locale:selected.locale,anonKey})}</script><script type="module" src="/tests/fixtures/customer_order_changes/main.js"></script></body></html>`;
   response.setHeader('content-type','text/html; charset=utf-8');response.setHeader('cache-control','no-store');return response.end(await vite.transformIndexHtml(request.url,html));
  }
  vite.middlewares(request,response,()=>{response.writeHead(404);response.end();});
 });
 await new Promise((ready,reject)=>{server.once('error',reject);server.listen(port,'127.0.0.1',ready);});
 const statePath=resolve(temporary,'fixture.json');writeFileSync(statePath,JSON.stringify({origin,fixtures:fixtures.map(({locale,url,order})=>({locale,url,order}))}),{mode:0o600});
 console.log(`Owned customer E2E ready. Private fixture locators: ${statePath}`);
 await new Promise(()=>{});
}catch(error){console.error(error.message);await cleanup();process.exitCode=1;}
