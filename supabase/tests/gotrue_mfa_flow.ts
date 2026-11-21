// Child process of the owned-disposable GoTrue integration test.
// Stdout contains only redacted observations.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.58.0';
import { spawn } from 'node:child_process';
import { createInterface } from 'node:readline';
import { issueExistingUserSession } from '../functions/_shared/issueExistingUserSession.ts';
import { accountAssurance } from '../functions/_shared/accountAssurance.ts';
import { handleGoogleAuth } from '../functions/_shared/googleAuthFlow.ts';
import { hash, randomSecret } from '../functions/_shared/googleAuthProtocol.ts';
import { requireFreshStrongAuthentication, verifiedSessionAssurance } from '../../tools/festapp/src/auth/assurance.mjs';
const env = (name: string) => { const value = Deno.env.get(name); if (!value) throw new Error('Missing isolated test input'); return value; };
const base = env('FESTAPP_LOCAL_AUTH_URL'), anonKey = env('FESTAPP_LOCAL_AUTH_ANON'), serviceKey = env('FESTAPP_LOCAL_AUTH_SERVICE');
const organization = Number(env('FESTAPP_LOCAL_AUTH_ORGANIZATION'));
const client = (key: string) => createClient(base, key, {auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false}});
const admin = client(serviceKey), browser = client(anonKey), delegated = client(anonKey);
function ensure(value: unknown, message: string): asserts value { if (!value) throw new Error(message); }
async function sql(statement: string) {
    const command = new Deno.Command('psql',{args:[env('FESTAPP_MCP_TEST_DATABASE_URL'),'-X','-qAt','-v','ON_ERROR_STOP=1'],stdin:'piped',stdout:'piped',stderr:'piped'}).spawn();
    const writer = command.stdin.getWriter();await writer.write(new TextEncoder().encode(statement));await writer.close();
    const output = await command.output();ensure(output.success,'Owned SQL request failed');return new TextDecoder().decode(output.stdout).trim();
}
function decodeClaimSet(jwt: string) {
    const encoded = jwt.split('.')[1].replaceAll('-', '+').replaceAll('_', '/');
    return atob(encoded);
}
async function decision(jwt: string, security = false, tenant = organization) {
    const response = await fetch(`${base}/rest/v1/rpc/get_account_assurance_v1`, {
        method: 'POST',
        headers: { apikey: anonKey, authorization: `Bearer ${jwt}`, 'content-type': 'application/json' },
        body: JSON.stringify({ p_organization: tenant, p_account_security: security }),
    });
    ensure(response.ok, `Account assurance RPC failed with HTTP ${response.status}`);
    return await response.json();
}
type RestRequest = { method?: string; body?: unknown; schema?: string };
async function rest(path: string, jwt: string, { method = 'GET', body, schema = 'public' }: RestRequest = {}) {
    return await fetch(`${base}/rest/v1/${path}`, {
        method,
        headers: {
            apikey: anonKey, authorization: `Bearer ${jwt}`, 'content-type': 'application/json',
            'accept-profile': schema, 'content-profile': schema,
        },
        ...(body === undefined ? {} : { body: JSON.stringify(body) }),
    });
}
const appContextRequest = {
    method: 'POST',
    body: { data_in: { organization, platform: { platform: 'web' } } },
};
async function context(jwt: string) {
    const result = await rest('rpc/get_app_config_v218', jwt, appContextRequest);
    ensure(result.ok, `App context failed with HTTP ${result.status}`);
    return await result.json();
}
async function expectDenied(response: Response, reason: string) {
    ensure(response.status === 403 && (await response.json()).message === reason,
        `Expected the request boundary to deny with ${reason}, got HTTP ${response.status}`);
}
const email = `${organization}+mfa-${crypto.randomUUID()}@example.invalid`, password=crypto.randomUUID()+crypto.randomUUID();
const created = await admin.auth.admin.createUser({email,password,email_confirm:true});ensure(!created.error&&created.data.user,'Owned Auth user creation failed');
const userId=created.data.user.id;ensure(/^[a-f0-9-]{36}$/.test(userId)&&Number.isSafeInteger(organization),'Invalid fixture binding');
await sql(`INSERT INTO public.user_info(id,organization,email_readonly) VALUES('${userId}'::uuid,${organization},'${email.split('+').slice(1).join('+')}');`);
const login=await browser.auth.signInWithPassword({email,password});ensure(!login.error&&login.data.session,'Password login failed');
const factor=await browser.auth.mfa.enroll({factorType:'totp'});ensure(!factor.error&&factor.data,'TOTP enrollment failed');
const enrolledFactorId = factor.data.id;
ensure(/^[a-f0-9-]{36}$/.test(enrolledFactorId), 'Invalid factor identity');
ensure(await sql(`SELECT status FROM auth.mfa_factors WHERE id = '${enrolledFactorId}'`) === 'unverified',
    'Enrollment must start unverified');
ensure(await decision(login.data.session.access_token, true) === 'allowed',
    'A fresh password and unverified factor must leave setup available');
ensure(await decision(login.data.session.access_token, false, organization + 1) === 'invalid_session',
    'The session must belong to the requested account tenant');
const publicContext = await context(anonKey);
ensure(publicContext.code === 200 && !publicContext.user_info?.id,
    'The public context must still load anonymously');
const passwordContext = await context(login.data.session.access_token);
ensure(passwordContext.code === 200 && passwordContext.user_info?.id === userId,
    'The normal authenticated context must load without a verified factor');
function decodeBase32(input:string) { let bits='';for(const char of input.replace(/=+$/,''))bits+='ABCDEFGHIJKLMNOPQRSTUVWXYZ234567'.indexOf(char.toUpperCase()).toString(2).padStart(5,'0');return Uint8Array.from(bits.match(/.{8}/g)??[],part=>parseInt(part,2)); }
async function codeFor(secret: string) {
    const key=await crypto.subtle.importKey('raw',decodeBase32(secret),{name:'HMAC',hash:'SHA-1'},false,['sign']);
    const counter=new Uint8Array(8);new DataView(counter.buffer).setBigUint64(0,BigInt(Math.floor(Date.now()/30000)));
    const mac=new Uint8Array(await crypto.subtle.sign('HMAC',key,counter)),offset=mac.at(-1)!&15;
    return String((new DataView(mac.buffer).getUint32(offset)&0x7fffffff)%1000000).padStart(6,'0');
}
const code = () => codeFor(factor.data!.totp.secret);
const browserChallenge=await browser.auth.mfa.challenge({factorId:factor.data.id});ensure(!browserChallenge.error&&browserChallenge.data,'Browser MFA challenge failed');
const verified=await browser.auth.mfa.verify({factorId:factor.data.id,challengeId:browserChallenge.data.id,code:await code()});ensure(!verified.error,'Browser MFA verification failed');
const original=(await browser.auth.getSession()).data.session;ensure(original,'Original browser session missing');
const previousJwt = login.data.session.access_token;
const userRequest = (jwt: string) => createClient(base, anonKey, {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
    global: { headers: { authorization: `Bearer ${jwt}` } },
});
ensure(await accountAssurance(userRequest(previousJwt)) === 'mfa_required',
    'Edge user authorization must use the same live assurance decision');
const ownProfile = `user_info?select=id&id=eq.${userId}`;
await expectDenied(await rest(ownProfile, previousJwt), 'mfa_required');
await expectDenied(await rest('rpc/get_app_config_v218', previousJwt, appContextRequest), 'mfa_required');
await expectDenied(await rest(`user_info?id=eq.${userId}`, previousJwt, {
    method: 'PATCH', body: { name: 'Blocked write fixture' },
}), 'mfa_required');
await expectDenied(await rest('rpc/graphql', previousJwt, {
    method: 'POST', schema: 'graphql_public', body: { query: '{ __typename }' },
}), 'mfa_required');
ensure(!await sql(`SELECT name FROM public.user_info WHERE id = '${userId}' AND name = 'Blocked write fixture';`),
    'The refused private mutation must not change the profile');
const upgradedContext = await context(original.access_token);
ensure(upgradedContext.code === 200 && upgradedContext.user_info?.id === userId,
    'The user should regain their actual context after verifying TOTP');
ensure(await accountAssurance(userRequest(original.access_token)) === 'allowed' &&
    await accountAssurance(admin) === 'assurance_unavailable',
    'Edge user authorization accepts the verified caller token and refuses a service token');
let refused=false;try{await issueExistingUserSession({targetUserId:userId,expectedAuthEmail:email},admin,client(anonKey));}catch(error){refused=error instanceof Error&&error.message==='mfa_required';}
ensure(refused,'Ordinary mint must never bypass MFA');
// The pinned production GoTrue rejects a verified challenge. A distinct real
// challenge verifies the current OTP without waiting for another 30s window.
const issued=await issueExistingUserSession({targetUserId:userId,expectedAuthEmail:email},admin,delegated,{
    purpose:'delegation',completeMfa:async session=>{
        ensure(session.access_token!==original.access_token,'Browser access must not be adopted');
        const replay=await delegated.auth.mfa.verify({factorId:factor.data!.id,challengeId:browserChallenge.data!.id,code:await code()});
        ensure(replay.error?.code==='mfa_ip_address_mismatch','A verified browser MFA challenge must not be replayed');
        const challenge=await delegated.auth.mfa.challenge({factorId:factor.data!.id});ensure(!challenge.error&&challenge.data,'Independent MFA challenge failed');
        ensure(challenge.data.id!==browserChallenge.data!.id,'Independent MFA must use its own challenge');
        const result=await delegated.auth.mfa.verify({factorId:factor.data!.id,challengeId:challenge.data.id,code:await code()});ensure(!result.error,'Independent MFA verification failed');
        const upgraded=(await delegated.auth.getSession()).data.session;ensure(upgraded,'Independent session missing');return upgraded;
    },
});
const identity=await admin.auth.getUser(issued.access_token);ensure(!identity.error&&identity.data.user?.id===userId,'GoTrue did not verify the issued actor');
ensure((await delegated.auth.mfa.getAuthenticatorAssuranceLevel()).data?.currentLevel==='aal2','Independent session did not reach AAL2');
ensure((await browser.auth.getSession()).data.session?.refresh_token===original.refresh_token,'Browser refresh credential changed');
const refreshed=await delegated.auth.refreshSession();ensure(!refreshed.error&&refreshed.data.session,'Independent refresh failed');
const current=await admin.auth.getUser(refreshed.data.session.access_token);ensure(!current.error&&current.data.user?.id===userId,'GoTrue did not verify refresh actor');

type Claims = { sub: string; aal: string; session_id: string; amr: {method: string; timestamp: number}[] };
function claims(jwt: string): Claims {
    return JSON.parse(decodeClaimSet(jwt));
}
const issuedClaims = claims(issued.access_token);
const refreshedClaims = claims(refreshed.data.session.access_token);
ensure(issuedClaims.session_id !== claims(original.access_token).session_id,
    'Independent mint must have its own session identity');
