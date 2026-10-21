import { bankSyncRemote, bankSyncErrorCode } from './bankSyncRemote.ts';
import { supabaseAdmin } from "./supabaseUtil.ts";
import type { BankConnection } from '../fetch-transactions/handler.ts';
/** Accept only the data returned by the authenticated SQL bank operation. */
export async function synchronizeCanonicalBankConnections(connections: BankConnection[]) {
  const results = [];
  for (const connection of connections ?? []) {
    if (!/^[0-9]+$/.test(connection.remote_bank_account_id)) throw new Error("invalid_remote_mapping");
    let result;
    try {
      result = await bankSyncRemote(`/bank-accounts/${connection.remote_bank_account_id}/fio-sync`, 'POST', {});
    } catch (error) {
      const code = bankSyncErrorCode(error);
      await supabaseAdmin.rpc('record_bank_sync_pull', {p_id:connection.connection_id,p_success_at:null,p_error:code});
      throw new Error(code);
    }
    const metadata = await supabaseAdmin.rpc("record_bank_sync_pull", {
      p_id: connection.connection_id, p_success_at: result.api_last_success_at, p_error: null,
    });
    if (metadata.error) throw new Error("canonical_bank_sync_metadata_failed");
    results.push({ connection_id: String(connection.connection_id), bank_pull_at: result.api_last_success_at,
      inserted: result.inserted, skipped_duplicate: result.skipped_duplicate });
  }
  return results;
}
