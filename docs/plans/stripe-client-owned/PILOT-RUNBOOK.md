# Stripe pilot preparation - not an authorization to deploy

Status: implementation and local evidence only. No production migration, runtime restart, cron installation or enablement has been performed. The execution prompt prohibits production operations without a later instruction. Actual JS and Flutter test purchases, signed webhooks and cross-site CMS handoff have local sandbox evidence. Existing sandbox-account OAuth/Google, both waitlist offer paths, cancellation/refund decisions and disabled-sales recovery now have actual evidence. Physical native devices, manual assistive screen-reader checks and the selected production host remain acceptance gates in [IMPLEMENTATION-STATUS.md](IMPLEMENTATION-STATUS.md).

## Hidden integration state - 2026-10-22

[INTEGRATION-READINESS.md](INTEGRATION-READINESS.md) owns the prepared main patch and current local proof. Keep `FESTAPP_STRIPE_PREVIEW=false` (the default) and SQL `new_payments_enabled=false`. Admin discovery, direct card settings and form-method configuration are hidden in an ordinary build. Neither a preview build nor connecting an account authorizes sales. Current local fresh/upgrade replay is complete; the older replay paragraph below describes the gate that must be preserved for a later authorized source revision. The full client wrapper currently references a missing upstream architecture checker; resolve that gate before claiming a full release validation.

## Pilot boundary

Select one tenant organization, one organizer unit, one form and one supported currency. Start with bank + card on that form, no deposit, surcharge, Fakturoid or unverified embed/native surface. Keep the global policy disabled while installing and checking. The organizer receives direct payments in their own Stripe account, pays their Stripe fees, retains their full Dashboard, and Stripe bears connected-account losses under the verified controller model. Festapp does not collect an application fee or create transfers.

Before enabling any actual sales, record product acceptance of the fixed 31-minute reservation (Stripe minimum 30 minutes plus one minute dispatch allowance), the admission hold during a dispute, the online-only Stripe admission requirement on every scanner, refund admission decisions, and handling of late payment without capacity resurrection. These are explicit pilot gates, not defaults approved by implementation.

## Source and migration preparation

Use the canonical `main` revision plus the single selected tenant overlay. Preserve unrelated dirty work; the current implementation workspace is not a deployable source revision. Prepare a reviewed release artifact before asking for production approval.

Generate and check the three unpublished migrations with `python3 automation/assemble-stripe-migrations.py --check` and verify the canonical source contract with `python3 automation/generate_canonical_source_contract.py --check`.

Check the reserved `/stripe` root preflight and ensure no existing occasion/alias is shadowed. The admin list/history DTOs must carry `payment_method` for exact card amounts.

Apply in order only in an approved deployment:

1. `20261022160000_stripe_foundation.sql`: private tables, capability scopes, economic totals and bank pairing boundary.
2. `20261022170000_stripe_connections.sql`: actor-bound OAuth, current account observations, explicit disconnect intents and connection controls.
3. `20261022180000_stripe_checkout_ingest.sql`: immutable order attempts, checkout leases, atomic ingestion, reconciliation, admission guards, receipted refund decisions, reports and email integration.

For a later authorized release revision, rehearse against a fresh canonical baseline plus the existing prerequisite migrations. Refreshing individual local functions does not establish fresh migration replay. Verify new private tables have RLS enabled, no client policies, and no anon/authenticated direct grants; service-only functions must reject authenticated callers. Verify no persistent application triggers were added. Capture schema/function source digests and the exact migration readback.

## Configuration

Store values only in the protected runtime secret store. Never put them in the repository, receipts, browser snapshots or command output.

| Name | Required value |
|---|---|
| `STRIPE_MODE` | `test` for rehearsal; `live` only for the later approved pilot |
| `STRIPE_SECRET_KEY` | Platform key matching mode and the verified platform account |
| `STRIPE_PLATFORM_ACCOUNT_ID` | Actual platform key owner, distinct from organizer |
| `STRIPE_API_VERSION` | Pinned and rehearsed `2025-06-30.basil` |
| `STRIPE_ALLOWED_ORIGINS` | JSON array of exact approved tenant HTTPS origins |
| `STRIPE_CONNECT_CLIENT_ID` | Mode-specific Connect application ID |
| `STRIPE_CONNECT_CALLBACK_URL` | Registered approved tenant `/stripe/connect/callback` URL |
| `STRIPE_WEBHOOK_SECRETS` | JSON array, at most three current/rotating endpoint secrets |
| Existing email encryption key | Existing AES-GCM source envelope owner; preserve rotation support |

Deploy the shared Stripe boundary, both clients, existing order sender and email renderer together. The self-hosted router patch adds JWT exceptions only for `stripe-checkout`, `stripe-return`, `stripe-webhook`, `stripe-reconcile`: these enforce capability, signature or machine authentication themselves. `stripe-connect` and `stripe-connect-callback` retain JWT verification and validate the current Auth user. A JWT exception alone is never sufficient endpoint authorization.

The webhook endpoint must receive connected-account events for the selected mode, including Checkout completion/expiry, PaymentIntent success/failure, refunds, disputes, `account.updated`, and application authorization/deauthorization. Verify raw byte signature handling, exact account/environment binding and 2xx only after the SQL receipt commits. Register a separate Festapp endpoint; do not alter Mendelio endpoints.

## Recovery installation and health