const assurance = verifiedSessionAssurance(refreshed.data.session.access_token, current.data.user, base);
ensure(assurance, 'Real verified GoTrue session must supply strong assurance');
requireFreshStrongAuthentication(assurance, current.data.user.id);
ensure(issuedClaims.amr.find(entry => entry.method === 'totp')?.timestamp ===
    refreshedClaims.amr.find(entry => entry.method === 'totp')?.timestamp,
    'Refresh must retain the MFA authentication time');
const now = Date.now;
let staleRejected = false;
try {
    Date.now = () => now() + 301000;
    requireFreshStrongAuthentication(assurance, current.data.user.id);
} catch (error) {
    staleRejected = error instanceof Error && error.message === 'INSUFFICIENT_USER_AUTHENTICATION';
} finally {
    Date.now = now;
}
ensure(staleRejected, 'Refresh must not allow an expired step-up');

async function facts(jwt: string) {
    const { aal, session_id: sessionId, sub: subject, amr } = claims(jwt);
    ensure([sessionId, subject].every(id => /^[a-f0-9-]{36}$/.test(id)), 'Invalid session identity');
    const live = await sql(`
        SELECT json_build_object('aal', s.aal,
            'verifiedFactor', EXISTS (
                SELECT FROM auth.mfa_factors f
                WHERE f.id = s.factor_id AND f.user_id = s.user_id AND f.status = 'verified'
            ),
            'methods', ARRAY(
                SELECT authentication_method FROM auth.mfa_amr_claims
                WHERE session_id = s.id ORDER BY authentication_method
            ))
        FROM auth.sessions s WHERE s.id = '${sessionId}' AND s.user_id = '${subject}';
    `);
    return {
        aal,
        methods: amr.map(entry => entry.method).sort(),
        live: live ? JSON.parse(live) : null,
    };
}
async function direct(path: string, { method = 'POST', jwt = anonKey, body = {} } = {}) {
    return await fetch(`${base}/auth/v1/${path}`, {
        method,
        headers: { apikey: anonKey, authorization: `Bearer ${jwt}`, 'content-type': 'application/json' },
        ...(method === 'GET' || method === 'DELETE' ? {} : { body: JSON.stringify(body) }),
    });
}

const passwordClaims = claims(login.data.session.access_token);
ensure(passwordClaims.aal === 'aal1' && passwordClaims.amr.some(entry => entry.method === 'password'),
    'Password must supply a password AAL1 claim');
const oldPassword = await facts(login.data.session.access_token);
ensure(oldPassword.live?.aal === 'aal2', 'Factor verification must upgrade the same live session');
ensure(await decision(login.data.session.access_token) === 'mfa_required',
    'The old password token must still require MFA after upgrading the live session');
const totp = await facts(original.access_token);
ensure(totp.aal === 'aal2' && totp.live?.verifiedFactor && totp.live.methods.includes('totp'),
    'TOTP must bind the AAL2 session to its verified factor and live method');
ensure(await decision(original.access_token, true) === 'allowed',
    'A live TOTP session with password primary proof must qualify for account security');
ensure(await decision(refreshed.data.session.access_token) === 'allowed' &&
    await decision(refreshed.data.session.access_token, true) === 'proof_required',
    'An OTP-based delegated session must require separate proof for account security');

async function verifyEmail(type: 'magiclink' | 'recovery') {
    const link = await admin.auth.admin.generateLink({ type, email });
    ensure(!link.error && link.data.properties.email_otp, 'Unable to issue a local email test code');
    const result = await client(anonKey).auth.verifyOtp({
        type: type === 'magiclink' ? 'email' : type, email, token: link.data.properties.email_otp,
    });
    ensure(!result.error && result.data.session, 'Unable to verify the local email test code');
    const verification = await facts(result.data.session.access_token);
    ensure(verification.aal === 'aal1' && verification.methods.includes('otp'),
        'Email codes must issue AAL1 with an OTP method');
    return { session: result.data.session, verification };
}
const emailCode = await verifyEmail('magiclink');
const passwordReset = await verifyEmail('recovery');
ensure(await decision(emailCode.session.access_token) === 'mfa_required' &&
    await decision(passwordReset.session.access_token) === 'mfa_required',
    'Email code and reset sessions must both require the verified second factor');

const passkeyOptions = await direct('passkeys/authentication/options');
ensure(passkeyOptions.ok, 'Passkey authentication options unavailable');
const passkeyUserVerification = (await passkeyOptions.json()).options?.userVerification;
ensure(passkeyUserVerification === 'preferred', 'Requalify the passkey user verification policy');

type Ceremony = (
    operation: 'create' | 'get' | 'client_sign_in', options: unknown, verified?: boolean,
) => Promise<any>;

async function withCeremonyBrowser<T>(origin: string, run: (ceremony: Ceremony) => Promise<T>): Promise<T> {
    const driver = spawn('node', ['tools/festapp/test/webauthn-browser-helper.mjs', origin], {
        stdio: ['pipe', 'pipe', 'inherit'],
        env: { PATH: env('PATH'), HOME: env('HOME') },
    });
    const stopped = new Promise(resolve => driver.once('close', resolve));
    const replies = createInterface({ input: driver.stdout })[Symbol.asyncIterator]();
    let sequence = 0;
    async function reply() {
        const item = await replies.next();
        ensure(!item.done, 'Chromium ceremony driver exited early');
        return JSON.parse(item.value);
    }
    async function ceremony(operation: 'create' | 'get' | 'client_sign_in', options: unknown, verified = true) {
        const id = ++sequence;
        driver.stdin.write(JSON.stringify({ id, operation, options, verified }) + '\n');
        const result = await reply();
        ensure(result.id === id && result.credential,
            `Chromium ${operation} ceremony failed: ${String(result.error ?? 'no response').split('\n')[0]}`);
        return result.credential;
    }
    try {
        ensure((await reply()).ready, 'Chromium ceremony driver did not initialize');
        return await run(ceremony);
    } finally {
        driver.stdin.end();
        await stopped;
    }
}

async function requireJson(response: Response, step: string) {
    ensure(response.ok, `${step} failed with HTTP ${response.status}`);
    return await response.json();
}

async function expectUserVerificationRequired(response: Response) {
    ensure(response.status === 403 &&
        (await response.json()).code === 'webauthn_user_verification_required',
        'The Auth ingress must reject a ceremony without user verification');
}

async function qualifyWebAuthn(jwt: string) {
    return await withCeremonyBrowser(base, async (ceremony) => {
    async function verifyWebAuthn(jwt: string, factorId: string, type: 'create' | 'request') {
        const challenge = await requireJson(await direct(`factors/${factorId}/challenge`, { jwt }), 'WebAuthn challenge');
        ensure(challenge.webauthn?.type === type, 'Wrong WebAuthn challenge type');
        const options = challenge.webauthn.credential_options.publicKey;
        const operation = type === 'create' ? 'create' : 'get';
        const finish = (assertion: unknown) => direct(`factors/${factorId}/verify`, {
            jwt,
            body: {
                challenge_id: challenge.id,
                webauthn: { type, credential_response: assertion },
            },
        });
        await expectUserVerificationRequired(await finish(await ceremony(operation, options, false)));
        if (type === 'request') {
            ensure((await facts(jwt)).live?.aal === 'aal1', 'Rejected WebAuthn MFA must leave the session at AAL1');
        } else {
            ensure(/^[a-f0-9-]{36}$/.test(factorId) &&
                await sql(`SELECT status FROM auth.mfa_factors WHERE id = '${factorId}'`) === 'unverified',
                'Rejected WebAuthn registration must leave the factor unverified');
        }
        const assertion = await ceremony(operation, options);
        const session = await requireJson(await finish(assertion), 'WebAuthn factor verification');
        return { session, credentialId: assertion.id };
    }
        const registration = await requireJson(await direct('passkeys/registration/options', { jwt }), 'Passkey options');
        const passkeyCredential = await ceremony('create', registration.options);
        await requireJson(await direct('passkeys/registration/verify', {
            jwt, body: { challenge_id: registration.challenge_id, credential: passkeyCredential },
        }), 'Passkey registration');

        const enrolled = await requireJson(await direct('factors', {
            jwt, body: { factor_type: 'webauthn', friendly_name: 'Virtual authenticator' },
        }), 'WebAuthn factor enrollment');
        const enrollment = await verifyWebAuthn(jwt, enrolled.id, 'create');
        const enrollmentFacts = await facts(enrollment.session.access_token);

        const options = await requireJson(await direct('passkeys/authentication/options'), 'Passkey authentication options');
        const finish = (assertion: unknown) => direct('passkeys/authentication/verify', {
            body: { challenge_id: options.challenge_id, credential: assertion },
        });
        const activeSessions = () => sql(`SELECT count(*) FROM auth.sessions WHERE user_id = '${userId}';`);
        const sessionsBefore = await activeSessions();
        // A device without UV needs a selected credential for this browser
        // ceremony. GoTrue's positive passkey path still uses discovery.
        await expectUserVerificationRequired(await finish(await ceremony('get', {
            ...options.options,
            allowCredentials: [{ id: passkeyCredential.id, type: 'public-key', transports: ['internal'] }],
        }, false)));
        ensure(await activeSessions() === sessionsBefore, 'Rejected passwordless passkey must not issue a session');
        const passkeyAssertion = await ceremony('get', options.options);
        const passkeyLogin = await requireJson(await finish(passkeyAssertion), 'Passkey authentication');
        const firstFactor = await facts(passkeyLogin.access_token);
        ensure(firstFactor.aal === 'aal1' && firstFactor.methods.length === 1 && firstFactor.methods[0] === 'passkey',
            'Passwordless passkey must supply only the first factor');
        const stepUp = await verifyWebAuthn(passkeyLogin.access_token, enrolled.id, 'request');
        const secondFactor = await facts(stepUp.session.access_token);
        ensure(enrollmentFacts.methods.includes('mfa/webauthn') &&
            secondFactor.aal === 'aal2' && secondFactor.live?.verifiedFactor &&
            secondFactor.methods.includes('passkey') && secondFactor.methods.includes('mfa/webauthn'),
            'WebAuthn MFA must add a separate verified factor and method to the passkey session');
        ensure(await decision(stepUp.session.access_token, true) === 'proof_required',
            'A successful provider-only passkey login and MFA do not establish the brokered primary purpose');
        ensure(passkeyAssertion.id === passkeyCredential.id && stepUp.credentialId === enrollment.credentialId &&
            stepUp.credentialId !== passkeyAssertion.id, 'Passkey and WebAuthn MFA must use distinct credentials');
        const registrationOptions = await requireJson(await direct('passkeys/registration/options', {
            jwt: stepUp.session.access_token,
        }), 'Second passkey options');
        const activePasskeys = () => sql(`SELECT count(*) FROM auth.webauthn_credentials WHERE user_id = '${userId}';`);
        const passkeysBefore = await activePasskeys();
        await expectUserVerificationRequired(await direct('passkeys/registration/verify', {
            jwt: stepUp.session.access_token, body: {
                challenge_id: registrationOptions.challenge_id,
                credential: await ceremony('create', registrationOptions.options, false),
            },
        }));
        ensure(await activePasskeys() === passkeysBefore, 'Rejected passwordless passkey must not register a credential');
        return { enrollment: enrollmentFacts, firstFactor, secondFactor, ingressRequiresUserVerification: true };
    });
}

