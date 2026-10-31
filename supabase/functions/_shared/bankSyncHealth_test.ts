import {assertEquals} from 'https://deno.land/std@0.224.0/assert/mod.ts';
Deno.env.set('SUPABASE_URL','http://127.0.0.1:55499');
Deno.env.set('SUPABASE_SERVICE_ROLE_KEY','synthetic-local-test-key');
Deno.env.set('BANKSYNC_API_URL','https://banksync.invalid');
Deno.env.set('BANKSYNC_TENANT_ADMIN_KEY','synthetic-scoped-key');
let handler: typeof fetch;
globalThis.fetch=((...args:Parameters<typeof fetch>)=>handler(...args)) as typeof fetch;
const {monitorBankSyncHealth}=await import('./bankSyncHealth.ts');
for (const scenario of ['healthy','inactive','fio-502','fio-rate-limited','fio-timeout','transport-failure','missing-token','email'] as const) {
 Deno.test(`bank health monitoring observes ${scenario} without polling or sending`,async()=>{
  const calls: {name:string;body:any}[]=[];
  handler=(async(input:any,init?:RequestInit)=>{
   const url=new URL(input instanceof Request?input.url:String(input));
   const body=init?.body?JSON.parse(String(init.body)):{};
   const response=(v:unknown,status=200)=>new Response(JSON.stringify(v),{status,headers:{'content-type':'application/json'}});
   if(url.hostname==='127.0.0.1') {
    const name=url.pathname.split('/').pop()!;calls.push({name,body});
    if(name==='get_bank_sync_health_targets')return response([{connection_id:7,remote_bank_account_id:'414',mode:scenario==='email'?'email':'api'}]);
    if(name==='enqueue_bank_sync_health_alerts')return response(2);
    return response(null);
   }
   assertEquals(init?.method,'GET');
   assertEquals(new Headers(init?.headers).get('x-tenant-secret'),'synthetic-scoped-key');
   if(scenario==='transport-failure')return response({},503);
   return url.pathname.endsWith('/ingest-state')
    ?response({ingest_enabled:1,api_token_hash:scenario==='missing-token'?null:'fixture-hash'})
    :response({api_fetch_enabled:true,api_last_success_at:'2026-10-14T22:00:00Z',api_last_error:scenario==='inactive'?'fio_token_invalid_or_inactive':scenario==='fio-502'?'FioTransientFailure: Fio API 502':scenario==='fio-rate-limited'?'FioRateLimited: Fio API 429':scenario==='fio-timeout'?'TimeoutError: The signal timed out':null});
  }) as typeof fetch;
  assertEquals(await monitorBankSyncHealth(3),{checked:1,queued:2});
  const observed=calls.find(c=>c.name==='record_bank_sync_health')!.body;
  assertEquals(observed.p_organization_id,3);
  assertEquals(observed.p_error,scenario==='inactive'?'fio_token_invalid_or_inactive':scenario==='transport-failure'?'bank_sync_unavailable':['fio-502','fio-rate-limited','fio-timeout'].includes(scenario)?'fio_temporarily_unavailable':null);
  assertEquals(observed.p_token_present,['email','transport-failure'].includes(scenario)?null:scenario!=='missing-token');
  assertEquals(calls.at(-1)?.name,'enqueue_bank_sync_health_alerts');
 });
}

const {bankSyncAccountError}=await import('./bankSyncRemote.ts');
Deno.test('bank observation decoding never diagnoses a token from an arbitrary 500 or leaks raw errors',()=>{
 for (const [input,expected] of [
  ['FioTransientFailure: Fio API 503','fio_temporarily_unavailable'],
  ['FioRateLimited: Fio API 409','fio_temporarily_unavailable'],
  ['AbortError: request aborted','fio_temporarily_unavailable'],
  ['FioApiError: Fio API 500','bank_sync_retry_required'],
  ['unknown-private-error-with-token','bank_sync_retry_required'],
  ['fio_token_invalid_or_inactive','fio_token_invalid_or_inactive'],
  ['Error: fio_receiving_account_mismatch','fio_receiving_account_mismatch'],
  ['',null],
 ] as const) assertEquals(bankSyncAccountError(input),expected);
});
