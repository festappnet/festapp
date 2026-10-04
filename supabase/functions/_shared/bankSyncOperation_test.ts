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

for (const scenario of ['valid','inactive','digest-mismatch'] as const) {
  Deno.test(`token update reaches BankSync and reports ${scenario} accurately`, async () => {
    let stored = 'old-fixture-token';
    let enabled = false;
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
      if (url.pathname.endsWith('/ingest-state')) return respond({api_token_hash:await bankSyncHash(scenario === 'digest-mismatch' ? 'wrong-token' : stored)});
      if (url.pathname.endsWith('/fio-token')) {
        if (body.fio_api_token) {stored=body.fio_api_token;tokenWrites++;}
        enabled=body.fetch_enabled;return respond({});
      }
      if (url.pathname.endsWith('/fio-sync')) {
        bankChecks++;assertEquals(stored,'new-fixture-token');
        return scenario==='inactive'
          ? respond({error:'fio_token_invalid_or_inactive'},422)
          : respond({api_last_success_at:'2026-10-04T12:00:00Z'});
      }
      throw new Error('Unexpected request path');
    }) as typeof fetch;
    try {
      const run=()=>runBankSyncOperation({operation_id:'fixture',operation:'set_token',token:'new-fixture-token'},'fixture-hash');
      if (scenario==='digest-mismatch') {
        await assertRejects(run,Error,'token_storage_not_verified');
        assertEquals(bankChecks,0);assertEquals(enabled,false);
        assertEquals(calls.at(-1)?.body.p_state,'uncertain');
      } else {
        const result=await run();
        assertEquals(stored,'new-fixture-token');assertEquals(tokenWrites,1);assertEquals(enabled,true);
        assertEquals(result.token_saved,true);
        assertEquals(result.state,scenario==='inactive'?'degraded':'connected');
        assertEquals(result.verification_error,scenario==='inactive'?'fio_token_invalid_or_inactive':undefined);
        assertEquals(calls.find(c=>c.name==='record_bank_sync_pull')?.body.p_error,
          scenario==='inactive'?'fio_token_invalid_or_inactive':null);
        assertEquals(calls.at(-1)?.body.p_state,'completed');
      }
    } finally { requestHandler=undefined; }
  });
}