const recoveryEnrollment = await direct('factors/recovery-codes', { jwt: original.access_token });
ensure(recoveryEnrollment.ok, 'Could not generate local recovery codes');
const { codes } = await recoveryEnrollment.json();
ensure(typeof codes?.[0] === 'string', 'GoTrue supplied no recovery codes');
const recoveryVerification = await direct('factors/recovery-codes/verify', {
    jwt: passwordReset.session.access_token, body: { code: codes[0] },
});
ensure(recoveryVerification.ok, 'Could not redeem local recovery code');
const { access_token: recoveryJwt } = await recoveryVerification.json();
const recoveryCode = await facts(recoveryJwt);
ensure(recoveryCode.aal === 'aal2' && recoveryCode.methods.includes('mfa/recovery_code'),
    'Recovery code must be identified by its distinct AAL2 method');
ensure(await decision(recoveryJwt) === 'mfa_required',
    'A recovery code alone must not authorize private access');

await sql(`INSERT INTO public.account_mfa_recovery_holds (user_id) VALUES ('${userId}');`);
ensure(await decision(original.access_token) === 'account_recovery',
    'A recovery hold must take effect before removing factors');
const deleted = await direct(`factors/${enrolledFactorId}`, { method: 'DELETE', jwt: original.access_token });
ensure(deleted.ok, 'Could not remove the local TOTP factor');
const afterRemoval = await facts(original.access_token);
ensure(afterRemoval.aal === 'aal2' && afterRemoval.live?.aal === 'aal1' &&
    !afterRemoval.live.verifiedFactor && !afterRemoval.live.methods.includes('totp'),
    'Factor removal must change the live session while the issued JWT retains AAL2');
const recoveryLogin = await client(anonKey).auth.signInWithPassword({ email, password });
ensure(!recoveryLogin.error && recoveryLogin.data.session, 'Password login in interrupted recovery failed');
ensure(await decision(recoveryLogin.data.session.access_token) === 'account_recovery',
    'The recovery hold must survive removal of the last everyday factor and a new login');
await expectDenied(await rest(ownProfile, recoveryLogin.data.session.access_token), 'account_recovery');
const issuer = await admin.rpc('resolve_existing_user_session_v1', { p_user: userId });
ensure(!issuer.error && issuer.data === null, 'The internal session issuer must deny an account under recovery');
await sql(`DELETE FROM public.account_mfa_recovery_holds WHERE user_id = '${userId}';`);
ensure(await decision(original.access_token) === 'invalid_session',
    'A stale AAL2 token must not authorize private access after removal of the last everyday factor');

const webauthn = env('FESTAPP_MFA_BROWSER_PROOF') === '1' ? await qualifyWebAuthn(recoveryJwt) : undefined;
const loggedOut = await direct('logout?scope=global', { jwt: recoveryJwt });
ensure(loggedOut.ok, 'Could not revoke disposable sessions');
const afterRevocation = await facts(original.access_token);
ensure(afterRevocation.live === null, 'Revocation must remove the live session');
ensure(await decision(recoveryLogin.data.session.access_token) === 'invalid_session',
    'A revoked AAL1 token must never enter the no-factor branch');
await expectDenied(await rest(ownProfile, recoveryLogin.data.session.access_token), 'invalid_session');

