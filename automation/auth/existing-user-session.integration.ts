/** Isolated, synthetic-only proof. Never reads .env.local or production data.
 * deno run --allow-run=docker,fvm --allow-net --allow-read --allow-write --allow-env automation/auth/existing-user-session.integration.ts
 */
import { encryptedProof } from "../../supabase/functions/_shared/googleAuthProtocol.ts";
import { issueExistingUserSession } from "../../supabase/functions/_shared/issueExistingUserSession.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.58.0";
import { assert, assertEquals, assertRejects } from "https://deno.land/std@0.224.0/assert/mod.ts";

const root = new URL("../../", import.meta.url);
const compose = await Deno.readTextFile(new URL("automation/hetzner-supabase/runtime/docker-compose.festapp.yml", root));
const image = compose.match(/image: (supabase\/gotrue:[^\s]+)/)?.[1];
if (!image?.includes("@sha256:")) throw new Error("Missing immutable runtime Auth image");
const id = `festapp-auth-proof-${crypto.randomUUID().slice(0, 8)}`;
const db = `${id}-db`, auth = `${id}-auth`;
const secret = crypto.randomUUID() + crypto.randomUUID();
const password = crypto.randomUUID();
const report: Record<string, unknown> = { authImage: image, sdk: "supabase-js@2.58.0" };
async function docker(args: string[], input?: string, tolerate = false): Promise<string> {
  const child = new Deno.Command("docker", { args, stdin: input == null ? "null" : "piped", stdout: "piped", stderr: "piped" }).spawn();
  if (input != null) {
    const writer = child.stdin.getWriter();
    await writer.write(new TextEncoder().encode(input));
    await writer.close();
  }
  const out = await child.output();
  // Never include command arguments, SQL or container logs containing credentials.
  if (!out.success && !tolerate) throw new Error(`Docker operation ${args[0]} failed (${out.code}): ${new TextDecoder().decode(out.stderr).replaceAll(password, "[redacted]").replaceAll(secret, "[redacted]")}`);
  return new TextDecoder().decode(out.stdout).trim();
}
const sql = (text: string) => docker(["exec", "-i", "-e", `PGPASSWORD=${password}`, db, "psql", "-U", "supabase_admin", "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-Atq"], text);
function b64(value: Uint8Array) {
  return btoa(String.fromCharCode(...value)).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
}
async function fixtureKey(role: string) {
  const encoder = new TextEncoder();
  const head = b64(encoder.encode(JSON.stringify({ alg: "HS256", typ: "JWT" })));
  const body = b64(encoder.encode(JSON.stringify({ role, iss: "supabase", exp: Math.floor(Date.now() / 1000) + 3600 })));
  const key = await crypto.subtle.importKey("raw", encoder.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  return `${head}.${body}.${b64(new Uint8Array(await crypto.subtle.sign("HMAC", key, encoder.encode(`${head}.${body}`))))}`;
}
try {
  await docker(["network", "create", id]);
  await docker(["run", "-d", "--name", db, "--network", id, "--tmpfs", "/var/lib/postgresql/data", "-e", `POSTGRES_PASSWORD=${password}`, "public.ecr.aws/supabase/postgres:15.8.1.085"]);
  for (let n = 0; n < 60; n++) {
    const ready = await docker(["exec", db, "pg_isready", "-U", "postgres"], undefined, true);
    if (ready.includes("accepting connections")) break;
    await new Promise((r) => setTimeout(r, 500));
  }
  await new Promise((r) => setTimeout(r, 2500));
  await sql(`CREATE SCHEMA IF NOT EXISTS auth; CREATE SCHEMA IF NOT EXISTS extensions;
    CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;
    DO $$ BEGIN IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='supabase_auth_admin') THEN CREATE ROLE supabase_auth_admin LOGIN; END IF; END $$;
    ALTER ROLE supabase_auth_admin WITH PASSWORD '${password}';
    ALTER ROLE supabase_auth_admin SET search_path = auth;
    GRANT ALL ON SCHEMA auth TO supabase_auth_admin;
    CREATE TABLE public.user_info(id uuid PRIMARY KEY, organization bigint, email_readonly text,
      email_delivery text,name text,surname text,sex text,phone text,birth_date date,data jsonb);`);
  await docker(["run", "-d", "--name", auth, "--network", id, "-p", "127.0.0.1::9999",
    "-e", "GOTRUE_API_HOST=0.0.0.0", "-e", "GOTRUE_API_PORT=9999", "-e", "API_EXTERNAL_URL=http://localhost:9999",
    "-e", "GOTRUE_SITE_URL=http://localhost:9999", "-e", "GOTRUE_DB_DRIVER=postgres",
    "-e", `GOTRUE_DB_DATABASE_URL=postgres://supabase_auth_admin:${password}@${db}:5432/postgres?search_path=auth`,
    "-e", `GOTRUE_JWT_SECRET=${secret}`, "-e", "GOTRUE_JWT_ADMIN_ROLES=service_role", "-e", "GOTRUE_JWT_AUD=authenticated",
    "-e", "GOTRUE_DISABLE_SIGNUP=true", "-e", "GOTRUE_MAILER_AUTOCONFIRM=true", "-e", "GOTRUE_RATE_LIMIT_EMAIL_SENT=1000", image]);
  const port = (await docker(["port", auth, "9999/tcp"])).split(":").at(-1);
  const base = `http://127.0.0.1:${port}`;
  let healthy = false;
  for (let n = 0; n < 80; n++) {
    try { const response = await fetch(`${base}/health`); await response.text(); if (response.ok) { healthy = true; break; } } catch { /* starting */ }
    await new Promise((r) => setTimeout(r, 500));
  }
  assert(healthy, "Isolated Auth failed to start");
  await sql(`CREATE OR REPLACE FUNCTION public.require_service_role() RETURNS void LANGUAGE plpgsql AS $$ BEGIN IF current_setting('request.jwt.claim.role',true) IS DISTINCT FROM 'service_role' THEN RAISE EXCEPTION 'not_authorized'; END IF; END $$;`);
  await sql(await Deno.readTextFile(new URL("database/functions/users/existing_user_session.sql", root)));
  await sql(await Deno.readTextFile(new URL("database/functions/users/create_user_in_organization_with_data_pure.sql", root)));
  const customFetch: typeof fetch = (input, init) => {
    const url = typeof input === "string" ? input : input instanceof URL ? input.href : input.url;
    return fetch(url.replace("/auth/v1/", "/"), init);
  };
  const options = { auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false }, global: { fetch: customFetch } };
  const admin = createClient(base, await fixtureKey("service_role"), options);
  const anonKey = await fixtureKey("anon");
  const client = () => createClient(base, anonKey, options);
  const fixture = async (org: number, email: string) => await sql(`SELECT public.create_user_in_organization_with_data_pure(${org},'${email}','proof-password','{}');`);
  const identities = [];
  for (const [org, email] of [[1, "planner@example.com"], [2, "planner@example.com"], [1, "planner+1@example.com"], [1, "1+real@example.com"]] as const) {
    const userId = await fixture(org, email);
    const authEmail = `${org}+${email}`;
    const before = await sql(`SELECT encrypted_password FROM auth.users WHERE id='${userId}';`);
    const link = await admin.auth.admin.generateLink({ type: "recovery", email: authEmail });
    assert(!link.error && link.data.user.id === userId, "Recovery generation identity");
    const verified = await client().auth.verifyOtp({ type: "recovery", token_hash: link.data.properties.hashed_token });
    assert(!verified.error && verified.data.session?.user.id === userId, "Recovery verification identity");
    const session = verified.data.session!;
    if (identities.length === 0) {
      const flutterProof = await new Deno.Command("fvm", { args: ["flutter","test","test/integration/google_session_sdk_test.dart"], cwd: root.pathname, env: {
        FESTAPP_FIXTURE_AUTH_URL: base, FESTAPP_FIXTURE_ANON_KEY: anonKey,
        FESTAPP_FIXTURE_REFRESH_TOKEN: session.refresh_token, FESTAPP_FIXTURE_USER_ID: userId,
      }, stdout: "piped", stderr: "piped" }).output();
      assert(flutterProof.success, "Flutter SDK session proof failed (see isolated test)");
      report.flutterSdk = { sameUuid: true, noPasswordRecoveryEvent: true, refresh: true };
      // Flutter refresh rotates its session. Use a fresh recovery for JS proof.
      const replacement = await admin.auth.admin.generateLink({ type: "recovery", email: authEmail });
      assert(!replacement.error);
      const next = await client().auth.verifyOtp({ type: "recovery", token_hash: replacement.data.properties.hashed_token });
      assert(!next.error && next.data.session);
      Object.assign(session, next.data.session);
    }
    const browser = client();
    const events: string[] = [];
    const { data: listener } = browser.auth.onAuthStateChange((event) => { events.push(event); });
    const installed = await browser.auth.setSession({ access_token: session.access_token, refresh_token: session.refresh_token });
    assert(!installed.error && installed.data.user?.id === userId, "SDK setSession");
    assert(!events.includes("PASSWORD_RECOVERY"), "Internal recovery must not open reset UI");
    const refreshed = await browser.auth.refreshSession();
    assert(!refreshed.error && refreshed.data.user?.id === userId, "SDK refresh");
    const freshRefreshToken = refreshed.data.session!.refresh_token;
    assertEquals(await sql(`SELECT encrypted_password FROM auth.users WHERE id='${userId}';`), before);
    const replay = await client().auth.verifyOtp({ type: "recovery", token_hash: link.data.properties.hashed_token });
    assert(replay.error, "Recovery replay rejected");
    const signedOut = await browser.auth.signOut({ scope: "global" });
    assert(!signedOut.error, "SDK global signout");
    const revoked = await client().auth.refreshSession({ refresh_token: freshRefreshToken });
    assert(revoked.error, "Revoked refresh rejected");
    listener.subscription.unsubscribe();
    const login = await client().auth.signInWithPassword({ email: authEmail, password: "proof-password" });
    assert(!login.error && login.data.user?.id === userId, "Original password preserved");
    identities.push({ org, rawEmail: email, sameUuid: true, setSessionEvents: events, refresh: true, revoke: true, replayRejected: true, passwordPreserved: true });
  }
  report.identities = identities;
  const count = await sql("SELECT count(*) FROM auth.users;");
  const missing = await admin.auth.admin.generateLink({ type: "recovery", email: "1+missing@example.com" });
  assert(missing.error, "Missing recovery rejected");
  assertEquals(await sql("SELECT count(*) FROM auth.users;"), count);
  report.missingRecoveryDoesNotCreate = true;
  const userId = await fixture(1, "deleted@example.com");
  const deletionLink = await admin.auth.admin.generateLink({ type: "recovery", email: "1+deleted@example.com" });
  assert(!deletionLink.error);
  await admin.auth.admin.deleteUser(userId);
  const deleted = await client().auth.verifyOtp({ type: "recovery", token_hash: deletionLink.data.properties.hashed_token });
  assert(deleted.error, "Deletion between generate and verify rejected");
  assertEquals(await sql("SELECT count(*) FROM auth.users;"), count);
  report.deletionDuringMintRejected = true;
  // Real SQL leases across concurrent callers, real SDK calls to pinned GoTrue.
  const sqlAdmin = Object.create(admin) as typeof admin;
  sqlAdmin.rpc = (async (name: string, params: Record<string, string>) => {
    if (!["acquire_existing_user_session_lease_v1", "check_existing_user_session_lease_v1", "release_existing_user_session_lease_v1"].includes(name)) throw new Error("Unexpected proof RPC");
    assert(/^[0-9a-f-]{36}$/.test(params.p_user) && /^[0-9a-f-]{36}$/.test(params.p_owner));
    const result = await sql(`SET request.jwt.claim.role='service_role'; SELECT public.${name}('${params.p_user}','${params.p_owner}');`);
    return { data: result ? JSON.parse(result) : null, error: null };
  }) as typeof admin.rpc;
  const concurrentId = await fixture(1, "concurrent@example.com");
  const target = { targetUserId: concurrentId, expectedAuthEmail: "1+concurrent@example.com" };
  const parallel = await Promise.allSettled([
    issueExistingUserSession(target, sqlAdmin, client()),
    issueExistingUserSession(target, sqlAdmin, client()),
    issueExistingUserSession(target, sqlAdmin, client()),
  ]);
  assertEquals(parallel.filter((r) => r.status === "fulfilled").length, 1);
  report.distributedConcurrentMint = { sessions: 1, retryableRejections: 2 };
  const next = await issueExistingUserSession(target, sqlAdmin, client());
  assertEquals(next.user.id, concurrentId);
  // A lease stolen/expired during mint may not yield a session or release the new owner.
  const replacementOwner = crypto.randomUUID();
  const expiresAdmin = Object.create(sqlAdmin) as typeof admin;
  expiresAdmin.rpc = (async (name: string, params: Record<string, string>) => {
    if (name === "check_existing_user_session_lease_v1") {
      await sql(`UPDATE public.existing_user_session_leases SET owner='${replacementOwner}' WHERE user_id='${concurrentId}';`);
    }
    return await sqlAdmin.rpc(name, params);
  }) as typeof admin.rpc;
  let rejected = false;
  try { await issueExistingUserSession(target, expiresAdmin, client()); } catch { rejected = true; }
  assert(rejected, "Lost lease mint rejected");
  assertEquals(await sql(`SELECT owner FROM public.existing_user_session_leases WHERE user_id='${concurrentId}';`), replacementOwner);
  report.lostLeaseRejectedAndNewOwnerPreserved = true;
  await sql(`DELETE FROM public.existing_user_session_leases WHERE user_id='${concurrentId}';`);
  // Public-domain deletion invalidates the target before Auth deletion.
  const domainId = await fixture(1, "domain-deleted@example.com");
  await sql(`DELETE FROM public.user_info WHERE id='${domainId}';`);
  rejected = false;
  try { await issueExistingUserSession({ targetUserId: domainId, expectedAuthEmail: "1+domain-deleted@example.com" }, sqlAdmin, client()); } catch { rejected = true; }
  assert(rejected);
  report.publicDomainDeletionRejected = true;
  const mismatchId = await fixture(1, "mismatch@example.com");
  await sql(`UPDATE auth.users SET email='1+other@example.com' WHERE id='${mismatchId}';`);
  rejected = false;
  try { await issueExistingUserSession({ targetUserId: mismatchId, expectedAuthEmail: "1+mismatch@example.com" }, sqlAdmin, client()); } catch { rejected = true; }
  assert(rejected);
  report.emailMismatchRejected = true;
  // MFA uses a password proof session and a real GoTrue challenge. Internal
  // recovery is blocked for MFA accounts and cannot manufacture AAL2.
  const mfaId = await fixture(1, "mfa@example.com");
  const mfaClient = client();
  const signedIn = await mfaClient.auth.signInWithPassword({ email: "1+mfa@example.com", password: "proof-password" });
  assert(!signedIn.error);
  const enrolled = await mfaClient.auth.mfa.enroll({ factorType: "totp", friendlyName: "fixture" });
  assert(!enrolled.error && enrolled.data.type === "totp", "TOTP enroll");
  const totp = async (secret: string) => {
    const alphabet="ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"; let bits="";
    for (const c of secret.toUpperCase().replaceAll("=", "")) bits += alphabet.indexOf(c).toString(2).padStart(5,"0");
    const bytes=new Uint8Array(bits.match(/.{8}/g)!.map(b=>parseInt(b,2)));
    const counter=new Uint8Array(8);new DataView(counter.buffer).setBigUint64(0,BigInt(Math.floor(Date.now()/30000)));
    const key=await crypto.subtle.importKey("raw",bytes,{name:"HMAC",hash:"SHA-1"},false,["sign"]);
    const digest=new Uint8Array(await crypto.subtle.sign("HMAC",key,counter));const offset=digest[19]&15;
    return String((new DataView(digest.buffer).getUint32(offset)&0x7fffffff)%1000000).padStart(6,"0");
  };
  const enrolledFactor=enrolled.data!;
  assert(enrolledFactor.type === "totp");
  const challenge=await mfaClient.auth.mfa.challenge({factorId:enrolledFactor.id});assert(!challenge.error);
  const verifiedMfa=await mfaClient.auth.mfa.verify({factorId:enrolledFactor.id,challengeId:challenge.data!.id,code:await totp(enrolledFactor.totp.secret)});assert(!verifiedMfa.error,"MFA verify");
  const assurance=await mfaClient.auth.mfa.getAuthenticatorAssuranceLevel();assertEquals(assurance.data!.currentLevel,"aal2");
  await mfaClient.auth.signOut({scope:"local"});
  await assertRejects(()=>issueExistingUserSession({targetUserId:mfaId,expectedAuthEmail:"1+mfa@example.com"},sqlAdmin,client()),Error,"mfa_required");
  assertEquals(await sql(`SELECT count(*) FROM public.existing_user_session_leases WHERE user_id='${mfaId}';`),"0");
  const passwordProof=client();
  const proofSignIn=await passwordProof.auth.signInWithPassword({email:"1+mfa@example.com",password:"proof-password"});
  assert(!proofSignIn.error && proofSignIn.data.user.id===mfaId && proofSignIn.data.user.factors?.some(f=>f.status==="verified"),"Fresh password exposes required verified factor");
  const freshChallenge=await passwordProof.auth.mfa.challenge({factorId:enrolledFactor.id});assert(!freshChallenge.error);
  const key="bc".repeat(32);
  const cipher=await encryptedProof(JSON.stringify({access_token:proofSignIn.data.session!.access_token,refresh_token:proofSignIn.data.session!.refresh_token}),key);
  const redeemedProof=client();const recovered=JSON.parse(await encryptedProof(cipher,key,true));
  const installedProof=await redeemedProof.auth.setSession(recovered);assert(!installedProof.error && installedProof.data.user?.id===mfaId);
  const correctCode=await totp(enrolledFactor.totp.secret);
  const wrongCode=correctCode.slice(0,5)+((Number(correctCode[5])+1)%10);
  const rejectedMfa=await redeemedProof.auth.mfa.verify({factorId:enrolledFactor.id,challengeId:freshChallenge.data!.id,code:wrongCode});assert(rejectedMfa.error,"Wrong second factor rejected");
  const provedMfa=await redeemedProof.auth.mfa.verify({factorId:enrolledFactor.id,challengeId:freshChallenge.data!.id,code:correctCode});assert(!provedMfa.error && provedMfa.data.user.id===mfaId,"Separate request verifies original MFA challenge after invalid code");
  const finalAssurance=await redeemedProof.auth.mfa.getAuthenticatorAssuranceLevel();assertEquals(finalAssurance.data!.currentLevel,"aal2");
  await redeemedProof.auth.signOut({scope:"local"});
  report.mfa={verifiedTotpAal2:true,internalRecoveryBlocked:true,freshPasswordAndEncryptedCrossRequestProof:true,wrongCodeRejected:true,correctRetrySameChallenge:true};
  report.status = "passed";
  await Deno.writeTextFile(new URL("docs/plans/google-sign-in-reference-2026-10-01/sdk-session-proof.json", root), JSON.stringify(report, null, 2) + "\n");
  console.log("PASS isolated pinned GoTrue: 4 prefixed identities, SDK events, refresh/revoke/replay, deletion, no implicit signup");
} finally {
  await docker(["rm", "-fv", auth, db], undefined, true);
  await docker(["network", "rm", id], undefined, true);
}
