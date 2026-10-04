import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.58.0";
import { issueExistingUserSession } from "../_shared/issueExistingUserSession.ts";
import { parseLoginQr, parseManualLoginCode, sha256Hex } from "./qr.ts";

export async function exchangeLoginCredential(
  input: unknown,
  admin: SupabaseClient,
  anon: SupabaseClient,
) {
  if (input == null || typeof input !== "object") return null;
  const value = input as {
    payload?: unknown;
    occasion?: unknown;
    manualCode?: unknown;
  };
  const parsed = value.payload != null
    ? parseLoginQr(value.payload)
    : parseManualLoginCode(value.occasion, value.manualCode);
  if (!parsed) return null;
  return exchangeResolvedCredential(parsed, admin, anon);
}

async function exchangeResolvedCredential(
  parsed: { occasion: number; token: string },
  admin: SupabaseClient,
  anon: SupabaseClient,
) {
  const { data: resolved, error: resolveError } = await admin.rpc(
    "resolve_reception_login_qr_v1",
    {
      p_occasion: parsed.occasion,
      p_token_hash: await sha256Hex(parsed.token),
    },
  );
  if (resolveError || !resolved?.authEmail) return null;
  let session;
  try {
    session = await issueExistingUserSession(
      { targetUserId: resolved.userId, expectedAuthEmail: resolved.authEmail }, admin, anon,
      { validateContext: async () => {
        const { data, error } = await admin.rpc("resolve_reception_login_qr_v1", {
          p_occasion: parsed.occasion, p_token_hash: await sha256Hex(parsed.token),
        });
        return !error && data?.userId === resolved.userId && data?.authEmail === resolved.authEmail;
      } },
    );
  } catch { return null; }
  const { error: markError } = await admin.rpc(
    "mark_reception_login_qr_used_v1",
    {
      p_occasion: parsed.occasion,
      p_token_hash: await sha256Hex(parsed.token),
    },
  );
  if (markError) {
    await admin.auth.admin.signOut(session.access_token, "local");
    return null;
  }
  return {
    access_token: session.access_token,
    refresh_token: session.refresh_token,
    expires_at: session.expires_at,
    token_type: session.token_type,
  };
}