async function qualifySupportRecovery(ceremony?: Ceremony) {
    const method = ceremony ? 'webauthn' : 'totp';
    const targetEmail = `${organization}+recovery-${crypto.randomUUID()}@example.invalid`;
    const reviewerEmail = `reviewer-${crypto.randomUUID()}@example.invalid`;
    const targetPassword = crypto.randomUUID() + crypto.randomUUID();
    const target = await admin.auth.admin.createUser({
        email: targetEmail, password: targetPassword, email_confirm: true,
    });
    const reviewer = await admin.auth.admin.createUser({ email: reviewerEmail, email_confirm: true });
    ensure(!target.error && !reviewer.error && target.data.user && reviewer.data.user, 'Recovery fixture creation failed');
    const targetId = target.data.user.id, reviewerId = reviewer.data.user.id;
    ensure([targetId, reviewerId].every(id => /^[a-f0-9-]{36}$/.test(id)), 'Invalid recovery fixture identity');
    const originalContact = targetEmail.split('+')[1];
    const caseId = crypto.randomUUID(), evidence = crypto.randomUUID(), otherEvidence = crypto.randomUUID();
    await sql(`
        INSERT INTO public.user_info (id, organization, email_readonly) VALUES ('${targetId}', ${organization}, '${originalContact}');
        INSERT INTO public.organization_users (organization, "user", is_admin) VALUES (${organization}, '${targetId}', true);
    `);
    const targetAuth = client(anonKey);
    const targetSession = await targetAuth.auth.signInWithPassword({ email: targetEmail, password: targetPassword });
    ensure(!targetSession.error && targetSession.data.session, 'Recovery subject session creation failed');
    const oldFactor = await targetAuth.auth.mfa.enroll({ factorType: 'totp', friendlyName: 'Lost device' });
    ensure(!oldFactor.error && oldFactor.data, 'Old recovery factor fixture not enrolled');
    const verifiedTarget = await targetAuth.auth.mfa.challengeAndVerify({
        factorId: oldFactor.data.id, code: await codeFor(oldFactor.data.totp.secret),
    });
    ensure(!verifiedTarget.error && verifiedTarget.data, 'Old recovery factor fixture not verified');
    const jwt = verifiedTarget.data.access_token;
    ensure(await decision(jwt) === 'allowed', 'Recovery subject starts with normal private access');
    await sql(`INSERT INTO public.occasion_users (occasion, "user", is_editor)
      SELECT id, '${targetId}', true FROM public.occasions WHERE organization = ${organization} LIMIT 1;`);
    const fileKey = 'private/disposable-recovery.txt';
    const issueFile = async () => rest('rpc/issue_account_private_image_grant_v1', jwt, {
        method: 'POST', body: { p_project: 'default', p_object_key: fileKey, p_expires_in: 3600 },
    });
    const fileGrant = await requireJson(await issueFile(), 'Session-bound private image grant');
    ensure(fileGrant?.code, 'An authorized editor must be able to share a private file');
    async function redeemFile(key = fileKey) {
        const response = await rest('rpc/redeem_account_private_image_grant_v1', anonKey, {
            method: 'POST', body: { p_project: 'default', p_object_key: key, p_code: fileGrant.code },
        });
        return await requireJson(response, 'Private file grant redemption');
    }
    ensure(await redeemFile() === true && await redeemFile('private/another-file.txt') === false,
        'The grant must authorize only the selected private file');
    await sql(`UPDATE public.occasion_users SET is_editor = false WHERE "user" = '${targetId}'`);
    ensure(await redeemFile() === false, 'A private file grant must honor live project rights');
    await sql(`UPDATE public.occasion_users SET is_editor = true WHERE "user" = '${targetId}'`);
    const ownerOnly = await admin.rpc('begin_account_mfa_recovery_v1', {
        p_user: targetId, p_organization: organization, p_case: caseId,
    });
    ensure(ownerOnly.error, 'The general service role cannot open a support case');
    const open = () => sql(`SELECT public.begin_account_mfa_recovery_v1('${targetId}', ${organization}, '${caseId}');`);
    const notice = await open();
    ensure(notice === await open() && /^[a-f0-9-]{36}$/.test(notice), 'A resumed case must keep one notification');
    ensure(await sql(`SELECT count(*) FROM public.email_messages WHERE message_id = '${notice}'
        AND code = 'ACCOUNT_MFA_RECOVERY_STARTED' AND recipient = '${originalContact}'
        AND tracking_policy = 'disabled'`) === '1', 'Recovery must notify the original contact without tracking');
    ensure(await decision(jwt) === 'account_recovery', 'The durable hold must precede session revocation');
    ensure(await redeemFile() === false, 'Recovery must close already issued private file grants');
    await expectDenied(await issueFile(), 'account_recovery');
    const approve = (actor: string, proof: string) =>
        sql(`SELECT public.approve_account_mfa_recovery_v1('${caseId}', '${actor}', '${proof}');`);
    const revoke = () => sql(`SELECT public.revoke_account_mfa_recovery_sessions_v1('${caseId}');`);
    ensure(await approve(targetId, evidence) === 'f', 'The subject cannot approve their own recovery');
    ensure(await approve(userId, evidence) === 't', 'First verified support approval must be recorded');
    ensure(await approve(userId, otherEvidence) === 'f' && await approve(reviewerId, evidence) === 'f',
        'Duplicate reviewer or copied evidence cannot satisfy the second approval');
    ensure(await revoke() === 'f' && (await facts(jwt)).live !== null,
        'A single approval cannot revoke an administrator session');
    const actorGrant = crypto.randomUUID(), linkGrant = crypto.randomUUID();
    await sql(`INSERT INTO public.scanner_sessions (id, occasion_id, actor_user_id, access_origin,
        token_hash, epoch, device_name, expires_at, offline_until)
      SELECT grants.id, oc.id, grants.actor, grants.origin, 'fixture', 1, 'Fixture', now()+interval '1 hour', now()+interval '1 hour'
      FROM (SELECT id FROM public.occasions WHERE organization = ${organization} LIMIT 1) oc
      CROSS JOIN (VALUES ('${actorGrant}'::uuid, '${targetId}'::uuid, 'authenticated'),
        ('${linkGrant}'::uuid, NULL::uuid, 'scan_link')) grants(id, actor, origin);`);
    ensure(await approve(reviewerId, otherEvidence) === 't', 'A distinct reviewer and evidence must complete approval');
    ensure(await revoke() === 't' && (await facts(jwt)).live === null, 'Approved recovery revokes live sessions');
    ensure(await sql(`SELECT (revoked_at IS NOT NULL) FROM public.scanner_sessions WHERE id = '${actorGrant}'`) === 't' &&
        await sql(`SELECT (revoked_at IS NULL) FROM public.scanner_sessions WHERE id = '${linkGrant}'`) === 't',
        'Recovery must revoke derived actor grants and preserve independent scan-link grants');
    const reopened = await client(anonKey).auth.signInWithPassword({ email: targetEmail, password: targetPassword });
    ensure(!reopened.error && reopened.data.session &&
        await decision(reopened.data.session.access_token) === 'account_recovery',
        'Fresh sign-in must remain blocked while an interrupted recovery is held');
    if (ceremony) {
        const checkoutLink = 'mfa-guest-' + crypto.randomUUID();
        await sql(`WITH fixture AS (
          INSERT INTO public.forms (occasion, link, data, is_open)
          SELECT id, '${checkoutLink}', '{}', true FROM public.occasions WHERE organization = ${organization} LIMIT 1
          RETURNING id, link
        ) INSERT INTO public.form_link_reservations (slug, form) SELECT link, id FROM fixture;`);
        const orderToken = Array.from(crypto.getRandomValues(new Uint8Array(32)), byte => byte.toString(16).padStart(2, '0')).join('');
        const orderId = Number(await sql(`WITH fixture AS (
          SELECT id, occasion FROM public.forms WHERE link = '${checkoutLink}'
        ), payment AS (
          INSERT INTO eshop.payment_info (amount, paid, currency_code) VALUES (100, 100, 'CZK') RETURNING id
        ), paid_order AS (
          INSERT INTO eshop.orders (occasion, form, order_symbol, order_sequence, state, price, currency_code, data, payment_info)
          SELECT fixture.occasion, fixture.id, public.generate_order_symbol(), public.next_order_sequence(fixture.occasion),
                 'paid', 100, 'CZK', '{}', payment.id FROM fixture CROSS JOIN payment
          RETURNING id, form
        ) INSERT INTO eshop.waitlist_capabilities (token_hash, organization_id, form_id, order_id, kind, expires_at)
          SELECT encode(extensions.digest('${orderToken}', 'sha256'), 'hex'), ${organization}, form, id, 'order_view', now()+interval '1 hour'
          FROM paid_order RETURNING order_id;`));
        ensure(Number.isSafeInteger(orderId) && orderId > 0, 'Paid customer order fixture was not created');
        const heldSession = {access_token: reopened.data.session.access_token, refresh_token: reopened.data.session.refresh_token};
        const checkout = await ceremony('client_sign_in', {
            auth: env('FESTAPP_LOCAL_STRICT_AUTH_URL'), rest: base, organization, anonKey,
            link: checkoutLink, heldSession, orderId, orderToken,
        });
        ensure(checkout.guestCheckoutWithHeldSession, 'The browser must retain a public checkout path while account recovery holds');
        ensure(checkout.paidCustomerLinkWithHeldSession, 'The paid order link must retain only its own capability scope');
    }
    ensure(await revoke() === 't' && (await facts(reopened.data.session.access_token)).live === null,
        'A resumed revocation must also remove sessions created during the interruption');

    if (env('FESTAPP_MFA_BROWSER_PROOF') !== '1') return;
    const issueCode = () => sql(`SELECT public.issue_account_mfa_replacement_code_v1('${caseId}');`);
    ensure(await issueCode() === '', 'The operator must remove lost factors before issuing a replacement code');
    ensure((await direct(`admin/users/${targetId}/factors/${oldFactor.data.id}`, {
        method: 'DELETE', jwt: serviceKey,
    })).ok, 'The internal provider must remove the lost factor');
    const recoveryCode = await issueCode();
    ensure(/^[A-Za-z0-9_-]{43}$/.test(recoveryCode), 'Support must issue an opaque replacement code');

    async function freshProof() {
        const next = await client(anonKey).auth.signInWithPassword({ email: targetEmail, password: targetPassword });
        ensure(!next.error && next.data.session, 'Replacement actor must have a fresh password session');
        return next.data.session.access_token;
    }
    const externalEvidence = crypto.randomUUID();
    const finishRecovery = (withEvidence = true) => sql(`SELECT public.complete_account_mfa_recovery_v1(
        '${caseId}', ${withEvidence ? "'" + externalEvidence + "'" : 'NULL'});`);
    ensure(await finishRecovery() === 'f', 'External evidence cannot replace the verified factor');
    const replacementJwt = await freshProof(), otherJwt = await freshProof();
    ensure(await decision(replacementJwt) === 'account_recovery', 'Replacement proof does not unlock private access');
    const redirectUri = new URL('/google-auth', base.replace(/^http:/, 'https:')).href;
    const origin = new URL(redirectUri).origin;
    const clientId = ceremony ? `${organization}:web:${origin}` : 'mfa-replacement-' + caseId;
    const channel = await admin.from('external_login_clients').insert({
        client_id: clientId, organization, platform: 'web', origin, redirect_uri: redirectUri, provisioned: true,
    });
    ensure(!channel.error, 'Recovery channel fixture could not be registered');
    await sql(`SELECT public.set_mfa_channel_method_v1('${clientId}', '${method}', true, true, false);`);
    const codeVerifier = crypto.randomUUID() + crypto.randomUUID();
    const hash = new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(codeVerifier)));
    const codeChallenge = btoa(String.fromCharCode(...hash)).replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');
    const operation = (path: string, body: Record<string, unknown>, token = replacementJwt) =>
        fetch(env('FESTAPP_LOCAL_STRICT_AUTH_URL') + '/auth/v1/festapp/mfa/' + path, {
            method: 'POST', redirect: 'manual',
            headers: { Origin: origin, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
            body: JSON.stringify(body),
        });
    const start = { clientId, organization, redirectUri, codeChallenge, method };
    ensure([401, 403].includes((await operation('registration/start', start)).status),
        'An account on hold cannot use ordinary enrollment');
    ensure((await operation('registration/start', { ...start, recoveryCode: 'z'.repeat(43) })).status === 403,
        'A wrong recovery code must not authorize enrollment');
    let factorId: string, completed: {access_token: string}, totpSecret = '';
    if (ceremony) {
        completed = await ceremony('client_sign_in', {
            auth: env('FESTAPP_LOCAL_STRICT_AUTH_URL'), rest: base, organization, anonKey,
            recoveryCredentials: {email: targetEmail, password: targetPassword}, recoveryCode,
        });
        factorId = await sql(`SELECT id FROM auth.mfa_factors WHERE user_id = '${targetId}'
            AND factor_type = 'webauthn' AND status = 'verified'`);
        ensure(/^[a-f0-9-]{36}$/.test(factorId), 'The browser must persist a single verified security key');
    } else {
        const starts = await Promise.all([
            operation('registration/start', { ...start, recoveryCode }),
            operation('registration/start', { ...start, recoveryCode }),
        ]);
        const issued = starts.find(response => response.status === 303);
        ensure(issued && starts.filter(response => response.status === 403).length === 1,
            'A recovery code must issue at most one registration handoff');
        const code = new URL(issued.headers.get('location')!).searchParams.get('mfa_code');
        const claim = { organization, code, codeVerifier, recovery: true };
        ensure((await operation('registration/claim', claim, otherJwt)).status === 403,
            'A different session with the same password cannot claim a recovery receipt');
        const receipt = await requireJson(await operation('registration/claim', claim), 'Recovery receipt');
        const factor = await requireJson(await operation('totp/enroll', {
            receipt: receipt.id, friendlyName: 'Replacement device', recovery: true,
        }), 'Recovery factor');
        factorId = factor.id;
        totpSecret = factor.totp.secret;
        const verify = { receipt: receipt.id, factorId, recovery: true, code: await codeFor(totpSecret) };
        ensure([401, 403].includes((await operation('totp/verify', { ...verify, recovery: false })).status),
            'A recovery factor cannot verify through the everyday enrollment path');
        completed = await requireJson(await operation('totp/verify', verify), 'Verified recovery factor');
    }
    ensure((await facts(completed.access_token)).live?.verifiedFactor &&
        await decision(completed.access_token) === 'account_recovery',
        'The replacement factor must be recorded while private access remains closed');

    ensure(await finishRecovery(false) === 'f' && await decision(completed.access_token) === 'account_recovery',
        'The operator must record closure of external access before releasing the hold');
    const ownerOnlyFinish = await admin.rpc('complete_account_mfa_recovery_v1', {
        p_case: caseId, p_external_revocation_evidence: externalEvidence,
    });
    ensure(ownerOnlyFinish.error, 'A generic service credential cannot complete recovery');
    ensure(await finishRecovery() === 't' && await finishRecovery() === 't', 'Completion must be safely replayable');
    ensure(await sql(`SELECT count(*) FROM public.account_mfa_recovery_completions
      WHERE case_id = '${caseId}' AND method = '${method}' AND jsonb_array_length(approvals) = 2`) === '1',
        'Completion must retain one support receipt after releasing the hold');
    ensure(await decision(completed.access_token) === 'invalid_session' && await redeemFile() === false,
        'Completion must leave old and replacement sessions, and their grants, revoked');

    const afterRecovery = await freshProof();
    ensure(await decision(afterRecovery) === 'mfa_required', 'A fresh login still needs the replacement second factor');
    const challenge = await requireJson(await direct(`factors/${factorId}/challenge`, { jwt: afterRecovery }),
        'Post-recovery second factor challenge');
    const proof = ceremony ? {
        webauthn: { type: 'request', credential_response: await ceremony('get', challenge.webauthn.credential_options.publicKey) },
    } : { code: await codeFor(totpSecret) };
    const signedIn = await requireJson(await direct(`factors/${factorId}/verify`, {
        jwt: afterRecovery, body: { challenge_id: challenge.id, ...proof },
    }), 'Post-recovery second factor');
    ensure(await decision(signedIn.access_token) === 'allowed', 'Only fresh MFA re-opens private access after recovery');

    if (ceremony) await qualifyGoogleWebAuthn(targetEmail, targetPassword, targetId, ceremony);
}
await qualifySupportRecovery();
if (env('FESTAPP_MFA_BROWSER_PROOF') === '1') {
    await withCeremonyBrowser(base.replace(/^http:/, 'https:'), qualifySupportRecovery);
}

