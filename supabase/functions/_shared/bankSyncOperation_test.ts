import { assertEquals, assertRejects } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { bankSyncHash } from './bankSyncToken.ts';

Deno.env.set('SUPABASE_URL','http://127.0.0.1:55499');
Deno.env.set('SUPABASE_SERVICE_ROLE_KEY','synthetic-local-test-key');
Deno.env.set('BANKSYNC_API_URL','https://banksync.invalid');
Deno.env.set('BANKSYNC_TENANT_ADMIN_KEY','synthetic-scoped-key');
Deno.env.set('BANKSYNC_INSTANCE_ID','test-instance');
let requestHandler: typeof fetch | undefined;
globalThis.fetch = ((...args: Parameters<typeof fetch>) => {
  if (!requestHandler) throw new Error('Unmocked test request');
  return requestHandler(...args);
}) as typeof fetch;
const {runBankSyncOperation} = await import('./bankSyncOperation.ts');

for (const scenario of ['valid','inactive','account-mismatch','throttled','transient','digest-mismatch'] as const) {
  Deno.test(`token update reaches BankSync and reports ${scenario} accurately`, async () => {
    let stored = 'old-fixture-token';
    let enabled = false;
    let ingestEnabled = false;
    let tokenWrites = 0;
    let bankChecks = 0;
    const calls: {name:string;body:any}[] = [];
    requestHandler = (async (input: string | URL | Request, init?: RequestInit) => {
      const url = new URL(input instanceof Request ? input.url : input.toString());
      const body = init?.body ? JSON.parse(String(init.body)) : {};
      const respond = (value:unknown,status=200) => new Response(JSON.stringify(value),{status,headers:{'content-type':'application/json'}});
      if (url.hostname === '127.0.0.1') {
        const name = url.pathname.split('/').pop()!;calls.push({name,body});
        if (name === 'claim_bank_sync_operation') return respond({connection_id:1,remote_id:'9',barrier:'active',lease_token:'fixture-lease'});
        return respond(null);
      }
      assertEquals(new Headers(init?.headers).get('x-tenant-secret'),'synthetic-scoped-key');
      if (url.pathname.endsWith('/ingest-state')) {
        if (init?.method === 'PUT') ingestEnabled = body.enabled;
        return respond({api_token_hash:await bankSyncHash(scenario === 'digest-mismatch' ? 'wrong-token' : stored)});
      }
      if (url.pathname.endsWith('/fio-token')) {
        if (body.fio_api_token) {stored=body.fio_api_token;tokenWrites++;}
        enabled=body.fetch_enabled;return respond({});
      }
      if (url.pathname.endsWith('/fio-sync')) {
        bankChecks++;assertEquals(stored,'new-fixture-token');assertEquals(ingestEnabled,true);
        return scenario==='inactive'
          ? respond({error:'fio_token_invalid_or_inactive'},422)
          : scenario==='account-mismatch' ? respond({error:'fio_receiving_account_mismatch'},422)
          : scenario==='throttled' ? respond({error:'api_fetch_throttled'},429)
          : scenario==='transient' ? respond({error:'fio_api_transient_failure'},503)
          : respond({api_last_success_at:'2026-10-04T12:00:00Z'});
      }
      throw new Error('Unexpected request path');
    }) as typeof fetch;
    try {
      const run=()=>runBankSyncOperation({operation_id:'fixture',operation:'set_token',token:'new-fixture-token'},'fixture-hash');
      if (scenario==='digest-mismatch') {
        await assertRejects(run,Error,'token_storage_not_verified');
        assertEquals(bankChecks,0);assertEquals(enabled,false);assertEquals(ingestEnabled,false);
        assertEquals(calls.at(-1)?.body.p_state,'uncertain');
      } else {
        const result=await run();
        assertEquals(stored,'new-fixture-token');assertEquals(tokenWrites,1);assertEquals(enabled,true);
        assertEquals(result.token_saved,true);
        assertEquals(calls.find(c=>c.name==='update_bank_sync_connection_metadata')?.body.p_mode,'api');
        assertEquals(result.state,scenario==='valid'?'connected':'degraded');
        assertEquals(result.verification_error,scenario==='inactive'?'fio_token_invalid_or_inactive':scenario==='account-mismatch'?'fio_receiving_account_mismatch':scenario==='valid'?undefined:'bank_sync_retry_required');
        assertEquals(calls.find(c=>c.name==='record_bank_sync_pull')?.body.p_error,
          scenario==='inactive'?'fio_token_invalid_or_inactive':scenario==='account-mismatch'?'fio_receiving_account_mismatch':scenario==='valid'?null:'bank_sync_retry_required');
        assertEquals(calls.at(-1)?.body.p_state,'completed');
      }
    } finally { requestHandler=undefined; }
  });
}

