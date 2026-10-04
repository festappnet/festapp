import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.58.0";

import { issueExistingUserSession } from "../_shared/issueExistingUserSession.ts";

export type SignOutTarget = (accessToken: string) => Promise<void>;

export async function cancelRegistration(
  occasion: number,
  user: string,
  userClient: SupabaseClient,
  admin: SupabaseClient,
  anon: SupabaseClient,
  signOutTarget: SignOutTarget,
) {
  const { data: domain, error: domainError } = await userClient.rpc(
    "cancel_reception_registration_v1",
    { p_occasion: occasion, p_user: user },
  );
  if (domainError || domain?.code !== 200) {
    return {
      status: domain?.code ?? 403,
      body: { error: "registration_unavailable" },
    };
  }
  try {
    const { data: target, error: targetError } = await admin.rpc("resolve_existing_user_session_v1", { p_user: user });
    if (targetError || !target?.authEmail) throw new Error("target unavailable");
    await issueExistingUserSession(
      { targetUserId: user, expectedAuthEmail: target.authEmail }, admin, anon,
      { purpose: "revoke", useSession: async (session) => { await signOutTarget(session.access_token); } },
    );
    const { error: markError } = await admin.rpc("mark_reception_auth_revoked_v1", {
      p_occasion: occasion,
      p_user: user,
    });
    if (markError) throw new Error("revocation receipt unavailable");
    return { status: 200, body: { status: "cancelled" } };
  } catch {
    return {
      status: 202,
      body: { status: "domain_blocked_auth_revocation_pending" },
    };
  }
}
