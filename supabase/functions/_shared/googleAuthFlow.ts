import { createClient } from "https://esm.sh/@supabase/supabase-js@2.58.0";
import { base64url, encryptedProof, hash, mailboxHash, randomSecret, requireSecret, validateGoogleToken } from "./googleAuthProtocol.ts";
import { issueExistingUserSession } from "./issueExistingUserSession.ts";
import { deliverEmail } from "./emailDelivery.ts";

const responseHeaders = { "Cache-Control": "no-store", "Referrer-Policy": "no-referrer", "X-Content-Type-Options": "nosniff" };
const publicErrors = new Set(["mfa_required","provider_cancelled","attempt_expired","invalid_provider_proof","account_proof_failed","registration_disabled","identity_already_linked","account_identity_inconsistent","auth_temporarily_unavailable","provider_unavailable","mailbox_proof_required","profile_required","rate_limited"]);
const boundedFetch: typeof fetch = (input, init) => fetch(input, { ...init, signal: AbortSignal.timeout(8000) });
const options = { auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false }, global: { fetch: boundedFetch } };
const makeAdmin = () => createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, options);
const makeAnon = () => createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, options);
type Attempt = { id: string; organization: number; status: string; challenge: string; state_hash: string; nonce_hash: string; browser_hash: string; verifier_encrypted: string; expires_at: string; origin: string; redirectUri: string; target_user: string; issuer: string; subject: string; email: string; proposed_name: string; mailbox_verified: boolean; mailbox_tries: number; intent: string; mfa_user: string; mfa_session_encrypted: string };
function json(body: unknown, origin?: string, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...responseHeaders, "Content-Type": "application/json", ...(origin ? { "Access-Control-Allow-Origin": origin, "Vary": "Origin", "Access-Control-Allow-Headers": "content-type,apikey,x-client-info,authorization", "Access-Control-Allow-Methods": "POST,OPTIONS" } : {}) } });
}
function config() {
  const clientId = Deno.env.get("GOOGLE_OIDC_CLIENT_ID"), clientSecret = Deno.env.get("GOOGLE_OIDC_CLIENT_SECRET");
  const callback = Deno.env.get("GOOGLE_OIDC_CALLBACK_URL"), encryption = Deno.env.get("GOOGLE_AUTH_ENCRYPTION_KEY");
  if (!clientId || !clientSecret || !callback?.startsWith("https://") || !/^[0-9a-f]{64}$/i.test(encryption ?? "") || !/^[0-9a-f]{64}$/i.test(Deno.env.get("GOOGLE_AUTH_MAILBOX_HMAC_KEY") ?? "")) throw new Error("provider_unavailable");
  return { clientId, clientSecret, callback, encryption: encryption! };
}
async function transition(admin: ReturnType<typeof makeAdmin>, op: string, attempt: string, secret: string, payload: Record<string, unknown> = {}): Promise<Attempt> {
  const { data, error } = await admin.rpc("google_auth_transition_v1", { p_operation: op, p_attempt: attempt, p_secret_hash: secret, p_payload: payload });
  if (error || !data) throw new Error(publicErrors.has(error?.message ?? "") ? error!.message : "auth_temporarily_unavailable");
  return data;
}
async function rate(admin: ReturnType<typeof makeAdmin>, key: string, limit = 20) {
  const { data, error } = await admin.rpc("google_auth_rate_limit_v1", { p_key: await hash(key), p_limit: limit });
  if (error || data !== true) throw new Error("rate_limited");
}
function cookieName(id: string) { return `__Host-festapp-google-${id}`; }
function readCookie(req: Request, id: string) { return (req.headers.get("cookie") ?? "").split(";").map((v) => v.trim()).find((v) => v.startsWith(`${cookieName(id)}=`))?.split("=")[1] ?? ""; }
export async function handleGoogleAuth(endpoint: "start" | "callback" | "complete", req: Request): Promise<Response> {
  let allowedOrigin: string | undefined;
  try {
    const cfg = config(), admin = makeAdmin(), url = new URL(req.url);
    if (endpoint === "start" && req.method === "GET") {
      const id = url.searchParams.get("attempt")!;
      if (!/^[0-9a-f-]{36}$/.test(id)) throw new Error("invalid_provider_proof");
      if ((req.headers.get("cookie")?.match(/__Host-festapp-google-/g)?.length ?? 0) >= 5) throw new Error("rate_limited");
      const browser = randomSecret();
      const a = await transition(admin, "bootstrap", id, await hash(requireSecret(url.searchParams.get("bootstrap"))), { browserHash: await hash(browser) });
      const proof = JSON.parse(await encryptedProof(a.verifier_encrypted, cfg.encryption, true));
      const google = new URL("https://accounts.google.com/o/oauth2/v2/auth");
      google.search = new URLSearchParams({ client_id: cfg.clientId, redirect_uri: cfg.callback, response_type: "code", scope: "openid email profile", state: proof.state, nonce: proof.nonce, code_challenge: await hash(proof.verifier), code_challenge_method: "S256", prompt: "select_account" }).toString();
      return new Response(null, { status: 303, headers: { ...responseHeaders, Location: google.href, "Set-Cookie": `${cookieName(id)}=${browser}; Secure; HttpOnly; SameSite=Lax; Path=/; Max-Age=600` } });
    }
    if (endpoint === "callback") {
      if (req.method !== "GET") return json({ error: "invalid_provider_proof" }, undefined, 405);
      const stateHash = await hash(requireSecret(url.searchParams.get("state")));
      const { data: stored, error } = await admin.from("external_login_attempts").select("*").eq("state_hash", stateHash).eq("status", "bootstrapped").single();
      if (error || !stored || new Date(stored.expires_at).getTime() <= Date.now() || stored.browser_hash !== await hash(requireSecret(readCookie(req, stored.id)))) throw new Error("invalid_provider_proof");
      await rate(admin, `callback:${stored.id}`, 5);
      const { data: client } = await admin.from("external_login_clients").select("*").eq("client_id", stored.client_id).eq("enabled", true).single();
      if (!client) throw new Error("provider_unavailable");
      const redirect = new URL(client.redirect_uri);
      if (url.searchParams.has("error")) {
        await admin.from("external_login_attempts").update({ status: "failed", verifier_encrypted: null }).eq("id", stored.id).eq("status", "bootstrapped");
        redirect.searchParams.set("google_error", "provider_cancelled");
      } else {
        const proof = JSON.parse(await encryptedProof(stored.verifier_encrypted, cfg.encryption, true));
        const code = url.searchParams.get("code");
        if (!code || code.length > 4096) throw new Error("invalid_provider_proof");
        const response = await boundedFetch("https://oauth2.googleapis.com/token", { method: "POST", body: new URLSearchParams({ code, client_id: cfg.clientId, client_secret: cfg.clientSecret, redirect_uri: cfg.callback, grant_type: "authorization_code", code_verifier: proof.verifier }) });
        const token = await response.json();
        if (!response.ok || typeof token.id_token !== "string") throw new Error("invalid_provider_proof");
        const claims = await validateGoogleToken(token.id_token, cfg.clientId, stored.nonce_hash);
        const handoff = randomSecret();
        await transition(admin, "provider", stored.id, stateHash, { ...claims, browserHash: stored.browser_hash, handoffHash: await hash(handoff) });
        redirect.searchParams.set("google_code", handoff);
        redirect.searchParams.set("google_attempt", stored.id);
      }
      return new Response(null, { status: 303, headers: { ...responseHeaders, Location: redirect.href, "Set-Cookie": `${cookieName(stored.id)}=; Secure; HttpOnly; SameSite=Lax; Path=/; Max-Age=0` } });
    }
    // Preflight must use the same exact client registry; no wildcard CORS.
    if (req.method === "OPTIONS") {
      const origin = req.headers.get("origin");
      const { data } = await admin.from("external_login_clients").select("client_id").eq("origin", origin).eq("enabled", true).limit(1);
      return data?.length ? json({}, origin!, 200) : json({ error: "provider_unavailable" }, undefined, 403);
    }
    if (req.method !== "POST") return json({ error: "invalid_provider_proof" }, undefined, 405);
    const reader = req.body?.getReader();
    if (!reader) throw new Error("invalid_provider_proof");
    const chunks: Uint8Array[] = []; let size = 0;
    for (;;) {
      const { value, done } = await reader.read(); if (done) break;
      size += value.byteLength;
      if (size > 8192) { await reader.cancel(); throw new Error("invalid_provider_proof"); }
      chunks.push(value);
    }
    const bytes = new Uint8Array(size); let offset = 0;
    for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
    const body = JSON.parse(new TextDecoder().decode(bytes));
    const { data: client } = await admin.from("external_login_clients").select("*").eq("client_id", body.clientId).eq("enabled", true).single();
    if (!client || client.organization !== body.organization || req.headers.get("origin") !== client.origin) throw new Error("provider_unavailable");
    allowedOrigin = client.origin;
    // Global/client/attempt limits also apply when forwarded IP is unavailable.
    // Only a gateway-owned trusted header may be configured as an extra key.
    await rate(admin, `global:${endpoint}`, 100);
    await rate(admin, `${endpoint}:${client.client_id}`, 30);
    const ipHeader = Deno.env.get("GOOGLE_AUTH_TRUSTED_IP_HEADER");
    if (ipHeader) await rate(admin, `${endpoint}:${req.headers.get(ipHeader) ?? "unknown"}`);
    if (endpoint === "start") {
      if (body.operation === "identity_status") {
        const token = req.headers.get("authorization")?.replace(/^Bearer /i, "");
        if (!token) throw new Error("account_proof_failed");
        const { data, error } = await admin.auth.getUser(token);
        if (error || !data.user) throw new Error("account_proof_failed");
        const { data: target } = await admin.rpc("resolve_existing_user_session_v1", { p_user: data.user.id });
        if (!target || target.organization !== client.organization) throw new Error("account_proof_failed");
        const { data: link } = await admin.from("external_login_identities").select("user_id").eq("organization",client.organization).eq("user_id",data.user.id).limit(1);
        return json({ enabled: true, linked: !!link?.length }, allowedOrigin);
      }
      if (body.operation === "capability") return json({ enabled: true }, allowedOrigin);
      const challenge = requireSecret(body.challenge), id = crypto.randomUUID();
      const state = randomSecret(), nonce = randomSecret(), verifier = randomSecret(), bootstrap = randomSecret();
      await transition(admin, "start", id, await hash(bootstrap), { intent: body.intent === 'unlink' ? 'unlink' : 'login', clientId: client.client_id, organization: client.organization, origin: client.origin, challenge, stateHash: await hash(state), nonceHash: await hash(nonce), verifierEncrypted: await encryptedProof(JSON.stringify({ state, nonce, verifier }), cfg.encryption) });
      const start = new URL(cfg.callback.replace(/google-auth-callback$/, "google-auth-start"));
      start.search = new URLSearchParams({ attempt: id, bootstrap }).toString();
      return json({ attempt: id, url: start.href }, allowedOrigin);
    }
    if (!/^[0-9a-f-]{36}$/.test(body.attempt)) throw new Error("invalid_provider_proof");
    await rate(admin, `attempt:${body.attempt}`, 10);
    const challenge = await hash(requireSecret(body.verifier)), continuation = randomSecret();
    const { data: stored } = await admin.from("external_login_attempts").select("*").eq("id", body.attempt).eq("client_id", client.client_id).single();
    if (!stored || new Date(stored.expires_at).getTime() <= Date.now()) throw new Error("attempt_expired");
    if (stored.challenge !== challenge) throw new Error("invalid_provider_proof");
    let a: Attempt;
    let secret = await hash(requireSecret(body.code ?? body.continuation));
    const payload = { challenge, continuationHash: await hash(continuation) };
    if (body.operation === "claim") a = await transition(admin, "claim", stored.id, secret, payload);
    else {
      if (stored.continuation_hash !== secret) throw new Error("invalid_provider_proof");
      if (body.operation === "prove_existing") {
        if (typeof body.email !== "string" || body.email.length > 254 || typeof body.password !== "string" || !body.password || body.password.length > 1024) throw new Error("account_proof_failed");
        await rate(admin, `proof:${client.organization}:${body.email.toLowerCase().trim()}`, 5);
        const { data: target } = await admin.rpc("google_auth_resolve_account_v1", { p_organization: client.organization, p_raw_email: body.email });
        if (!target) throw new Error("account_proof_failed");
        const proofClient = makeAnon();
        const proof = await proofClient.auth.signInWithPassword({ email: target.authEmail, password: body.password });
        if (proof.error || proof.data.user?.id !== target.userId) throw new Error("account_proof_failed");
        const factors = proof.data.user.factors?.filter((f) => f.status === "verified") ?? [];
        if (target.requiresMfa && !factors.length) { await proofClient.auth.signOut({ scope: "local" }); throw new Error("mfa_required"); }
        if (factors.length) {
          const factor = factors.find(f => f.factor_type === "totp") ?? factors.find(f => f.factor_type === "phone");
          if (!factor) { await proofClient.auth.signOut({ scope: "local" }); throw new Error("mfa_required"); }
          const challengeResult = await proofClient.auth.mfa.challenge(factor.factor_type === "phone" ? { factorId: factor.id, channel: "sms" } : { factorId: factor.id });
          if (challengeResult.error || !proof.data.session) { await proofClient.auth.signOut({ scope: "local" }); throw new Error("account_proof_failed"); }
          try {
            a = await transition(admin, "mfa_begin", stored.id, secret, { ...payload, provenUser: target.userId, sessionEncrypted: await encryptedProof(JSON.stringify({ access_token: proof.data.session.access_token, refresh_token: proof.data.session.refresh_token, factorId: factor.id, challengeId: challengeResult.data.id }), cfg.encryption) });
          } catch (error) { await proofClient.auth.signOut({ scope: "local" }); throw error; }
          return json({ status: "needs_mfa", continuation, intent: a.intent }, allowedOrigin);
        }
        await proofClient.auth.signOut({ scope: "local" });
        a = await transition(admin, stored.intent === "unlink" ? "unlink" : "link", stored.id, secret, { ...payload, provenUser: target.userId });
      } else if (body.operation === "mfa_verify") {
        if (stored.status !== "awaiting_mfa" || typeof body.mfaCode !== "string" || !/^\d{6}$/.test(body.mfaCode)) throw new Error("account_proof_failed");
        await rate(admin, `mfa:${stored.id}`, 5);
        const proof = JSON.parse(await encryptedProof(stored.mfa_session_encrypted, cfg.encryption, true));
        const proofClient = makeAnon();
        const installed = await proofClient.auth.setSession({ access_token: proof.access_token, refresh_token: proof.refresh_token });
        if (installed.error || installed.data.user?.id !== stored.mfa_user) throw new Error("account_proof_failed");
        const verified = await proofClient.auth.mfa.verify({ factorId: proof.factorId, challengeId: proof.challengeId, code: body.mfaCode });
        if (verified.error) throw new Error("account_proof_failed");
        const assurance = await proofClient.auth.mfa.getAuthenticatorAssuranceLevel();
        if (assurance.error || assurance.data.currentLevel !== "aal2" || verified.data.user.id !== stored.mfa_user) { await proofClient.auth.signOut({ scope: "local" }); throw new Error("account_proof_failed"); }
        try {
          await transition(admin, "mfa_proven", stored.id, secret, { challenge, provenUser: stored.mfa_user });
          a = await transition(admin, stored.intent === "unlink" ? "unlink" : "link", stored.id, secret, { ...payload, provenUser: stored.mfa_user });
          if (a.status === "consumed") { await proofClient.auth.signOut({ scope: "local" }); return json({ status: "unlinked" }, allowedOrigin); }
          const issuing = await transition(admin, "issue", stored.id, await hash(continuation), { challenge });
          await transition(admin, "finish", issuing.id, await hash(continuation), { challenge });
          return json({ status: "authenticated", session: { access_token: verified.data.access_token, refresh_token: verified.data.refresh_token }, userId: stored.mfa_user, organization: stored.organization }, allowedOrigin);
        } catch (error) { await proofClient.auth.signOut({ scope: "local" }); throw error; }
      } else if (body.operation === "register") {
        const profile = body.profile;
        if (!profile || typeof profile.name !== "string" || typeof profile.surname !== "string") throw new Error("profile_required");
        a = await transition(admin, "register", stored.id, secret, { ...payload, profile: { name: profile.name.trim().slice(0, 100), surname: profile.surname.trim().slice(0, 100) }, consent: body.consent === true, password: randomSecret(), unitTitle: body.unitTitle === "My events" ? "My events" : "Moje akce" });
      } else if (body.operation === "mailbox_send") {
        const codeBytes = crypto.getRandomValues(new Uint32Array(1));
        const code = String(codeBytes[0] % 1_000_000).padStart(6, "0");
        const digest = await mailboxHash(stored.id, code, Deno.env.get("GOOGLE_AUTH_MAILBOX_HMAC_KEY") ?? "");
        a = await transition(admin, "mailbox_send", stored.id, secret, { ...payload, mailboxHash: digest });
        await deliverEmail({ to: a.email, context: { organization: a.organization }, template: { id: null, subject: "FestApp - ověření e-mailu", html: `<p>Ověřovací kód: <strong>${code}</strong></p><p>Kód platí nejvýše 10 minut.</p>` }, substitutions: {} });
        return json({ status: "needs_profile", continuation: body.continuation, email: a.email, name: a.proposed_name, mailboxRequired: true, mailboxSent: true }, allowedOrigin);
      } else if (body.operation === "mailbox_verify") {
        if (typeof body.mailboxCode !== "string" || !/^\d{6}$/.test(body.mailboxCode)) throw new Error("invalid_provider_proof");
        a = await transition(admin, "mailbox_verify", stored.id, secret, { ...payload, mailboxHash: await mailboxHash(stored.id, body.mailboxCode, Deno.env.get("GOOGLE_AUTH_MAILBOX_HMAC_KEY") ?? "") });
      } else throw new Error("invalid_provider_proof");
    }
    if (a.status === "consumed") return json({ status: "unlinked" }, allowedOrigin);
    secret = await hash(continuation);
    if (a.status === "ready") {
      a = await transition(admin, "issue", a.id, secret, { challenge });
      const { data: target } = await admin.rpc("resolve_existing_user_session_v1", { p_user: a.target_user });
      if (!target || target.organization !== a.organization) throw new Error("account_identity_inconsistent");
      const session = await issueExistingUserSession({ targetUserId: a.target_user, expectedAuthEmail: target.authEmail }, admin, makeAnon(), {
        validateContext: async () => {
          const { data } = await admin.from("external_login_identities").select("user_id").eq("organization", a.organization).eq("subject", a.subject).eq("issuer", a.issuer).eq("user_id", a.target_user).single();
          return !!data;
        },
        useSession: async () => { await transition(admin, "finish", a.id, secret, { challenge }); },
      });
      return json({ status: "authenticated", session: { access_token: session.access_token, refresh_token: session.refresh_token }, userId: session.user.id, organization: a.organization }, allowedOrigin);
    }
    return json({ status: a.status === "awaiting_profile" ? "needs_profile" : "needs_account_proof", continuation, email: a.email, name: a.proposed_name, mailboxRequired: !a.mailbox_verified, intent: a.intent, mailboxAttemptsRemaining: 5 - a.mailbox_tries }, allowedOrigin);
  } catch (error) {
    const code = error instanceof Error && publicErrors.has(error.message) ? error.message : "auth_temporarily_unavailable";
    return json({ error: code }, allowedOrigin, code === "rate_limited" ? 429 : 400);
  }
}