async function qualifyGoogleWebAuthn(email: string, password: string, user: string, ceremony: Ceremony) {
    const origin = base.replace(/^http:/, 'https:');
    const ingress = 'https://google-webauthn-ingress.fixture.invalid';
    const strict = env('FESTAPP_LOCAL_STRICT_AUTH_URL');
    const clientId = 'mfa-google-webauthn-' + crypto.randomUUID();
    const attempt = crypto.randomUUID();
    const verifier = randomSecret(), bootstrap = randomSecret(), code = randomSecret();
    const challenge = await hash(verifier);
    const registered = await admin.from('external_login_clients').insert({
        client_id: clientId, organization, platform: 'web', origin,
        redirect_uri: origin + '/google-auth', provisioned: true, enabled: true,
    });
    ensure(!registered.error, 'Could not register the disposable Google WebAuthn client');
    const advance = async (operation: string, secret: string, payload: Record<string, unknown>) => {
        const result = await admin.rpc('google_auth_transition_v1', {
            p_operation: operation, p_attempt: attempt, p_secret_hash: secret, p_payload: payload,
        });
        ensure(!result.error, `Could not seed the disposable Google ${operation} state`);
    };
    const stateHash = await hash(randomSecret());
    const browserHash = await hash(randomSecret());
    await advance('start', await hash(bootstrap), {
        clientId, origin, organization, challenge, stateHash, nonceHash: await hash(randomSecret()),
    });
    await advance('bootstrap', await hash(bootstrap), { browserHash });
    await advance('provider', stateHash, {
        browserHash, issuer: 'https://accounts.google.com', subject: attempt,
        email: email.split('+')[1], mailboxVerified: true, handoffHash: await hash(code),
    });
    const config = {
        SUPABASE_URL: base, SUPABASE_ANON_KEY: anonKey, SUPABASE_SERVICE_ROLE_KEY: serviceKey,
        GOOGLE_OIDC_CLIENT_ID: 'fixture', GOOGLE_OIDC_CLIENT_SECRET: 'fixture',
        GOOGLE_OIDC_CALLBACK_URL: ingress + '/functions/v1/google-auth-callback',
        GOOGLE_AUTH_ENCRYPTION_KEY: 'a'.repeat(64), GOOGLE_AUTH_MAILBOX_HMAC_KEY: 'b'.repeat(64),
        GOOGLE_AUTH_WEBAUTHN_INGRESS: ingress,
    };
    const previous = Object.keys(config).map(key => [key, Deno.env.get(key)] as const);
    for (const [key, value] of Object.entries(config)) Deno.env.set(key, value);
    const fixtureFetch = globalThis.fetch;
    let attemptedWrongOrigin = false;
    let forceWrongOrigin = false;
    globalThis.fetch = async (input, init) => {
        if (typeof input !== 'string' || !input.startsWith(ingress + '/auth/v1/factors/')) {
            return await fixtureFetch(input, init);
        }
        const headers = new Headers(init?.headers);
        ensure(headers.get('origin') === origin && init?.redirect === 'error',
            'The Edge broker must send the registered origin and refuse redirects');
        if (forceWrongOrigin) headers.set('origin', 'https://other.invalid');
        const response = await fixtureFetch(strict + new URL(input).pathname, { ...init, headers });
        if (forceWrongOrigin) {
            attemptedWrongOrigin = response.status === 403 &&
                (await response.clone().json()).code === 'invalid_webauthn_origin';
        }
        return response;
    };
    const complete = (operation: string, body: Record<string, unknown>) => handleGoogleAuth('complete', new Request(
        ingress + '/functions/v1/google-auth-complete', {
            method: 'POST', headers: { Origin: origin, 'Content-Type': 'application/json' },
            body: JSON.stringify({ clientId, organization, attempt, verifier, operation, ...body }),
        },
    ));
    try {
        const claimed = await requireJson(await complete('claim', { code }), 'Google provider handoff');
        ensure(claimed.status === 'needs_account_proof' && !claimed.session, 'Google proof cannot issue a first-factor session');
        const pending = await requireJson(await complete('prove_existing', {
            continuation: claimed.continuation, email: email.split('+')[1], password, supportsWebAuthn: true,
        }), 'Google WebAuthn challenge');
        ensure(pending.status === 'needs_mfa' && pending.mfaMethod === 'webauthn' && !pending.session,
            'The password proof must return only the security-key challenge');
        const verify = (mfaAssertion: unknown) => complete('mfa_verify', { continuation: pending.continuation, mfaAssertion });
        const withoutUv = await verify(await ceremony('get', pending.webAuthnOptions, false));
        ensure(!withoutUv.ok && !(await withoutUv.json()).session,
            'Google must deny a signed assertion without user verification');
        forceWrongOrigin = true;
        const assertion = await ceremony('get', pending.webAuthnOptions);
        ensure(!(await verify(assertion)).ok && attemptedWrongOrigin,
            'The exclusive ingress must deny an assertion at a different channel origin');
        forceWrongOrigin = false;
        const session = await requireJson(await verify(assertion), 'Google WebAuthn continuation');
        const proof = await facts(session.session.access_token);
        ensure(session.status === 'authenticated' && session.userId === user && proof.aal === 'aal2' &&
            proof.methods.includes('mfa/webauthn') && await decision(session.session.access_token) === 'allowed',
            'Google must return the correct account with a live WebAuthn second factor');
        ensure(!(await verify(assertion)).ok, 'The completed Google assertion must not issue a second session');
    } finally {
        globalThis.fetch = fixtureFetch;
        for (const [key, value] of previous) {
            if (value === undefined) Deno.env.delete(key);
            else Deno.env.set(key, value);
        }
    }
}

