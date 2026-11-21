import test from 'node:test';
import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {randomBytes,randomUUID} from 'node:crypto';
import {mkdtemp,readFile,rm,writeFile} from 'node:fs/promises';
import {execFile,spawn} from 'node:child_process';
import {promisify} from 'node:util';
import {once} from 'node:events';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {SignJWT} from 'jose';
import {openDisposableDatabase} from './postgres.mjs';
import {fixture} from '../../../automation/authorization/benchmark.mjs';
const exec=promisify(execFile),connection=process.env.FESTAPP_MCP_TEST_DATABASE_URL;

async function qualifyRealtimeInventory(db) {
    const inventory=await readFile(new URL('../../../database/operations/audit_account_assurance_realtime.sql',import.meta.url),'utf8');
    const read=async(query=inventory)=>Object.values((await db.query(query)).rows[0])[0];
    const baseline=await read();
    assert.deepEqual(baseline.publicationRelations.filter(row=>row.schema!=='realtime'),[],
        'Review application publications before enabling MFA in this schema');
    assert.equal(baseline.messageClientAccess.some(role=>
        (role.can_select||role.can_insert) && (!baseline.messagesRlsEnabled||role.permissive_policies.length>0)),false,
        'Review client-facing message access before enabling MFA in this schema');
    await db.query('BEGIN');
    try {
        // The installed Realtime schema is provider-owned. Probe the same
        // catalog rules against a fixture relation owned by this test role.
        await db.query(`CREATE PUBLICATION mfa_realtime_inventory_probe FOR TABLE public.user_info;
            CREATE SCHEMA mfa_realtime_inventory_probe;
            CREATE TABLE mfa_realtime_inventory_probe.messages (id bigint);
            ALTER TABLE mfa_realtime_inventory_probe.messages ENABLE ROW LEVEL SECURITY;
            GRANT SELECT ON mfa_realtime_inventory_probe.messages TO authenticated;
            CREATE POLICY mfa_realtime_inventory_probe ON mfa_realtime_inventory_probe.messages
              FOR SELECT TO authenticated USING (true);`);
        const changed=await read(inventory.replace("to_regclass('realtime.messages')",
            "to_regclass('mfa_realtime_inventory_probe.messages')"));
        assert.ok(changed.publicationRelations.some(row=>row.publication==='mfa_realtime_inventory_probe'&&
            row.schema==='public'&&row.relation==='user_info'));
        assert.equal(changed.messagesRlsEnabled,true);
        assert.ok(changed.messageClientAccess.some(role=>role.role_name==='authenticated'&&role.can_select&&
            role.permissive_policies.includes('mfa_realtime_inventory_probe')));
    } finally {
        await db.query('ROLLBACK');
    }
    return {applicationPublicationRelations:0, messageClientAccess:baseline.messageClientAccess,
        messagesRlsEnabled:baseline.messagesRlsEnabled, changeSubscriptionTablePresent:baseline.changeSubscriptionTablePresent};
}

async function qualifyRequestHookInstallation(db) {
    const installer=await readFile(new URL('../../../database/operations/enable_account_assurance_postgrest.sql',import.meta.url),'utf8');
    const database=(await db.query('SELECT current_database() AS name')).rows[0].name;
    assert.match(database,/^festapp_run_[a-f0-9]+$/);
    await db.query('BEGIN');
    try {
        await db.query(`ALTER ROLE authenticator IN DATABASE ${database}
            SET pgrst.db_pre_request TO 'public.log_canonical_mutation_request_v1'`);
        await db.query(installer);
        const configured=await db.query(`SELECT entry FROM pg_db_role_setting settings
            CROSS JOIN LATERAL unnest(settings.setconfig) entry
            WHERE setrole='authenticator'::regrole
              AND setdatabase=(SELECT oid FROM pg_database WHERE datname=current_database())
              AND entry LIKE 'pgrst.db_pre_request=%'`);
        assert.equal(configured.rows[0]?.entry,'pgrst.db_pre_request=public.enforce_account_assurance_and_observe_v1');
        await db.query(`ALTER ROLE authenticator IN DATABASE ${database}
            SET pgrst.db_pre_request TO 'public.unrecognized_test_hook'`);
        await assert.rejects(db.query(installer), /existing pre-request hook requires explicit composition/);
    } finally {
        await db.query('ROLLBACK');
    }
}

