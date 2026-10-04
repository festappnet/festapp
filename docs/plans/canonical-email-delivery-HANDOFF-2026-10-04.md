# Canonical email delivery - implementation and production readiness handoff

## Current production readiness (2026-10-04)

The user subsequently authorized completion through production, AWS configuration, all active tenants and a real canary to bujnmi@gmail.com. The implementation branch was rebased onto authoritative main `c2c5634f72287a86a1b2f55e58ea63727f53ac0f`; a fresh fetch confirmed no missing main commits. Main requires one approving review before merge. No production migration has been performed yet. PR #266 is published and requires review.

All 11 active tenants matched generation 1 and their canonical organization: `prod/absolventskyvelehrad`, `prod/aksmcz`, `prod/cavfotofest`, `prod/csmostrava2026`, `prod/doobiscup`, `prod/farnostopava`, `prod/festapp`, `prod/festapptickets`, `prod/festivalslunovrat`, `prod/hvezdamorska`, `prod/jubileum2025`. The protected live host/database assertions passed. Live migration ledger is at 20261003210000; 34 legacy queue entries remain and SMTP is still active. Email cron is in the postgres control-plane database and schedules work in the canonical runtime database; do not run the broad database-finalization script for this rollout.

AWS console login confirmed account 274371802740, Frankfurt, sending quota 50,000/day and 14/second. A dedicated least-privilege gateway user was provisioned and the feedback CloudFormation stack reached CREATE_COMPLETE; gateway secrets remain protected outside the repository. Existing SMTP credentials cannot provide API access. Shared-account allocations must be verified before unpausing.

Validation after updating main: 105 SQL files passed, 235 Deno tests passed, 1,052 Flutter tests passed (1 skipped), 211 web tests passed (9 skipped). The bank-import integration subset passed 3 tests; 27 unrelated/service-dependent cases were skipped. Automation initially exposed two existing main issues (native PWA install suppression and a font test comparing against an obsolete migration); both were fixed and all five targeted checks passed. No load/capacity test was run.

On 2026-10-04 the gateway implementation and isolated canonical SQL authority sent two designated real canaries to bujnmi@gmail.com. SES accepted both; the user confirmed both arrived and the PDF opened. Provider IDs: plain `010701a104642a25-aa6fbf56-c5f9-4b12-aac1-66b77b8e4456-000000`; attachment `010701a104649f11-655c7f1b-773a-424b-aa8e-fc3a0c58caf4-000000`. The live preflight exposed a SigV4 canonical URI escaping bug for an email identity; the signer now double-escapes the canonical path and a regression test passes (12 targeted tests total). Provider feedback is captured by a temporary encrypted SQS canary subscription; the production HTTPS handler is not deployed or confirmed yet. The operations alarm topic still requires a monitored sink before unpausing.

The following sections retain the historical local-phase evidence and outstanding operational checklist; their earlier authorization and target blockers are superseded by the status above.

## Historical local phase

Completed locally on `implementation/canonical-email-delivery-20261003` in `/Users/miakh/source/festapp-email-delivery`, based on main `3912447c8`. The original `/Users/miakh/source/festapp` release worktree and its unrelated changes are untouched. Nothing committed, pushed, deployed or sent to a real recipient. No capacity/load test was performed.

## Delivered behavior

- One transactional PostgreSQL queue, fenced attempts, encrypted immutable prepared bodies/attachments, post-commit pg_net wake, bounded dispatcher, private SES gateway and verified durable SNS event journal. Quota/capacity is shared by all tenants using that authority. Invalid quota/account/sender/feedback configuration fails closed. In-flight/unknown sends remain budget reservations.
- Order confirmations, Fakturoid-blocked confirmations, payments, automatic/manual tickets, reminders, updates/storno, account registration/sign-in/reset/deletion, app links, Google mailbox proof and native GoTrue all use that path. Source-version and expiry checks run before preparation/send. Accepted domain post-actions are idempotent. Lock order is consistent with order mutations; a failed wake cannot block on a conflicting capacity lock.
- Older sender routes/clients and historical templates/verification links remain compatible. Missing request IDs join unresolved intents; an explicit ticket resend after a known terminal result has its own ID. Old queue IDs/logs remain; uncertain historical SMTP/implicit paid-ticket sends are unknown and require reconciliation. Legacy invitation count projection stays read-only.
- Admin order list loads summaries in the orders bundle. Failures/uncertain tickets take precedence over later successes. History/overview are permission scoped, redacted and filterable, including organization scope. Accepted, delivered, disabled tracking and no observations are distinct; tooltip shows read freshness. Public order success/QR renders immediately; a limited opaque receipt updates queued wording only after canonical acceptance, without promising delivery time.

Main sources: `database/functions/emails/`, generated migration `supabase/migrations/20261003200000_canonical_email_delivery.sql`, shared email modules and the five new routes `process-email-queue`, `send-email-gateway`, `email-provider-events`, `auth-email-hook`, `email-confirmation-status`. Runtime routing/policy/coverage/readiness artifacts and opt-in Compose/CloudFormation configuration are included. [Operator runbook](../../automation/email-delivery/RUNBOOK.md) has setup, compatibility, incident/replay and cutover steps.

