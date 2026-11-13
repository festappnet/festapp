import test from 'node:test';
import assert from 'node:assert/strict';
import { setup, connect, apiRequest, httpRequest } from './api-fixture.mjs';
import { parseRemoteConfig } from '../src/remote/config.mjs';
import { profile } from './fixture.mjs';
import { generateKeyPair, exportJWK, SignJWT, calculateJwkThumbprint } from 'jose';
import { randomUUID, createHash } from 'node:crypto';

test('real OAuth API grants isolate resources, transports, immutable profile and revoked reads', async t => {
    const f = await setup(t);
    const browser=f.browser;let consentHtml;f.browser=async(...args)=>{const response=await browser(...args);if(response.status===200&&response.headers.get('content-type')?.includes('text/html')){const html=await response.clone().text();if(html.includes('consentVersion'))consentHtml=html;}return response;};
    const global = await connect(f);
    assert(consentHtml.includes(f.config.endpoints[0].resource));assert(consentHtml.includes('Data: <code>operator</code>'));
    let r = await apiRequest(f, global.tokens);
    assert.equal(r.status,200,await r.clone().text());
    const result = await r.json();
    assert.equal(r.headers.get('x-request-id'),result.meta.requestId);
    assert.equal(result.meta.organizationId,1);
    assert.equal((await apiRequest(f,global.tokens,'context.inspect',{},'regional-api')).status,401);
    const regional = await connect(f,{ resources:[f.config.endpoints[1].resource] });
    assert.equal((await apiRequest(f,regional.tokens,'context.inspect',{},'regional-api')).status,200);
    assert.equal((await apiRequest(f,regional.tokens)).status,401);
    const mcp = await connect(f,{clientId:'chatgpt-fixture',resources:[f.config.resource]});
    assert.equal((await apiRequest(f,mcp.tokens)).status,401);
    const refused = await fetch(f.issuer+'/mcp',{method:'POST',headers:{authorization:'Bearer '+global.tokens.access_token,'content-type':'application/json'},body:'{}'});
    assert.equal(refused.status,401);
    const grant = f.storage.values('Delegation').find(g=>g.resource===f.config.endpoints[0].resource);
    assert.equal(grant.proofProfile,'bearer');assert.equal(grant.profileBinding,profile().binding);
    f.storage.revoke(grant.id);
    assert.equal((await apiRequest(f,global.tokens)).status,401);
});

test('API ingress, parsers, method, policy and unknown routes return safe Problem Details', async t => {
    const f=await setup(t), {tokens}=await connect(f);
    for (const [operation,body,headers,status] of [
        ['context.inspect','{',{},400],['context.inspect','x'.repeat(50000),{},413],
        ['context.inspect','['.repeat(40)+'0'+']'.repeat(40),{},413],
        ['context.inspect','{}',{'content-type':'text/plain'},415],
        ['unknown',{}, {},404],['products.list',{occasionId:7}, {},403],
        ['context.inspect',{organizationId:2},{},422],
        ['context.inspect',{}, {'x-festapp-endpoint':'regional-api'},400],
        ['context.inspect',{}, {forwarded:'host=evil.example'},400],
    ]) {
        const r=await apiRequest(f,tokens,operation,body,'global-api',headers);
        assert.equal(r.status,status,await r.clone().text());
        assert.match(r.headers.get('content-type'),/application\/problem\+json/);
        const problem=await r.json();assert.equal(problem.status,status);assert.equal(problem.requestId,r.headers.get('x-request-id'));
    }
    const endpoint=f.config.endpoints[0],headers={host:new URL(endpoint.publicBase).host,'x-forwarded-host':new URL(endpoint.publicBase).host,'x-festapp-endpoint':endpoint.endpointId,'x-forwarded-proto':'https'};
    const metadata=await httpRequest(f.issuer+'/.well-known/oauth-protected-resource/integrations',{headers});
    assert.equal((await metadata.json()).resource,endpoint.resource);
    const method=await httpRequest(f.issuer+'/integrations/v1/operations/context.inspect',{headers});assert.equal(method.status,405);assert.equal(method.headers.get('allow'),'POST');
});

