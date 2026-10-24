# Canonical email delivery - operator runbook

The canonical queue architecture and its original deployment were recorded on
2026-10-04. Those receipts document the approved tenants, versions, acceptance
and feedback at that time; they do not establish today's pause state, installed
bundle, quotas or unresolved-message count. See the
[Edge cutover](../../docs/archive/plans/canonical-email-delivery-EDGE-CUTOVER-2026-10-04.md)
and [production record](../../docs/archive/plans/canonical-email-delivery-PRODUCTION-2026-10-04.md).
The current delivery boundary is also summarized in [SES setup](../../docs/setup/aws_ses.md).

## Routine maintenance on the existing queue

Resolve the selected tenant and canonical database through
[protected backend access](../../.agents/skills/festapp-backend-access/SKILL.md).
Inspect current queue health, provider capacity and unknown/in-flight sends
without exposing message bodies or credentials. Run the read-only
`automation/email-delivery/check-readiness.sql` against that identity-verified
target with `ON_ERROR_STOP=1`; it checks producer access and missing account
templates without sending a canary.

A change to SQL, the Function bundle/router or provider configuration needs the
exact reviewed release sequence and affected scope. Preserve snapshot encryption
keys and durable intents. Record whether the queue was already paused; do not
unpause an operator pause just because a deployment completed. Never replay the
original migration on an already migrated database. Use new forward
migrations and the [canonical bundle path](../../docs/backend/edge_functions.md#deployment).


## Authority and compatibility

PostgreSQL `email_messages`, `email_attempts`, `email_delivery_events` and `email_capacity` are the only delivery authority. Producers enqueue transactionally; `pg_net` wakes after commit; the dispatcher prepares one encrypted immutable snapshot; the same Edge Function reserves one fenced send; signed SNS events reconcile delivery. `accepted` means SES accepted the message, not delivery or a human reading it. Open/click are provider observations, not proof of reading. Disabled tracking and absent observations remain distinct.

Public sender routes and existing payload/response contracts remain adapters. Older clients without request IDs join an unresolved current intent. Explicit manual ticket resend gets its own request ID after a known terminal outcome; pending or unknown current ticket sends are joined. Existing templates, wrappers, attachment lists, OTPs and verification links remain valid. Old invitation counts also read legacy SMTP logs; these logs do not become canonical delivery proof. Old attempted sends and implicit paid-ticket backlog become `unknown`, not automatically resent. Historical IDs and dedupe tombstones remain.

The confirmation must be accepted (or explicitly cancelled/expired) before dependent order messages can send. A dead/unknown confirmation blocks successors until operator resolution. Do not cancel an uncertain parent solely to force its children through. Product edits invalidate the old version; the existing sent-order behavior remains, and an explicit resend renders the new version.

## Release checks

1. Resolve the requested tenant's `project.conf` and live activation document. Match activation generation, organization, SSH host, active runtime database and `current_database()` using the persisted `festapp-backend-agent` connection. Do not use former cloud credentials as an alternative. On 2026-10-04 all 11 active tenant activation documents matched canonical generation 1 and their configured organizations. The protected host and runtime database matched festapp-supabase-rehearsal-01 / festapp_rehearsal_20260909220601.
2. Inventory deployed sender routes, cron jobs, Auth SMTP/hook settings, function bundle, Fakturoid release/abort gates and current in-flight work. Save a database backup and a copy of runtime configuration and function bundle under the existing protected operational process. Never print credentials or decrypted bodies.
3. Resolve the actual SES account and region, verified sender and reply-to, production access, sending enabled, rate/daily quota, configuration sets and the allocation if Mendelio shares the account. Read quotas, never probe them by sending a batch. Every Festapp instance/project must use the same database authority and queue worker; separate singleton tables cannot enforce an account-wide budget. Shared external senders require explicit allocated rate/daily budget.
4. Review `feedback-infrastructure.json` against the target account, validate the template with AWS and deploy within the approved production rollout. It defines three SES configuration sets, signed SNS v2 HTTPS feedback, source-account/source-configuration-set topic policy, bounded delivery retries, encrypted 14-day SQS dead-letter retention and its alarm. Configure an existing monitored alarm topic. Record topic/configuration-set identities and confirm the HTTPS subscription. The festapp-canonical-email-feedback CloudFormation stack reached CREATE_COMPLETE on 2026-10-04. Its HTTPS subscription is now confirmed on the production handler; the owner subscription to festapp-email-operations is confirmed for bujnmi@gmail.com.
5. Build the reviewed production function bundle from clean canonical main. `process-email-queue` prepares and sends through `_shared/emailSender.ts` in the existing pinned Supabase Edge Runtime. The router removes `EMAIL_SES_*` from every other worker environment. `docker-compose.email.yml` injects these credentials into the runtime master; no separate sender service, gateway URL/token, or image is used. For upgrades, pause the queue, drain in-flight work, preserve the payload key, install the bundle/router and recreate only the functions container. The former sender container, image and staged archive were removed in the recorded deployment.

SES sender permissions: `ses:SendEmail` for the approved sender/configuration sets; read `ses:GetAccount`, `ses:GetEmailIdentity`, `ses:GetConfigurationSetEventDestinations`; and signed `sts:GetCallerIdentity` to assert credential ownership. Restrict sender/configuration-set/region where the AWS policy supports it. The authenticated `process-email-queue` worker alone receives `EMAIL_SES_ACCESS_KEY_ID`, `EMAIL_SES_SECRET_ACCESS_KEY` and optional session token. Neither ordinary functions nor clients receive AWS credentials.

Set all required variables in the overlay from the verified tenant/runtime authority, not this repository's test fixtures. Use a base64 32-byte `EMAIL_PAYLOAD_KEY`, and a signed GoTrue `AUTH_EMAIL_HOOK_SECRET` in `v1,whsec_<base64-secret>` format. `AUTH_EMAIL_PUBLIC_URL` is the public HTTPS Auth API origin; `APP_LINKS_ORGANIZATION_ID` must match activation. Preserve the payload key until all retained pending/unknown snapshots have been reconciled; rotating it without a migration makes those snapshots unreadable.

Use the exact verified SNS topic ARN. The security configuration set must have no OPEN/CLICK destination; transactional tracking can observe OPEN but cannot rewrite clicks. Engagement OPEN/CLICK is optional, only for public URLs accepted by the conservative origin/path allowlist. Queries, fragments and sensitive links disable click rewriting. The sender preflight fails closed if sender identity, credential account, quota or event/tracking configuration differs.

Approved Festapp allocation: 2 emails/second and 10,000 emails/day, as requested by the user on 2026-10-04. This is a Festapp allocation within the shared account, not an account quota increase; the queue still applies its safety reserves. Owner alerts: bujnmi@gmail.com through the confirmed operations SNS subscription.

## Incidents and feedback replay

The service-only health RPC reports queue age/states, preparation timing, provider feedback lag/unmatched events, quota freshness, worker heartbeat, circuits and post-action backlog. Tenant UI exposes scoped redacted attempts/events and prioritizes trouble over later successful messages. Admin history filters state/kind/date/order/user/occasion and can switch to organization scope; scope permissions are enforced by SQL.

Producer readiness also reports `producer_access_ok`, `missing_account_templates`,
and alerts `producer_permissions_missing` / `account_templates_missing`. These
cover failures before a queue row exists. The schema grant belongs to the shared
runtime role; anon/authenticated gain no new privileges. Account defaults reuse
the verified CSM template content with dynamic branding and the recipient
organization's wrapper. Existing template overrides retain precedence.

SQL producer contract tests switch to the actual `service_role`. The isolated
rehearsal starts with its production schema-access denial, applies the follow-up,
and runs the read-only readiness gate. Admin-only fixture tests cannot replace
these checks. Acceptance remains distinct from provider-confirmed delivery.

A successful provider send followed by a database failure stays fenced. Sending-lease expiry becomes `unknown`. Do not automatically retry it. Use provider message ID, trusted signed events or an explicit provider investigation to reconcile with `reconcile_unknown_email(message_uuid, decision, evidence, provider_id)`. Decisions are `accepted`, `cancelled` or `known_not_accepted`; `known_not_accepted` requires evidence that the provider did not accept it. Save evidence without secrets. A confirmation with a known fatal failure requires an audited operator decision about cancellation before successors can proceed.

The SNS handler returns success only after the event batch commits. Database failure returns 503; duplicate/out-of-order events are idempotent and trouble cannot be erased by a later success. Keep unmatched events for later correlation. Monitor the SNS dead-letter alarm and oldest message during outages. Replay the original signed SNS envelope from the authorized incoming DLQ workflow to the same exact-topic verifier, then confirm journal persistence before deleting the DLQ item. If SNS stored only an inner SES body, obtain a fresh authentic SNS delivery through the authorized AWS path; do not bypass signature verification or mint a fake signature. Replay feedback, never resend the original email. Logical event identity is stable across SNS redelivery IDs.

Expired/terminal sensitive ciphertext is erased by recovery; operational bodies expire after 30 days and provider events after 90 days. Dedupe tombstones and correlation remain. Keep recovery running even while paused. When enabled and idle, recovery also wakes the same worker for a missing or older-than-five-minute quota snapshot; worker reservations coalesce refreshes and no email intent is created. A cancelled/used ticket is never revived by acceptance post-actions. Payment removal, changed reminder settings/deadlines and source versions invalidate old pending intents at both claim and send.

## Historical local cutover fixture

Only the dedicated disposable database on port 55434 is allowed. Do not point these commands at production. `rehearse-local.sh` recreates only project `festapp-email-tests-pg15`, imports main snapshot `c2c5634f72287a86a1b2f55e58ea63727f53ac0f`, installs legacy fixtures and the new migration, asserts compatibility, and disables local cron. It leaves the queue paused for inspection.

The snapshot selects migration *filenames* through `git ls-tree`, but baseline
and migration bytes are read from the current checkout with `psql -f`; this is
not an immutable replay of that Git SHA. The harness installs only its selected
historical cutover/follow-up set, not the full current migration tail. Keep its
working revision and observed results with the evidence. For ordinary current
SQL regressions use [the standard local database](../../docs/setup/local_development.md).

```sh
EMAIL_LOCAL_REHEARSAL=1 bash automation/email-delivery/rehearse-local.sh
DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:55434/postgres?sslmode=disable' node web_client/scripts/run_db_tests.js /emails/ reminder surcharge storno_reminder client_sync reset_user_password_permissions deadline_change race_overpay full_deposit overpayment invitation_delivery_status update_ticket_products
EMAIL_TEST_DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:55434/postgres' node --test automation/tests/email_delivery_database.test.mjs
EMAIL_NATIVE_REHEARSAL=1 deno test --allow-env --allow-net --allow-read --allow-run automation/email-delivery/native-gotrue-test.ts
```

The current SQL runner exits nonzero for files still failing after sequential retry. Inspect its selected-file count and summary too: a filter matching no tests exits zero. The pg_net test sends one local machine wake and races the same intent across two connections. The pinned GoTrue test uses no SMTP/SES and checks signed enqueue, outage, and both secure email-change links. None of these is a load or synthetic batch test.

Provider contracts: [SES SendEmail](https://docs.aws.amazon.com/ses/latest/APIReference-V2/API_SendEmail.html), [SES GetAccount](https://docs.aws.amazon.com/ses/latest/APIReference-V2/API_GetAccount.html), [STS identity](https://docs.aws.amazon.com/STS/latest/APIReference/API_GetCallerIdentity.html), [signed Auth hook](https://supabase.com/docs/guides/auth/auth-hooks/send-email-hook), [self-hosted hooks](https://supabase.com/docs/guides/self-hosting/self-hosted-auth-hooks), [SNS topic signature configuration](https://docs.aws.amazon.com/AWSCloudFormation/latest/TemplateReference/aws-resource-sns-topic.html).

### Disposable ticket-mode rehearsal

After preparing a dedicated local database named `festapp_ticket_email_*` with
current canonical SQL and isolated fixtures, run from `web_client`:

```sh
DATABASE_URL=postgresql://postgres:postgres@127.0.0.1:57322/festapp_ticket_email_20261023 \
  pnpm exec node ../automation/email-delivery/rehearse-ticket-delivery.mjs
```

The runner rejects nonlocal or differently named databases. A rollback-only
transaction exercises paid transitions, the canonical queue, encrypted prepared
snapshots, send fencing, SES stubs, post-actions and repeated admission for all
three modes. The Deno adapter has no network permission. No provider credentials,
real payment or mailbox are used. It writes a self-contained email preview to
`/tmp/festapp-ticket-email-previews/index.html` (override with
`TICKET_EMAIL_PREVIEW_DIR`). These generated codes cease to exist after rollback.
This does not replace approved real-mail-client checks before production inline
activation.
