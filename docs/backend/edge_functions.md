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
| `send-email` | Transactional emails for ticket orders. Supports single sends and batch queue. Template codes: `TICKET_ORDER_STORNO`, `TICKET_ORDER_UPDATE`, `TICKET_ORDER_REMINDER`. Strategy Pattern for data gathering. |
| `send-custom-email` | Editor-initiated custom email. Validates editor role, then sends with provided template/substitutions. |
| `send-sign-in-code` | Resets password and sends sign-in code through the delivery resolver (`email_delivery`, otherwise `email_readonly`). Used by admins/editors to invite users. |
| `send-reset-password-link` | Self-service "Forgot Password" flow. Looks up by `email_readonly` and uses the same delivery resolver. |
| `send-ticket-order` | Creates/replaces an order through one receipted RPC; confirmation effects are queued transactionally. |
| `send-tickets` | Generates and emails PDF tickets (standard or named) for an order. |
| `download-ticket` | Returns a single ticket PDF as Base64 JSON for in-app download. |
| `fetch-transactions` | Syncs bank transactions from FIO API for an occasion. |
| `synchronize-orders` | Batch-syncs transactions across all fetchable accounts (cron). Matches to orders and triggers confirmation emails. |
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

Cron-invoked functions (`synchronize-orders`, `send-email` with `processQueue`) use `requestSecret` auth. The secret is generated via `generate_request_secret` RPC with a TTL.

Ticket-order confirmation, Fakturoid and contract attachment work runs through
`queue_emails`. The order command inserts the queue row in its DB transaction;
`send-email` claims rows with `FOR UPDATE SKIP LOCKED`, retains failed rows for
retry, and uses the command UUID as the stable SMTP Message-ID and Fakturoid
`custom_id`.

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

Required secrets/config: the existing Supabase URL/anon/service-role and SMTP
values, `ACCOUNT_DELETION_ORGANIZATION_ID` matching the reviewed backend
manifest `organizationId` (currently target organization `12`; `9` is only the
pre-merge source ID), and optional `ACCOUNT_DELETION_CONFIRMATION_URL`.
`ONESIGNAL_APP_ID` remains non-secret organization configuration, while the REST
credential lives only in `organization_notification_secrets` and is readable
through the service-role-only delivery-config RPC. Never log tokens, UUIDs,
email addresses, or delivery credentials.
