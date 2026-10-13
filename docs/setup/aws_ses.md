# Outbound SES and the canonical email queue

Every outbound application email uses `public.email_messages`: registration,
sign-in, password reset, signed GoTrue hooks, order notices, tickets, custom
messages and account deletion. Only `process-email-queue` owns SES credentials
and sends; there is no SMTP fallback or producer-specific sending path.

## Delivery boundary

Producers persist durable intents. The shared renderer resolves templates and
wrappers into encrypted immutable snapshots. `claim_email` and
`begin_email_send` enforce global capacity, quota, rate, pause, suppression and
the one-shot send fence. Higher-priority security messages use the same gate.
Post-commit wakeups drive normal delivery; recovery cron resumes the same queue.

`queued` confirms persistence, `accepted` means SES accepted the send, and
provider delivery/bounce/complaint feedback supplies later transport evidence.
Compatibility `sent`/`email_sent` responses are issued only after canonical
acceptance; they do not prove mailbox delivery. Ambiguous sends require audited
reconciliation, not blind resend.

## Configuration and deployment

The host router exposes `EMAIL_SES_*` transport inputs only to the queue worker
through `_shared/emailWorkerEnvironment.ts`. Private provider and snapshot
keys belong in protected runtime inputs, never `project.conf`, client assets,
logs or documentation. SES account/region quota and the allocated shared budget
must be verified before unpausing capacity. Signed GoTrue callbacks enter through
`auth-email-hook`; `email-provider-events` verifies exact-topic SNS Signature
Version 2 feedback and persists a redacted journal.

Follow [canonical Edge deployment](../backend/edge_functions.md#deployment).
See the [shared modules](../../supabase/functions/_shared/README.md),
[email delivery design](../plans/canonical-email-delivery-plan-2026-10-03.md),
[production evidence](../plans/canonical-email-delivery-PRODUCTION-2026-10-04.md),
and [Edge cutover evidence](../plans/canonical-email-delivery-EDGE-CUTOVER-2026-10-04.md)
for key isolation, feedback/DLQ, quota, fencing and recovery gates. These dated
receipts are not a new live check or authority to change AWS/runtime settings.

## Receiving bank emails

Bank email intake belongs to [BankSync](bank_import.md). It is independent of
the outbound SES queue. The former receiving/SNS setup is preserved only as
[historical evidence](../archive/setup/aws_ses-pre-banksync.md); do not use it
to create a subscription to the retired Festapp parser or change tenant MX.
