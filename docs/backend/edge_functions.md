# Supabase Edge Functions Reference

## Reception QR authentication

`exchange-login-qr` is the only anonymous authentication exception. It accepts
only `POST {"payload":"festapp-login:v1:<occasion>:<opaque-token>"}` and is
deployed with JWT verification disabled. It hashes the token, asks a
service-role-only RPC to verify the active credential, membership and enabled
`reception` feature, then exchanges an Admin-generated magic-link proof for a
normal Supabase session. Responses use `Cache-Control: no-store`; payloads,
identity details, generated links and session tokens must never be logged.
It needs `SUPABASE_URL`, `SUPABASE_ANON_KEY`,
`SUPABASE_SERVICE_ROLE_KEY`, and a stable `QR_RATE_SALT`.

`cancel-reception-registration` requires the caller JWT. Its SQL command first
marks the receipt cancelled and removes occasion membership (which cascades the
QR credential). Only after that commit does the function attempt a global Auth
sign-out for the target. An Auth failure returns
`domain_blocked_auth_revocation_pending` and a retry completes the pending
revocation. Global sign-out revokes refresh sessions; it does not promise that
an already issued access JWT dies before `exp`. Immediate occasion protection
therefore comes from membership removal and membership checks on private roots
and writes.

## Overview

Deno-based edge functions for privileged operations, external API calls, and
email delivery. Functions deployed with `--no-verify-jwt` must enforce their
own user, system-secret or verified-provider boundary. `instance-install` is a
bootstrap-only remote-SQL tool and must not be deployed to canonical production.

## Function Inventory

| Function | Purpose |
|----------|---------|
| `cancel-reception-registration` | Cancels reception membership first, then revokes the user's refresh sessions. |
| `confirm-account-deletion` | Inspects a deletion token and performs the confirmed Auth, Storage and notification cleanup. |
| `exchange-login-qr` | Exchanges a bounded one-time reception QR/manual code for a normal user session. |
| `notify` | Push notifications via OneSignal, triggered by DB webhook. Supports targeted and broadcast sends. |
| `register` | User registration: creates user via RPC, sends welcome email with sign-in code and platform links. |
| `request-account-deletion` | Creates an opaque deletion request and sends its confirmation link to the resolved delivery address. |
| `send-app-links` | Sends CSM application links and records their delivery state idempotently. |
| `send-email` | Enqueues transactional order email; legacy `processQueue` only wakes the canonical worker. Template codes: `TICKET_ORDER_STORNO`, `TICKET_ORDER_UPDATE`, `TICKET_ORDER_REMINDER`. Strategy Pattern for data gathering. |
| `send-custom-email` | Editor-initiated custom email. Validates editor role, then sends with provided template/substitutions. |
| `send-sign-in-code` | Resets password and sends sign-in code through the delivery resolver (`email_delivery`, otherwise `email_readonly`). Used by admins/editors to invite users. |
| `process-email-queue` | The only SES sender; drains all message kinds through the global SQL gate. |
| `auth-email-hook` | Verifies signed GoTrue callbacks and persists encrypted Auth email intents in the same queue. |
| `send-reset-password-link` | Self-service "Forgot Password" flow. Looks up by `email_readonly` and uses the same delivery resolver. |
| `send-ticket-order` | Creates/replaces an order through one receipted RPC; confirmation effects are queued transactionally. |
| `send-tickets` | Enqueues PDF ticket email through the canonical global queue. |
| `report-exchange-rates` | Verified-user, fixed CNB endpoint proxy; one-hour cache, dated indicative CZK rates, no event data or service-role path. |
| `preview-ticket-layout` | Unit-editor JWT only; resolves local editor resources or explicitly generates a synthetic PDF through the existing ticket functions, without writes. |
| `download-ticket` | Returns a single ticket PDF as Base64 JSON for in-app download. |
| `fetch-transactions` | Syncs bank transactions from FIO API for an occasion. |
| `synchronize-orders` | Batch-syncs transactions across all fetchable accounts (cron). Matches legacy, unapproved accounts; email dispatch is independent of this cron. |
| `instance-install` | Runs SQL scripts from GitHub for setup/migrations (tables, functions, policies, seeds). |
| `fetch-http-data` | Authenticated occasion-editor image fetch. Rejects private/local DNS and redirect targets, non-images and responses over 10 MiB. |
| `bank-mail-parser` | Receives AWS SNS bank confirmation emails, parses transaction details, inserts into DB. |
| `generate-order-agreement` | Generates the tenant-configured PDF order agreement using `pdf-lib`; tenant identity is supplied through the canonical configuration boundary. |

## Test coverage contract

`supabase/functions/test-coverage.json` maps every Function in the production
runtime policy to executable smoke and behavior tests. The sole excluded
Function is operator-only `instance-install`; its exclusion is proven by the
production bundle tests. The repository preflight fails when a Function is
missing from the matrix, a mapped test does not exist, or runtime policy and
test scope diverge.

`automation/test_all.sh` runs both established Deno naming conventions,
`test_*.ts` and `*_test.ts`. `_shared/edgeEntrypoints_test.ts` captures the real
registered HTTP handlers and verifies that every production entrypoint is
reachable and rejects invalid or unauthenticated input before privileged work.
Deeper per-Function tests cover authorization, retry/idempotency, provider
verification, bounded network access, templates, delivery and canonical data
contracts.

## Auth Patterns

### `authorizeRequest` (`_shared/auth.ts`)

Dual-path authorization:

