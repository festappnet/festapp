import { bankSyncRemote, bankSyncAccountError, bankSyncErrorCode } from '../_shared/bankSyncRemote.ts';
import { runBankSyncOperation } from "../_shared/bankSyncOperation.ts";
import { sealBankSyncToken } from "../_shared/bankSyncToken.ts";
import { createUserClient, supabaseAdmin } from "../_shared/supabaseUtil.ts";

const cors = { "access-control-allow-origin": "*", "access-control-allow-headers": "authorization,apikey,content-type,x-client-info" };
const json = (data: unknown, status = 200) => new Response(JSON.stringify(data), {
  status, headers: { ...cors, "content-type": "application/json", "cache-control": "no-store" },
});
const operations = new Set(["create", "set_token", "rotate_pairing", "sync", "suspend"]);
async function hash(value: string): Promise<string> {
  return Array.from(new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value))))
    .map((byte) => byte.toString(16).padStart(2, "0")).join("");
}
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  const authorization = req.headers.get("authorization");
  if (!authorization) return json({ error: "unauthorized" }, 401);
  const user = createUserClient(authorization);
  const { data: auth, error: authError } = await user.auth.getUser();
  if (authError || !auth.user) return json({ error: "unauthorized" }, 401);
  let input;
  try {
    const text = await req.text();
    if (text.length > 8192) return json({ error: "body_limit" }, 413);
    input = JSON.parse(text);
  } catch { return json({ error: "invalid_json" }, 400); }
  if (!input || typeof input !== "object" || Array.isArray(input)) return json({ error: "invalid_json" }, 400);
  if (!Number.isSafeInteger(input.account_id) || input.account_id <= 0) return json({ error: "account_required" }, 400);
  const { data: status, error: rightsError } = await user.rpc("get_bank_sync_connection", { p_bank_account_id: input.account_id });
  if (rightsError) return json({ error: "bank_account_admin_required" }, 403);
  if (input.operation === "status") {
    if (!status || !status.remote_bank_account_id) return json(status);
    try {
      if (!/^[0-9]+$/.test(status.remote_bank_account_id)) throw new Error('invalid_remote_mapping');
      const remote = await bankSyncRemote(`/bank-accounts/${status.remote_bank_account_id}`);
      const lastError = bankSyncAccountError(remote.api_last_error);
      const recorded = await supabaseAdmin.rpc('record_bank_sync_pull', {
        p_id:status.id,p_success_at:remote.api_last_success_at,p_error:lastError,
      });
      if (recorded.error) throw new Error('status_update_failed');
      const refreshed = await user.rpc('get_bank_sync_connection', {p_bank_account_id:input.account_id});
      if (refreshed.error) throw new Error('status_read_failed');
      return json({...refreshed.data,token_masked:remote.api_token_prefix ? `${remote.api_token_prefix}********` : null});
    } catch { return json({...status,last_error:status.last_error ?? 'bank_sync_retry_required'}); }
  }
  if (!operations.has(input.operation) || typeof input.operation_id !== "string" || !/^[0-9a-f-]{36}$/i.test(input.operation_id)) {
    return json({ error: "operation_required" }, 400);
  }
  if (input.operation === "create" && !["api", "email"].includes(input.mode)) return json({ error: "mode_required" }, 400);
  if (input.operation === "set_token" && (typeof input.token !== "string" || !/^[a-zA-Z0-9]{8,256}$/.test(input.token))) {
    return json({ error: "invalid_token" }, 400);
  }
  const instanceId = Deno.env.get("BANKSYNC_INSTANCE_ID") ?? "";
  const origin = Deno.env.get("BANKSYNC_API_URL") ?? "";
  const adminKey = Deno.env.get("BANKSYNC_TENANT_ADMIN_KEY") ?? "";
  if (!instanceId || !origin.startsWith("https://") || !adminKey) return json({ error: "management_not_configured" }, 503);
  const fingerprint = await hash(JSON.stringify({ operation: input.operation, account: input.account_id,
    mode: input.mode ?? null, token_hash: input.token ? await hash(input.token) : null, expiry: input.expiry ?? null }));
  const { data: intent, error: intentError } = await user.rpc("begin_bank_sync_operation", {
    p_id: input.operation_id, p_account_id: input.account_id, p_operation: input.operation, p_hash: fingerprint,
  });
  if (intentError) return json({ error: "operation_conflict" }, 409);
  if (intent.state === "completed") return json(intent.result);
  input.operation_id = intent.id;
  try {
    const { token, ...request } = input;
    const tokenCipher = token ? await sealBankSyncToken(token, input.operation_id, fingerprint) : null;
    const stage = await supabaseAdmin.rpc("stage_bank_sync_operation", {
      p_id: input.operation_id, p_hash: fingerprint, p_request: request, p_token_cipher: tokenCipher,
    });
    if (stage.error) return json({ error: "operation_busy", operation_id: input.operation_id }, 409);
    return json(await runBankSyncOperation(input, fingerprint));
  } catch (error) {
    return json({ error: bankSyncErrorCode(error), operation_id: input.operation_id }, 503);
  }
});
