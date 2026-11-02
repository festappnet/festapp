# External billing delivery operations

Integrity review as of 2026-10-28: the three P2 findings in the
[independent critic report](../../../docs/plans/wix-partner-billing-CRITIC-2026-10-28.md)
are fixed, re-reviewed and deployed by migration `20261028160000`. Reporting uses
version 2 with source-assigned immutable refund sequences; old formats fail closed.
Billing still requires the actual commercial prerequisites below. Unknown
reconciliation must fence the old worker before authorizing another send.

Server-only code: `dispatcher.mjs`; canonical SQL: `database/functions/wix_billing/`.
Economic source and import contract: [service fees](../../../docs/architecture/service-fees.md).

The 2026-10-28 official API review found one reporting POST and no documented
business idempotency key or event lookup. This is a documentation finding, not
proof Wix has no internal reconciliation. References:

- [OAuth](https://dev.wix.com/docs/build-apps/develop-your-app/auth/authenticate-using-oauth)
- [Create token](https://dev.wix.com/docs/api-reference/app-management/oauth-2/create-access-token)
- [Report event](https://dev.wix.com/docs/api-reference/app-management/app-billing/external-billing-events/report-external-billing-event)
- [Sample flows](https://dev.wix.com/docs/api-reference/app-management/app-billing/external-billing-events/sample-flows)

Use OAuth client credentials with the original installation's `instance_id`.
Verify the returned token through token-info before reporting. The provider
receipt must match app, installation, time, kind and every projected USD amount.
REST snake_case and the documented camelCase object fields are decoded explicitly;
conflicting aliases fail. Tokens and arbitrary provider errors are never persisted.
An uninstalled installation may prevent OAuth; this implementation holds the event
for operator resolution rather than adding an unreviewed account API-key fallback.

## State and recovery

`prepared -> sending -> confirmed | rejected | unknown`.

Atomic SQL claim permits one attempt. An expired `sending` lease becomes `unknown`
and never grants another send. A claim is committed by the RPC before provider
I/O. The attempt UUID fences finalization and reconciliation. The original payload
and SQL digest cannot change under the stable app/receipt/kind key.

Timeout, lost response, 5xx, ambiguous statuses, malformed success and wrong-instance
success are unknown. Explicit validation/auth/precondition errors are rejected;
none is automatically retried. Authentication failure before the billing POST is
recorded as rejected with no billing effect. A missing finish acknowledgement is
recovered through inspection after the lease expires. Refund delivery additionally
requires the original charge to be confirmed for the same installation.

For unknown or rejected events:

1. Inspect and retain receipt ID, kind, attempt UUID and payload digest. Stop
   the original sending worker and verify it cannot resume, retaining process
   termination/fencing evidence with the operator record. An expired SQL lease
   does not stop a paused process from making a future HTTP request.
2. Obtain authoritative Wix evidence for that exact installation, timestamp,
   amounts and attempt window. With no documented lookup endpoint, use provider
   support/reconciliation records. Absence from a local log or an arbitrary delay
   is not proof the POST was rejected.
3. Record `accepted` only for confirmed provider acceptance. Record
   `proven-not-accepted` only with evidence no delayed acceptance can occur; this
   reopens the same immutable event for an explicit new attempt. If evidence is
   inconclusive, leave it unknown. Never resolve by creating another receipt ID.

The reconciliation RPC requires the current attempt and digest, evidence reference
and operator reference, and appends the decision without erasing attempt history.
A second caller holding an earlier attempt cannot authorize another send.

## Commands and activation

Use pnpm 11.24.0 in `integrations/wix`. Inject `SUPABASE_URL`,
`SUPABASE_SERVICE_ROLE_KEY` and `WIX_APP_SECRET` through the existing protected
server runtime/secret environment. No secret arguments, browser code, public
cron or checked-in environment file. These are operator commands, not an Edge
HTTP route; no new public ingress or Functions restart is required for them.

```
pnpm run billing:operations export <organization> <YYYY-MM> <approval.json> .private/settled-fees.json
pnpm run billing:prepare .private/settled-fees.json .private/new-report
pnpm run billing:operations stage <organization> <YYYY-MM> <approval.json>
pnpm run billing:operations inspect <receipt-uuid> CHARGE
pnpm run billing:operations dispatch <receipt-uuid> CHARGE
pnpm run billing:operations reconcile <receipt-uuid> CHARGE <attempt-uuid> <digest> accepted <wix-evidence-reference> <operator-reference>
```

Stage/export obtain amounts from the canonical DB only. The approval JSON uses
the existing shared approval contract; it contains no receipt amounts. Stage older
periods and confirm their charges before dispatching later refunds. Export or
staging never dispatches. Empty batches are not submitted as real activity.

`wix_billing_activation.enabled` defaults to false. There is deliberately no
activation CLI/RPC. A reviewed operational SQL change must record actual executed
addendum, native activation, settlement source and acquisition evidence, then enable
that app. Its signed addendum reference must equal the projected agreement
reference. Such a change is blocked until those facts exist. No operational secret
provisioning, activation or real event was performed in this implementation.

## Zero-value BI qualification

Completed: Wix approved the zero-value protocol on 2026-10-29, the single attempt
returned HTTP200, and Erel confirmed BI ingestion on 2026-11-01. See the
[completion receipt](../evidence/bi-verification-completion-20261101.json).
The shared journal is confirmed. Do not send again or remove the attempt fence.
Normal billing remains a separate activation decision. The preparation procedure
below is retained as history, not an instruction to make another attempt.

Wix requested a BI event on 2026-10-29. The existing live instance-scoped OAuth
and token-info checks succeeded; this does not prove billing permission or BI
receipt. The API documents charges/refunds, without a dedicated test flag.
A zero-only qualification proposal has been sent to Erel; vendor acceptance is
still awaited. See `../evidence/bi-verification-preparation-20261029.json`.

`qualification.mjs` reuses the production provider and strict dispatch response
checks, with one fixed owned QA installation and CHARGE gross/net/share USD0.
It never creates settlements, normal delivery rows, refunds or activation.
No sender parameters can select another installation or monetary amount.
`pnpm run billing:qualify inspect` reads local attempt state without network I/O.

After independently verifying Wix's actual approval of this exact zero-only
protocol, retain a private operator-reviewed JSON receipt with schemaVersion1,
the assigned appId and QA instanceId from `qualificationTarget`,
zeroValueChargeApproved=true and wixApprovalMessageId pointing to that approval.
The existing preparation receipt is not approval and is rejected. A supplied
message ID is an operator assertion, not automated verification of vendor consent.
Inject WIX_APP_SECRET only through the protected process environment and run:

```
pnpm run billing:qualify send .private/reviewed-zero-qualification-approval.json
pnpm run billing:qualify inspect
```

The sender reserves an exclusive mode600 JSONL attempt in the repository's git
common directory, so all its worktrees share the same fence. Its timestamp,
payload and reviewed approval reference are synced to disk, including the parent
directory, before OAuth or billing provider I/O. Any existing attempt blocks
another send, including authorization rejection, process death, unknown response,
partial file or confirmed delivery. There is no reset or retry command. Preserve
and reconcile such evidence with Wix instead of deleting the file or using
another clone. A new supported protocol requires a separate reviewed decision.

A confirmed local result proves strict response matching; Erel must still verify
BI ingestion. Zero values cannot validate fee, FX or revenue-share arithmetic.
The single approved zero-value qualification POST is now confirmed; the normal
activation gate remains.
