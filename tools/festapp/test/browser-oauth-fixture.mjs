// Local browser harness: real issuer/MCP, with explicit real or simulated backend mode.
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { mkdtemp, rm, readFile, writeFile } from 'node:fs/promises';
import { execFileSync } from 'node:child_process';
import { createClient } from '@supabase/supabase-js';
import { parseProfile, digest } from '../src/context/profile.mjs';
import { canonicalBackendProfileSha256 } from '../../../automation/lib/backend_activation_manifest.mjs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { randomBytes, createHash, generateKeyPairSync } from 'node:crypto';
import { Client, StreamableHTTPClientTransport } from '@modelcontextprotocol/client';
import { fixture, profile } from './fixture.mjs';
import { parseRemoteConfig, READ_SCOPE } from '../src/remote/config.mjs';
import { openRemoteStorage } from '../src/remote/storage.mjs';
import { createRemoteApp } from '../src/remote/server.mjs';
import { connectionActive } from '../../../packages/festapp_contracts/mcp-connection.mjs';
const cleanups=[]; const t={after: f => cleanups.push(f)};
const real=process.env.FESTAPP_BROWSER_REAL_BACKEND === '1';
const root=await mkdtemp(join(tmpdir(),'festapp-browser-'));
let base, profileValue;
if(real) {
 const privateRoot=process.env.FESTAPP_BROWSER_BACKEND_DIR;
 assert(privateRoot, 'FESTAPP_BROWSER_BACKEND_DIR is required for the task-owned backend');
 const status=JSON.parse(await readFile(privateRoot+'/status.json','utf8'));
 assert.equal(status.API_URL,'http://127.0.0.1:62421');
 const sql=statement=>execFileSync('psql',['-h','127.0.0.1','-p','62422','-U','postgres','-d','postgres','-XqAt','-v','ON_ERROR_STOP=1','-c',statement],{encoding:'utf8',env:{...process.env,PGPASSWORD:'postgres'}}).trim();
 assert.equal(sql("select current_setting('cron.launch_active_jobs')"),'off');
 assert.equal(sql('select project from festapp_test_support.disposable_environment'),'festapp-pr749-oauth-local');
 assert.equal(sql('select bool_and(paused AND worker_url IS NULL) from email_capacity'),'t');
 const org=Number(sql("insert into organizations(title,data) values('MCP browser test','{}') returning id"));
 const unit=Number(sql(`insert into units(title,organization) values('Browser organizer',${org}) returning id`));
 const email=`${org}+browser-${randomBytes(8).toString('hex')}@example.invalid`, password=randomBytes(24).toString('base64url');
 const admin=createClient(status.API_URL,status.SERVICE_ROLE_KEY,{auth:{persistSession:false,autoRefreshToken:false}});
 const created=await admin.auth.admin.createUser({email,password,email_confirm:true}); assert.ifError(created.error); const actor=created.data.user.id;
 sql(`insert into user_info(id,email_readonly,organization) values('${actor}','${email}',${org}); insert into unit_users(unit,"user",is_manager,is_editor,is_editor_view) values(${unit},'${actor}',true,true,true);`);
 const occasion=Number(sql(`insert into occasions(title,link,organization,unit,start_time,end_time,is_open,is_hidden,data,features) values('Browser occasion',gen_random_uuid()::text,${org},${unit},now(),now()+interval '1 day',true,false,'{}','[]') returning id`));
 sql(`insert into occasion_link_reservations(slug,occasion) select link,id from occasions where id=${occasion}; insert into occasion_users(occasion,"user",is_editor,is_editor_view,is_editor_order,is_editor_order_view,is_manager) values(${occasion},'${actor}',true,true,true,true,true); notify pgrst, 'reload schema';`);
 await writeFile(privateRoot+'/browser-login.json',JSON.stringify({email,password}),{mode:0o600});
 const activation=JSON.stringify({schemaVersion:1,tenantId:'browser-fixture',generation:1,backend:'canonical'});
 profileValue=parseProfile({schemaVersion:1,name:'browser-fixture',kind:'disposable-local',tenantId:'browser-fixture',backendOrigin:status.API_URL,publicApiKey:status.ANON_KEY,organizationId:org,activationUrl:status.API_URL+'/backend-activation.json',activationSha256:digest(activation),generation:1,canonicalProfileSha256:canonicalBackendProfileSha256({tenantId:'browser-fixture',canonicalOrigin:status.API_URL,canonicalAnonKey:status.ANON_KEY,canonicalOrganizationId:org})});
 base={owner:{fetch:(input,init)=>new URL(input instanceof Request?input.url:input).href===profileValue.activationUrl?new Response(activation):fetch(input,init)}};
} else {base=await fixture(t);profileValue=profile();}
const storage=await openRemoteStorage(root,randomBytes(32));
const server=createServer(); await new Promise(r=>server.listen(0,'127.0.0.1',r));
const issuer=`http://127.0.0.1:${server.address().port}`;
const {binding,...rawProfile}=profileValue;
const config=parseRemoteConfig({schemaVersion:2,issuer,profile:rawProfile,clients:[{id:'browser-fixture',name:'Browser fixture',redirectUris:[issuer+'/callback']}]});
const {privateKey}=generateKeyPairSync('rsa',{modulusLength:2048});
const app=createRemoteApp(config,storage,{cookieKeys:['a'.repeat(48),'b'.repeat(48)],jwks:{keys:[{...privateKey.export({format:'jwk'}),kid:'fixture',use:'sig',alg:'RS256'}]},brokerSecret:'b'.repeat(43),fetchImpl:base.owner.fetch});
let verifier; let tokens=[]; let result='';
server.on('request',async(req,res)=>{ try {
 const u=new URL(req.url,issuer);
 if(u.pathname==='/start') { verifier=randomBytes(32).toString('base64url'); const p=new URLSearchParams({client_id:'browser-fixture',response_type:'code',redirect_uri:issuer+'/callback',scope:`openid offline_access ${READ_SCOPE}`,code_challenge:createHash('sha256').update(verifier).digest('base64url'),code_challenge_method:'S256',state:u.searchParams.get('abandon')?'abandon':'normal',resource:config.resource}); res.writeHead(302,{location:'/auth?'+p}); res.end(); return; }
 if(u.pathname==='/callback') {
  assert.equal(u.searchParams.get('iss'),issuer); assert(u.searchParams.get('code'));
  if(u.searchParams.get('state')==='abandon') { result='Callback reached; replacement code intentionally not exchanged.'; }
  else { const r=await fetch(issuer+'/token',{method:'POST',body:new URLSearchParams({client_id:'browser-fixture',grant_type:'authorization_code',code:u.searchParams.get('code'),redirect_uri:issuer+'/callback',code_verifier:verifier,resource:config.resource})}); assert.equal(r.status,200,await r.clone().text()); let token=await r.json();
   const client=new Client({name:'browser-fixture',version:'1'}); await client.connect(new StreamableHTTPClientTransport(new URL(config.resource),{requestInit:{headers:{authorization:`Bearer ${token.access_token}`}}})); const list=await client.listTools(); assert(list.tools.length>0); await client.close();
   const refresh=await fetch(issuer+'/token',{method:'POST',body:new URLSearchParams({client_id:'browser-fixture',grant_type:'refresh_token',refresh_token:token.refresh_token,resource:config.resource})}); assert.equal(refresh.status,200,await refresh.clone().text()); const next=await refresh.json(); assert.notEqual(next.refresh_token,token.refresh_token); tokens.push(next); result='Token exchange, MCP tools/list and refresh succeeded.'; }
  res.writeHead(200,{'content-type':'text/html'});res.end(`<h1>${result}</h1><a href="/start">Start</a>`);return;
 }
 if(u.pathname==='/fixture-check') { const grants=storage.values('Delegation'); const active=grants.filter(g=>connectionActive(g)); const statuses=[]; for(const token of tokens) { const r=await fetch(config.resource,{method:'POST',headers:{authorization:`Bearer ${token.access_token}`,'content-type':'application/json'},body:'{}'}); statuses.push(r.status); } res.writeHead(200,{'content-type':'application/json'});res.end(JSON.stringify({issued:tokens.length,active:active.length,revoked:grants.filter(g=>g.revoked).length,statuses,backend:real?'real local Auth and REST; activation manifest simulated':'simulated Auth and REST transport'}));return; }
 app.app(req,res);
 } catch(e) {console.error(e.stack);res.writeHead(500);res.end('Fixture assertion failed');} });
console.log(issuer);
process.on('SIGTERM',async()=>{await new Promise(r=>server.close(r));await storage.close();for(const f of cleanups)await f();await rm(root,{recursive:true,force:true});process.exit(0)});
