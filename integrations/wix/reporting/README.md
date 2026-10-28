# Partner Billed App reporting preparation

The header-only CSV template preserves the nine columns of Wix's official
template downloaded on 2026-10-28. Sample transactions were removed. It contains
no real transactions and has not been submitted.

Source: https://dev.wix.com/docs/build-apps/launch-your-app/pricing-and-billing/report-revenue-for-partner-billed-apps

Wix requires transaction rows attributed to an app instance, USD amounts and
manual reports in addition to API events. The actual unsigned addendum supplied
to this app requires **monthly reporting within 15 days**, overriding reliance
on the public guide's quarterly/monthly threshold. Retain the actual source
amounts, exchange rate, service-fee calculation and refund relationship.

API: `POST https://www.wixapis.com/apps/v1/billing-event`, authenticated as the
Wix app/user with `Manage Your App` permission. A browser-provided instance ID
must not grant backend authority or establish billable attribution.

Source: https://dev.wix.com/docs/api-reference/app-management/app-billing/external-billing-events/report-external-billing-event

## One preparation path

`prepare.mjs` consumes settled service-fee receipts and produces both the CSV and
API request bodies from a single normalized projection. It does not calculate
or collect the organizer's percentage-based service fee. That belongs to the
authoritative service-fee settlement process, separate from ticket-buyer payments.
Neither bank transactions nor Stripe ticket payments are fee receipts.

```sh
pnpm run billing:prepare .private/settled-fees.json .private/report-2026-10
```

The output directory must be new and inside `.private`. Files are private and
contain no tokens. The manifest records a deterministic digest and explicitly
marks the batch **prepared-not-submitted**. Public widget packaging does not
include the reporting module or its inputs/outputs.

Input schema version 2 contains `period` (`YYYY-MM`), `agreement` and `receipts`:

- Agreement: actual approval `reference`, `attributionPolicyReference`,
  `refundPolicyReference`; affirmative `serviceFeeOnly`, `grossTicketValueExcluded`,
  `externalTicketCheckoutApproved`, `partnerBillingApproved`,
  `refundTreatmentConfirmed`; explicit
  `refundConversion: "original-charge"`. These declarations require actual
  evidence. The current unsigned addendum does **not** satisfy them.
  `../billing/approval.mjs` owns this approval gate for both reporting and the
  marketplace release check; neither has its own weaker approval path.
- Every receipt: unique `id`, `kind` (`charge`/`refund`), `sourceReference`,
  `productName`, ISO UTC `occurredAt` with milliseconds, `currency`,
  `amountBasis: "settled-service-fee-excluding-tax"`, positive integer string
  `feeMinor`, nonnegative integer string `agreedExpensesMinor`, `instanceId`
  and `instanceVerificationReference` from trusted server-side verification.
  `refundSequence` is a required integer string assigned by SQL: zero for
  charges, positive and contiguous per original allocation for refunds.
- Every charge: the applicable historical `wixShareBps` (including an explicit
  zero when applicable), `fx` with integer-string `usdMinorNumerator`,
  `sourceMinorDenominator` and accounting evidence `reference`.
  It also requires `organizerAgreementReference`, the individually agreed
  `organizerFeeRateBps`, `customerOrigin: "wix"` and
  `customerOriginEvidenceReference`. There is no default organizer percentage.
  Fee settlement remains the source's responsibility; this projection records
  its agreement evidence without recalculating buyer payments as service income.
  Pre-existing non-Wix customer revenue must be excluded by the authoritative
  export; attempting to include it here rejects the batch.
- Every refund: `chargeReceiptId`; same currency, instance and product as the
  charge. Supply the original charge and all preceding refunds even when they
  fall outside the selected month. They are validated before period filtering.
  USD refunds and share use cumulative differences at the original charge's
  conversion/rate, preventing rounding drift across partial refunds. This policy
  must be agreed before operational use. Nonzero expenses need an
  `expenseApprovalReference` on the affected receipt.

USD amounts exclude organizer ticket proceeds. Both output formats use exact
integer arithmetic and the same rounded amounts. The API body is intended for
an app-instance-scoped token; the separately retained instance identity is for
dispatch scope, not an untrusted body parameter. References in an offline file
are provenance assertions, not proof of authentication or external approval.

Authenticated installation attribution and atomic order provenance are implemented
and tested locally, but not deployed; see `../billing/CHECKOUT-ORIGIN.md`.
The canonical platform service-fee source, acquisition records and delivery journal
are now implemented locally under `database/functions/service_fees/` and
`database/functions/wix_billing/`. They contain no real business records and are
not deployed or activated. The server exporter consumes only that canonical
source; see [architecture](../../../docs/architecture/service-fees.md) and
[delivery operations](../billing/DELIVERY.md). An external accounting feed,
actual agreements/paid fee invoices, acquisition evidence and executed Wix terms
are still operational prerequisites. Unknown provider outcomes require evidenced
operator reconciliation; no automatic retry is provided.
Do not report ticket face value as app revenue, infer an approved revenue-share
base/rate, emit fabricated events or submit an empty report as real activity.
The written commercial clarification is recorded in
`../evidence/commercial-clarification-20261028.json`; final addendum execution
and Partner Billed activation remain outstanding. No report or API request was sent in this task.

## Immutable refund ordering - reporting version 2

The canonical SQL exporter now returns `{schemaVersion: 2, receipts: [...]}`.
Each charge has `refundSequence: "0"`; each refund has a positive integer-string
sequence assigned under its customer's unit lock, independently for its original
allocation. Caller input cannot select the sequence. Full history must contain
contiguous sequences starting at one. The projector rejects duplicates, gaps and
v1 inputs, and the journal rejects events without this v2 basis.

One USD projector computes cumulative deltas in that committed order before
sorting output by the actual settlement time. A backdated imported refund appends
to the sequence and cannot change previously projected receipt payloads. Its
reported transaction date remains the real settlement date. Late facts can
require an amended period report; they never rewrite earlier event amounts.

Reportable allocation metadata is validated atomically at source admission,
including original FX evidence and integer share. Source references retain the
external source reference; allocation identity is the separate receipt UUID.
No synthetic source-reference suffix can push an otherwise valid reference
past the export contract's limit.
