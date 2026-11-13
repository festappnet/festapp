// Real HTTP + OAuth + canonical Operations + PostgreSQL. Only the upstream
// GoTrue identity boundary is simulated; SQL runs as the fixture's real actor.
import assert from 'node:assert/strict';
import {createHash,randomUUID} from 'node:crypto';
import {generateKeyPair,exportJWK,SignJWT} from 'jose';
import {setup as programSetup} from './program-fixtures.mjs';
import {setup,connect,apiRequest} from './api-fixture.mjs';
import {profile,reply} from './fixture.mjs';
import {orderDataSchemas} from '../src/operations/orders.mjs';
import {OperationError} from '../src/errors.mjs';
import {operationIds,publicCatalog} from '../src/remote/api-contract.mjs';
import {MCP_PERMISSIONS,READ_SCOPE,CREATE_SCOPE} from '../src/remote/config.mjs';
export async function postgresApi(t,{strong=false,seed,sqlSetup=programSetup}={}) {
    const sql=await sqlSetup(t), {db,f}=sql;
    if(seed){await db.query('RESET ROLE');await seed(db,f);await db.query('SET LOCAL ROLE authenticated');}
    let lose=false,revoke=false,writes=0;
    const rpcCalls=[],rpcFailures=[];
    const types=new Map();
    const backend=async(url,init)=>{
        if(!url.pathname.startsWith('/rest/v1/rpc/'))return;
        const name=url.pathname.split('/').at(-1),args=JSON.parse(init.body??'{}');
        assert.match(name,/^[a-z_0-9]+$/);
        let signatures=types.get(name);
        if(!signatures){
            signatures=(await db.query(`select proargnames names, proargtypes::oid[] types
                from pg_proc p join pg_namespace n on n.oid=p.pronamespace
                where n.nspname='public' and p.proname=$1 and p.prokind='f'`,[name])).rows;
            types.set(name,signatures);
        }
        const keys=Object.keys(args);
        const signature=signatures.find(s=>keys.every(k=>s.names?.includes(k)));
        if(!signature)rpcFailures.push({name,code:'RPC_SIGNATURE_MISMATCH',message:'Named parameters do not match the installed canonical SQL function',keys,signatures});
        assert(signature,'canonical RPC exists: '+name);
        for(const key of keys)assert.match(key,/^[a-z_0-9]+$/);
        const values=keys.map(k=>[114,3802].includes(signature.types[signature.names.indexOf(k)])?JSON.stringify(args[k]):args[k]);
        await db.query('SAVEPOINT api_rpc');
        try {
            const data=(await db.query('select public.'+name+'('+keys.map((k,i)=>k+'=> $'+(i+1)).join(',')+') value',values)).rows[0].value;
            await db.query('RELEASE SAVEPOINT api_rpc');rpcCalls.push({name,args});
            if(name==='get_operator_orders_v1'){const parsed=orderDataSchemas['orders.inspect'].safeParse(data);if(!parsed.success)rpcFailures.push({name,code:'UPSTREAM_CONTRACT_FAILURE',message:parsed.error.message});}
            const mutation=Boolean(data?.mutation || data?.commandId || data?.status==='applied');
            if(mutation){writes++;if(revoke){revoke=false;service.storage.revoke(service.storage.values('Delegation').find(g=>g.clientId==='api-fixture').id);}
                if(lose){lose=false;return reply({code:'response_lost'},503);}}
            return reply(data);
        }catch(error){rpcFailures.push({name,code:error.code,message:error.message});await db.query('ROLLBACK TO SAVEPOINT api_rpc');await db.query('RELEASE SAVEPOINT api_rpc');return reply({code:error.code},error.code==='42501'?403:400);}
    };
    const p=profile(undefined,f.org),now=Math.floor(Date.now()/1000);
    const scopes=[READ_SCOPE,CREATE_SCOPE,...Object.keys(MCP_PERMISSIONS)];
    const service=await setup(t,{profileValue:p,userId:f.actor,fetchImpl:backend,proofProfile:strong?'dpop':'bearer',
        apiPolicy:{allowedScopes:scopes,allowedOperations:operationIds,...(strong?{requirePar:true}:{})},
        ...(strong?{sessionClaims:{iss:p.backendOrigin+'/auth/v1',aud:'authenticated',aal:'aal2',session_id:randomUUID(),amr:[{method:'totp',timestamp:now}]},
            userFactors:[{id:randomUUID(),status:'verified',factor_type:'totp'}]}:{})});
    let sign;
    if(strong){const keys=await generateKeyPair('ES256'),jwk=await exportJWK(keys.publicKey);
        sign=async(htu,ath)=>new SignJWT({htm:'POST',htu,iat:Math.floor(Date.now()/1000),jti:randomUUID(),...(ath?{ath}:{})}).setProtectedHeader({alg:'ES256',typ:'dpop+jwt',jwk}).sign(keys.privateKey);
        service.tokenProof=()=>sign(service.issuer+'/token');}
    let credentials;
    const reconnect=async()=>{service.clearBrowserCookies();credentials=await connect(service,{visibleOccasionId:f.occasion,hiddenOccasionId:Number.MAX_SAFE_INTEGER,usePar:strong,unitId:f.unit,create:true,scope:scopes.join(' ')});return credentials;};
    await reconnect();
    const call=async(id,args={})=>{
        const headers=strong?{authorization:'DPoP '+credentials.tokens.access_token,dpop:await sign('https://api.festapp.net/integrations/v1/operations/'+id,createHash('sha256').update(credentials.tokens.access_token).digest('base64url'))}:{};
        return apiRequest(service,credentials.tokens,id,{...(publicCatalog().find(d=>d.id===id)?.input.shape?.occasionId?{occasionId:f.occasion}:{}),...args},'global-api',headers);
    };
    const invoke=async(id,args={})=>{const response=await call(id,args),body=await response.json();if(response.status!==200){const error=new OperationError(body.code,body.retryable);error.lastRpc=rpcCalls.at(-1)?.name;if(rpcFailures.length)error.sql=rpcFailures.at(-1);throw error;}assert.equal(body.ok,true,JSON.stringify(body));return body.data;};
    return {...sql,service,call,invoke,reconnect,rpcCalls,rpcFailures,loseNext:()=>{lose=true;},revokeNext:()=>{revoke=true;},writeCount:()=>writes,
        command:(id,args={})=>invoke(id,{commandId:randomUUID(),...args})};
}
