import { supabaseAdmin } from "./supabaseUtil.ts";

/** Database-issued order, captured before remote I/O; independent of worker clocks. */
export async function beginBankSyncObservation(
  connectionId: number | string,
): Promise<string> {
  const { data, error } = await supabaseAdmin.rpc(
    "begin_bank_sync_observation",
    {
      p_connection_id: connectionId,
    },
  ).abortSignal(AbortSignal.timeout(10_000));
  if (error || typeof data !== "string" || !/^[1-9][0-9]*$/.test(data)) {
    throw new Error("bank_sync_observation_failed");
  }
  return data;
}
