import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.58.0";
import { issueExistingUserSession } from "../_shared/issueExistingUserSession.ts";
export async function exchangeSignInCode(
  input: unknown,
  admin: SupabaseClient,
  anon: SupabaseClient,
) {
  if (!input || typeof input !== "object") return null;
  const value = input as Record<string, unknown>;
  if (
    typeof value.email !== "string" || value.email.length > 320 ||
    typeof value.code !== "string" || !/^\d{6}$/.test(value.code) ||
    !Number.isSafeInteger(value.organization) || Number(value.organization) <= 0
  ) return null;
  const { data, error } = await admin.rpc("consume_sign_in_code_v1", {
    p_email: value.email,
    p_organization: value.organization,
    p_code: value.code,
  });
  if (error) throw new Error("code_exchange_unavailable");
  if (!data?.userId || !data?.authEmail) return null;
  const session = await issueExistingUserSession(
    { targetUserId: data.userId, expectedAuthEmail: data.authEmail },
    admin,
    anon,
  );
  return { refresh_token: session.refresh_token };
}
