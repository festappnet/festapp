import type { Session, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.58.0";

export class SessionIssuanceError extends Error {
  constructor(code = "auth_temporarily_unavailable") { super(code); }
}
export type ExistingSessionTarget = { targetUserId: string; expectedAuthEmail: string };

/** All application-internal OTP producers share the same database lease.
 * Use dedicated non-persisting Auth clients with bounded fetch timeouts.
 * No proof/action link is ever returned to callers. No implicit signup.
 */
export async function issueExistingUserSession(
  target: ExistingSessionTarget,
  admin: SupabaseClient,
  anon: SupabaseClient,
  options: {
    purpose?: "login" | "revoke";
    validateContext?: () => Promise<boolean>;
    useSession?: (session: Session) => Promise<void>;
  } = {},
): Promise<Session> {
  const owner = crypto.randomUUID();
  const params = { p_user: target.targetUserId, p_owner: owner };
  let session: Session | null = null;
  let acquired = false;
  // On any uncertain remote result quarantine the lease until its TTL. A late
  // generateLink must never overlap an immediately retried application mint.
  let safelyFinished = false;
  const started = Date.now();
  const matches = (row: Record<string, unknown> | null) => row?.userId === target.targetUserId && row?.authEmail === target.expectedAuthEmail;
  try {
    const lease = await admin.rpc("acquire_existing_user_session_lease_v1", params);
    acquired = !lease.error && matches(lease.data);
    if (acquired && lease.data.requiresMfa && options.purpose !== "revoke") { safelyFinished = true; throw new SessionIssuanceError("mfa_required"); }
    if (!acquired || Date.now() - started > 20_000) throw new SessionIssuanceError();
    if (options.validateContext && !await options.validateContext()) {
      safelyFinished = true;
      throw new SessionIssuanceError();
    }
    const link = await admin.auth.admin.generateLink({ type: "recovery", email: target.expectedAuthEmail });
    if (link.error || link.data.user?.id !== target.targetUserId || !link.data.properties?.hashed_token || Date.now() - started > 20_000) throw new SessionIssuanceError();
    const verified = await anon.auth.verifyOtp({ type: "recovery", token_hash: link.data.properties.hashed_token });
    session = verified.data.session;
    if (verified.error || session?.user.id !== target.targetUserId || Date.now() - started > 20_000) throw new SessionIssuanceError();
    const live = await admin.rpc("check_existing_user_session_lease_v1", params);
    if (live.error || !matches(live.data) || Date.now() - started > 20_000 || (options.validateContext && !await options.validateContext())) throw new SessionIssuanceError();
    // Revocation callers hold the lease until their global signout completes.
    if (options.useSession) await options.useSession(session);
    // Including callbacks and revocation HTTP responses in the same deadline
    // prevents a delayed response from returning a mint after lease expiry.
    const finalLease = await admin.rpc("check_existing_user_session_lease_v1", params);
    if (finalLease.error || !matches(finalLease.data) || (finalLease.data.requiresMfa && options.purpose !== "revoke")) throw new SessionIssuanceError();
    if (options.validateContext && !await options.validateContext()) throw new SessionIssuanceError();
    if (Date.now() - started > 20_000) throw new SessionIssuanceError();
    safelyFinished = true;
    return session;
  } catch (error) {
    if (session?.access_token) {
      // Revoke only this mint, never another concurrent session.
      await admin.auth.admin.signOut(session.access_token, "local").catch(() => undefined);
    }
    throw error instanceof SessionIssuanceError ? error : new SessionIssuanceError();
  } finally {
    if (acquired && safelyFinished) await admin.rpc("release_existing_user_session_lease_v1", params);
  }
}
