import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.58.0";

export type AccountAssuranceDecision =
  | "allowed"
  | "mfa_required"
  | "proof_required"
  | "account_recovery"
  | "invalid_session"
  | "assurance_unavailable";

/** Use a client carrying the original user token. A service role client
 * cannot decide assurance for a caller based on their user ID. */
export async function accountAssurance(
  client: SupabaseClient,
  organization?: number,
): Promise<AccountAssuranceDecision> {
  const { data, error } = await client.rpc("get_account_assurance_v1",
    organization === undefined ? {} : { p_organization: organization });
  if (error) return "assurance_unavailable";
  switch (data) {
    case "allowed":
    case "mfa_required":
    case "proof_required":
    case "account_recovery":
    case "invalid_session":
      return data;
    default:
      return "assurance_unavailable";
  }
}

export function accountAssuranceFailureStatus(decision: Exclude<AccountAssuranceDecision, "allowed">) {
  if (decision === "assurance_unavailable") return 503;
  if (decision === "invalid_session") return 401;
  return 403;
}
