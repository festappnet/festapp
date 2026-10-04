import { supabaseAdmin } from "./supabaseUtil.ts";
/** The caller must already have checked editor rights on this occasion/unit. */
export async function synchronizeCanonicalBankConnections(unitId: number) {
  const { data: connections, error } = await supabaseAdmin.rpc("get_bank_sync_connections_for_unit", { p_unit_id: unitId });
  if (error) throw new Error("canonical_connections_unavailable");
  const results = [];
  for (const connection of connections ?? []) {
    if (!/^[0-9]+$/.test(connection.remote_bank_account_id)) throw new Error("invalid_remote_mapping");
    const origin = Deno.env.get("BANKSYNC_API_URL");
    const key = Deno.env.get("BANKSYNC_TENANT_ADMIN_KEY");
    if (!origin?.startsWith("https://") || !key) throw new Error("canonical_bank_sync_not_configured");
    const response = await fetch(`${origin.replace(/\/$/, "")}/bank-accounts/${connection.remote_bank_account_id}/fio-sync`, {
      method: "POST", redirect: "error", signal: AbortSignal.timeout(30_000),
      headers: { "x-tenant-secret": key, "content-type": "application/json" }, body: "{}",
    });
    if (!response.ok) {
      await supabaseAdmin.rpc("record_bank_sync_pull", { p_id: connection.connection_id, p_success_at: null, p_error: "bank_sync_retry_required" });
      throw new Error("canonical_bank_sync_retry_required");
    }
    const result = await response.json();
    const metadata = await supabaseAdmin.rpc("record_bank_sync_pull", {
      p_id: connection.connection_id, p_success_at: result.api_last_success_at, p_error: null,
    });
    if (metadata.error) throw new Error("canonical_bank_sync_metadata_failed");
    results.push({ connection_id: String(connection.connection_id), bank_pull_at: result.api_last_success_at,
      inserted: result.inserted, skipped_duplicate: result.skipped_duplicate });
  }
  return results;
}