test('provider does not advertise unsupported default DPoP or PAR and resource server refuses bound Bearer downgrade', async t=>{
    const f=await setup(t);
    const discovery=await (await fetch(f.issuer+'/.well-known/openid-configuration')).json();
    assert.equal(discovery.dpop_signing_alg_values_supported,undefined);assert.equal(discovery.pushed_authorization_request_endpoint,undefined);
    const {tokens}=await connect(f);
    const token=f.storage.values('AccessToken')[0];
    // Persist a provider-recognized sender constraint, then exercise the actual
    // token lookup/HTTP path. A bearer request must not shed that constraint.
    token.jkt='fixture-bound-thumbprint';
    const access=await f.provider.AccessToken.find(tokens.access_token);
    access.jkt=token.jkt;
    f.storage.put('AccessToken',access.jti,{...token,jkt:token.jkt},300);
    assert.equal((await apiRequest(f,tokens)).status,401);
});

test('resource DPoP validates signatures, public URL, ath, replay and rejects Bearer downgrade',async()=>{
    const {createProofVerifier}=await import('../src/remote/proof.mjs');
    const verify=createProofVerifier(),{publicKey,privateKey}=await generateKeyPair('ES256');
    const jwk=await exportJWK(publicKey),jkt=await calculateJwkThumbprint(jwk),credential='a'.repeat(40);
    const endpoint={publicBase:'https://api.vstupenky.online/integrations/v1'};
    const path='/integrations/v1/operations/context.inspect';
    const proof=async(changes={})=>new SignJWT({htm:'POST',htu:'https://api.vstupenky.online'+path,ath:createHash('sha256').update(credential).digest('base64url'),iat:Math.floor(Date.now()/1000),jti:randomUUID(),...changes}).setProtectedHeader({alg:'ES256',typ:'dpop+jwt',jwk}).sign(privateKey);
    const req={method:'POST',path,headers:{authorization:'DPoP '+credential,dpop:await proof()}};
    await verify(req,{jkt},credential,endpoint,{proofProfile:'dpop'});
    await assert.rejects(()=>verify(req,{jkt},credential,endpoint,{proofProfile:'dpop'}),/AUTHENTICATION_REQUIRED/);
    for(const changes of [{htm:'GET'},{htu:'https://api.festapp.net'+path},{ath:'wrong'},{iat:1}]){
        req.headers.dpop=await proof(changes);await assert.rejects(()=>verify(req,{jkt},credential,endpoint,{proofProfile:'dpop'}),/AUTHENTICATION_REQUIRED/);
    }
    req.headers.authorization='Bearer '+credential;await assert.rejects(()=>verify(req,{jkt},credential,endpoint,{proofProfile:'dpop'}),/AUTHENTICATION_REQUIRED/);
});

test('pinned provider issues DPoP tokens and real HTTP refuses missing proof, key substitution, replay and bearer downgrade',async t=>{
    const f=await setup(t,{proofProfile:'dpop'});
    const keys=await generateKeyPair('ES256'),jwk=await exportJWK(keys.publicKey);
    const sign=async(htu,ath)=>new SignJWT({htm:'POST',htu,iat:Math.floor(Date.now()/1000),jti:randomUUID(),...(ath?{ath}:{})}).setProtectedHeader({alg:'ES256',typ:'dpop+jwt',jwk}).sign(keys.privateKey);
    f.tokenProof=()=>sign(f.issuer+'/token');
    const {tokens}=await connect(f);
    assert.equal(tokens.token_type,'DPoP');
    const downgrade=await apiRequest(f,tokens);assert.equal(downgrade.status,401);assert.match(downgrade.headers.get('www-authenticate'),/^DPoP /);
    const ath=createHash('sha256').update(tokens.access_token).digest('base64url');
    const headers={authorization:'DPoP '+tokens.access_token,dpop:await sign('https://api.festapp.net/integrations/v1/operations/context.inspect',ath)};
    const good=await apiRequest(f,tokens,'context.inspect',{},'global-api',headers);assert.equal(good.status,200,await good.clone().text());
    assert.equal((await apiRequest(f,tokens,'context.inspect',{},'global-api',headers)).status,401);
    const missing={...headers};delete missing.dpop;assert.equal((await apiRequest(f,tokens,'context.inspect',{},'global-api',missing)).status,401);
    const wrong={...headers,dpop:await sign('https://api.vstupenky.online/integrations/v1/operations/context.inspect',ath)};
    assert.equal((await apiRequest(f,tokens,'context.inspect',{},'global-api',wrong)).status,401);
});