test('production-pinned GoTrue qualifies MFA, independent delegation and live session changes',
{skip:!connection,timeout:120000},async t=>{
    const db=await openDisposableDatabase(connection);t.after(()=>db.end());
    t.diagnostic(JSON.stringify({realtimeInventory:await qualifyRealtimeInventory(db)}));
    await db.query('BEGIN');const f=await fixture(db,1);await db.query('COMMIT');
    const name='festapp-mfa-'+randomUUID(),restName=name+'-rest',project=process.env.FESTAPP_LOCAL_DB_PROJECT_ID;
    assert.match(project,/^festapp-[a-z0-9-]+$/);
    const source=await readFile(new URL('../../../automation/hetzner-supabase/runtime/docker-compose.festapp.yml',import.meta.url),'utf8');
    const productionImage=source.match(/image: (supabase\/gotrue:v[\d.]+@sha256:[a-f0-9]{64})/)[1];
    assert.equal(productionImage,'supabase/gotrue:v2.197.0@sha256:3439d5affb9e96395d1348521f4c675eea7096d8d76d18d4e31fcc08df802116','Requalify the matching Auth release when production changes');
    // Immutable release index contains the exact production arm64 manifest and
    // its amd64 sibling, so CI and this workstation execute the same release.
    const image='supabase/gotrue:v2.197.0@sha256:1736a63078f5922b198c4cbe50f80ab9a2d3b54fe8b7b6cfb2e9dc5dbbc12c6b';
    const productionRest=source.match(/image: (postgrest\/postgrest:v[\d.]+@sha256:[a-f0-9]{64})/)[1];
    assert.equal(productionRest,'postgrest/postgrest:v14.18@sha256:dfa6464b877fa7b1b0be85740f6ce6985144b509a6edb5f09c5ee67e687e8c1f',
        'Requalify the matching PostgREST release when production changes');
    const restImage='postgrest/postgrest:v14.18@sha256:c7cd7e265a85b05248abf53f4473fcec7e327c282d0bd0cf60f1551996d09fcf';
    const address=(await exec('docker',['inspect','--format','{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}','supabase_db_'+project])).stdout.trim();
    assert.match(address,/^\d+\.\d+\.\d+\.\d+$/);
    const database=new URL(connection);database.hostname=address;database.port='5432';database.username='supabase_admin';
    const secret=randomBytes(48).toString('base64url');
    const key=Buffer.from(secret),token=role=>new SignJWT({role,aud:'authenticated'}).setProtectedHeader({alg:'HS256'}).setIssuedAt().setExpirationTime('1h').sign(key);
    const serviceToken=await token('service_role');
    let authPort,restPort,authIngress=false,strictAuthUrl='';
    const proxy=createServer(async(req,res)=>{
        try {
            const routes={'/auth/v1':authPort,'/rest/v1':restPort};
            const prefix=Object.keys(routes).find(path=>req.url.startsWith(path+'/'));
            if(!prefix){res.writeHead(404).end();return;}
            const upstream='127.0.0.1:'+routes[prefix];
            const parts=[];for await(const part of req)parts.push(part);
            const path=prefix==='/auth/v1'&&authIngress?req.url:req.url.slice(prefix.length);
            const response=await fetch('http://'+upstream+path,{method:req.method,redirect:'manual',
                headers:{...req.headers,host:upstream},...(parts.length?{body:Buffer.concat(parts)}:{})});
            res.writeHead(response.status,Object.fromEntries([...response.headers].filter(([k])=>!['content-encoding','content-length','transfer-encoding'].includes(k))));res.end(Buffer.from(await response.arrayBuffer()));
        }catch{res.writeHead(502).end();}
    });
    await new Promise(resolve=>proxy.listen(0,'127.0.0.1',resolve));t.after(()=>new Promise(resolve=>proxy.close(resolve)));
    const origin='http://localhost:'+proxy.address().port;
    const authEnvironment={GOTRUE_API_HOST:'0.0.0.0',PORT:'9999',GOTRUE_API_PORT:'9999',
        API_EXTERNAL_URL:origin,GOTRUE_SITE_URL:origin,GOTRUE_DB_DRIVER:'postgres',GOTRUE_DB_NAMESPACE:'auth',
        GOTRUE_DB_DATABASE_URL:database.href,GOTRUE_JWT_SECRET:secret,GOTRUE_JWT_ISSUER:origin,
        GOTRUE_JWT_AUD:'authenticated',GOTRUE_JWT_DEFAULT_GROUP_NAME:'authenticated',GOTRUE_JWT_EXP:'3600',
        GOTRUE_MAILER_AUTOCONFIRM:'true',GOTRUE_DISABLE_SIGNUP:'true',GOTRUE_JWT_ADMIN_ROLES:'service_role',
        GOTRUE_RATE_LIMIT_EMAIL_SENT:'100',GOTRUE_SECURITY_REFRESH_TOKEN_ROTATION_ENABLED:'true',
        GOTRUE_PASSKEY_ENABLED:'true',GOTRUE_WEBAUTHN_RP_ID:'localhost',
        GOTRUE_WEBAUTHN_RP_DISPLAY_NAME:'Festapp disposable test',GOTRUE_WEBAUTHN_RP_ORIGINS:[origin,origin.replace(/^http:/,'https:')].join(','),
        GOTRUE_MFA_WEB_AUTHN_ENROLL_ENABLED:'true',GOTRUE_MFA_WEB_AUTHN_VERIFY_ENABLED:'true',
        GOTRUE_MFA_RECOVERY_CODES_ENROLL_ENABLED:'true',GOTRUE_MFA_RECOVERY_CODES_VERIFY_ENABLED:'true'};
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
    const health=await fetch('http://127.0.0.1:'+authPort+'/health').then(response=>response.json());
    assert.equal(health.version.replace(/^v/,''),'2.197.0');
    const browserProof=process.env.FESTAPP_MFA_BROWSER_PROOF==='1';
    if(browserProof){
        const build=await mkdtemp(join(tmpdir(),'festapp-mfa-ingress-'));
        t.after(()=>rm(build,{recursive:true,force:true}));
        const binary=join(build,'auth-ingress');
        await exec('go',['build','-mod=readonly','-o',binary,'.'],{
            cwd:new URL('../../../automation/hetzner-supabase/auth-ingress/',import.meta.url),
        });
        const args=[
            '-direct-gotrue','-upstream','http://127.0.0.1:'+authPort,
            '-policy-origin','http://127.0.0.1:'+proxy.address().port,
        ];
        async function startIngress(extraArgs){
            const gateway=spawn(binary,[...args,...extraArgs],
                {stdio:['ignore','pipe','inherit'],env:{FESTAPP_AUTH_POLICY_SERVICE_TOKEN:serviceToken,FESTAPP_PASSKEY_HANDOFF_KEY:randomBytes(32).toString("hex")}});
            const closed=once(gateway,'close');
            t.after(async()=>{gateway.kill();await closed;});
            const [address]=await Promise.race([
                once(gateway.stdout,'data'),
                closed.then(()=>{throw new Error('Owned Auth ingress exited during startup');}),
            ]);
            const host=String(address).trim();
            assert.match(host,/^127\.0\.0\.1:[1-9][0-9]*$/);
            return host;
        }
        const strictHost=await startIngress([]);
        strictAuthUrl='http://'+strictHost;
        const host=await startIngress(['-qualify-provider']);
        authPort=Number(host.split(':')[1]);
        authIngress=true;
        await exec('python3',['automation/hetzner-supabase/auth-ingress/check-caddy.py',strictHost.split(':')[1]],{
            cwd:new URL('../../../',import.meta.url),
        });
    }
    const restDatabase=new URL(database);
    const restLogin='festapp_mfa_rest_'+randomUUID().replaceAll('-','');
    const restPassword=randomBytes(32).toString('base64url');
    const testAdmin=await openDisposableDatabase(connection,{administrative:true});
    t.after(async()=>{
        try{
            await exec('docker',['rm','-f',restName]).catch(()=>{});
            await testAdmin.query('DROP ROLE IF EXISTS '+restLogin);
        }finally{await testAdmin.end();}
    });
    // Each workspace has its own login. Never reset the shared provider role.
    await testAdmin.query(`CREATE ROLE ${restLogin} LOGIN NOINHERIT PASSWORD '${restPassword}'`);
    await testAdmin.query('GRANT anon, authenticated, service_role TO '+restLogin);
    await qualifyRequestHookInstallation(testAdmin);
    restDatabase.username=restLogin;
    restDatabase.password=restPassword;
    const restEnvironment={
        PGRST_DB_URI:restDatabase.href, PGRST_DB_SCHEMAS:'public,graphql_public',
        PGRST_DB_ANON_ROLE:'anon', PGRST_DB_EXTRA_SEARCH_PATH:'public,extensions',
        PGRST_JWT_SECRET:secret, PGRST_JWT_AUD:'authenticated',
        PGRST_DB_PRE_REQUEST:'public.enforce_account_assurance_and_observe_v1',
    };
    await exec('docker',['run','-d','--name',restName,'--memory','192m','--cpus','0.5',
        '--label','festapp.owned-mfa-test='+project,'-p','127.0.0.1::3000',
        ...Object.keys(restEnvironment).flatMap(k=>['-e',k]),restImage],{env:{...process.env,...restEnvironment}});
    restPort=Number((await exec('docker',['port',restName,'3000/tcp'])).stdout.trim().split(':').at(-1));
    let restReady=false;
    for(let attempt=0;attempt<150;attempt++){
        try{if((await fetch('http://127.0.0.1:'+restPort+'/')).ok){restReady=true;break;}}catch{}
        await new Promise(resolve=>setTimeout(resolve,100));
    }
    if(!restReady){
        const logs=await exec('docker',['logs',restName]);
        await writeFile('/tmp/'+restName+'-startup.log',logs.stdout+logs.stderr,{mode:0o600});
    }
    assert(restReady,'Owned PostgREST did not become healthy; private startup log: /tmp/'+restName+'-startup.log');
    const env={PATH:process.env.PATH,HOME:process.env.HOME,FESTAPP_MCP_TEST_DATABASE_URL:connection,FESTAPP_LOCAL_AUTH_URL:origin,FESTAPP_LOCAL_AUTH_ANON:await token('anon'),
        FESTAPP_LOCAL_AUTH_SERVICE:serviceToken,FESTAPP_LOCAL_AUTH_ORGANIZATION:String(f.org),
        FESTAPP_MFA_BROWSER_PROOF:browserProof?'1':'0',FESTAPP_LOCAL_STRICT_AUTH_URL:strictAuthUrl};
    const result=await new Promise(resolve=>{
        const child=spawn('deno',['run','--quiet','--check','--frozen','--lock=supabase/functions/deno.lock','--allow-env','--allow-read','--allow-net',
            browserProof?'--allow-run=psql,node':'--allow-run=psql','supabase/tests/gotrue_mfa_flow.ts'],{cwd:new URL('../../../',import.meta.url),env,stdio:['ignore','pipe','pipe']});
        let stdout='',stderr='';child.stdout.on('data',b=>stdout+=b);child.stderr.on('data',b=>stderr+=b);child.on('close',code=>resolve({code,stdout,stderr}));
    });
    if(result.code!==0)await writeFile('/tmp/'+name+'-flow.log',result.stderr,{mode:0o600});
    assert.equal(result.code,0,'Isolated MFA flow failed; private diagnostic: /tmp/'+name+'-flow.log');
    const report=JSON.parse(result.stdout);
    if(browserProof){
        assert.equal(report.brokeredWebAuthnRecoveryReplacement,true);
        assert.equal(report.brokeredPasskeyPrimaryProof,true);
        assert.equal(report.webClientAgainstPinnedAuth,true);
        assert.equal(report.guestCheckoutWithHeldSession,true);
        assert.equal(report.paidCustomerLinkWithHeldSession,true);
        assert.equal(report.googleWebAuthnWithPinnedAuth,true);
        assert.equal(report.accountSettingsAgainstPinnedAuth,true);
        assert.equal(report.accountRecoveryAgainstPinnedAuth,true);
    }
    t.diagnostic(JSON.stringify(report));
});