for (const mismatch of [false, true]) {
  Deno.test(`account label update verifies persistence (mismatch=${mismatch})`, async () => {
    const calls: any[] = []; let stored='old';
    requestHandler = (async (input: any, init?: RequestInit) => {
      const url=new URL(input instanceof Request ? input.url : String(input));
      const body=init?.body ? JSON.parse(String(init.body)) : {};
      const response=(v:unknown)=>new Response(JSON.stringify(v),{headers:{'content-type':'application/json'}});
      if(url.hostname==='127.0.0.1') {
        calls.push(body);
        return response(url.pathname.endsWith('claim_bank_sync_operation') ? {connection_id:1,remote_id:'9',barrier:'active',lease_token:'lease',title:'New label'} : null);
      }
      assertEquals(url.pathname,'/bank-accounts/9');
      if(init?.method==='PUT') {assertEquals(body,{label:'New label'});stored=body.label;}
      return response({label:mismatch?'old':stored});
    }) as typeof fetch;
    try {
      const run=()=>runBankSyncOperation({operation_id:'fixture',operation:'update_details'},'hash');
      if(mismatch) {await assertRejects(run,Error,'account_details_not_verified'); assertEquals(calls.at(-1).p_state,'uncertain');}
      else {assertEquals(await run(),{details_saved:true});assertEquals(calls.at(-1).p_state,'completed');}
    } finally {requestHandler=undefined;}
  });
}

for (const scenario of ['resume-api', 'resume-inactive', 'resume-email', 'suspend-api', 'suspend-email', 'resume-readback-mismatch'] as const) {
  Deno.test(`synchronization control: ${scenario}`, async () => {
    const suspend = scenario.startsWith('suspend');
    const mode = scenario.endsWith('email') ? 'email' : 'api';
    let ingress = suspend;
    let polling = suspend;
    let pulls = 0;
    let tokenWrites = 0;
    const calls: {name:string;body:any}[] = [];
    requestHandler = (async (input:any, init?:RequestInit) => {
      const url = new URL(input instanceof Request ? input.url : String(input));
      const body = init?.body ? JSON.parse(String(init.body)) : {};
      const respond = (value:unknown,status=200) => new Response(JSON.stringify(value),{status,headers:{'content-type':'application/json'}});
      if (url.hostname === '127.0.0.1') {
        const name = url.pathname.split('/').pop()!;
        calls.push({name,body});
        return respond(name === 'claim_bank_sync_operation'
          ? {connection_id:1,remote_id:'9',barrier:'active',lease_token:'lease',mode}
          : null);
      }
      if (url.pathname.endsWith('/ingest-state')) {
        if (init?.method === 'PUT') ingress = body.enabled;
        return respond({ingest_enabled:scenario === 'resume-readback-mismatch' ? false : ingress});
      }
      if (url.pathname.endsWith('/fio-token')) {
        polling = body.fetch_enabled;
        if (body.fio_api_token) tokenWrites++;
        return respond({});
      }
      if (url.pathname.endsWith('/fio-sync')) {
        pulls++;
        assertEquals(ingress,true);
        assertEquals(polling,true);
        return scenario === 'resume-inactive'
          ? respond({error:'fio_token_invalid_or_inactive'},422)
          : respond({api_last_success_at:'2026-10-14T22:00:00Z'});
      }
      if (url.pathname === '/bank-accounts/9') return respond({api_fetch_enabled:polling});
      throw new Error('Unexpected request');
    }) as typeof fetch;
    try {
      const run = () => runBankSyncOperation({operation_id:'fixture',operation:suspend?'suspend':'resume'},'hash');
      if (scenario === 'resume-readback-mismatch') {
        await assertRejects(run,Error,'sync_state_not_verified');
        assertEquals(calls.some(c=>c.name==='update_bank_sync_connection_metadata'),false);
        assertEquals(calls.at(-1)?.body.p_state,'uncertain');
      } else {
        const result = await run();
        assertEquals(ingress,!suspend);
        assertEquals(polling,mode==='api' ? !suspend : suspend);
        assertEquals(pulls,!suspend && mode==='api' ? 1 : 0);
        assertEquals(result.state,suspend?'suspended':scenario==='resume-inactive'?'degraded':'connected');
        assertEquals(calls.at(-1)?.body.p_state,'completed');
        assertEquals(calls.find(c=>c.name==='update_bank_sync_connection_metadata')?.body.p_expiry,null);
        if (scenario==='resume-inactive') assertEquals(result.verification_error,'fio_token_invalid_or_inactive');
      }
      assertEquals(tokenWrites,0,'Pause/resume must preserve existing credentials');
    } finally {requestHandler=undefined;}
  });
}