test('API refresh requires the bound resource, rotation detects reuse and races never create a wider grant',async t=>{
    const f=await setup(t),issued=await connect(f);
    const refresh=async(resource,refreshToken=issued.tokens.refresh_token)=>fetch(f.issuer+'/token',{method:'POST',body:new URLSearchParams({client_id:'api-fixture',grant_type:'refresh_token',refresh_token:refreshToken,...(resource?{resource}:{})})});
    assert.equal((await refresh()).status,400);
    assert.equal((await refresh(f.config.resource)).status,400);
    assert.equal((await refresh(f.config.endpoints[1].resource)).status,400);
    const good=await refresh(f.config.endpoints[0].resource);assert.equal(good.status,200,await good.clone().text());
    const rotated=await good.json();assert.notEqual(rotated.refresh_token,issued.tokens.refresh_token);
    assert.equal((await refresh(f.config.endpoints[0].resource)).status,400);
    assert.equal((await apiRequest(f,rotated)).status,401);
    const next=await connect(f),race=await Promise.all([refresh(f.config.endpoints[0].resource,next.tokens.refresh_token),refresh(f.config.endpoints[0].resource,next.tokens.refresh_token)]);
    assert.deepEqual(race.map(r=>r.status).sort(),[200,400]);
    const accepted=await race.find(r=>r.status===200).json();
    assert.equal((await apiRequest(f,accepted)).status,401);
});

test('regional grant cannot rebind its profile and API client policy cannot widen an already consented operation allowlist',async t=>{
    const f=await setup(t),{tokens}=await connect(f,{resources:[f.config.endpoints[1].resource]});
    const grant=f.storage.values('Delegation')[0];
    assert.equal(grant.endpointId,'regional-api');
    f.storage.putUntil('Delegation',grant.id,{...grant,profileBinding:'a'.repeat(64)},grant.expiresAt);
    assert.equal((await apiRequest(f,tokens,'context.inspect',{},'regional-api')).status,401);
    f.storage.putUntil('Delegation',grant.id,grant,grant.expiresAt);
    const client=f.config.clients.find(c=>c.id==='api-fixture');
    const original=grant.operationAllowlist;
    f.storage.putUntil('Delegation',grant.id,{...grant,operationAllowlist:original.filter(id=>id!=='access.inspect')},grant.expiresAt);
    assert(client.allowedOperations.includes('access.inspect'));
    assert.equal((await apiRequest(f,tokens,'access.inspect',{},'regional-api')).status,403);
});

test('hosted DPoP replay evidence survives a fresh verifier instance against the same owning auth store',async t=>{
    const f=await setup(t),{createProofVerifier}=await import('../src/remote/proof.mjs');
    const {publicKey,privateKey}=await generateKeyPair('ES256'),jwk=await exportJWK(publicKey),jkt=await calculateJwkThumbprint(jwk),credential='b'.repeat(40);
    const endpoint=f.config.endpoints[0],path='/integrations/v1/operations/context.inspect';
    const dpop=await new SignJWT({htm:'POST',htu:'https://api.festapp.net'+path,ath:createHash('sha256').update(credential).digest('base64url'),iat:Math.floor(Date.now()/1000),jti:randomUUID()}).setProtectedHeader({alg:'ES256',typ:'dpop+jwt',jwk}).sign(privateKey);
    const request={method:'POST',path,headers:{authorization:'DPoP '+credential,dpop}};
    await createProofVerifier({storage:f.storage})(request,{jkt},credential,endpoint,{proofProfile:'dpop'});
    await assert.rejects(()=>createProofVerifier({storage:f.storage})(request,{jkt},credential,endpoint,{proofProfile:'dpop'}),/AUTHENTICATION_REQUIRED/);
    assert.equal(f.storage.stats().byModel.DPoPResourceReplay,1);
});

