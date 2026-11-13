import assert from 'node:assert/strict';
import { readFile, writeFile, mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawn } from 'node:child_process';
import { generateKeyPair, exportJWK, SignJWT } from 'jose';
import { createHash, randomUUID } from 'node:crypto';
import { setup, connect, httpRequest } from '../test/api-fixture.mjs';

// Explicit disposable runtime gate, not a production Caddy reload. Run inside
// the local candidate image with a pinned Caddy binary and no host network.
const binary=process.argv[2]??process.env.FESTAPP_API_CADDY_BINARY;
assert(binary,'Supply the pinned Caddy binary for the isolated ingress gate');
const callbacks=[],t={after:fn=>callbacks.push(fn)},directory=await mkdtemp(join(tmpdir(),'festapp-api-proxy-'));
let child;
try{
    const f=await setup(t,{proofProfile:'dpop'}),keys=await generateKeyPair('ES256'),jwk=await exportJWK(keys.publicKey);
    const sign=async(url,token)=>new SignJWT({htm:'POST',htu:url,iat:Math.floor(Date.now()/1000),jti:randomUUID(),...(token?{ath:createHash('sha256').update(token).digest('base64url')}:{})}).setProtectedHeader({alg:'ES256',typ:'dpop+jwt',jwk}).sign(keys.privateKey);
    f.tokenProof=()=>sign(f.issuer+'/token');
    const global=await connect(f),regional=await connect(f,{resources:[f.config.endpoints[1].resource]});
    let source=await readFile(new URL('../../../automation/hetzner-supabase/runtime/Caddyfile.integrations',import.meta.url),'utf8');
    source=source.replace('api.vstupenky.online {','http://api.vstupenky.online:8080 {');
    const config=`{\n admin off\n auto_https off\n}\n${source}\nhttp://api.festapp.net:8080 {\n import festapp_global_integrations\n handle /auth/v1/* {\n respond "existing-auth" 200\n }\n handle /rest/v1/* {\n respond "existing-rest" 200\n }\n handle /functions/v1/* {\n respond "existing-functions" 200\n }\n handle {\n respond "existing-fallback" 404\n }\n}\n`;
    const file=join(directory,'Caddyfile');await writeFile(file,config);
    let diagnostics='';
    child=spawn(binary,['run','--config',file,'--adapter','caddyfile'],{env:{...process.env,FESTAPP_CANONICAL_MCP_LISTENER:new URL(f.issuer).host},stdio:['ignore','ignore','pipe']});
    child.stderr.on('data',chunk=>{diagnostics=(diagnostics+chunk).slice(-3000);});
    child.on('error',error=>{diagnostics=error.message;});
    let ready=false;
    for(let i=0;i<100;i++){
        if(child.exitCode!==null)throw new Error('Disposable Caddy failed: '+diagnostics);
        try{const probe=await httpRequest('http://127.0.0.1:8080/rest/v1/probe',{headers:{host:'api.festapp.net'}});if(probe.status===200){ready=true;break;}}catch{}
        await new Promise(resolve=>setTimeout(resolve,50));
    }
    assert(ready,'Disposable Caddy did not become ready: '+diagnostics);
    for(const [path,expected] of [['auth','existing-auth'],['rest','existing-rest'],['functions','existing-functions']]){
        const response=await httpRequest(`http://127.0.0.1:8080/${path}/v1/probe`,{headers:{host:'api.festapp.net'}});assert.equal(response.status,200);assert.equal(await response.text(),expected);
    }
    const path='/integrations/v1/operations/context.inspect';
    let ingress;f.server.prependListener('request',req=>{if(req.url.startsWith('/integrations/'))ingress={host:req.headers.host,proto:req.headers['x-forwarded-proto'],forwardedHost:req.headers['x-forwarded-host'],endpoint:req.headers['x-festapp-endpoint'],forwarded:req.headers.forwarded};});
    const call=async(host,tokens,proofUrl='https://'+host+path)=>httpRequest('http://127.0.0.1:8080'+path,{method:'POST',headers:{host,authorization:'DPoP '+tokens.access_token,dpop:await sign(proofUrl,tokens.access_token),'content-type':'application/json',forwarded:'host=attacker.invalid;proto=http','x-festapp-endpoint':'forged','x-forwarded-host':'attacker.invalid','x-forwarded-proto':'http'},body:'{}'});
    const a=await call('api.festapp.net',global.tokens);assert.equal(a.status,200,JSON.stringify(ingress)+' '+await a.clone().text());
    const b=await call('api.vstupenky.online',regional.tokens);assert.equal(b.status,200,await b.clone().text());
    assert.deepEqual((await a.json()).data,(await b.json()).data);
    assert.equal((await call('api.festapp.net',regional.tokens)).status,401);
    assert.equal((await call('api.vstupenky.online',global.tokens)).status,401);
    assert.equal((await call('api.vstupenky.online',regional.tokens,'https://api.festapp.net'+path)).status,401);
    for(const host of ['api.festapp.net','api.vstupenky.online']){
        const oversized=await httpRequest('http://127.0.0.1:8080'+path,{method:'POST',headers:{host,'content-type':'application/json'},body:JSON.stringify({payload:'x'.repeat(50000)})});
        assert.equal(oversized.status,413);
        assert.match(oversized.headers.get('content-type')??'',/application\/problem\+json/);
        const problem=await oversized.json();assert.equal(problem.code,'BODY_TOO_LARGE');assert.equal(problem.requestId,oversized.headers.get('x-request-id'));
    }
    const direct=await httpRequest(f.issuer+path,{method:'POST',headers:{host:'api.festapp.net','content-type':'application/json'},body:'{}'});assert.equal(direct.status,400);
    await new Promise(resolve=>f.server.close(resolve));
    const unavailable=await httpRequest('http://127.0.0.1:8080'+path,{method:'POST',headers:{host:'api.festapp.net','content-type':'application/json'},body:'{}'});
    assert.equal(unavailable.status,502);assert.match(unavailable.headers.get('content-type')??'',/application\/problem\+json/);
    const unknown=await unavailable.json();assert.equal(unknown.outcome,'unknown');assert.equal(unknown.requestId,unavailable.headers.get('x-request-id'));
    console.log(JSON.stringify({ok:true,checks:22,facades:2,canonicalListeners:1,preserved:['auth/v1','rest/v1','functions/v1'],dpopPublicPrefix:true,forgedForwardingStripped:true,resourceSubstitutionRejected:true,productionChanged:false}));
}finally{
    if(child&&child.exitCode===null){child.kill('SIGTERM');await new Promise(resolve=>child.once('exit',resolve));}
    for(const callback of callbacks.reverse())await callback();await rm(directory,{recursive:true,force:true});
}
