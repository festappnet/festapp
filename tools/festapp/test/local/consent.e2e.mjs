// Explicit opt-in integration runner. All credentials stay in the private task root.
import assert from 'node:assert/strict';
import {Client} from '@modelcontextprotocol/sdk/client/index.js';
import {StreamableHTTPClientTransport} from '@modelcontextprotocol/sdk/client/streamableHttp.js';
import { createServer } from 'node:http';
import { createServer as createHttps } from 'node:https';
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { resolve } from 'node:path';
import { execFile, spawn } from 'node:child_process';
import { promisify } from 'node:util';
import { randomBytes, createHash, generateKeyPairSync } from 'node:crypto';
import { createClient } from '@supabase/supabase-js';
import { parseProfile, digest } from '../../src/context/profile.mjs';
import { parseRemoteConfig, READ_SCOPE } from '../../src/remote/config.mjs';
import { createRemoteApp } from '../../src/remote/server.mjs';
import { openRemoteStorage } from '../../src/remote/storage.mjs';
import { canonicalBackendProfileSha256 } from '../../../../automation/lib/backend_activation_manifest.mjs';
const exec = promisify(execFile), root=resolve(import.meta.dirname,'../../../..');
const privateRoot='/Users/miakh/source/festapp-blueprint-mcp-closure-local-20261020';
const evidence=resolve(root,'docs/plans/evidence/blueprint-mcp-closure-20261020');
const status=JSON.parse(await readFile(privateRoot+'/backend-status.json','utf8'));
assert.equal(status.API_URL,'http://127.0.0.1:59721');
const guard=await exec('psql',['-h','127.0.0.1','-p','59722','-U','postgres','-d','postgres','-XqAt','-v','ON_ERROR_STOP=1','-c',"select json_build_object('project',(select project from festapp_test_support.disposable_environment where singleton),'paused',(select bool_and(paused and worker_url is null) from public.email_capacity),'cron',(select count(*) from cron.job where active))"],{env:{...process.env,PGPASSWORD:'postgres'}});
const owned=JSON.parse(guard.stdout);assert.equal(owned.project,'festapp-blueprint-1000-e2e-20261020');assert.equal(owned.paused,true);assert.equal(owned.cron,0);