test('authorized HTTP artifacts reuse the canonical cache and reauthorize connection and grant on every binary read',async t=>{
    const {readFile}=await import('node:fs/promises'),{reply}=await import('./fixture.mjs');
    const sample=JSON.parse(await readFile(new URL('../../../integrations/make/src/samples.json',import.meta.url),'utf8'))['orders.report'];
    let authorization=true;
    const scopes=['festapp:ticket-layouts:read','festapp:orders:read','festapp:report-exports:read'];
    const f=await setup(t,{apiPolicy:{allowedScopes:scopes,allowedOperations:['context.inspect','access.inspect','orders.report','reports.export']},fetchImpl:(url)=>{
        if(url.pathname.endsWith('/get_operator_order_report_v1'))return reply(sample);
        if(url.pathname.endsWith('/authorize_authoring_export'))return reply(authorization);
    }});
    const first=await connect(f,{scope:scopes.join(' ')});
    const exported=await apiRequest(f,first.tokens,'reports.export',{occasionId:7});assert.equal(exported.status,200,await exported.clone().text());
    const uri=(await exported.json()).data.file.uri;
    const endpoint=f.config.endpoints[0];
    const read=tokens=>httpRequest(f.issuer+'/integrations/v1/artifacts/read',{method:'POST',headers:{host:'api.festapp.net','x-forwarded-host':'api.festapp.net','x-forwarded-proto':'https','x-festapp-endpoint':endpoint.endpointId,authorization:'Bearer '+tokens.access_token,'content-type':'application/json'},body:JSON.stringify({uri})});
    let response=await read(first.tokens);assert.equal(response.status,200);assert.match(response.headers.get('content-type'),/application\/json/);assert.equal(response.headers.get('cache-control'),'no-store');assert.deepEqual(await response.json(),sample);
    const second=await connect(f,{scope:scopes.join(' ')});
    assert.equal((await read(second.tokens)).status,403,'a new connection cannot adopt a previous private export');
    authorization=false;assert.equal((await read(first.tokens)).status,403,'live domain rights are checked again');
    authorization=true;
    const issued=await f.provider.AccessToken.find(first.tokens.access_token);f.storage.revoke(issued.grantId);
    assert.equal((await read(first.tokens)).status,401);
});

test('managed PAR profile accepts a pushed PKCE flow, refuses unpushed requests and cannot replay request_uri',async t=>{
    const f=await setup(t,{apiPolicy:{requirePar:true}});
    const discovery=await(await fetch(f.issuer+'/.well-known/openid-configuration')).json();
    assert.equal(discovery.pushed_authorization_request_endpoint,f.issuer+'/request');
    const direct=await f.browser('/auth?'+new URLSearchParams({client_id:'api-fixture',response_type:'code',redirect_uri:f.issuer+'/callback',scope:'openid festapp:ticket-layouts:read',resource:f.config.endpoints[0].resource,code_challenge:'a'.repeat(43),code_challenge_method:'S256'}));
    assert.equal(direct.status,303);
    assert(new URL(direct.headers.get('location'),f.issuer).searchParams.get('error')); 
    const {tokens}=await connect(f,{usePar:true});assert.equal((await apiRequest(f,tokens)).status,200);
    const replay=await f.browser('/auth?'+new URLSearchParams({client_id:'api-fixture',request_uri:f.lastPar}));
    if(replay.status===303)assert(new URL(replay.headers.get('location'),f.issuer).searchParams.get('error'));else assert.equal(replay.status,400);
});

test('issuer signing/cookie key overlap retains valid opaque credentials while explicit revocation still wins',async t=>{
    const f=await setup(t),{tokens}=await connect(f);
    const {generateKeyPairSync}=await import('node:crypto');
    const newKey=generateKeyPairSync('rsa',{modulusLength:2048}).privateKey.export({format:'jwk'});
    const {createRemoteApp}=await import('../src/remote/server.mjs');
    const rotated=createRemoteApp(f.config,f.storage,{...f.keyMaterial,cookieKeys:['c'.repeat(48),...f.keyMaterial.cookieKeys],jwks:{keys:[{...newKey,kid:'rotated-fixture',use:'sig',alg:'RS256'},...f.keyMaterial.jwks.keys]},fetchImpl:f.owner.fetch});
    f.server.removeAllListeners('request');f.server.on('request',rotated.app);
    const keys=await(await fetch(f.issuer+'/jwks')).json();assert(keys.keys.some(k=>k.kid==='fixture'));assert(keys.keys.some(k=>k.kid==='rotated-fixture'));assert(keys.keys.every(k=>!k.d));
    assert.equal((await apiRequest(f,tokens)).status,200);
    const issued=await rotated.provider.AccessToken.find(tokens.access_token);f.storage.revoke(issued.grantId);
    assert.equal((await apiRequest(f,tokens)).status,401);
});

