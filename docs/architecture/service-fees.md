# Platform service fees and partner revenue reporting

Platform service income belongs to a separate bounded context in `public`, beside
organization and unit contracts. Buyer orders, bank matches, Stripe payments and
organizer invoices remain owned by `eshop`. Their totals are not Festapp income.
The existing `authoring/finance.sql` is an organizer bank/refund adapter. Fakturoid
preparation in the ticket-order workflow issues organizer buyer invoices; it does
not establish collection of Festapp's own service fees.

## Canonical facts and writers

`database/functions/service_fees/source.sql` owns the service-only import/export
boundary; `database/tables/service_fees.sql` owns its relational records:

| Record | Meaning and authority |
| --- | --- |
| `service_fee_agreements` | A unit's individual, evidenced percentage and effective period. No default. Organization is captured from the stored unit. Overlapping versions are rejected under a unit lock. |
| `service_fee_customer_acquisitions` | Independently evidenced first acquisition of the unit as customer. Wix order provenance cannot create this fact. A pre-existing non-Wix customer cannot be relabelled by normal RPC. |
| `service_fee_settlements` | Imported actual payment or reversal of a Festapp fee invoice. Original invoice, payment and allocation evidence references are mandatory. Tax is a separate fact. Refunds reference the original payment. |
| `service_fee_allocations` | Complete, evidenced allocation of an actual settled fee to original buyer orders. Sum must equal the settlement; no pro-rata allocation is invented. Original orders must belong to that unit, organization and contract period. A refund references an original allocation and cannot exceed its fee, expenses or net amount. |

These are a new canonical platform fee source, explicitly authorized on
2026-10-28 after repository reconnaissance found no prior source. They are not
seeded with business data. Import is a deliberate assertion of real external
facts by a trusted server/operator. A reference alone cannot verify the external
invoice or bank payment. No external accounting account or payment feed has yet
been connected. This boundary does not issue invoices, collect fees, calculate
an amount due from ticket prices, or replace statutory accounting.

Only `service_role` can execute the writers, and each writer checks
`require_service_role()`. Browser users and tenant administrators cannot assert
platform income or acquisition. RLS and revoked table privileges prevent direct
API access, including through `service_role`. PostgreSQL administrators remain
trusted operators. No application triggers, scheduled dispatch or outbound email
are added. Any future invoice email must use the existing email queue.

Contract amendments are new versions, with explicit validity bounds. An open-ended
version may be ended through `end_service_fee_agreement`, with termination evidence,
only if no stored service falls outside the resulting period. Settled history is
not repriced. Imports use stable UUID and source references; identical settlement
replay returns the original ID, changed facts under that ID fail. Corrections to
recorded money are explicit reversals and replacement facts, not in-place edits.
Agreement and acquisition corrections require a separately reviewed operation.

## External accounting adapter

The first supported writer is an operator import via the service RPCs, backed by
an actual paid invoice and accounting/payment evidence. A future accounting API
adapter must call the same writers after verifying that provider's payment state;
never introduce another amount calculator in Wix. The provider account, credentials,
real agreements and acquisition documents are operational inputs still required.
If a single payment covers several contracts, split it using evidenced accounting
allocations and stable source references. Ambiguous allocations are quarantined
outside the canonical settled source until resolved. Recording the invoice alone
or a payment to an organizer is insufficient.

`record_service_fee_settlement({p_input})` accepts:

- UUID `id`, `agreementId`, `kind` (`charge` or `refund`), and for refunds
  `originalSettlementId`.
- `sourceReference`, `invoiceReference`, `paymentEvidenceReference`,
  `allocationEvidenceReference`; all must identify retained real evidence.
- UTC `settledAt` and `serviceAt`, ISO `currency`,
  `amountBasis: settled-service-fee-excluding-tax`, positive integer-string
  `feeMinor`, nonnegative integer-string `taxMinor`.
- `allocations`: stable UUID `id`, canonical `orderId`, positive integer-string
  `feeMinor`, nonnegative integer-string `agreedExpensesMinor`, and evidence for
  nonzero expenses. A refund also supplies `originalAllocationId`.
- A Wix-reportable charge allocation additionally supplies `partnerTermsReference`,
  historical `wixShareBps` and `fx` in the existing reporting contract. Missing
  terms keep it out of the export; missing/invalid FX prevents report preparation.
  Historical FX is evidence, not today's inferred exchange rate.

The imported total is already net of sales tax. Each allocation snapshots the
server-recorded Wix installation, original provenance record and order creation time.
The retained provenance snapshot contains no raw Wix token or signed URL. It never accepts
a client-supplied installation. Historical order IDs survive order deletion as
financial references; they confer no access to the removed buyer data. Contract
and customer records retain their foreign keys. Refunds inherit original provenance.

## Wix adapter and delivery

`export_wix_service_fee_receipts` reads only the chosen organization and the
specified partner terms. Eligibility requires both server-recorded order origin
and independent Wix acquisition dated no later than the order. Non-Wix and
pre-existing non-Wix customers are excluded. Refunds keep the original installation
and charge relationship. Export includes full prior history so cumulative refund
rounding remains correct when `reporting/prepare.mjs` filters the selected month.

`reporting/prepare.mjs` remains the sole CSV/API USD projection. The dispatcher
adds no economic calculations. `wix_billing_deliveries` and `wix_billing_attempts`
record only delivery state and immutable projected payloads. They are not a second
fee source. See the [operator runbook](../../integrations/wix/billing/DELIVERY.md).

Production activation requires actual contract/payment/acquisition inputs,
executed Partner Billed terms and verified Wix activation. The migration creates
an explicitly disabled activation row. Neither imports nor CSV preparation send
billing events. The foundation is deployed with billing disabled; see the
[deployment receipt](../operations/releases/festapptickets-wix-foundation-2026-10-28.json).

## Reporting integrity revision - 2026-10-28

The importer rereads the agreement after obtaining the unit lock, so a concurrent
contract termination is visible before validating service and order periods.
A charge allocation stores sequence zero; refunds receive an immutable increasing
`refund_sequence` for that original allocation under the same lock. Only SQL
assigns it. Actual settlement timestamps are never adjusted to fake arrival order.
The v2 exporter returns a versioned receipts envelope and the sole USD projector
uses this committed sequence for rounding, then formats actual dates for CSV/API.
Old input formats and deliveries without a v2 sequence are rejected.

A charge marked with `partnerTermsReference` must supply valid historical FX
strings/evidence and an integer Wix share. Evidence references match the
projection's control-character, whitespace and UTF-16 length requirements.
Rejected imports leave no settlement or allocations behind. Charges without
partner terms remain excluded rather than being relabelled as reportable.

The deployed migration `20261028150000` is frozen by digest. Forward migration
`20261028160000_service_fee_reporting_integrity.sql` applies the new sequence
contract only while the source and delivery journal are empty and billing is
disabled, with table locks preventing concurrent changes. It does not guess a
sequence or rewrite existing money/history. A populated target requires a separate
evidence-backed upgrade rather than bypassing this guard.