async function qualifyRegistrationHandoff(clientId: string, origin: string) {
    const strict = env('FESTAPP_LOCAL_STRICT_AUTH_URL') + '/auth/v1/';
    const redirectUri = origin + '/google-auth';
    const registrationEmail = `${organization}+registration-${crypto.randomUUID()}@example.invalid`;
    const registrationPassword = crypto.randomUUID() + crypto.randomUUID();
    const user = await admin.auth.admin.createUser({
        email: registrationEmail, password: registrationPassword, email_confirm: true,
    });
    ensure(!user.error && user.data.user && /^[a-f0-9-]{36}$/.test(user.data.user.id), 'Could not create the handoff actor');
    await sql(`INSERT INTO public.user_info (id, organization, email_readonly)
        VALUES ('${user.data.user.id}', ${organization}, '${registrationEmail.split('+')[1]}');`);
    const enrollmentNoticeCount = () => sql(`SELECT count(*) FROM public.email_messages
        WHERE organization = ${organization} AND recipient = '${registrationEmail.split('+')[1]}'
        AND code = 'ACCOUNT_MFA_METHOD_ADDED' AND tracking_policy = 'disabled'`);
    async function passwordSession() {
        const result = await client(anonKey).auth.signInWithPassword({
            email: registrationEmail, password: registrationPassword,
        });
        ensure(!result.error && result.data.session, 'Could not sign in the handoff actor');
        return result.data.session.access_token;
    }
    const actorToken = await passwordSession();
    const otherSession = await passwordSession();
    const raw = (route: string, jwt: string, body: unknown, method = 'POST') => fetch(strict + route, {
        method, headers: { Authorization: `Bearer ${jwt}`, 'Content-Type': 'application/json' },
        ...(method === 'GET' ? {} : { body: JSON.stringify(body) }),
    });
    ensure((await raw('factors', actorToken, { factor_type: 'totp' })).status === 403,
        'Public clients must not enroll directly in GoTrue');
    ensure((await raw('admin/users', serviceKey, null, 'GET')).status === 403,
        'Public Auth must not expose the internal administration route');
    ensure((await raw('passkeys/authentication/options', anonKey, {})).status === 403,
        'Passkey sign-in must wait for its brokered public channel');
    const verifier = crypto.randomUUID() + crypto.randomUUID();
    const hash = new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(verifier)));
    const challenge = btoa(String.fromCharCode(...hash)).replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');
    const request = (operation: string, body: Record<string, unknown>, jwt: string, callerOrigin = origin) =>
        fetch(strict + 'festapp/mfa/registration/' + operation, {
            method: 'POST', redirect: 'manual',
            headers: { Origin: callerOrigin, Authorization: `Bearer ${jwt}`, 'Content-Type': 'application/json' },
            body: JSON.stringify(body),
        });
    const startInfo = { clientId, organization, redirectUri, method: 'passkey', codeChallenge: challenge };
    ensure((await request('start', startInfo, actorToken, 'https://other.invalid')).status === 403,
        'A different origin must not obtain a registration handoff');
    ensure((await request('start', { ...startInfo, redirectUri: origin + '/wrong' }, actorToken)).status === 403,
        'An unregistered callback must not obtain a registration handoff');
    ensure((await request('start', { ...startInfo, method: 'totp' }, actorToken)).status === 403,
        'A visible method must still obey its independent registration flag');

    async function start(method: string, jwt = actorToken) {
        const response = await request('start', { ...startInfo, method }, jwt);
        ensure(response.status === 303, `Registration handoff failed with HTTP ${response.status}`);
        const destination = new URL(response.headers.get('location')!);
        const code = destination.searchParams.get('mfa_code');
        destination.search = '';
        ensure(destination.href === redirectUri && code, 'The registration code must be sent to the exact callback');
        return code;
    }
    const preflight = await fetch(strict + 'festapp/mfa/registration/start', {
        method: 'OPTIONS', headers: { Origin: origin, 'Access-Control-Request-Headers': 'apikey,authorization,content-type' },
    });
    ensure(preflight.status === 204 && preflight.headers.get('access-control-allow-headers')?.includes('apikey'),
        'Authenticated cross-origin registration must allow the expected API header');
    const code = await start('passkey');
    const claim = { organization, code, codeVerifier: verifier };
    ensure((await request('claim', { ...claim, codeVerifier: 'z'.repeat(43) }, actorToken)).status === 403,
        'Wrong PKCE proof must leave the registration handoff unclaimed');
    ensure((await request('claim', claim, otherSession)).status === 403,
        'Registration must return to the originating user session');
    const attempts = await Promise.all([request('claim', claim, actorToken), request('claim', claim, actorToken)]);
    const response = attempts.find(response => response.status === 200);
    ensure(response && attempts.filter(response => response.status === 403).length === 1,
        'Exactly one concurrent request can claim a registration handoff');
    const receipt = await response.json();
    ensure(typeof receipt.id === 'string' && receipt.method === 'passkey', 'The receipt must be scoped to the original registration method');

    const setTotpRegistration = (enabled: boolean) =>
        sql(`SELECT public.set_mfa_channel_method_v1('${clientId}', 'totp', true, ${enabled}, false);`);
    await setTotpRegistration(true);
    const interrupted = await start('totp');
    await setTotpRegistration(false);
    ensure((await request('claim', { ...claim, code: interrupted }, actorToken)).status === 403,
        'Disabling registration must close an unfinished handoff');

    await setTotpRegistration(true);
    ensure((await request('claim', { ...claim, code: interrupted }, actorToken)).status === 403,
        'Restarting registration must not revive an interrupted handoff');
    const activeCode = await start('totp', otherSession);
    const claimed = await request('claim', { ...claim, code: activeCode }, otherSession);
    ensure(claimed.ok, 'An enabled TOTP channel must issue a scoped receipt');
    const totpReceipt = (await claimed.json()).id;
    ensure(typeof totpReceipt === 'string' && /^[a-f0-9-]{36}$/.test(totpReceipt), 'Invalid test receipt identity');
    const totpOperation = (operation: string, body: Record<string, unknown>, jwt = otherSession) =>
        fetch(strict + 'festapp/mfa/totp/' + operation, {
            method: 'POST',
            headers: { Origin: origin, Authorization: `Bearer ${jwt}`, 'Content-Type': 'application/json' },
            body: JSON.stringify(body),
        });
    const enrollment = { receipt: totpReceipt, friendlyName: 'Disposable TOTP' };
    ensure((await totpOperation('enroll', enrollment, actorToken)).status === 403,
        'A second session must not enroll with the claimed receipt');
    const enrollments = await Promise.all([totpOperation('enroll', enrollment), totpOperation('enroll', enrollment)]);
    const acceptedEnrollment = enrollments.find(response => response.ok);
    const enrollmentStatuses = await Promise.all(enrollments.map(async response =>
        response.ok ? String(response.status) : `${response.status}/${(await response.clone().json()).code}`));
    const enrollmentFacts = await sql(`SELECT json_build_object(
        'pendingFactors', (SELECT count(*) FROM auth.mfa_factors
                           WHERE user_id = '${user.data.user.id}' AND status = 'unverified'),
        'entered', enrollment_started_at IS NOT NULL, 'bound', factor_id IS NOT NULL)
        FROM public.account_mfa_registration_handoffs WHERE id = '${totpReceipt}';`);
    ensure(acceptedEnrollment && enrollments.filter(response => response.status === 403).length === 1,
        `A TOTP receipt must enroll a single factor even across parallel requests (${enrollmentStatuses.join(', ')}; ${enrollmentFacts})`);
    const data = await acceptedEnrollment.json();
    ensure((await raw(`factors/${data.id}/challenge`, otherSession, {})).status === 403,
        'An unverified factor must use the registration flow');
    const verify = { receipt: totpReceipt, factorId: data.id, code: await codeFor(data.totp.secret) };
    await setTotpRegistration(false);
    ensure((await totpOperation('verify', verify)).status === 403,
        'Disabling registration must stop completion of a bound TOTP factor');
    await setTotpRegistration(true);
    ensure((await totpOperation('verify', verify)).status === 403,
        'Restarting registration must not revive a previously bound factor');
    const newSession = await passwordSession();
    const inPlace = await requireJson(await request('start', { ...startInfo, method: 'totp', inPlace: true }, newSession),
        'In-place registration handoff');
    const inPlaceCallback = new URL(inPlace.callback);
    const codeAfterRestart = inPlaceCallback.searchParams.get('mfa_code');
    inPlaceCallback.search = '';
    ensure(codeAfterRestart && inPlaceCallback.href === redirectUri, 'In-place registration must preserve the registered callback');
    const newClaim = await request('claim', { ...claim, code: codeAfterRestart }, newSession);
    ensure(newClaim.ok, 'New registration must be possible after re-enabling TOTP');
    const newReceipt = (await newClaim.json()).id;
    const newEnrollment = await totpOperation('enroll', { receipt: newReceipt, friendlyName: 'Second disposable TOTP' }, newSession);
    ensure(newEnrollment.ok, 'A new receipt may enroll a factor after the restart');
    const next = await newEnrollment.json();
    const verified = await totpOperation('verify', {
        receipt: newReceipt, factorId: next.id, code: await codeFor(next.totp.secret),
    }, newSession);
    ensure(verified.ok, `TOTP verification failed with HTTP ${verified.status}`);
    const session = await verified.json();
    ensure(await decision(session.access_token, true) === 'allowed',
        'Brokered TOTP registration must return the real upgraded session');
    ensure(await enrollmentNoticeCount() === '1', 'Only the confirmed TOTP enrollment may send a notice');
    const password = await passwordSession();
    ensure((await raw('user', password, { data: { changed: true } }, 'PUT')).status === 403,
        'An enrolled account cannot update Auth with its AAL1 session');
    const challengeResult = await raw(`factors/${next.id}/challenge`, password, {});
    ensure(challengeResult.ok, 'A verified factor must remain available for normal sign-in');
    const stepUp = await raw(`factors/${next.id}/verify`, password, {
        challenge_id: (await challengeResult.json()).id, code: await codeFor(next.totp.secret),
    });
    const steppedUp = await requireJson(stepUp, 'Existing TOTP verification');
    ensure(await decision(steppedUp.access_token) === 'allowed',
        'The normal public endpoint must verify an existing factor after the first login');

    const setWebAuthnRegistration = (enabled: boolean) =>
        sql(`SELECT public.set_mfa_channel_method_v1('${clientId}', 'webauthn', true, ${enabled}, false);`);
    await setWebAuthnRegistration(true);
    const webAuthnActor = steppedUp.access_token;
    const webAuthnOperation = (operation: string, body: Record<string, unknown>) =>
        fetch(strict + 'festapp/mfa/webauthn/' + operation, {
            method: 'POST',
            headers: { Origin: origin, Authorization: `Bearer ${webAuthnActor}`, 'Content-Type': 'application/json' },
            body: JSON.stringify(body),
        });
    async function webAuthnChallenge() {
        const code = await start('webauthn', webAuthnActor);
        const handoff = await requireJson(await request('claim', { ...claim, code }, webAuthnActor), 'WebAuthn claim');
        ensure(handoff.method === 'webauthn' && /^[a-f0-9-]{36}$/.test(handoff.id), 'Invalid WebAuthn receipt');
        const factor = await requireJson(await webAuthnOperation('enroll', {
            receipt: handoff.id, friendlyName: 'Disposable WebAuthn ' + handoff.id.slice(0, 8),
        }), 'Brokered WebAuthn enrollment');
        ensure((await raw(`factors/${factor.id}/challenge`, webAuthnActor, {})).status === 403,
            'Raw challenge must deny the pending WebAuthn factor');
        const scope = { receipt: handoff.id, factorId: factor.id };
        const options = await requireJson(await webAuthnOperation('challenge', scope), 'Brokered WebAuthn challenge');
        ensure(options.webauthn?.type === 'create', 'Brokered challenge must register a new authenticator');
        return { ...scope, options };
    }

    const pending = await webAuthnChallenge();
    const pendingState = () => sql(`SELECT status FROM auth.mfa_factors WHERE id = '${pending.factorId}'`);
    const wrongOrigin = await withCeremonyBrowser(base, ceremony =>
        ceremony('create', pending.options.webauthn.credential_options.publicKey));
    const rejected = await webAuthnOperation('verify', {
        receipt: pending.receipt, factorId: pending.factorId, challengeId: pending.options.id, credential: wrongOrigin,
    });
    ensure(rejected.status === 403 && (await rejected.json()).code === 'invalid_webauthn_origin',
        'A provider-trusted origin outside the registered channel must be refused');
    await withCeremonyBrowser(origin, async ceremony => {
        const publicKey = pending.options.webauthn.credential_options.publicKey;
        const finish = (credential: unknown) => webAuthnOperation('verify', {
            receipt: pending.receipt, factorId: pending.factorId, challengeId: pending.options.id, credential,
        });
        await expectUserVerificationRequired(await finish(await ceremony('create', publicKey, false)));
        ensure(await pendingState() === 'unverified', 'A rejected WebAuthn credential must leave the factor pending');
        const credential = await ceremony('create', publicKey);
        await setWebAuthnRegistration(false);
        ensure((await finish(credential)).status === 403, 'Disabling WebAuthn must stop an open ceremony');
        await setWebAuthnRegistration(true);
        ensure((await finish(credential)).status === 403, 'Re-enabling WebAuthn must keep the old ceremony closed');
        ensure(await pendingState() === 'unverified', 'The discontinued ceremony must leave the factor pending');
        await sql(`UPDATE public.account_mfa_registration_handoffs SET expires_at = now() WHERE id = '${pending.receipt}'`);

        const active = await webAuthnChallenge();
        const response = await requireJson(await webAuthnOperation('verify', {
            receipt: active.receipt, factorId: active.factorId, challengeId: active.options.id,
            credential: await ceremony('create', active.options.webauthn.credential_options.publicKey),
        }), 'Brokered WebAuthn registration');
        const verified = await facts(response.access_token);
        ensure(verified.aal === 'aal2' && verified.methods.includes('mfa/webauthn') &&
            await decision(response.access_token, true) === 'allowed',
            'Brokered WebAuthn registration must verify a real factor and return a live upgraded session');

        const passkeyActor = response.access_token;
        const passkeyOperation = (operation: string, body: Record<string, unknown>, jwt = passkeyActor) =>
            fetch(strict + 'festapp/passkey/registration/' + operation, {
                method: 'POST',
                headers: { Origin: origin, Authorization: `Bearer ${jwt}`, 'Content-Type': 'application/json' },
                body: JSON.stringify(body),
            });
        const passkeyCount = () => sql(`SELECT count(*) FROM auth.webauthn_credentials
            WHERE user_id = '${user.data.user.id}'`);
        const beforePasskey = await passkeyCount();
        const passkeyCode = await start('passkey', passkeyActor);
        const passkeyReceipt = await requireJson(await request('claim', {
            ...claim, code: passkeyCode,
        }, passkeyActor), 'Passkey claim');
        ensure(passkeyReceipt.method === 'passkey', 'A passkey receipt must retain its method');
        ensure((await passkeyOperation('options', { receipt: passkeyReceipt.id }, session.access_token)).status === 403,
            'Another verified session of the same user must not use the receipt');
        const unverified = await passkeyOperation('options', { receipt: passkeyReceipt.id }, password);
        ensure([401, 403].includes(unverified.status),
            'An insufficiently verified session must not use the receipt');
        ensure((await raw('passkeys/registration/options', passkeyActor, {})).status === 403,
            'Raw passkey registration must remain disabled');
        const options = await requireJson(await passkeyOperation('options', { receipt: passkeyReceipt.id }), 'Passkey options');
        ensure((await passkeyOperation('options', { receipt: passkeyReceipt.id })).status === 403,
            'A receipt must only create one provider challenge');
        const finishPasskey = (credential: unknown, challengeId = options.challenge_id) =>
            passkeyOperation('verify', { receipt: passkeyReceipt.id, challengeId, credential });
        await expectUserVerificationRequired(await finishPasskey(await ceremony('create', options.options, false)));
        const passkey = await ceremony('create', options.options);
        ensure((await finishPasskey(passkey, crypto.randomUUID())).status === 403,
            'The passkey receipt must require its own GoTrue challenge');
        ensure(await passkeyCount() === beforePasskey, 'Denied ceremonies must not write a passkey');
        const registrations = await Promise.all([finishPasskey(passkey), finishPasskey(passkey)]);
        ensure(registrations.filter(result => result.ok).length === 1 &&
            registrations.filter(result => result.status === 403).length === 1 &&
            Number(await passkeyCount()) === Number(beforePasskey) + 1,
            'Concurrent verification must save exactly one passkey');
        ensure(await decision(passkeyActor, true) === 'allowed',
            'Adding a passkey must leave the already verified MFA session valid');
        ensure(await enrollmentNoticeCount() === '3',
            'Completed TOTP, WebAuthn and passkey enrollment each queue one untracked notice');

        const signIn = (operation: string, body: Record<string, unknown>, callerOrigin = origin, jwt?: string) =>
            fetch(strict + 'festapp/passkey/sign-in/' + operation, {
                method: 'POST',
                headers: { Origin: callerOrigin, 'Content-Type': 'application/json',
                    ...(jwt && { Authorization: `Bearer ${jwt}` }) },
                body: JSON.stringify(body),
            });
        const startFields = { clientId, organization, redirectUri, codeChallenge: challenge };
        ensure((await signIn('options', startFields, origin, passkeyActor)).status === 409,
            'An authenticated caller cannot start the anonymous passkey flow');
        ensure((await signIn('options', { ...startFields, organization: organization + 1 })).status === 403,
            'Sign-in must use the registered tenant');
        ensure((await signIn('options', startFields, 'https://outside.invalid')).status === 403,
            'Sign-in must use the registered origin');
        const setPasskeySignIn = (enabled: boolean) =>
            sql(`SELECT public.set_mfa_channel_method_v1('${clientId}', 'passkey', true, true, ${enabled});`);
        const activeSessions = () => sql(`SELECT count(*) FROM auth.sessions WHERE user_id = '${user.data.user.id}'`);
        const beforeSignIn = await activeSessions();
        const stale = await requireJson(await signIn('options', startFields), 'Passkey sign-in options');
        const staleAssertion = await ceremony('get', stale.options);
        await setPasskeySignIn(false);
        ensure((await signIn('options', startFields)).status === 403,
            'Disabling passkey sign-in must stop new options');
        await setPasskeySignIn(true);
        ensure((await signIn('verify', { challengeId: stale.challenge_id, credential: staleAssertion })).status === 403,
            'Restart must not make old sign-in options valid again');
        ensure(await activeSessions() === beforeSignIn, 'Replayed options must not issue a provider session');
        const discovery = await requireJson(await signIn('options', startFields), 'Discoverable passkey options');
        const verifyLogin = (credential: unknown) =>
            signIn('verify', { challengeId: discovery.challenge_id, credential });
        await expectUserVerificationRequired(await verifyLogin(await ceremony('get', {
            ...discovery.options,
            allowCredentials: [{ id: passkey.id, type: 'public-key', transports: ['internal'] }],
        }, false)));
        ensure(await activeSessions() === beforeSignIn, 'UV rejection must leave the session inventory unchanged');
        const assertion = await ceremony('get', discovery.options);
        ensure(assertion.id === passkey.id, 'Use the credential registered through the broker');
        const handoff = await requireJson(await verifyLogin(assertion), 'Verified passkey sign-in');
        ensure(Object.keys(handoff).join(',') === 'callback', 'Verification must return only an opaque handoff via the callback');
        const callback = new URL(handoff.callback);
        const exchangeCode = callback.searchParams.get('passkey_code');
        callback.search = '';
        ensure(exchangeCode && callback.href === redirectUri, 'The opaque code must use the registered callback');
        const exchange = { clientId, organization, code: exchangeCode, codeVerifier: verifier };
        ensure((await signIn('exchange', { ...exchange, codeVerifier: 'z'.repeat(43) })).status === 403,
            'Wrong PKCE proof must not redeem the exchange');
        ensure((await signIn('exchange', { ...exchange, clientId: 'another-client' })).status === 403,
            'The exchange belongs to the client that requested the ceremony');
        ensure((await signIn('exchange', exchange, 'https://outside.invalid')).status === 403,
            'A foreign origin must not redeem the exchange');
        const exchanges = await Promise.all([signIn('exchange', exchange), signIn('exchange', exchange)]);
        const accepted = exchanges.find(result => result.ok);
        ensure(accepted && exchanges.filter(result => result.status === 403).length === 1,
            'Exactly one concurrent PKCE exchange must succeed');
        const login = await accepted.json();
        ensure(login.userId === user.data.user.id && login.organization === organization && login.requiresMfa,
            'The discoverable credential must resolve the correct enrolled account and require MFA');
        const passkeyJwt = login.session.access_token;
        const passkeyFacts = await facts(passkeyJwt);
        ensure(passkeyFacts.aal === 'aal1' && passkeyFacts.methods.includes('passkey') &&
            await decision(passkeyJwt) === 'mfa_required',
            'Brokered passkey sign-in must only provide the first factor for an MFA account');
        await expectDenied(await rest('user_info?id=eq.' + user.data.user.id, passkeyJwt), 'mfa_required');
        const existingChallenge = await requireJson(await raw(`factors/${active.factorId}/challenge`, passkeyJwt, {}),
            'Existing WebAuthn challenge');
        const secondAssertion = await ceremony('get', existingChallenge.webauthn.credential_options.publicKey);
        ensure(secondAssertion.id !== passkey.id, 'MFA must use a separate registered credential');
        const upgraded = await requireJson(await raw(`factors/${active.factorId}/verify`, passkeyJwt, {
            challenge_id: existingChallenge.id,
            webauthn: { type: 'request', credential_response: secondAssertion },
        }), 'WebAuthn after brokered passkey sign-in');
        ensure(await decision(upgraded.access_token) === 'allowed',
            'Client context must only unlock after the second proof');

        const webClientId = organization + ':web:' + origin;
        const webChannel = await admin.from('external_login_clients').upsert({
            client_id: webClientId, organization, platform: 'web', origin, redirect_uri: redirectUri, provisioned: true,
        }, {onConflict: 'client_id'});
        ensure(!webChannel.error, 'Normal web-client channel must be registered');
        await sql(`SELECT public.set_mfa_channel_method_v1('${webClientId}', 'passkey', true, true, true);`);
        const webProof = await ceremony('client_sign_in', {auth: new URL(strict).origin, rest: base, organization, anonKey});
        ensure(webProof.passkeyFirstFactor && webProof.independentWebAuthnSecondFactor,
            'The normal web auth service must complete independent MFA through the pinned Auth stack');

        const settingsEmail = `${organization}+web-settings-${crypto.randomUUID()}@example.invalid`;
        const settingsCredentials = {email: settingsEmail, password: randomSecret()};
        const settingsActor = await admin.auth.admin.createUser({...settingsCredentials, email_confirm: true});
        ensure(!settingsActor.error && /^[a-f0-9-]{36}$/.test(settingsActor.data.user?.id ?? ''),
            'Could not create the browser settings subject');
        const settingsUser = settingsActor.data.user!.id;
        await sql(`INSERT INTO public.user_info(id, organization, email_readonly)
            VALUES ('${settingsUser}', ${organization}, '${settingsEmail.split('+')[1]}');
            SELECT public.set_mfa_channel_method_v1('${webClientId}', 'totp', true, true, false);
            SELECT public.set_mfa_channel_method_v1('${webClientId}', 'webauthn', true, true, false);`);
        const settings = await ceremony('client_sign_in', {
            auth: new URL(strict).origin, rest: base, organization, anonKey, settingsCredentials,
        });
        ensure(settings.accountSettingsAgainstPinnedAuth, 'The web settings must complete its normal user controls');
        const remainingFactors = await sql(`SELECT count(*) FROM auth.mfa_factors WHERE user_id = '${settingsUser}'`);
        const keptPasskeys = await sql(`SELECT count(*) FROM auth.webauthn_credentials WHERE user_id = '${settingsUser}'
            AND friendly_name = 'Travel passkey'`);
        ensure(remainingFactors === '0' && keptPasskeys === '1',
            `Settings must remove the factors and preserve the named passwordless credential (factors ${remainingFactors}, named passkeys ${keptPasskeys})`);

        const managePasskey = (operation: string, body: Record<string, unknown>, jwt: string) =>
            fetch(strict + 'festapp/passkey/manage/' + operation, {
                method: 'POST',
                headers: { Origin: origin, Authorization: `Bearer ${jwt}`, 'Content-Type': 'application/json' },
                body: JSON.stringify(body),
            });

        const primaryEmail = `${organization}+passkey-primary-${crypto.randomUUID()}@example.invalid`;
        const primaryPassword = crypto.randomUUID() + crypto.randomUUID();
        const primaryUser = await admin.auth.admin.createUser({ email: primaryEmail, password: primaryPassword, email_confirm: true });
        ensure(!primaryUser.error && primaryUser.data.user, 'Create a passkey-first account without MFA');
        const primaryId = primaryUser.data.user.id;
        ensure(/^[a-f0-9-]{36}$/.test(primaryId), 'Invalid passkey-first account id');
        await sql(`INSERT INTO public.user_info (id, organization) VALUES ('${primaryId}', ${organization})`);
        const primaryLogin = await client(anonKey).auth.signInWithPassword({ email: primaryEmail, password: primaryPassword });
        ensure(!primaryLogin.error && primaryLogin.data.session, 'Get the primary enrollment proof');
        const primaryJwt = primaryLogin.data.session.access_token;
        const registrationCode = await start('passkey', primaryJwt);
        const registration = await requireJson(await request('claim', {
            ...claim, code: registrationCode,
        }, primaryJwt), 'Passkey-first registration receipt');
        const primaryOptions = await requireJson(await passkeyOperation('options', { receipt: registration.id }, primaryJwt),
            'Passkey-first registration options');
        const primaryKey = await ceremony('create', primaryOptions.options);
        await requireJson(await passkeyOperation('verify', {
            receipt: registration.id, challengeId: primaryOptions.challenge_id, credential: primaryKey,
        }, primaryJwt), 'Passkey-first credential saved');
        const assertPrimary = (options: Record<string, unknown>) => ceremony('get', {
            ...options, allowCredentials: [{ id: primaryKey.id, type: 'public-key', transports: ['internal'] }],
        });
        const providerPrimary = await requireJson(await direct('passkeys/authentication/options'), 'Provider-only passkey options');
        const providerLogin = await requireJson(await direct('passkeys/authentication/verify', {
            body: { challenge_id: providerPrimary.challenge_id, credential: await assertPrimary(providerPrimary.options) },
        }), 'Provider-only passkey sign-in');
        ensure(await decision(providerLogin.access_token) === 'allowed' &&
            await decision(providerLogin.access_token, true) === 'proof_required',
            'Signed passkey proof without a completed handoff cannot confirm account security');
        const primaryDiscovery = await requireJson(await signIn('options', startFields), 'Brokered primary options');
        const primaryHandoff = await requireJson(await signIn('verify', {
            challengeId: primaryDiscovery.challenge_id, credential: await assertPrimary(primaryDiscovery.options),
        }), 'Brokered primary handoff');
        const primaryExchange = await requireJson(await signIn('exchange', {
            ...exchange, code: new URL(primaryHandoff.callback).searchParams.get('passkey_code'),
        }), 'Brokered primary exchange');
        const brokeredPrimaryJwt = primaryExchange.session.access_token;
        ensure(!primaryExchange.requiresMfa && primaryExchange.userId === primaryId &&
            await decision(brokeredPrimaryJwt, true) === 'allowed',
            'A bound, completed passkey exchange can confirm changes on a no-factor account');
        const savedKeys = await requireJson(await managePasskey('list', {}, brokeredPrimaryJwt), 'Passkey-first list');
        const renamed = await requireJson(await managePasskey('rename', { id: savedKeys[0].id, name: 'Primary key' }, brokeredPrimaryJwt),
            'Passkey-first rename');
        ensure(renamed.friendly_name === 'Primary key', 'Passkey-first security management must reach GoTrue');
        const primarySessionId = claims(brokeredPrimaryJwt).session_id;
        ensure(/^[a-f0-9-]{36}$/.test(primarySessionId), 'Invalid primary proof session id');
        await sql(`UPDATE auth.mfa_amr_claims SET updated_at = now() - interval '6 minutes'
            WHERE session_id = '${primarySessionId}' AND authentication_method = 'passkey'`);
        ensure(await decision(brokeredPrimaryJwt) === 'allowed' && await decision(brokeredPrimaryJwt, true) === 'proof_required',
            'The normal session may outlive the step-up proof');

        const keys = await requireJson(await managePasskey('list', {}, upgraded.access_token), 'Passkey listing');
        ensure(keys.length === 1 && /^[a-f0-9-]{36}$/.test(keys[0].id), 'Passkey list must contain only the enrolled account credential');
        const passkeyId = keys[0].id;
        ensure((await raw('passkeys', upgraded.access_token, {}, 'GET')).status === 403,
            'Direct passkey management must remain closed');
        const named = await requireJson(await managePasskey('rename', { id: passkeyId, name: 'Reference key' },
            upgraded.access_token), 'Passkey rename');
        ensure(named.friendly_name === 'Reference key', 'Managed rename must persist on GoTrue');
        const missingAlternative = await managePasskey('remove', { id: passkeyId }, upgraded.access_token);
        ensure(missingAlternative.status === 409 && (await missingAlternative.json()).code === 'password_proof_required',
            'A session opened with the last passkey must also prove a usable password before deletion');
        const removeFactor = (jwt: string, factorId: string, confirmDisable = false) =>
            fetch(strict + 'festapp/mfa/factors/remove', {
                method: 'POST',
                headers: { Origin: origin, Authorization: `Bearer ${jwt}`, 'Content-Type': 'application/json' },
                body: JSON.stringify({ factorId, confirmDisable }),
            });
        ensure((await raw(`factors/${next.id}`, upgraded.access_token, {}, 'DELETE')).status === 403,
            'A raw provider factor removal must be denied');
        const unconfirmed = [next.id, active.factorId];
        const removals = await Promise.all(unconfirmed.map(id => removeFactor(upgraded.access_token, id)));
        ensure(removals.filter(result => result.ok).length === 1,
            'Concurrent removals without last-factor confirmation may remove at most one factor');
        const remaining = unconfirmed[removals.findIndex(result => !result.ok)];
        const firstRemoval = await removals.find(result => result.ok)!.json();
        ensure(firstRemoval.removed && !firstRemoval.disabledMfa, 'The first removal must preserve MFA');

        const oldAal1 = await passwordSession();
        ensure(await decision(oldAal1) === 'mfa_required', 'The remaining verified factor must still protect the account');
        const finalChallenge = await requireJson(await raw(`factors/${remaining}/challenge`, oldAal1, {}),
            'Last factor reauthentication');
        const finalProof = remaining === next.id
            ? { code: await codeFor(next.totp.secret) }
            : { webauthn: {
                type: 'request',
                credential_response: await ceremony('get', finalChallenge.webauthn.credential_options.publicKey),
            } };
        const fresh = await requireJson(await raw(`factors/${remaining}/verify`, oldAal1, {
            challenge_id: finalChallenge.id, ...finalProof,
        }), 'Last factor verification');
        const lastUnconfirmed = await removeFactor(fresh.access_token, remaining);
        ensure(lastUnconfirmed.status === 409 && (await lastUnconfirmed.json()).code === 'confirm_disable_mfa',
            'Removing the last factor requires an explicit disable confirmation');
        const disabled = await requireJson(await removeFactor(fresh.access_token, remaining, true), 'Last factor removal');
        ensure(disabled.removed && disabled.disabledMfa, 'Explicit confirmation must remove the last factor');
        ensure(await decision(oldAal1) === 'invalid_session' && await decision(fresh.access_token) === 'invalid_session',
            'Old first- and second-factor tokens must stay revoked after disabling MFA');
        const newLogin = await passwordSession();
        ensure(await decision(newLogin) === 'allowed', 'A fresh login may access an account after voluntary MFA disablement');
        ensure(await sql(`SELECT count(*) FROM public.email_messages
            WHERE organization = ${organization} AND recipient = '${registrationEmail.split('+')[1]}'
            AND code = 'ACCOUNT_MFA_FACTOR_REMOVED' AND tracking_policy = 'disabled'`) === '2',
            'Each completed removal queues one untracked security notice');

        const deletedKey = await requireJson(await managePasskey('remove', { id: passkeyId }, newLogin),
            'Last passkey removal with verified password');
        ensure(deletedKey.revokesSession && await decision(newLogin) === 'invalid_session',
            'Removing a passkey must revoke sessions when the provider cannot attribute a session to a specific key');
        const revokedOptions = await requireJson(await signIn('options', startFields), 'Passkey after deletion');
        ensure((await signIn('verify', {
            challengeId: revokedOptions.challenge_id,
            credential: await ceremony('get', {
                ...revokedOptions.options, allowCredentials: [{ id: passkey.id, type: 'public-key', transports: ['internal'] }],
            }),
        })).status === 403, 'The deleted authenticator must not issue a session');
        const passwordAgain = await passwordSession();
        const finalList = await requireJson(await managePasskey('list', {}, passwordAgain), 'Passkey list after deletion');
        ensure(finalList.length === 0 && await decision(passwordAgain) === 'allowed',
            'The password remains a verified alternate sign-in route');

    });
}