test('confidential PKCE client authenticates with registered private_key_jwt and rejects assertion replay without a shared secret',async t=>{
    const keys=await generateKeyPair('RS256'),jwk={...await exportJWK(keys.publicKey),kid:'confidential-fixture',alg:'RS256',use:'sig'};
    const f=await setup(t,{apiPolicy:{tokenEndpointAuthMethod:'private_key_jwt',jwks:{keys:[jwk]}}});
    let assertion;
    const fresh=()=>new SignJWT({jti:randomUUID()}).setIssuer('api-fixture').setSubject('api-fixture').setAudience(f.issuer+'/token').setIssuedAt().setExpirationTime('60s').setProtectedHeader({alg:'RS256',kid:jwk.kid}).sign(keys.privateKey);
    f.clientAssertion=async()=>assertion=await fresh();
    const {tokens}=await connect(f);assert.equal((await apiRequest(f,tokens)).status,200);
    const refresh=jwt=>fetch(f.issuer+'/token',{method:'POST',body:new URLSearchParams({client_id:'api-fixture',grant_type:'refresh_token',refresh_token:tokens.refresh_token,resource:f.config.endpoints[0].resource,client_assertion_type:'urn:ietf:params:oauth:client-assertion-type:jwt-bearer',client_assertion:jwt})});
    assert.equal((await refresh(assertion)).status,401);
    const rotated=await refresh(await fresh());assert.equal(rotated.status,200,await rotated.clone().text());
});

test('a disconnected MCP export retains the shared document slot until actual work settles, then API admission recovers',async t=>{
    const {request}=await import('node:http'),{readFile}=await import('node:fs/promises'),{reply}=await import('./fixture.mjs');
    const sample=JSON.parse(await readFile(new URL('../../../integrations/make/src/samples.json',import.meta.url),'utf8'))['orders.report'];
    let entered,release,finished;
    const began=new Promise(resolve=>entered=resolve),blocked=new Promise(resolve=>release=resolve),settled=new Promise(resolve=>finished=resolve);
    let hold=true;
    const scopes=['festapp:ticket-layouts:read','festapp:orders:read','festapp:report-exports:read'];
    const f=await setup(t,{apiPolicy:{allowedScopes:scopes,allowedOperations:['context.inspect','access.inspect','orders.report','reports.export']},auditObserver:event=>{if(event.event==='operation'&&event.operation==='reports.export')finished();},fetchImpl:async url=>{
        if(url.pathname.endsWith('/get_operator_order_report_v1')){if(hold){entered();await blocked;}return reply(sample);}
        if(url.pathname.endsWith('/authorize_authoring_export'))return reply(true);
    }});
    const mcp=await connect(f,{clientId:'chatgpt-fixture',resources:[f.config.resource],scope:scopes.join(' ')}),api=await connect(f,{scope:scopes.join(' ')});
    const disconnected=request(f.issuer+'/mcp',{method:'POST',headers:{authorization:'Bearer '+mcp.tokens.access_token,'content-type':'application/json',accept:'application/json, text/event-stream','mcp-protocol-version':'2025-11-25'}});
    disconnected.on('error',()=>{});
    disconnected.end(JSON.stringify({jsonrpc:'2.0',id:1,method:'tools/call',params:{name:'festapp_reports_export',arguments:{occasionId:7}}}));
    try{
        await began;disconnected.destroy();
        const refused=await apiRequest(f,api.tokens,'reports.export',{occasionId:7});assert.equal(refused.status,429);assert.equal((await refused.json()).outcome,'rejected');
    }finally{hold=false;release();}
    await settled;
    const recovered=await apiRequest(f,api.tokens,'reports.export',{occasionId:7});assert.equal(recovered.status,200,await recovered.clone().text());
});

test('public static routes serve every facade, data and proof projection with cache revalidation',async t=>{
    const f=await setup(t);
    for(const endpoint of f.config.endpoints)for(const profile of ['operator','order-summary'])for(const proof of ['bearer','dpop']){
        const headers={host:new URL(endpoint.publicBase).host,'x-forwarded-host':new URL(endpoint.publicBase).host,'x-festapp-endpoint':endpoint.endpointId,'x-forwarded-proto':'https'};
        const prefix=f.issuer+'/integrations/v1'+(profile==='operator'?'':'/profiles/order-summary')+(proof==='bearer'?'':'/proofs/dpop');
        const spec=await httpRequest(prefix+'/openapi.json',{headers});assert.equal(spec.status,200);const body=await spec.json();assert.equal(body['x-proof-profile'],proof);
        const cached=await httpRequest(prefix+'/openapi.json',{headers:{...headers,'if-none-match':spec.headers.get('etag')}});assert.equal(cached.status,304);
        const manifest=await httpRequest(prefix+'/manifest.json',{headers});assert.equal((await manifest.json()).projectionDigest,body['x-projection-digest']);
        const docs=await httpRequest(prefix+'/docs/',{headers});assert.equal(docs.status,200);assert.match(docs.headers.get('content-security-policy'),/connect-src 'none'/);assert((await docs.text()).includes(body['x-projection-digest']));
    }
});