`automation/hetzner-supabase/runtime/install-stripe-reconciliation.sh` is prepared but has not been executed. It requires root on the approved host, the verified canonical database name, exact `https://api.festapp.net` origin and `FESTAPP_STRIPE_RECOVERY_INSTALL_ACK=install-stripe-recovery-on-canonical-database`. Its other inputs are `FESTAPP_RUNTIME_DATABASE`, optional `FESTAPP_RUNTIME_COMPOSE_DIR`, and `FESTAPP_STRIPE_RECOVERY_ORIGIN`. Read the guard checks before execution; never bypass a rejected identity.

The installer schedules a minutely request from the postgres cron control plane into the actual canonical database. `request_stripe_reconciliation` generates the existing short-lived request secret; no static service secret enters cron command text. The endpoint starts at most ten attempt jobs and two account jobs within its bounded start budget. SQL leases fence concurrent webhook/customer/recovery work. Refund and lost-Session cursors commit with their facts and resume in later invocations. Failed observations back off and preserve prior checked-at timestamps; they do not mean the account was revoked.

After authorized installation, verify the cron database, username, active flag and exact request origin. Verify endpoint authentication rejects missing/expired secrets, and one scheduled invocation has an actual receipt. Monitor oldest due attempt, lease age, reconcile failures, incomplete refund/Session cursors, oldest account `checked_at`, status failures, uncommitted inbox entries and email delivery separately. Any persistent unresolved observation requires an operator; HTTP success alone is insufficient.

Encrypted payment sources expire after 30 days and are deleted in bounded recovery batches. Capability hashes, immutable attempts, financial facts, inbox receipts and audit history remain. Historical synchronization and nonpayable confirmation rendering do not depend on decrypting old pay links. Never delete historical financial facts to repair a link.

## Acceptance sequence

Use real Festapp order creation and emitted capabilities, rather than a provider-only probe. Record the actual UI, SQL receipt and Stripe account-scoped readback for each case:

- Existing organizer OAuth including Google sign-in, manager rights, denial/cancel/expiry and replay. Validate the full controller model before binding the recipient.
- Fresh quote and recipient; bank, free and supported card purchase; changed quote requires an explicit fresh review with answers retained.
- Ordinary payment, authenticated 3DS, decline, cancel/Back, two tabs, timeout and duplicate webhook. Returning to the page is never payment proof.
- Paid order, queue eligibility and actual email; payment, ticket validity and delivery status shown separately. Reload/resume and storage loss do not create a new order or attempt.
- Partial refund with explicit keep/cancel-unused decision and audit reason, full refund preserving used history, dispute hold and won/lost observations, late payment after capacity release.
- Online admission through each web/native/retained scanner writer; bank offline queues still work and Stripe tickets are excluded from offline exports.
- Pausing, restriction, access loss, replacement preserving historical recipient identity, explicit impact-reviewed disconnect and uncertain external response recovery.
- Mobile/desktop, keyboard focus, large text, long translations and tenant themes. Enable embed/native only after their real return/handoff and CMS/device tests pass.

Run the targeted SQL, Deno and UI gates from the status document, with exactly one Flutter task on the workstation and `--concurrency=1`. The real SQL concurrency suite clones a logical snapshot into a unique disposable database and requires the loopback `55432/postgres` harness; it cannot target production. It proves contention by observing two blocked PostgreSQL sessions before releasing the shared form lock.

## Stop new payments and recover

The immediate sales stop is `stripe_runtime_policy.new_payments_enabled=false` for the exact organization and mode, or the existing authorized unit pause control. Submit rechecks the setting under locks. Preserve all existing attempts, capabilities, sources and receipts. Keep webhook, return reads, recovery, admission and email eligibility running. A sales stop is not a disconnect and does not erase access to historic refunds/disputes.

If checkout creation is uncertain, retain its attempt, recipient, original expiry and idempotency key. Before expiry recovery uses the same key; after expiry it performs a fixed-window read-only Session search with durable cursors. No matching Session releases unpaid capacity only after the search is exhausted. A later real payment remains a fact and requires resolution without restoring released capacity.

Account disconnect is an explicit manager action with an impact check. Open/unresolved attempts prevent it. External deauthorization dispatches once; an uncertain response remains a durable intent and is resolved by a current account observation, not blind repeated deauthorization. Historical records remain, but losing provider access can prevent automatic reconciliation; explain that impact before confirming.

## Rollback

Disable new sales first and preserve the compatible database/runtime readers and money ingestion. Roll back presentation to the last compatible artifact only if it still observes existing Stripe orders safely. Do not drop payment columns/tables, convert Stripe movements to bank transactions, revoke organizer access or restore a prepayment database snapshot. Keep return routes, raw-signature webhook ingestion, reconciliation, online admission and queue fences until all affected attempts and retained history have a reviewed successor. Re-enable only after the exact failed acceptance case and affected gates pass.

## Native delivery boundary

Native pay/return capture validates the exact tenant HTTPS origin and four canonical/alias paths, separates write/read capabilities and strips them from routed paths. The inbox is process memory only; reopening the original protected email link is the recovery source after process death. Android App Links and iOS AASA are generated for those paths; existing iOS universal-link routing remains enabled. Native Connect/Replace explicitly directs organizers to the web app. Neither Android nor iOS is enabled in Stripe runtime supported_surfaces until actual device system-browser return/resume, verified tenant links and online admission pass. Unit and widget tests are not device acceptance.
