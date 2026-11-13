import test from 'node:test';
import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {randomBytes,randomUUID} from 'node:crypto';
import {readFile,writeFile} from 'node:fs/promises';
import {execFile,spawn} from 'node:child_process';
import {promisify} from 'node:util';
import {SignJWT} from 'jose';
import {openDisposableDatabase} from './postgres.mjs';
import {fixture} from '../../../automation/authorization/benchmark.mjs';
import {verifiedSessionAssurance,requireFreshStrongAuthentication} from '../src/auth/assurance.mjs';
const exec=promisify(execFile),connection=process.env.FESTAPP_MCP_TEST_DATABASE_URL;
const claims=jwt=>JSON.parse(Buffer.from(jwt.split('.')[1],'base64url'));
test('production-pinned GoTrue verifies independent MFA delegation and refresh never renews step-up freshness',
{skip:!connection,timeout:120000},async t=>{
    const db=await openDisposableDatabase(connection);t.after(()=>db.end());
    await db.query('BEGIN');const f=await fixture(db,1);await db.query('COMMIT');
    const name='festapp-mfa-'+randomUUID(),project=process.env.FESTAPP_LOCAL_DB_PROJECT_ID;
    assert.match(project,/^festapp-[a-z0-9-]+$/);
    const source=await readFile(new URL('../../../automation/hetzner-supabase/runtime/docker-compose.festapp.yml',import.meta.url),'utf8');
    const productionImage=source.match(/image: (supabase\/gotrue:v[\d.]+@sha256:[a-f0-9]{64})/)[1];
    assert.equal(productionImage,'supabase/gotrue:v2.189.0@sha256:cce6c1d00352f22ee7634066012830f69636c157017ea166634c48dbb58eefb7','Requalify the matching Auth release when production changes');
    // Immutable release index contains the exact production arm64 manifest and
    // its amd64 sibling, so CI and this workstation execute the same release.
    const image='supabase/gotrue:v2.189.0@sha256:385184459f57569c54c25209f51f3b2be99ddd7c4ce9e3555b5d3eea8447b7cf';
    const address=(await exec('docker',['inspect','--format','{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}','supabase_db_'+project])).stdout.trim();
    assert.match(address,/^\d+\.\d+\.\d+\.\d+$/);
    const database=new URL(connection);database.hostname=address;database.port='5432';database.username='supabase_admin';
    const secret=randomBytes(48).toString('base64url');
    const key=Buffer.from(secret),token=role=>new SignJWT({role,aud:'authenticated'}).setProtectedHeader({alg:'HS256'}).setIssuedAt().setExpirationTime('1h').sign(key);
    let authPort;
    const proxy=createServer(async(req,res)=>{
        try {
            if(!req.url.startsWith('/auth/v1/')){res.writeHead(404).end();return;}
            const parts=[];for await(const part of req)parts.push(part);
            const response=await fetch('http://127.0.0.1:'+authPort+req.url.slice('/auth/v1'.length),{method:req.method,
                headers:{...req.headers,host:'127.0.0.1:'+authPort},...(parts.length?{body:Buffer.concat(parts)}:{})});
            res.writeHead(response.status,Object.fromEntries([...response.headers].filter(([k])=>!['content-encoding','content-length','transfer-encoding'].includes(k))));res.end(Buffer.from(await response.arrayBuffer()));
        }catch{res.writeHead(502).end();}
    });
    await new Promise(resolve=>proxy.listen(0,'127.0.0.1',resolve));t.after(()=>new Promise(resolve=>proxy.close(resolve)));
    const origin='http://127.0.0.1:'+proxy.address().port;
    const authEnvironment={GOTRUE_API_HOST:'0.0.0.0',PORT:'9999',GOTRUE_API_PORT:'9999',
        API_EXTERNAL_URL:origin,GOTRUE_SITE_URL:origin,GOTRUE_DB_DRIVER:'postgres',GOTRUE_DB_NAMESPACE:'auth',
        GOTRUE_DB_DATABASE_URL:database.href,GOTRUE_JWT_SECRET:secret,GOTRUE_JWT_ISSUER:origin,
        GOTRUE_JWT_AUD:'authenticated',GOTRUE_JWT_DEFAULT_GROUP_NAME:'authenticated',GOTRUE_JWT_EXP:'3600',
        GOTRUE_MAILER_AUTOCONFIRM:'true',GOTRUE_DISABLE_SIGNUP:'true',GOTRUE_JWT_ADMIN_ROLES:'service_role',
        GOTRUE_RATE_LIMIT_EMAIL_SENT:'100',GOTRUE_SECURITY_REFRESH_TOKEN_ROTATION_ENABLED:'true'};
    const names=Object.keys(authEnvironment);
    const environment={...process.env,...authEnvironment};
    t.after(async()=>{await exec('docker',['rm','-f',name]).catch(()=>{});});
    await exec('docker',['run','-d','--name',name,'--memory','256m','--cpus','0.5',
        '--label','festapp.owned-mfa-test='+project,'-p','127.0.0.1::9999',...names.flatMap(k=>['-e',k]),image],{env:environment});
    authPort=Number((await exec('docker',['port',name,'9999/tcp'])).stdout.trim().split(':').at(-1));
    let healthy=false;for(let attempt=0;attempt<150;attempt++){
        try{if((await fetch('http://127.0.0.1:'+authPort+'/health')).ok){healthy=true;break;}}catch{}
        await new Promise(resolve=>setTimeout(resolve,100));
    }
    if(!healthy){const logs=await exec('docker',['logs',name]);await writeFile('/tmp/'+name+'-startup.log',logs.stdout+logs.stderr,{mode:0o600});}
    assert(healthy,'Owned GoTrue did not become healthy; private startup log: /tmp/'+name+'-startup.log');
    const env={PATH:process.env.PATH,HOME:process.env.HOME,FESTAPP_MCP_TEST_DATABASE_URL:connection,FESTAPP_LOCAL_AUTH_URL:origin,FESTAPP_LOCAL_AUTH_ANON:await token('anon'),
        FESTAPP_LOCAL_AUTH_SERVICE:await token('service_role'),FESTAPP_LOCAL_AUTH_ORGANIZATION:String(f.org)};
    const result=await new Promise(resolve=>{
        const child=spawn('deno',['run','--quiet','--check','--frozen','--lock=supabase/functions/deno.lock','--allow-env','--allow-read','--allow-net','--allow-run=psql','supabase/tests/gotrue_mfa_flow.ts'],{cwd:new URL('../../../',import.meta.url),env,stdio:['ignore','pipe','pipe']});
        let stdout='',stderr='';child.stdout.on('data',b=>stdout+=b);child.stderr.on('data',b=>stderr+=b);child.on('close',code=>resolve({code,stdout,stderr}));
    });
    if(result.code!==0)await writeFile('/tmp/'+name+'-flow.log',result.stderr,{mode:0o600});
    assert.equal(result.code,0,'Isolated MFA flow failed; private diagnostic: /tmp/'+name+'-flow.log');
    const proof=JSON.parse(result.stdout),issued=claims(proof.issued),refreshed=claims(proof.refreshed);
    assert.notEqual(issued.session_id,claims(proof.browser).session_id,'Independent mint must have its own session identity');
    const assurance=verifiedSessionAssurance(proof.refreshed,proof.user,origin);assert(assurance,'Real verified GoTrue session must supply strong assurance');
    requireFreshStrongAuthentication(assurance,proof.user.id);
    const first=issued.amr.find(a=>a.method==='totp').timestamp;
    assert.equal(refreshed.amr.find(a=>a.method==='totp').timestamp,first,'Refresh must retain the actual MFA authentication time');
    const now=Date.now;try{Date.now=()=>now()+301000;assert.throws(()=>requireFreshStrongAuthentication(assurance,proof.user.id),/INSUFFICIENT_USER_AUTHENTICATION/);}finally{Date.now=now;}
});