test('explicit 365-day API consent keeps the 30-day refresh idle limit and capacity rejects before token consumption',async t=>{
 const f=await setup(t,{apiPolicy:{maxConsentDays:365}}),{tokens}=await connect(f,{consentFields:{durationDays:'365'}});
 const grant=f.storage.values('Delegation').find(g=>g.clientId==='api-fixture');assert(grant.expiresAt-Date.now()>364*86400000);
 const active=await f.storage.adapter('RefreshToken').find(tokens.refresh_token);assert(active.exp*1000-Date.now()<=30*86400000+1000);
 const stats=f.storage.stats;f.storage.stats=()=>({...stats(),records:19990});
 const response=await fetch(f.issuer+'/token',{method:'POST',body:new URLSearchParams({client_id:'api-fixture',grant_type:'refresh_token',refresh_token:tokens.refresh_token,resource:f.config.endpoints[0].resource})});
 assert.equal(response.status,503);assert.equal((await response.json()).error,'temporarily_unavailable');assert(!(await f.storage.adapter('RefreshToken').find(tokens.refresh_token)).consumed);
 f.storage.stats=stats;assert.equal((await apiRequest(f,tokens)).status,200);
});

test('HTTP synthetic preview uses the canonical PDF renderer and rasterizer without saving artwork',async t=>{
 const {canonicalPreview}=await import('./render-fixture.mjs'),{reply}=await import('./fixture.mjs');const rendered=await canonicalPreview();
 const scopes=['festapp:ticket-layouts:read','festapp:ticket-artwork:preview'];let previews=0;
 const f=await setup(t,{apiPolicy:{allowedScopes:scopes,allowedOperations:['context.inspect','access.inspect','ticket_layouts.preview']},previewFetch:(_url,init)=>{previews++;return reply(rendered[JSON.parse(init.body).mode]);}});
 const {tokens}=await connect(f,{scope:scopes.join(' ')});
 const response=await apiRequest(f,tokens,'ticket_layouts.preview',{occasionId:7,type:'named',scenario:'long'});assert.equal(response.status,200,await response.clone().text());
 const result=await response.json();assert.equal(result.data.image.mimeType,'image/png');assert.equal(result.data.pdf.mimeType,'application/pdf');assert(result.data.draftFingerprint);assert.equal(previews,2);
 const endpoint=f.config.endpoints[0];
 const artifact=await httpRequest(f.issuer+'/integrations/v1/artifacts/read',{method:'POST',headers:{host:new URL(endpoint.publicBase).host,'x-forwarded-host':new URL(endpoint.publicBase).host,'x-festapp-endpoint':endpoint.endpointId,'x-forwarded-proto':'https',authorization:'Bearer '+tokens.access_token,'content-type':'application/json'},body:JSON.stringify({uri:result.data.pdf.uri})});
 assert.equal(artifact.status,200);assert.equal((await artifact.text()).slice(0,5),'%PDF-');
 assert.equal(f.audit.filter(e=>e.event==='operation'&&e.operation==='ticket_layouts.save').length,0);
 const now=Date.now;try{
  Date.now=()=>now()+16*60000;
  const refreshed=await fetch(f.issuer+'/token',{method:'POST',body:new URLSearchParams({client_id:'api-fixture',grant_type:'refresh_token',refresh_token:tokens.refresh_token,resource:endpoint.resource})});assert.equal(refreshed.status,200);
  const fresh=await refreshed.json();
  const expired=await httpRequest(f.issuer+'/integrations/v1/artifacts/read',{method:'POST',headers:{host:new URL(endpoint.publicBase).host,'x-forwarded-host':new URL(endpoint.publicBase).host,'x-festapp-endpoint':endpoint.endpointId,'x-forwarded-proto':'https',authorization:'Bearer '+fresh.access_token,'content-type':'application/json'},body:JSON.stringify({uri:result.data.pdf.uri})});
  assert.equal(expired.status,404,'freshly authenticated access cannot revive an expired PDF');
 }finally{Date.now=now;}

});