async function qualifyGoogleHandoff() {
    const attempt = crypto.randomUUID();
    const clientId = 'mfa-test-' + attempt;
    const origin = base.replace(/^http:/, 'https:');
    const challenge = 'c'.repeat(43);
    const handoffHash = 'h'.repeat(43);
    const createdClient = await admin.from('external_login_clients').insert({
        client_id: clientId, organization, platform: 'web', origin,
        redirect_uri: origin + '/google-auth', provisioned: true, enabled: true,
    });
    ensure(!createdClient.error, 'Could not register the disposable Google client');
    const transition = (operation: string, hash: string, payload: Record<string, unknown>) =>
        admin.rpc('google_auth_transition_v1', {
            p_operation: operation, p_attempt: attempt, p_secret_hash: hash, p_payload: payload,
        });
    const start = await transition('start', 'b'.repeat(43), {
        clientId, origin, organization, challenge, stateHash: crypto.randomUUID(), nonceHash: 'n'.repeat(43),
    });
    ensure(!start.error && start.data.status === 'created', 'Could not start the disposable Google attempt');
    const bootstrap = await transition('bootstrap', 'b'.repeat(43), { browserHash: 'r'.repeat(43) });
    ensure(!bootstrap.error, 'Could not bootstrap the disposable Google attempt');
    const provider = await transition('provider', start.data.state_hash, {
        browserHash: 'r'.repeat(43), issuer: 'https://accounts.google.com', subject: attempt,
        email, mailboxVerified: true, handoffHash,
    });
    ensure(!provider.error, 'Could not record the disposable provider proof');
    const claims = await Promise.all(['a', 'z'].map(value =>
        transition('claim', handoffHash, { challenge, continuationHash: value.repeat(43) })));
    const rejected = claims.filter(result => result.error?.message === 'invalid_provider_proof');
    const accepted = claims.filter(result => !result.error && result.data?.handoff_hash === null);
    ensure(rejected.length === 1 && accepted.length === 1, 'Exactly one concurrent Google claim must consume the handoff');

    const args = { p_client_id: clientId, p_organization: organization, p_origin: origin,
        p_redirect_uri: origin + '/google-auth' };
    const before = await admin.rpc('resolve_mfa_channel_policy_v1', args);
    ensure(!before.error && before.data.platform === 'web' &&
        Object.values(before.data.methods).every(flags => {
            const method = flags as Record<string, unknown>;
            return method.offer === false && method.registration === false && method.signIn === false;
        }),
        'A provisioned channel with no method policy must be disabled by default');
    for (const wrong of [
        { p_organization: organization + 1 },
        { p_origin: 'https://other.invalid' },
        { p_redirect_uri: origin + '/different' },
    ]) {
        const result = await admin.rpc('resolve_mfa_channel_policy_v1', { ...args, ...wrong });
        ensure(!result.error && result.data === null, 'MFA policy must bind the exact tenant and channel');
    }
    const googleOff = await admin.from('external_login_clients').update({ enabled: false }).eq('client_id', clientId);
    ensure(!googleOff.error, 'Must be able to disable Google independently of MFA');
    await sql(`SELECT public.set_mfa_channel_method_v1('${clientId}', 'totp', true, false, false);
        SELECT public.set_mfa_channel_method_v1('${clientId}', 'passkey', false, true, true);`);
    const enabled = await admin.rpc('resolve_mfa_channel_policy_v1', args);
    ensure(!enabled.error && enabled.data.methods.totp.offer && !enabled.data.methods.totp.registration &&
        !enabled.data.methods.passkey.offer && enabled.data.methods.passkey.registration && enabled.data.methods.passkey.signIn &&
        !enabled.data.methods.webauthn.registration,
        'MFA offer, registration and passkey login must be independent of Google and each other');
    const authenticatedGrant = await sql(`SELECT has_function_privilege(
        'authenticated','public.resolve_mfa_channel_policy_v1(text,bigint,text,text)','EXECUTE');`);
    ensure(authenticatedGrant === 'f', 'MFA channel policy must remain broker-only');
    if (env('FESTAPP_MFA_BROWSER_PROOF') === '1') {
        const url = new URL(base + '/auth/v1/festapp/mfa/channel');
        url.search = new URLSearchParams({ client_id: clientId, organization: String(organization),
            redirect_uri: origin + '/google-auth' }).toString();
        const result = await fetch(url, { headers: { Origin: origin } });
        const flags = (await result.json()).methods;
        ensure(result.ok && result.headers.get('access-control-allow-origin') === origin &&
            flags.totp.offer && !flags.totp.registration && flags.passkey.signIn,
            'The public Auth broker must return effective availability for the exact registered channel');
        const outside = await fetch(url, { headers: { Origin: 'https://other.invalid' } });
        ensure(outside.status === 404 && !outside.headers.has('access-control-allow-origin'),
            'Unregistered origins must not receive channel availability');
        await qualifyRegistrationHandoff(clientId, origin);
    }
}
await qualifyGoogleHandoff();