for (const deferred of ['cooldown','busy'] as const) {
  Deno.test(`resume treats ${deferred} as pending synchronization, not a bank failure`, async()=>{
    const calls:{name:string;body:any}[]=[];
    requestHandler=(async(input:any,init?:RequestInit)=>{
      const url=new URL(input instanceof Request?input.url:String(input));
      const body=init?.body?JSON.parse(String(init.body)):{};
      const respond=(v:unknown,status=200)=>new Response(JSON.stringify(v),{status,headers:{'content-type':'application/json'}});
      if(url.hostname==='127.0.0.1') {
        const name=url.pathname.split('/').pop()!;calls.push({name,body});
        return respond(name==='claim_bank_sync_operation'?{connection_id:1,remote_id:'9',barrier:'active',lease_token:'lease',mode:'api',state:'suspended'}:null);
      }
      if(url.pathname.endsWith('/ingest-state'))return respond({ingest_enabled:true});
      if(url.pathname.endsWith('/fio-token'))return respond({});
      if(url.pathname.endsWith('/fio-sync'))return deferred==='cooldown'
        ?respond({error:'api_fetch_throttled',retry_after_s:30},429)
        :respond({deferred:true,api_last_success_at:null});
      if(url.pathname==='/bank-accounts/9')return respond({api_fetch_enabled:true});
      throw new Error('Unexpected request');
    }) as typeof fetch;
    try {
      const result=await runBankSyncOperation({operation_id:'fixture',operation:'resume'},'hash');
      assertEquals(result.state,'connected');
      assertEquals(result.sync_pending,true);
      assertEquals(result.verification_error,undefined);
      assertEquals(calls.some(c=>c.name==='record_bank_sync_pull'),false,'No bank request means no new success or failure fact');
      assertEquals(calls.at(-1)?.body.p_state,'completed');
    } finally {requestHandler=undefined;}
  });
}

for (const provider of ['CSOB','MONETA','CREDITAS','RAIFFEISENBANK','UNICREDIT','CSAS']) {
  Deno.test(`${provider} can provision email connection but cannot provision API`, async () => {
    let remoteCreates=0;
    requestHandler=(async (input: string | URL | Request, init?: RequestInit) => {
      const url=new URL(input instanceof Request ? input.url : String(input));
      const body=init?.body ? JSON.parse(String(init.body)) : {};
      const response=(value:unknown)=>new Response(JSON.stringify(value),{headers:{'content-type':'application/json'}});
      if(url.hostname==='127.0.0.1') {
        const name=url.pathname.split('/').pop();
        if(name==='claim_bank_sync_operation') return response({provider,account_number:'123456/0800',title:'Fixture',lease_token:'lease'});
        if(name==='save_bank_sync_connection') return response(1);
        return response(null);
      }
      if(url.pathname==='/bank-accounts') {
        remoteCreates++;
        assertEquals(body.account_type,provider);
        assertEquals(body.ingest_mode,'email');
        assertEquals(body.ingest_enabled,false);
        return response({id:9,pairing_code:'fixture-pairing'});
      }
      if(url.pathname==='/subscriptions') return response([{consumer_app_id:'festapp'}]);
      if(url.pathname==='/bank-accounts/9/ingest-state') return response({});
      throw new Error(`Unexpected request ${url.pathname}`);
    }) as typeof fetch;
    try {
      const result=await runBankSyncOperation({operation_id:'fixture',operation:'create',mode:'email'},'fixture-hash');
      assertEquals(result.state,'connected');
      assertEquals(result.receiving_address,'fixture-pairing@banksync.festapp.net');
      assertEquals(remoteCreates,1);
      await assertRejects(()=>runBankSyncOperation({operation_id:'fixture',operation:'create',mode:'api'},'fixture-hash'),Error,'unsupported_bank_capability');
      assertEquals(remoteCreates,1);
    } finally {requestHandler=undefined;}
  });
}