```
Path 1: Request Secret (System/Cron)
  - `requestSecret` in body, validated via `check_request_secret` RPC
  - Returns { user: null }
  - Used by: cron jobs, inter-function calls

Path 2: User Token + Editor Check
  - Authorization header + occasionId
  - Token validated, then editor role checked
  - Returns { user: supabaseUser }
  - Used by: editor-initiated actions
```

`AuthError` carries an HTTP status (401, 403); functions catch it and return the appropriate code. The default permission is order-editor access; user-management callers select `manageUsers`, which matches the Users admin UI's manager/admin/unit-editor roles.

### Direct Auth

`send-sign-in-code` creates a user-scoped Supabase client from the `Authorization` header and calls RPCs through it, relying on RLS enforcement.

`send-custom-email` validates the user token via `getSupabaseUser`, then explicitly checks editor role via `isUserEditor`/`isUserEditorOrder` using the admin client (no RLS).

### Webhook-triggered (No Auth)

`notify` is triggered by DB webhooks; `bank-mail-parser` is triggered by AWS SNS. Neither performs user auth. Both use the service-role admin client.

## Deployment

```bash
supabase functions deploy <function-name> --no-verify-jwt --project-ref <ref>
```

This command is not a blanket production allowlist. Canonical
`bank-mail-parser` requires the exact `AWS_SNS_TOPIC_ARN` and Signature Version
2. Canonical `notify` requires `NOTIFY_WEBHOOK_TOKEN` matching the
`festapp_notify_webhook_token_v1` Vault value. Both require live ingress
canaries before side effects are enabled.

Machine-invoked functions (`synchronize-orders`, `process-email-queue`, and `bank-sync-reconcile`) use `requestSecret` auth generated by `generate_request_secret` with a TTL. `send-email` retains its old `processQueue` request as a thin authenticated wake adapter.

All outbound application email goes through `public.email_messages`: registration, sign-in, password reset, signed GoTrue Auth hooks, tickets, order notices, custom editor messages and account deletion. Producers create durable intents; only `process-email-queue` receives SES credentials and sends. `claim_email` and `begin_email_send` enforce the same global account capacity, quota, priority, pause, outage circuit and one-shot send fence for every message kind. Security messages have higher priority, not a budget bypass.

A paid BankSync webhook follows the existing SQL matcher into the paid order transition and `enqueue_paid_order_tickets`. The ledger, order/ticket eligibility, immediately due email intent and inbox receipt commit together. `enqueue_email` schedules `wake_email_worker` via pg_net after commit, so normal delivery does not wait for the bank synchronization cron. The global email gate can defer delivery; recovery cron resumes the same intent rather than creating another send path. If creation of the paid transition or ticket intent fails, payment recalculation raises and the webhook remains retryable.

Keep bank-provided dates separate from detection and delivery timestamps: bank statement facts do not promise an exact real-time posting timestamp. API polling and bank availability still determine when BankSync can first observe a movement.

## CORS Pattern

Most functions share this pattern (exceptions: `notify` and `bank-mail-parser`, which have no CORS handling):

```typescript
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};
```

- `OPTIONS` preflight returns `200` immediately.
- Every response (success or error) includes CORS headers.
- `AuthError` instances return their status code; all others return `500`.
# Account deletion

`request-account-deletion` accepts only authenticated `POST {}` requests, derives the identity from the JWT, stores a SHA-256 token hash and sends `ACCOUNT_DELETION_CONFIRM` through the shared template/wrapper delivery boundary. `confirm-account-deletion` permits side-effect-free `GET` inspection and performs deletion only on explicit `POST {token}`. It owns Supabase Admin hard-delete and OneSignal Delete User by `external_id`; transient vendor failures stay in the durable `processing` state.

Required secrets/config: the existing Supabase URL/anon/service-role and canonical queue configuration, `ACCOUNT_DELETION_ORGANIZATION_ID` matching the reviewed backend
manifest `organizationId` (currently target organization `12`; `9` is only the
pre-merge source ID), and optional `ACCOUNT_DELETION_CONFIRMATION_URL`.
`ONESIGNAL_APP_ID` remains non-secret organization configuration, while the REST
credential lives only in `organization_notification_secrets` and is readable
through the service-role-only delivery-config RPC. Never log tokens, UUIDs,
email addresses, or delivery credentials.

## Google OIDC broker

`google-auth-start`, `google-auth-callback`, and `google-auth-complete` share
`_shared/googleAuthFlow.ts`. They are anonymous proof endpoints with exact client
registry/origin, cookie, Google signature/nonce, one-use handoff and continuation
checks. Their routes are explicitly exempted in the pinned runtime router; no
other Function becomes anonymous. Identity/attempt/lease writes remain service
role only. Capability stays hidden until all private inputs and an enabled client
row exist. Google is not configured as a parallel GoTrue OAuth provider.

Organization admins control `organizations.data.IS_GOOGLE_LOGIN_ENABLED` through
`update_organization_admin`. That writer atomically projects the flag onto each
client's `enabled` capability. Operators approve a client with `provisioned=true`;
when provisioning, set `enabled` to the organization's current flag. The schema
rejects enabled but unprovisioned clients, so an organization switch cannot expose
unfinished native or other clients. Backfill preserves previously enabled clients.
Turning the switch off blocks new attempts and subsequent broker transitions but
keeps linked identities. `IS_REGISTRATION_ENABLED` continues to govern new users
independently of Google sign-in.

The common `_shared/issueExistingUserSession.ts` also owns QR login and cancellation
revocation recovery minting, with database leases and UUID checks. Google MFA
uses an encrypted proof session and real GoTrue challenge, never OTP-derived AAL2.
See [the operation guide](../operations/auth/google-sign-in.md) for configuration,
rollout, cleanup, native links and rollback.
