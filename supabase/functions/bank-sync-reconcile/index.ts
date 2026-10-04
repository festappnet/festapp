import { supabaseAdmin } from '../_shared/supabaseUtil.ts';
import { authorizeRequest, AuthError } from '../_shared/auth.ts';
import { openBankSyncToken } from '../_shared/bankSyncToken.ts';
import { runBankSyncOperation } from '../_shared/bankSyncOperation.ts';
Deno.serve(async (req) => {
  const json = (data: unknown, status=200) => new Response(JSON.stringify(data), {
    status, headers:{'content-type':'application/json','cache-control':'no-store'},
  });
  if (req.method !== 'POST') return json({error:'method_not_allowed'},405);
  try {
    const {requestSecret} = await req.json();
    await authorizeRequest({requestSecret});
    const {data, error} = await supabaseAdmin.rpc('get_recoverable_bank_sync_operations');
    if (error) throw new Error('operations_read_failed');
    const results = [];
    const started = Date.now();
    for (const operation of data ?? []) {
      if (Date.now()-started>180_000) break;
      try {
        const input = {...operation.request};
        if (operation.token_cipher) input.token = await openBankSyncToken(operation.token_cipher,operation.id,operation.payload_sha256);
        await runBankSyncOperation(input,operation.payload_sha256);
        results.push({id:operation.id,state:'completed'});
      } catch { results.push({id:operation.id,state:'uncertain'}); }
    }
    return json({results},results.some(r=>r.state==='uncertain')?503:200);
  } catch (error) {
    return json({error:error instanceof AuthError?error.message:'operation_recovery_failed'},error instanceof AuthError?error.status:503);
  }
});