test('refresh burst cap preserves the unconsumed credential and recovers after the original limiter window',async t=>{
 const {createRateLimiter}=await import('../src/remote/rate-limit.mjs');let clock=0;
 const f=await setup(t,{rateLimiter:createRateLimiter({now:()=>clock})});let {tokens}=await connect(f);
 const refresh=()=>fetch(f.issuer+'/token',{method:'POST',body:new URLSearchParams({client_id:'api-fixture',grant_type:'refresh_token',refresh_token:tokens.refresh_token,resource:f.config.endpoints[0].resource})});
 for(let i=0;i<12;i++){const response=await refresh();assert.equal(response.status,200);tokens=await response.json();}
 const limited=await refresh();assert.equal(limited.status,503);assert.equal(limited.headers.get('retry-after'),'60');assert(!(await f.storage.adapter('RefreshToken').find(tokens.refresh_token)).consumed);
 clock=60001;const recovered=await refresh();assert.equal(recovered.status,200);tokens=await recovered.json();assert.equal((await apiRequest(f,tokens)).status,200);
});

test('the eight-slot issuer token queue refuses overflow and recovers without revoking an admitted valid family',async t=>{
 const f=await setup(t),{tokens}=await connect(f);let entered,release,arrived,seen=0;
 const started=new Promise(r=>entered=r),gate=new Promise(r=>release=r),eight=new Promise(r=>arrived=r);
 f.server.prependListener('request',req=>{if(req.url==='/token'&&++seen===8)arrived();});
 const find=f.provider.RefreshToken.find.bind(f.provider.RefreshToken);let hold=true;
 f.provider.RefreshToken.find=async(value,...args)=>{if(hold&&value===tokens.refresh_token){entered();await gate;}return find(value,...args);};
 const exchange=token=>fetch(f.issuer+'/token',{method:'POST',body:new URLSearchParams({client_id:'api-fixture',grant_type:'refresh_token',refresh_token:token,resource:f.config.endpoints[0].resource})});
 const accepted=exchange(tokens.refresh_token);await started;
 const waiting=Array.from({length:7},(_,i)=>exchange('invalid-unissued-token-'+i));
 try{
  await eight;const overflow=await exchange('overflow-unissued-token');assert.equal(overflow.status,429);
 }finally{hold=false;release();}
 const issued=await accepted;assert.equal(issued.status,200);const rotated=await issued.json();
 assert((await Promise.all(waiting)).every(response=>response.status===400));
 assert.equal((await exchange(rotated.refresh_token)).status,200);
 assert.equal((await apiRequest(f,rotated)).status,200);
});

test('legacy Make remains available beyond the former date while review cutover is deferred', async t => {
 const f=await setup(t,{makeMigration:true});
 t.mock.method(Date,'now',()=>Date.UTC(2027,0,1));
 const response=await httpRequest(f.issuer+'/make/v1');
 assert.equal(response.status,200);
 assert.equal(response.headers.get('sunset'),null);
});

test('same Make client keeps original grants live while a distinct regional API grant is consented, without audience promotion',async t=>{
 const f=await setup(t,{makeMigration:true}),scope='festapp:ticket-layouts:read festapp:orders:read';
 const options={clientId:'festapp-make',callbackUri:'https://www.make.com/oauth/cb/app',scope};
 const old=await connect(f,{...options,resources:[f.config.resource]});
 const grant=f.storage.values('Delegation').find(g=>g.clientId==='festapp-make');
 const legacy={...grant};delete legacy.resource;delete legacy.endpointId;delete legacy.operationAllowlist;f.storage.putUntil('Delegation',grant.id,legacy,grant.expiresAt);
 const exchange=(token,resource)=>fetch(f.issuer+'/token',{method:'POST',body:new URLSearchParams({client_id:'festapp-make',grant_type:'refresh_token',refresh_token:token,...(resource?{resource}:{})})});
 assert.equal((await exchange(old.tokens.refresh_token,f.config.endpoints[1].resource)).status,400);
 const rotated=await exchange(old.tokens.refresh_token);assert.equal(rotated.status,200,await rotated.clone().text());const oldTokens=await rotated.json();
 assert.equal(f.storage.get('Delegation',grant.id).resource,undefined);
 const regional=await connect(f,{...options,resources:[f.config.endpoints[1].resource]});
 assert.equal((await apiRequest(f,regional.tokens,'context.inspect',{},'regional-api')).status,200);
 assert.equal((await apiRequest(f,oldTokens,'context.inspect',{},'regional-api')).status,401);
 const callOld=token=>httpRequest(f.issuer+'/make/v1/operations/context.inspect',{method:'POST',headers:{authorization:'Bearer '+token.access_token,'content-type':'application/json'},body:'{}'});
 assert.equal((await callOld(oldTokens)).status,200);assert.equal((await callOld(regional.tokens)).status,401);
 assert.equal((await exchange(regional.tokens.refresh_token)).status,400);
 assert.equal((await exchange(regional.tokens.refresh_token,f.config.resource)).status,400);
 const fresh=await exchange(regional.tokens.refresh_token,f.config.endpoints[1].resource);assert.equal(fresh.status,200);
 f.storage.revoke(grant.id);assert.equal((await callOld(oldTokens)).status,401);
 assert.equal((await apiRequest(f,await fresh.json(),'context.inspect',{},'regional-api')).status,200);
});

