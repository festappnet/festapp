# Wix ticketing revenue scope - investigation, 2026-10-28

## Recommendation

Keep native distribution, free installation, direct organizer payments and a
percentage-based Festapp service fee. Use a Custom plan to disclose the connected
service, not a new app subscription. Obtain a precise acceptance of the
service-fee reporting basis before executing the current addendum. This is one
commercial interpretation to confirm, not a redesign of checkout or pricing.

## What the payment architecture establishes

- Forms and payment records reference a configured bank account; bank accounts
  are linked to organizer units. See `database/tables/tables.sql`,
  `public.forms`, `eshop.payment_info` and `eshop.unit_bank_accounts`.
- Stripe requests use the specific connected-account scope in
  `supabase/functions/_shared/stripe/provider.ts`. The facts boundary explicitly
  rejects platform application fees, transfers and on-behalf-of payments in
  `supabase/functions/_shared/stripe/facts.ts`.
- The published service terms identify the event organizer as responsible for
  the event, its price and payments, and Michael Bujnovský as the technical
  system provider. See `automation/release/legal/terms.cs.md`.

This is strong evidence for a direct-to-organizer architecture. It is not an
audit proving ownership of every configured live bank or Stripe account. It
also does not make ticket payment facts into collected Festapp service fees.
The owner has confirmed an individual percentage-based fee per organizer
contract, with no global default. An authoritative fee settlement/export process
has not yet been identified.

## Why the legal ambiguity is real

The general agreement's section 9.3 describes amounts paid to Wix or the Partner
for use of the app and related Partner income. That supports a service-income
interpretation. However, the actual supplied addendum's B.2 expressly extends
the definition to end-user orders and transactions through the app, with listed
deductions for processing, reversals and taxes. It does not expressly deduct
organizer proceeds or clearly restrict the definition to sums received by us.
The addendum states that it prevails where terms conflict.

Therefore direct-to-organizer payments strengthen our position, but do not prove
that contractual share is limited to accounting revenue. Conversely, the broad
wording does not prove Wix intends to charge our entire unrelated portal business.
Neither extreme is an established fact for this app. A generic marketplace
example or another vendor's pricing cannot prove our individual agreement.

The USD 500 provision is an accumulation threshold, with quarter-end payment
required even below it. It is not a registration fee or minimum revenue charge.
The actual addendum requires monthly reports within 15 days. No separate
one-time publication fee was found in the reviewed documents.

## Concrete acceptance test for Wix

Illustration only, before tax/FX and not our actual agreed tariff:

| Movement | Amount | Reporting interpretation to confirm |
| --- | ---: | --- |
| Buyer pays organizer for a ticket | CZK 1,000 | Organizer proceeds; excluded from our reportable service income |
| Organizer separately pays our service fee | CZK 50 | Our app revenue for the Wix-attributed sale |
| Wix share at a 20% rate | CZK 10 | Share of the CZK 50 service fee |

Ask Wix to accept this exact calculation and reflect it in the addendum or the
applicable written clarification before execution. Do not silently place an
override into the app-description field or sign a corporation declaration for
a sole trader. A response that merely repeats “Partner Billed App” or its rate
does not answer the calculation.

The base question was included in today's sent reply `1a1819ad29c4274a`.
After the owner instructed us to resolve the identified issue and continue,
the concrete follow-up prepared as draft `r-3627929290758998176` was sent as
`1a1824973badc261` in the same expert thread. It asks Wix to accept this
calculation and provide the appropriate written terms, plus sole-trader wording.
Erel replied in message `1a1825fe56ce9706`, confirming service-fee-only reporting,
external checkout, no separate publisher fees, original-instance refund reporting
and exclusion of pre-existing non-Wix customers. The commercial-base question
is resolved in writing. Sole-trader wording remains unanswered; follow-up
`1a18267de29c3241` asks for it without signing the corporation declaration.

## Portal defect resolved during this investigation

Native readback initially showed `businessModel: FREE`, no plans and
`isExternalBilling: false`. The supported Add Plan screen offers Custom billing
with a text pricing structure. After saving a single `Ticketing service` Custom
plan, refresh and native API readback show `businessModel: DYNAMIC` with the
correct persisted text and benefits. This matches Wix's documented mapping of
Custom plans to the custom business model.

The plan says `Ticket-sales percentage fee`, `Free widget installation`,
`Rate agreed with organizer`, `No separate app subscription`, and
`Checkout stays in vstupenky.online`. No rate was invented, no subscription was
created and no charge was made. These are saved draft listing settings, not
an App Market publication or legal approval. `isExternalBilling` remains false.
See `../evidence/pricing-20261028.json`.

## Canonical implementation boundary

1. Existing order/payment SQL remains the sole authority for buyer payments.
2. The real organizer agreement owns the service-fee percentage and recognition.
   A fee invoice/settlement producer must explicitly supply actual collected
   service fees. Do not estimate them inside a Wix report from total ticket sales.
3. A Wix host token is verified by the backend using Wix's documented token-info
   route. The instance is provenance for attribution, not Festapp authorization.
4. Erel requires the installation associated with the sale and excludes revenue
   from pre-existing customers who did not originate through Wix. An order
   provenance record alone does not establish customer acquisition eligibility;
   the fee export must supply evidence for both.
5. Capture server-verified origin once for the checkout and preserve it in the
   order and direct-link handoff. Do not trust URL instance IDs, retroactively
   reattribute orders or infer origin solely from referrers.
6. The existing local preparer consumes settled fee receipts and projects the
   same USD amounts to monthly CSV and API events. Its approval predicate is
   shared with marketplace readiness. Refunds reuse the original approved
   conversion/rate under an explicitly approved policy.
7. Actual delivery needs durable confirmed/unknown outcomes. The published
   External Billing Event object has no documented business event identity for
   automatic replay protection; uncertain sends require reconciliation.

Items 1, 3, 5 and local preparation in item 6 are implemented and tested locally.
The provenance implementation uses the canonical order command and SQL, not a
second checkout. It is not deployed. Fee settlement/export, customer-acquisition
evidence and live API dispatch remain outstanding. See
[`CHECKOUT-ORIGIN.md`](CHECKOUT-ORIGIN.md) for exact boundaries and checks.

## Next steps in order

Use each organizer's actual contractual rate and identify the authoritative
settled-fee receipts and customer-acquisition evidence. Complete the sole-trader
addendum, connect a durable reporting dispatcher and verify charge/refund delivery
without fabricated financial events. Deploy the tested provenance path with its
backend and public client together, then complete the native marketplace review.
Keep one-time publisher costs zero.

## Primary sources

- https://dev.wix.com/app-market-partner-agreement (sections 8 and 9.3)
- Actual unsigned DocuSign addendum, sections B.1.3, B.2 and B.3; private PDF and
  digest in `../evidence/addendum-review-20261028.json`
- https://dev.wix.com/docs/build-apps/launch-your-app/pricing-and-billing/about-pricing-plans-and-business-models
- https://dev.wix.com/docs/build-apps/launch-your-app/pricing-and-billing/report-revenue-for-partner-billed-apps
- https://dev.wix.com/docs/build-apps/develop-your-app/develop-a-self-managed-app/supported-extensions/site-extensions/site-widgets-and-plugins/identify-the-app-instance-in-a-self-managed-site-widget
- https://dev.wix.com/docs/api-reference/app-management/app-billing/external-billing-events/external-billing-event-object
