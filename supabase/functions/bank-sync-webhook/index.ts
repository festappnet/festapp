import { supabaseAdmin } from "../_shared/supabaseUtil.ts";
import { bankSyncWebhook } from "./handler.ts";

Deno.serve((req) => bankSyncWebhook(req, {
  secret: Deno.env.get("BANKSYNC_WEBHOOK_SECRET") ?? "",
  instanceId: Deno.env.get("BANKSYNC_INSTANCE_ID") ?? "",
  async ingest(digest, envelope) {
    const { data, error } = await supabaseAdmin.rpc("ingest_bank_sync_transaction", {
      p_instance_id: Deno.env.get("BANKSYNC_INSTANCE_ID"),
      p_consumer_app_id: "festapp",
      p_body_sha256: digest,
      p_envelope: envelope,
    }).abortSignal(AbortSignal.timeout(15_000));
    if (error) throw new Error(error.message);
    return data;
  },
}));