const admin=createClient(status.API_URL,status.SERVICE_ROLE_KEY,{auth:{persistSession:false,autoRefreshToken:false}});
const fixtures=JSON.parse(await readFile('/Users/miakh/source/festapp-blueprint-1000-e2e-20261020/blueprint-1000-fixtures.json','utf8')).fixtures;
const originalActor=(JSON.parse(await readFile('/Users/miakh/source/festapp-blueprint-1000-e2e-20261020/fixture.json','utf8'))).actor;
const created=await admin.auth.admin.createUser({email:'1+closure-mcp-'+Date.now()+'@example.invalid',password:randomBytes(24).toString('base64url'),email_confirm:true});assert.ifError(created.error);
const actor=created.data.user.id;
const seed=`INSERT INTO public.user_info(id,email_readonly,organization) VALUES('${actor}','${created.data.user.email.replace(/^1\+/,"")}',1); INSERT INTO public.occasion_users(occasion,\"user\",is_editor_order_view) VALUES ${fixtures.map(f=>`(${f.occasion},'${actor}',true)`).join(',')};`;
const seedFile=privateRoot+'/mcp-user.sql';await writeFile(seedFile,seed,{mode:0o600});
await exec('psql',['-h','127.0.0.1','-p','59722','-U','postgres','-d','postgres','-Xq','-v','ON_ERROR_STOP=1','-f',seedFile],{env:{...process.env,PGPASSWORD:'postgres'}});
const user=await admin.auth.admin.getUserById(actor);assert.ifError(user.error);
// The marked disposable database contains only the prior task's synthetic seed.
const password=randomBytes(24).toString('base64url');
assert.ifError((await admin.auth.admin.updateUserById(actor,{password})).error);
await writeFile(privateRoot+'/browser-login.json',JSON.stringify({email:user.data.user.email.replace(/^1\+/,''),password}),{mode:0o600});
const activation=JSON.stringify({schemaVersion:1,tenantId:'closure-fixture',generation:1,backend:'canonical'});
const profile=parseProfile({schemaVersion:1,name:'closure-fixture',kind:'disposable-local',tenantId:'closure-fixture',backendOrigin:status.API_URL,publicApiKey:status.ANON_KEY,organizationId:1,activationUrl:status.API_URL+'/backend-activation.json',activationSha256:digest(activation),generation:1,canonicalProfileSha256:canonicalBackendProfileSha256({tenantId:'closure-fixture',canonicalOrigin:status.API_URL,canonicalAnonKey:status.ANON_KEY,canonicalOrganizationId:1})});
const cert=privateRoot+'/cert.pem',key=privateRoot+'/key.pem';
await exec('openssl',['req','-x509','-newkey','rsa:2048','-nodes','-keyout',key,'-out',cert,'-days','1','-subj','/CN=127.0.0.1','-addext','subjectAltName=IP:127.0.0.1']);
const issuer='http://127.0.0.1:59732',tenant='https://127.0.0.1:59733',clientCallback='http://127.0.0.1:59734/callback';
const {binding:profileBinding,...rawProfile}=profile;
const config=parseRemoteConfig({schemaVersion:2,issuer,profile:rawProfile,tenantOrigin:tenant,clients:[{id:'closure-native',name:'Closure synthetic client',applicationType:'native',redirectUris:['http://127.0.0.1/callback']}]});
const brokerSecret=randomBytes(32).toString('base64url');
const {privateKey}=generateKeyPairSync('rsa',{modulusLength:2048});
const storage=await openRemoteStorage(privateRoot+'/broker-'+Date.now(),randomBytes(32));
const {app}=createRemoteApp(config,storage,{cookieKeys:[randomBytes(32).toString('base64url'),randomBytes(32).toString('base64url')],jwks:{keys:[{...privateKey.export({format:'jwk'}),kid:'closure',use:'sig',alg:'RS256'}]},brokerSecret,fetchImpl:async(input,init)=>new URL(input instanceof Request?input.url:input).href===profile.activationUrl?new Response(activation):fetch(input,init)});
const broker=createServer(app);
let lastTokens=null,callbackCount=0,nativeClient;
const verifier=randomBytes(32).toString('base64url');
const callback=createServer(async(req,res)=>{try{const url=new URL(req.url,clientCallback);if(url.pathname==='/favicon.ico'){res.writeHead(204);res.end();return;}assert.equal(url.pathname,'/callback');assert.equal(url.searchParams.get('state'),'closure-state');assert.equal(url.searchParams.get('iss'),issuer);const response=await fetch(issuer+'/token',{method:'POST',body:new URLSearchParams({client_id:'closure-native',grant_type:'authorization_code',code:url.searchParams.get('code'),redirect_uri:clientCallback,code_verifier:verifier,resource:config.resource})});assert.equal(response.status,200);lastTokens=await response.json();nativeClient=new Client({name:'closure-synthetic-native',version:'1.0.0'});await nativeClient.connect(new StreamableHTTPClientTransport(new URL(config.resource),{requestInit:{headers:{authorization:'Bearer '+lastTokens.access_token}}}));const available=await nativeClient.listTools();assert(available.tools.some(t=>t.name==='festapp_access_inspect'));callbackCount++;res.end('Synthetic native client received its scoped token.');}catch(e){res.statusCode=500;res.end('callback failed');console.error(e.message);}});
const edgeConfig=privateRoot+'/edge.json';await writeFile(edgeConfig,JSON.stringify({api:status.API_URL,anon:status.ANON_KEY,service:status.SERVICE_ROLE_KEY,port:59731,instanceId:actor,tenant:{tenantId:profile.tenantId,organizationId:1,tenantOrigin:tenant,issuer:issuer.replace('http:','https:'),brokerSecret}}),{mode:0o600});
const edge=spawn('deno',['run','--allow-read','--allow-env','--allow-net',resolve(import.meta.dirname,'exchange.ts'),edgeConfig],{stdio:['ignore','pipe','pipe']});let edgeLog='';edge.stderr.on('data',b=>edgeLog+=b);edge.stdout.on('data',b=>edgeLog+=b);
let vite,preview,browserOpen=false;
const browserConfig=privateRoot+'/browser.json';const session='closure-mcp-real-'+process.pid;await writeFile(browserConfig,JSON.stringify({provider:null,plugins:[],headed:false,autoConnect:false}),{mode:0o600});
const browser=async(...args)=>{const {stdout}=await exec('agent-browser',['--config',browserConfig,'--headed','false','--ignore-https-errors','--session',session,'--json',...args],{timeout:45000,env:{...process.env,AGENT_BROWSER_CONFIG:browserConfig,AGENT_BROWSER_PLUGINS:'[]'}});const r=JSON.parse(stdout);assert(r.success,r.error);return r.data;};
const evaluate=async js=>(await browser('eval',js)).result;
const proxy=createHttps({key:await readFile(key),cert:await readFile(cert)},async(req,res)=>{try{const target=req.url.startsWith('/functions/v1/mcp-session-exchange')?'http://127.0.0.1:59731':req.url.startsWith('/auth/')||req.url.startsWith('/rest/')?status.API_URL:'http://127.0.0.1:59735';const chunks=[];for await(const c of req)chunks.push(c);const headers={...req.headers};delete headers.host;const response=await fetch(target+req.url,{method:req.method,headers,body:['GET','HEAD'].includes(req.method)?undefined:Buffer.concat(chunks)});const outHeaders=Object.fromEntries(response.headers);for(const name of ['content-encoding','transfer-encoding','content-length','connection'])delete outHeaders[name];res.writeHead(response.status,outHeaders);res.end(Buffer.from(await response.arrayBuffer()));}catch{res.statusCode=502;res.end('local transport unavailable');}});
try{
 await Promise.all([new Promise(r=>broker.listen(59732,'127.0.0.1',r)),new Promise(r=>callback.listen(59734,'127.0.0.1',r)),new Promise(r=>proxy.listen(59733,'127.0.0.1',r))]);
 let edgeReady=false;for(let n=0;n<40;n++){try{const health=await (await fetch('http://127.0.0.1:59731/__closure-health')).json();assert.equal(health.instanceId,actor);edgeReady=true;break;}catch{await new Promise(r=>setTimeout(r,250));}}
 assert(edgeReady,'task exchange did not become ready');
 const viteModule=await import('../../../../web_client/node_modules/vite/dist/node/index.js');
 // Production bundle of the real consent and real LoginModal. Only transport/config
 // and the synthetic client's exact continuation resolver are injected.
 const html=`<html><body><main id="app"></main><script type="module" src="./closure-entry.js"></script></body></html>`;
 const source=`import {AppConfig} from '/src/app_config.js';import {SupabaseService} from '/src/services/supabase_service.js';import {LocalizationService} from '/src/services/localization_service.js';import {McpConnectionPage} from '/src/components/mcp/mcp_connection_page.js';AppConfig.supabaseUrl=${JSON.stringify(tenant)};AppConfig.anonKey=${JSON.stringify(status.ANON_KEY)};AppConfig.organization=1;AppConfig.Keys.auth='closure-mcp-real';await LocalizationService.init();await SupabaseService.initialize();const resume=value=>{const u=new URL(value);if(u.origin!==${JSON.stringify(issuer)}||u.username||u.password||u.hash||!/^\\/connect\\/[A-Za-z0-9_-]+\\/finish$/.test(u.pathname)||[...u.searchParams].length!==1||!/^[A-Za-z0-9_-]{43}$/.test(u.searchParams.get('resume')||''))throw Error('invalid local continuation');return u.href;};window.closurePage=new McpConnectionPage(document.getElementById('app'),{resume});await window.closurePage.init();window.closureReady=true;`;
 const buildRoot=privateRoot+'/web';await mkdir(buildRoot,{recursive:true});await writeFile(buildRoot+'/index.html',html);await writeFile(buildRoot+'/closure-entry.js',source);
 const bundle=await viteModule.build({configFile:false,root:buildRoot,publicDir:resolve(root,'web_client/public'),logLevel:'error',build:{outDir:privateRoot+'/dist',emptyOutDir:true,rollupOptions:{input:buildRoot+'/index.html'}},plugins:[{name:'closure-source',resolveId(id){if(id.startsWith('/src/'))return resolve(root,'web_client',id.slice(1));}}]});
 preview=await viteModule.preview({configFile:false,root:buildRoot,build:{outDir:privateRoot+'/dist'},preview:{host:'127.0.0.1',port:59735,strictPort:true},logLevel:'error'});
 await mkdir(privateRoot+'/dist/assets/translations',{recursive:true});for(const language of ['cs','en'])await writeFile(privateRoot+'/dist/assets/translations/'+language+'.json',await readFile(resolve(root,'assets/translations/'+language+'.json')));
 // Vite copies public assets only from the configured project root.
 await browser('open','about:blank');browserOpen=true;await browser('network','route','**/*supabase.co/**','--abort');await browser('network','route','**/*festapp.net/**','--abort');
 const query=new URLSearchParams({client_id:'closure-native',response_type:'code',redirect_uri:clientCallback,resource:config.resource,scope:READ_SCOPE,state:'closure-state',code_challenge_method:'S256',code_challenge:createHash('sha256').update(verifier).digest('base64url')});
 await browser('open',issuer+'/auth?'+query);try { await browser('wait','--fn','window.closureReady === true'); } catch (error) { console.log(JSON.stringify(await browser('errors')));console.log(JSON.stringify(await evaluate('({page:location.origin+location.pathname,html:document.documentElement.outerHTML.slice(0,1000),scripts:[...document.scripts].map(x=>x.src.split("?")[0])})')));console.log(JSON.stringify(await browser('console')));throw error; }
 await browser('snapshot','-i');await writeFile(privateRoot+'/ready.json',JSON.stringify({tenant,issuer,actor,occasions:fixtures.map(f=>f.occasion)}),{mode:0o600});
 console.log('LOCAL_MCP_READY');
 await browser('click','button');
 await browser('wait','#login-form');
 await browser('snapshot','-i');
 await browser('fill','#email',user.data.user.email.replace(/^1\+/,''));
 await browser('fill','#password',password);
 await browser('click','#login-form button[type=submit]');
 try{await browser('wait','[data-select-all]');}catch(error){console.log(JSON.stringify(await evaluate('({page:location.origin+location.pathname,state:window.closurePage?.state,body:document.body.innerText.slice(0,1500)})')));console.log(JSON.stringify(await browser('console')));throw error;}
 assert.equal(await evaluate('closurePage.details.occasions.length'),3);
 console.log('LOCAL_MCP_LOGIN_PASS');
 assert.equal(storage.values('Delegation').length,0);
 await browser('snapshot','-i');
 await browser('click',`[data-occasion="${fixtures[0].occasion}"]`);
 assert.equal(await evaluate('document.querySelector("[data-select-all]").indeterminate'),true);
 await browser('click','[data-select-all]');
 assert.equal(await evaluate('closurePage.selected.size'),3);
 assert.equal(storage.values('Delegation').length,0);
 await browser('click','[data-select-all]');
 assert.equal(await evaluate('closurePage.selected.size'),0);
 await browser('click','[data-select-all]');
 await browser('snapshot','-i');
 const approveLabel=await evaluate("closurePage.text('approve')");
 await browser('find','role','button','click','--name',approveLabel);
 await browser('tab','t1');
 try { await browser('wait','--fn','window.closurePage?.state === "connected"'); } catch (error) { console.log(JSON.stringify({callbackCount,grants:storage.values('Delegation').map(g=>({access:g.access,connected:!!g.clientConnectedAt})),page:await evaluate('({state:window.closurePage?.state,path:location.pathname})')}));throw error; }
 assert.equal(callbackCount,1);assert(lastTokens?.access_token);
 const grants=storage.values('Delegation');assert.equal(grants.length,1);
 assert.deepEqual(new Set(grants[0].access.occasionIds),new Set(fixtures.map(f=>f.occasion)));
 assert.equal(grants[0].access.type,'occasions');
 assert(lastTokens.scope.includes(READ_SCOPE));
 assert(!lastTokens.scope.includes('festapp:occasions:create'));
 assert.equal(await evaluate('performance.getEntriesByType("resource").some(r=>/main\.dart|flutter|canvaskit/.test(r.name))'),false);
 const report={backend:status.API_URL,syntheticActor:actor,loginModal:true,productionBundle:true,brokerAndExchange:true,partialAllClear:true,grantsBeforeApproval:0,grantsAfterCompletion:grants.length,callbackCount,access:grants[0].access,createScope:false,noFlutter:true,transportBoundary:'test TLS proxy and exact HTTPS issuer-to-loopback HTTP mapping; synthetic native client callback',cases:[]};
 const appToken=await evaluate('(async()=> (await closurePage.client.auth.getSession()).data.session.access_token)()');
 const exchange=async(request,operation,extra={})=>fetch('http://127.0.0.1:59731/functions/v1/mcp-session-exchange',{method:'POST',headers:{origin:tenant,authorization:'Bearer '+appToken,'content-type':'application/json'},body:JSON.stringify({request,operation,...extra})});
 const completedRequest=await evaluate('closurePage.request');
 assert.equal((await exchange(completedRequest,'approve',{access:grants[0].access})).status,403);assert.equal(storage.values('Delegation').length,1);report.cases.push('repeated approval cannot mint a second grant');
 const freshRequest=async()=>{await browser('open',issuer+'/auth?'+query);await browser('wait','--fn','window.closureReady === true');return await evaluate('new URL(location.href).searchParams.get("request")');};
 // Unknown response observation must not replay approve or create another grant.
 let request=await freshRequest();
 assert.equal((await exchange(request,'approve',{access:{type:'occasions',occasionIds:[2147483647]}})).status,403);
 assert.equal(storage.values('Delegation').length,1);report.cases.push('foreign event rejected');
 const pending=storage.values('Connect').find(f=>f.request===request);assert(pending);storage.put('Connect',storage.get('TenantRequest',digest(request)).uid,{...pending,expiresAt:Date.now()-1},600);
 assert.equal((await exchange(request,'details')).status,403);report.cases.push('expired request rejected');
 request=await freshRequest();assert.equal((await exchange(request,'cancel')).status,200);assert.equal(storage.values('Delegation').length,1);report.cases.push('cancel does not grant');
 request=await freshRequest();
 const sqlFile=privateRoot+'/revoke-mcp.sql';await writeFile(sqlFile,`UPDATE public.occasion_users SET is_editor_order_view=false WHERE "user"='${actor}';`,{mode:0o600});
 await exec('psql',['-h','127.0.0.1','-p','59722','-U','postgres','-d','postgres','-Xq','-v','ON_ERROR_STOP=1','-f',sqlFile],{env:{...process.env,PGPASSWORD:'postgres'}});
 const empty=await exchange(request,'details');assert.equal(empty.status,200);assert.deepEqual((await empty.json()).occasions,[]);
 await browser('eval','closurePage.init()');await browser('wait','--fn','closurePage.state === "consent"');
 assert.equal(await evaluate('document.querySelector("[data-select-all]") === null'),true);
 assert.equal(await evaluate('closurePage.canApprove'),false);report.cases.push('live rights removal yields empty list and disabled approval');
 const inspected=await nativeClient.callTool({name:'festapp_access_inspect',arguments:{}});
 assert(!inspected.isError);assert.deepEqual(inspected.structuredContent?.data?.occasions ?? JSON.parse(inspected.content[0].text).data.occasions,[]);report.cases.push('existing native session observes revoked live access');

 const wrongOrigin=await fetch('http://127.0.0.1:59731/functions/v1/mcp-session-exchange',{method:'POST',headers:{origin:'https://other.example.invalid','content-type':'application/json'},body:JSON.stringify({request,operation:'details'})});assert.equal(wrongOrigin.status,403);report.cases.push('foreign tenant origin rejected');
 assert.equal(storage.values('Delegation').length,1);
 await writeFile(evidence+'/mcp-real-local.json',JSON.stringify(report,null,2)+'\n');
 console.log('LOCAL_MCP_GRANT_PASS');

} finally{if(browserOpen)await browser('close').catch(()=>{});await nativeClient?.close().catch(()=>{});edge.kill('SIGTERM');await new Promise(r=>preview?.httpServer?preview.httpServer.close(r):r());await new Promise(r=>proxy.close(r));await new Promise(r=>broker.close(r));await new Promise(r=>callback.close(r));await storage.close();await writeFile(privateRoot+'/edge.log',edgeLog,{mode:0o600});}
