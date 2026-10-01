# Google sign-in broker

Implementation: `docs/plans/google-sign-in-plan-2026-10-01.md`.
Local validation and console evidence: `docs/plans/google-sign-in-reference-2026-10-01/`.

## Current state

Google Cloud project `festapp-d23ef`, brand FestApp, External audience, publishing
status **In production**. The dedicated Web application OAuth client is recorded
in `google-console-config.json`. Its sole redirect is
`https://api.festapp.net/functions/v1/google-auth-callback`. It uses only openid,
userinfo.email and userinfo.profile. No native Google SDK/provider credentials
are shared with Mendelio. This is a server OIDC client for all FestApp adapters.
Authorized brand domains: vstupenky.online, festapp.net. The consent homepage,
privacy and terms point to vstupenky.online. No sensitive/restricted scopes or
logo verification were requested.

Local credentials are in ignored `automation/auth/.env.local`, mode 0600.
Do not print, commit or include that file in build output. They have **not** been
installed on the server. Google Console configuration is not an application deploy
or proof of a live end-to-end login.

## Explicit rollout steps

1. Rehearse migration `20261001150000_google_auth_broker.sql` on the canonical
   backend. Apply through the existing approved migration path. It creates RLS
   protected identity, attempt, rate-limit and distributed lease tables and an
   hourly pg_cron cleanup job. No existing UUID/email backfill is performed.
2. Provision these server-only private inputs through the approved secret manager:
   `GOOGLE_OIDC_CLIENT_ID`, `GOOGLE_OIDC_CLIENT_SECRET`,
   `GOOGLE_OIDC_CALLBACK_URL`, `GOOGLE_AUTH_ENCRYPTION_KEY`,
   `GOOGLE_AUTH_MAILBOX_HMAC_KEY`. The last two are independent 32-byte hex keys.
   Compose passes them to Edge runtime; absent inputs keep capability unavailable.
   Do not enable Supabase's separate Google provider.
3. Install the production Function bundle with the canonical installer, including
   `patch-function-proof-routes.py`. Its exact anonymous exceptions are
   google-auth-start/callback/complete; other JWT routes retain their existing
   protection. The patch matches the pinned upstream router and fails on drift.
   All three handlers additionally validate their own attempt/client boundaries.
4. Provision the **one approved tenant**, FestApp at live.festapp.net, organization 1, using the registry
   template below. Keep rows disabled until runtime, current clients and callback
   URLs have been verified. Preview/rehearsal origins need separate exact registry
   entries and a separate Google callback/client; do not reuse production redirects.
5. Build the selected tenant normally. `/google-auth` serves webclient;
   `/app/google-auth` serves Flutter. Both are no-store/no-referrer and bypass PWA
   caches. Native returns use HTTPS App/Universal Links, not custom schemes.
6. Android: set public `ANDROID_APP_LINK_SHA256_FINGERPRINTS` in the selected
   tenant's project.conf to its **Play App Signing** SHA-256 certificate(s),
   comma-separated. Run normal configuration generation. Empty input intentionally
   generates `[]` and is **not verified Android readiness**. Verify the served
   assetlinks.json, package and installed signing identity on a device before
   enabling its row. iOS: verify generated AASA/associated-domain bundle identity,
   warm and cold callbacks on a device, and resolve Apple 4.8 before release.
7. With an explicitly authorized synthetic/test account, run live Google E2E:
   existing-account proof, repeat login, wrong tenant, new registration, external
   mailbox, cancel/retry/expired callback, password reset, MFA, unlink, deletion,
   refresh/logout and preserved ticket/program permissions. Never use real account
   mutations merely for screenshots. Test SMTP delivery and phone MFA separately.