for(const endpointId of ['global-api','regional-api'])test(`first-party API consent requires displayed resource/profile acknowledgement and binds the resulting grant: ${endpointId}`,async t=>{
 const {token:supabaseToken}=await import('./fixture.mjs');const f=await setup(t,{tenant:true}),endpoint=f.config.endpoints.find(e=>e.endpointId===endpointId),verifier='v'.repeat(43);
 const query=new URLSearchParams({client_id:'api-fixture',response_type:'code',redirect_uri:f.issuer+'/callback',resource:endpoint.resource,scope:'openid offline_access festapp:ticket-layouts:read',code_challenge:createHash('sha256').update(verifier).digest('base64url'),code_challenge_method:'S256'});
 let response=await f.browser('/auth?'+query),connectPath=response.headers.get('location');response=await f.browser(connectPath);
 if(response.status===200){const html=await response.text();const csrf=html.match(/name="csrf" value="([^"]+)"/)[1];response=await f.browser(new URL(connectPath,f.issuer).pathname+'/context',{csrf,context:f.config.profile.binding});response=await f.browser(response.headers.get('location'));}
 assert.equal(response.status,303);const tenant=new URL(response.headers.get('location'));assert.equal(tenant.origin,f.config.tenantOrigin);const request=tenant.searchParams.get('request');
 const broker=(operation,extra={})=>fetch(f.issuer+'/tenant-connection',{method:'POST',headers:{'content-type':'application/json','x-festapp-mcp-broker':'b'.repeat(43)},body:JSON.stringify({operation,request,tenantId:f.config.profile.tenantId,organizationId:f.config.profile.organizationId,tenantOrigin:f.config.tenantOrigin,...extra})});
 const details=await broker('details',{accessToken:supabaseToken});assert.equal(details.status,200);const info=await details.json();assert.deepEqual(info.api,{resource:endpoint.resource,dataProfile:'operator'});
 const access={consentVersion:2,selection:{type:'occasions',occasionIds:[7]},permissions:[]};
 assert.equal((await broker('prepare',{accessToken:supabaseToken,access})).status,403,'old UI cannot silently consent to a new API target');
 assert.equal((await broker('prepare',{accessToken:supabaseToken,access:{...access,apiReview:{version:1,resource:f.config.resource,dataProfile:'operator'}}})).status,403);
 assert.equal(f.storage.values('Delegation').length,0);
 response=await broker('prepare',{accessToken:supabaseToken,access:{...access,apiReview:{...info.api,version:1}}});assert.equal(response.status,200,await response.clone().text());const prepared=await response.json();
 response=await broker('complete',{lease:prepared.lease,session:{access_token:supabaseToken,refresh_token:'independent-api-broker-refresh'}});assert.equal(response.status,200);const {resumeUrl}=await response.json();
 response=await f.browser(resumeUrl);let target=response.headers.get('location');
 for(let i=0;i<8&&!new URL(target,f.issuer).pathname.startsWith('/callback');i++){response=await f.browser(target);target=response.headers.get('location');}
 const code=new URL(target,f.issuer).searchParams.get('code');assert(code);
 response=await fetch(f.issuer+'/token',{method:'POST',body:new URLSearchParams({grant_type:'authorization_code',code,client_id:'api-fixture',redirect_uri:f.issuer+'/callback',code_verifier:verifier,resource:endpoint.resource})});assert.equal(response.status,200,await response.clone().text());
 const tokens=await response.json();assert.equal((await apiRequest(f,tokens,'context.inspect',{},endpointId)).status,200);assert.equal(f.storage.values('Delegation')[0].resource,endpoint.resource);
});