Removed: SMTP/nodemailer outgoing transport and duplicate send/log ownership, direct bank-sync ticket loop, old due/remove/implicit-ticket SQL source files, old queue claim/release RPCs, old sender cron paths and two extra baseline legacy reminder functions. Historical migrations remain intact. Final migration asserts no active SQL function references `queue_emails`. Unrelated incoming bank-mail processing stays intact.

## Verification evidence

All tests used fixtures/disposable local services. No AWS calls, production queries or actual messages were used.

| Gate | Result |
| --- | --- |
| Clean main baseline + all snapshot migrations + legacy fixture + canonical migration | PASS; starts paused, preserves historical IDs/audit, quarantines uncertain sends; catalog guard removes old queue references |
| SQL domain/security/compatibility suite | 19 distinct files pass, 0 fail across the 18-file suite and added ticket-domain contract; changed queue/post-action/reconciliation contracts additionally pass the existing 3 email files |
| Deno sender/renderer/gateway/account/Google/Auth/SNS/entrypoint contracts | 74 tests pass, 0 fail |
| Deno typecheck | All 16 affected sender/worker/gateway/hook/feedback/status/Google entrypoints pass |
| Real pg_net and concurrent database connections | 1 test passes; no pre-commit/rollback wake, one coalesced committed wake, same-intent claims/begin fenced, unknown not reclaimed |
| Actual pinned GoTrue 2.189.0 | 1 test passes; signed durable recovery hook, database-outage failure, and both secure email-change links completing native verification |
| Web result/status/QR/payment-reference/lifecycle | 11 tests pass, 0 fail |
| Flutter result, order indicator/model/history | 8 distinct tests pass; organization-switch follow-up passes both history tests |
| Runtime router, infrastructure, coverage, readiness, canary and inventory | 48 tests pass; changed opt-in image/cache configuration additionally passes 6 infrastructure tests |
| Targeted Dart analysis | No errors/warnings; informational style/deprecation findings in history/result screen, ticket adapter clean |
| Generated migration consistency and git whitespace | PASS |

The isolated database is project `festapp-email-tests-pg15` at localhost:55434, with cron disabled and the queue paused. Reproduction commands are in the runbook. The SQL test runner summary must be inspected because its exit code does not represent failed files. Test localization warnings come from passthrough widget fixtures, not missing shipped translation keys.

Coverage includes retry/fatal/uncertain outcomes, accepted-write failure without resend, malformed/mismatched encrypted content before provider call, early/duplicate/out-of-order feedback, bounce precedence and suppression, durable feedback outage/replay, scoped reads, anonymous proof-minting denial, reset-token/enqueue atomicity and old-client unresolved retry, expiry recovery while paused, receipt read limits, reminder settings/deadline/payment invalidation, Fakturoid gate, unchanged deferred snapshots, attachments beyond three, accessibility/narrow layouts and nonblocking result rendering. Real SES transport, delivery timing and deployed gateway image/network bootstrap remain unverified.

## Exact unperformed operational work

1. Resolve the requested tenant and current activation generation/organization. The local configuration has empty activation fields and does not establish the Festapp tenant. SSH hostname matched `festapp-supabase-rehearsal-01`; the database/organization assertion was not completed, so live sender inventory was not queried. Use the protected connection, then assert runtime `.env` database, `current_database()` and organization before reading live data.
2. Inventory live functions/cron/Auth settings/legacy in-flight SMTP, obtain protected backups, and verify actual SES credential account/region, sender identity, production access, quota and the allocated rate/daily budget if shared with Mendelio. No quota probing by email batches.
3. Review and AWS-validate/apply feedback configuration sets/topic/subscription/DLQ/alarm/IAM under separate authorization. Build and verify the architecture-compatible digest-pinned gateway image with the complete cached dependency graph at `/opt/deno-cache`, matching `/functions` imports. Install runtime secrets only in the appropriate containers. No image/DNS/AWS deployment was performed here.
4. In approved maintenance, stop all old outgoing senders, apply only the reviewed canonical migration, install the canonical bundle/router/gateway/signed Auth hook and recovery scheduler atomically, and retain `paused=true`. Configure account/region/allocation/worker URL from verified activation facts. Confirm no outgoing SMTP or old cron remains.
5. Retarget/review the existing broad integration-canary runner before using it: its pre-existing target host/database/origin are an older rehearsal environment. Its SES check now reads canonical verified quota authority, but its unrelated live mutations were not run or authorized by this task. Never invoke it against its historical direct-IP default as a substitute for the protected tenant assertion.
6. Separately authorize designated single-message SES/live simulator canaries and stopped-worker/feedback-outage/replay/accepted-write-failure cases. Verify durable status and domain projections, record actual latency and monitor health/feedback. Unpause only after these gates pass. No load/capacity test is needed or authorized.
7. Reconcile historical unknown sends individually using actual evidence. Preserve pending/unknown payload-key readability; arrange retention/recovery and DLQ alert response. Do not bulk retry or manufacture delivered/opened status from SMTP logs. Commit/push only under separate authorization.

The [festapp-backend-access skill](</Users/miakh/.codex/skills/festapp-backend-access/SKILL.md>) requires: “Resolve the requested tenant from its project.conf and live backend-activation.json, including generation and canonical organization.” It also says: “Stop on a mismatch rather than trying another backend.” These explicit rules prevent guessing a live target from the incomplete local activation configuration. This blocks live verification, not the completed local implementation.
