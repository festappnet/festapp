import { bankSyncRemote as remote, bankSyncErrorCode } from './bankSyncRemote.ts';
import { bankSyncHash as hash } from "./bankSyncToken.ts";
import { supabaseAdmin } from "../_shared/supabaseUtil.ts";
export async function runBankSyncOperation(input: Record<string, any>, fingerprint: string) {
  const instanceId = Deno.env.get("BANKSYNC_INSTANCE_ID") ?? "";
  const origin = Deno.env.get("BANKSYNC_API_URL") ?? "";
  const adminKey = Deno.env.get("BANKSYNC_TENANT_ADMIN_KEY") ?? "";
  if (!instanceId || !origin.startsWith("https://") || !adminKey) throw new Error("management_not_configured");
  const { data: context, error: claimError } = await supabaseAdmin.rpc("claim_bank_sync_operation", { p_id: input.operation_id });
  if (claimError) throw new Error("operation_busy");
  async function rpc(name: string, params: Record<string, unknown>) {
    const { data, error } = await supabaseAdmin.rpc(name, params).abortSignal(AbortSignal.timeout(10_000));
    if (error) throw new Error("operation_database_failed");
    return data;
  }
  try {
    let result;
    if (input.operation === "create") {
      if (!["FIO", "AIRBANK"].includes(context.provider) || (input.mode === "api" && context.provider !== "FIO")) {
        throw new Error("unsupported_bank_capability");
      }
      // A remote account is paused and tokenless until mapping and subscription
      // survive local commit. POST retry uses one durable operation identity.
      const account = await remote("/bank-accounts", "POST", {
        account_number: context.account_number, account_type: context.provider, label: context.title,
        owner_app_id: "festapp", ingest_mode: input.mode, ingest_enabled: false,
      }, input.operation_id);
      const subscriptions = await remote(`/subscriptions?bank_account_id=${account.id}`);
      if (!Array.isArray(subscriptions) || !subscriptions.some((s) => s.consumer_app_id === "festapp")) {
        throw new Error("owner_subscription_missing");
      }
      const connectionId = await rpc("save_bank_sync_connection", {
        p_operation_id: input.operation_id, p_instance_id: instanceId, p_remote_id: String(account.id),
        p_pairing_code: account.pairing_code, p_mode: input.mode,
      });
      await rpc("activate_bank_sync_connection", { p_connection_id: connectionId, p_manifest_sha256: fingerprint });
      await remote(`/bank-accounts/${account.id}/ingest-state`, "PUT", { enabled: true });
      result = { state: "connected", receiving_address: `${account.pairing_code}@banksync.festapp.net` };
    } else {
      if (!context.remote_id || !/^[0-9]+$/.test(context.remote_id) || !context.barrier) throw new Error("canonical_connection_required");
      const path = `/bank-accounts/${context.remote_id}`;
      if (input.operation === "update_details") {
        await remote(path, 'PUT', {label:context.title ?? ''});
        const stored = await remote(path);
        if (stored.label !== (context.title ?? '')) throw new Error('account_details_not_verified');
        result = {details_saved:true};
      } else if (input.operation === "set_token") {
        // A timeout is reconciled by the full credential digest, not its prefix.
        const proof = await remote(`${path}/ingest-state`);
        if (proof.api_token_hash !== await hash(input.token)) {
          await remote(`${path}/fio-token`, 'PUT', { fetch_enabled: false });
          await remote(`${path}/fio-token`, "PUT", { fio_api_token: input.token, fetch_enabled: false, ingest_mode: "api" });
        }
        // Persisted digest must match before the UI is allowed to report storage success.
        const stored = await remote(`${path}/ingest-state`);
        if (stored.api_token_hash !== await hash(input.token)) throw new Error('token_storage_not_verified');
        // A replacement token also resumes a previously expired/suspended account.
        await remote(`${path}/ingest-state`, 'PUT', {enabled:true});
        let verificationError: string | null = null;
        try {
          const pull = await remote(`${path}/fio-sync`, "POST", {});
          await rpc("record_bank_sync_pull", {p_id:context.connection_id,p_success_at:pull.api_last_success_at,p_error:null});
        } catch (error) {
          // Storage is already proven. Cooldown, an in-flight poll or bank downtime
          // must not turn a saved token into a reported storage failure.
          verificationError = bankSyncErrorCode(error);
          await rpc("record_bank_sync_pull", {p_id:context.connection_id,p_success_at:null,p_error:verificationError});
        }
        // Authorization can happen later in Fio; the same stored token is retried.
        await remote(`${path}/fio-token`, "PUT", { fetch_enabled: true, ingest_mode: "api" });
        await rpc("update_bank_sync_connection_metadata", { p_id: context.connection_id,
          p_pairing_code: null, p_expiry: input.expiry ?? null, p_mode: "api", p_state: verificationError ? "degraded" : "connected" });
        result = { state: verificationError ? "degraded" : "connected", token_saved:true,
          ...(verificationError ? {verification_error:verificationError} : {}) };
      } else if (input.operation === "rotate_pairing") {
        let account = await remote(path);
        if (account.pairing_code === context.request.expected_pairing) account = await remote(`${path}/regenerate-pairing`, "POST", {});
        await rpc("update_bank_sync_connection_metadata", { p_id: context.connection_id,
          p_pairing_code: account.pairing_code, p_expiry: null, p_state: context.state });
        result = { receiving_address: `${account.pairing_code}@banksync.festapp.net` };
      } else if (input.operation === "suspend") {
        await remote(`${path}/ingest-state`, "PUT", { enabled: false });
        if (context.mode === "api") await remote(`${path}/fio-token`, "PUT", { fetch_enabled: false });
        await rpc("update_bank_sync_connection_metadata", { p_id: context.connection_id,
          p_pairing_code: null, p_expiry: null, p_state: "suspended" });
        result = { state: "suspended" };
      } else {
        result = await remote(`${path}/fio-sync`, "POST", {});
        await rpc("record_bank_sync_pull",{p_id:context.connection_id,p_success_at:result.api_last_success_at,p_error:null});
      }
    }
    await rpc("complete_bank_sync_operation", { p_id: input.operation_id, p_state: "completed", p_result: result,p_lease_token:context.lease_token });
    return result;
  } catch (error) {
    const code = bankSyncErrorCode(error);
    if (context.connection_id) await supabaseAdmin.rpc('record_bank_sync_pull', {
      p_id:context.connection_id,p_success_at:null,p_error:code,
    });
    await supabaseAdmin.rpc("complete_bank_sync_operation", { p_id: input.operation_id, p_state: "uncertain", p_result: null,p_lease_token:context.lease_token });
    throw error;
  }
}
