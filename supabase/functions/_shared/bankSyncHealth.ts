import { bankSyncRemote, bankSyncAccountError } from './bankSyncRemote.ts';
import { supabaseAdmin } from './supabaseUtil.ts';

// This observes the owning bank service. It never polls the bank or sends email.
export async function monitorBankSyncHealth(organizationId: number) {
  async function rpc(name: string, params: Record<string, unknown>) {
    const {data,error} = await supabaseAdmin.rpc(name,params).abortSignal(AbortSignal.timeout(10_000));
    if (error) throw new Error('bank_sync_health_database_failed');
    return data;
  }
  const targets = await rpc('get_bank_sync_health_targets',{p_organization_id:organizationId});
  const started = Date.now();
  let checked = 0;
  for (const target of targets ?? []) {
    if (Date.now()-started>180_000) break;
    if (!/^[0-9]+$/.test(target.remote_bank_account_id)) throw new Error('invalid_remote_mapping');
    let success = null;
    let error: string | null = null;
    let ingress: boolean | null = null;
    let polling: boolean | null = null;
    let tokenPresent: boolean | null = null;
    try {
      const path = `/bank-accounts/${target.remote_bank_account_id}`;
      const [account,state] = await Promise.all([bankSyncRemote(path),bankSyncRemote(`${path}/ingest-state`)]);
      if (typeof state.ingest_enabled !== 'boolean' && ![0,1].includes(state.ingest_enabled)) throw new Error('invalid_ingest_state');
      ingress = Boolean(state.ingest_enabled);
      if (target.mode === 'api') {
        if (typeof account.api_fetch_enabled !== 'boolean' && ![0,1].includes(account.api_fetch_enabled)) throw new Error('invalid_poll_state');
        polling = Boolean(account.api_fetch_enabled);
        tokenPresent = Boolean(state.api_token_hash);
        success = account.api_last_success_at ?? null;
        error = bankSyncAccountError(account.api_last_error);
      }
    } catch {
      // A failed management read is not evidence that Fio or its token failed.
      error = 'bank_sync_unavailable';
    }
    await rpc('record_bank_sync_health',{
      p_organization_id:organizationId,p_connection_id:target.connection_id,p_success_at:success,p_error:error,
      p_ingest_enabled:ingress,p_polling_enabled:polling,p_token_present:tokenPresent,
    });
    checked++;
  }
  const queued = await rpc('enqueue_bank_sync_health_alerts',{p_organization_id:organizationId});
  return {checked,queued};
}
