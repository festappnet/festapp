# External billing delivery operations

Activation hold as of 2026-10-28: the [independent critic report](../../../docs/plans/wix-partner-billing-CRITIC-2026-10-28.md)
identifies three P2 source/projection defects (contract race, backdated refund
payload drift, unreportable immutable metadata). Fix and regress these before
activating billing, in addition to the commercial prerequisites below. Unknown
reconciliation must also fence the old worker before authorizing another send.

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

1. Inspect and retain receipt ID, kind, attempt UUID and payload digest.
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