8. Enable only validated platform rows. No other prod/* branch is in scope.

```sql
INSERT INTO public.external_login_clients
  (client_id, organization, platform, origin, redirect_uri, enabled)
VALUES
  ('1:web:https://live.festapp.net',1,'web','https://live.festapp.net','https://live.festapp.net/google-auth',false),
  ('1:flutter-web:https://live.festapp.net',1,'flutter-web','https://live.festapp.net','https://live.festapp.net/app/google-auth',false),
  ('1:android:https://live.festapp.net',1,'android','https://live.festapp.net','https://live.festapp.net/app/google-auth',false),
  ('1:ios:https://live.festapp.net',1,'ios','https://live.festapp.net','https://live.festapp.net/app/google-auth',false);
```

## Security and lifecycle

Raw email normalization/prefixing belongs to SQL's format_auth_email. Resolution
uses profile UUID and organization, and validates live auth.users email/deletion/
ban. Google links use verified issuer/sub plus organization, never automatic email
linking. Existing accounts require fresh password proof for first linking and
unlinking. A linked MFA account requires password plus its verified GoTrue TOTP
or phone challenge. The broker holds the proof session encrypted and returns it
only after verified AAL2; it never labels a recovery session AAL2. Unsupported
factors fail closed. No application JWT signer or auth.sessions writer exists.

Non-MFA internal session issuance uses recovery generateLink + verifyOtp under a
shared 120-second per-user lease and 20-second overall deadline. Dedicated Auth
clients bound HTTP to 8 seconds. QR login and cancellation/global revocation share
this issuer. Uncertain remote responses quarantine the lease until TTL; retry
means starting a new attempt. Recovery proofs/action links stay server-side.

Browser bootstrap sets host-only Secure HttpOnly SameSite=Lax cookies. Attempts
last 10 minutes, handoffs 60 seconds and are consumed once with a client verifier.
Continuation secrets rotate and exist only in live client memory; native cold-start
verifiers use secure storage, web uses tab sessionStorage. Callback URLs contain
only the short-lived handoff, and are removed synchronously on startup.

External Google mailboxes require a fresh attempt-bound HMAC code, maximum five
tries; registration policy must be exactly true. Profile, original registration
unit and manager/editor initialization, identity link and readiness are one SQL
transaction. Random unknown passwords are never shown/emailed. Original password
reset remains the supported recovery route.

Account deletion explicitly invalidates email/subject attempts, links and leases
before deleting the public profile; FK cascades also cover direct profile/Auth
removal. Hourly cleanup removes expired attempts/leases and old rate counters.

## Operations and rollback

Leave GOOGLE_AUTH_TRUSTED_IP_HEADER unset unless the gateway removes incoming
values and supplies that header itself. Global/client/attempt/target rate limits
remain active without it. Tokens, codes and passwords must not enter logs.

Disable external_login_clients.enabled for the affected client to stop new and
pending attempts and hide its CTA. Preserve identity rows and users. Existing
password login/session/refresh continues; revoke already issued sessions only
under a separate approved operation. Do not roll back by deleting Google-created
users or returning to a historical backend.

## Reproducible local checks

- `deno run --allow-run=docker,fvm --allow-net --allow-read --allow-write --allow-env automation/auth/existing-user-session.integration.ts`
  creates and removes isolated synthetic Docker fixtures. Uses the exact repo
  GoTrue digest; checks JS and Flutter SDK events, UUID, prefix, password, refresh,
  logout, replay, concurrent SQL leases, deletion and real TOTP AAL2.
- Canonical SQL plus google_auth_test.sql/registration/reception/account-deletion
  assertions run inside a rolled-back local transaction. No production migrations.
- Targeted Deno protocol/broker/issuer/QR/cancel/entrypoint tests; Node client,
  generated runtime/hosting/link/config/PWA checks; Flutter panel and existing
  navigation/refresh tests. Mock Google signature/JWKS tests are not live Google E2E.
- `node automation/auth/build-visual-preview.mjs` creates a self-contained actual
  web LoginModal fixture. `python3 automation/auth/capture-visual-preview.py`
  captures it in an isolated headless agent-browser session.
- `FESTAPP_EXPORT_GOOGLE_VISUALS=1 fvm flutter test test/components/users/google_login_panel_test.dart`
  exports actual Flutter panel PNGs. These are component renders, not device-link
  or live-backend tests. Browse implementation/index.html directly from disk.

MFA protocol reference: [Supabase MFA](https://supabase.com/docs/guides/auth/auth-mfa)
and [TOTP challenge](https://supabase.com/docs/guides/auth/auth-mfa/totp).