console.log(JSON.stringify({
    oldPassword, totp, emailCode: emailCode.verification, passwordReset: passwordReset.verification,
    passkeyUserVerification, webauthn, recoveryCode, afterRemoval, afterRevocation,
    delegatedSessionIndependent: true, refreshRetainsMfaTime: true, expiredStepUpRejected: true,
    recoveryHoldSurvivesLastFactorRemoval: true, supportRecoveryRevocation: true, privateImageGrantRevocation: true,
    atomicGoogleHandoff: true, exactMfaChannelPolicy: true,
    ...(webauthn && { brokeredRecoveryReplacement: true, brokeredWebAuthnRecoveryReplacement: true, supportRecoveryCompletion: true, atomicMfaRegistrationHandoff: true, brokeredTOTPEnrollment: true, brokeredWebAuthnEnrollment: true, brokeredPasskeyRegistration: true, brokeredPasskeySignIn: true, brokeredPasskeyPrimaryProof: true, brokeredFactorRemoval: true, passkeyManagement: true, webClientAgainstPinnedAuth: true, guestCheckoutWithHeldSession: true, paidCustomerLinkWithHeldSession: true, googleWebAuthnWithPinnedAuth: true, accountSettingsAgainstPinnedAuth: true, accountRecoveryAgainstPinnedAuth: true }),
    guardedRestGraphQlAndAppContext: true,
}));
