# Ticketing revenue basis - approval required

Status: **service-fee-only reporting and external checkout confirmed in writing
by Erel on 2026-10-28; addendum execution and live reporting remain incomplete**.
This document records commercial findings and the actual correspondence below.
No new agreement, paid product or marketplace application was accepted.

## Latest written clarification and account verification

Erel's reply at 11:58:04 UTC, Gmail message `1a1825fe56ce9706`, explicitly
confirms reporting only service/platform fees, excluding ticket face value and
organizer funds, retained external checkout and no separate registration,
submission, listing or recurring retention fees. Each qualifying sale must link
to its originating Wix installation. Revenue from pre-existing customers who
did not originate through Wix is excluded. Reversed service fees must be reported
against the original app instance. See
`evidence/commercial-clarification-20261028.json` for the precise scope.

The source email does not address sole-trader wording or confirm completed
Partner Billed App activation. Signing, the authoritative fee ledger/export, customer-acquisition evidence and
live reporting are still outstanding. Verified attribution capture is implemented
and tested locally, but not deployed; see `billing/CHECKOUT-ORIGIN.md`.
Follow-up `1a18267de29c3241` asks Wix for appropriate sole-trader wording. Historical
statements below about an unanswered revenue-base question are superseded by
this reply; they are not current blockers.

The account verification link for `info@festapp.net` was opened in an authorized
task tab. Wix displayed “Your email is now confirmed.” This verifies the account
address, not acceptance of a billing contract or App Market publication.

The [deeper decision brief](billing/DECISION.md) separates contractual scope from
accounting income and records the Custom-plan fix. The draft pricing model now
persists as DYNAMIC; the previously observed Free readback was caused by the
missing plan. This configuration is not evidence of external billing approval.

## Actual addendum reviewed 2026-10-28

The DocuSign email validation was completed through the owner's forwarded Gmail
message, and the unsigned three-page PDF was downloaded for review. Electronic
record/signature delivery consent was accepted to access the document; no
contract signature was applied and Finish was not submitted. The private PDF
is `.private/partner-billed-addendum-unsigned-20261028.pdf`; see its digest and
findings in `evidence/addendum-review-20261028.json`.

This changes the public-terms-only interpretation below:

- Section B.2 expressly includes amounts paid for end-user transactions through
  the app and lists deductions for payment processing, refunds/chargebacks and
  taxes. It does **not** expressly deduct the ticket proceeds owed to organizers.
  Do not sign or declare the service-fee-only basis approved under this wording.
- B.1.3 requires monthly reporting within 15 days, rather than reliance on the
  public guide's quarterly threshold.
- B.3's USD 500 is a settlement threshold, not a one-time registration or listing
  fee; amounts below the threshold are still payable following each quarter.
- The form identifies the partner as a corporation; our documented operator is
  a Czech sole trader. The correct partner wording must also be settled.

The owner confirmed an individual percentage of ticket value per organizer
contract, with no default rate. No authoritative settlement ledger or production
fee recognition rule was specified. Do
not infer that ticket-buyer bank/Stripe payments are our service-fee income.
The Stripe provider boundary explicitly rejects application fees and transfers;
this work does not alter that invariant or add a second checkout.

A follow-up was prepared as draft `r-3627929290758998176` in the existing expert
thread. After the owner instructed us to resolve the identified issue and
continue, that specific follow-up was sent as message `1a1824973badc261`, thread
`1a18198a75444077`, to `support4@wix.com`. It asks for acceptance of the concrete
CZK 1,000 ticket / CZK 50 service fee / CZK 10 Wix-share example and suitable
sole-trader wording. No new support case was opened. A local report preparer now
projects actual settled fees to both CSV and API bodies, but cannot replace
the outstanding commercial approval, ledger, attribution or dispatch work.

## Update 2026-10-28

Erel (Wix Developer Relations) replied from `support4@wix.com`, subject
`DevRel Applications Ref:065800261`, Gmail message `1a18198a75444077`.
Wix identified **Partner Billed App** as the appropriate model and requested
the Partner Billed App Addendum, manual revenue reports and External Billing
Events for charges/refunds before proceeding. This is not completed approval
of our service-fee-only revenue basis or confirmation of zero publisher fees.

A reply was sent in that thread (Gmail message `1a1819ad29c4274a`) asking for
the service-fee-only basis, retained external checkout, zero fixed publisher
fees, instance attribution, refund/chargeback treatment and a supported route
for the previously failing Contact Info / Security & Privacy pages. Gmail
accepted the send; recipient delivery and a further response are not confirmed.
No agreement was signed and no completion of reporting was claimed.

The owner initially instructed us to defer payment-requiring steps, then
clarified that the concern is a **one-time publisher payment**, not ordinary
revenue sharing. Revenue sharing is acceptable subject to the service-fee basis
below. Publication is authorized if it requires no one-time payment and its
other release requirements are satisfied. Do not treat a standard revenue share
alone as a reason to stop. Do not invent an app subscription or extra ticket
charge: installation of this wrapper has no independent price.

### Revenue scope assessment, 2026-10-28

Rechecked the public Partner Agreement (effective 2026-06-30), section 9.3,
and App Market Guidelines, Payment and pricing. No separate one-time publisher
listing fee was found in those materials. This initial public-document
assessment is superseded where applicable by the actual unsigned addendum
review above.

The guidelines explicitly cover a free integration connected to a paid service.
An independently priced app subscription is therefore not required for those
rules to apply. The agreement covers income generated from the related app;
it does not explicitly establish a claim on the entire unrelated Festapp
ticketing business. The reporting template also attributes rows to app instances.

Our proposed interpretation is service fees attributable to use of the Wix
integration, with the organizer's ticket value kept separate. This is not an
individually approved pass-through exclusion. Attribution of existing customers
and the same form distributed through several channels remains unspecified;
neither assigning all of their sales to Wix nor automatically declaring zero
reportable revenue is justified by the public text alone. Keep ticket value,
our service fee and its Wix attribution separate in any implementation.

Sources:
- https://dev.wix.com/app-market-partner-agreement
- https://dev.wix.com/docs/build-apps/launch-your-app/app-distribution/app-market-guidelines
- https://dev.wix.com/docs/build-apps/launch-your-app/pricing-and-billing/report-revenue-for-partner-billed-apps

Remaining gates: written commercial clarification, owner decision if any paid
terms apply, authenticated instance attribution/reporting design and
implementation once terms are resolved and the existing submission checks.
Portal profile and privacy completion and native version 1.1 release are now
recorded in `evidence/portal-20261028.json` and `evidence/minor-release-20261028.json`.
Do not mark billing approval complete.

## Owner constraint confirmed 2026-10-25

No fixed publisher registration, submission, listing or recurring retention fee
is acceptable. A commission tied to sales/service revenue is acceptable, subject
to the revenue-base distinction below. Do not buy a Wix Premium plan to build or
test this widget. Wix documents [development sites](https://dev.wix.com/docs/build-apps/develop-your-app/development-sites/about-development-sites)
as free, including Premium capabilities for app testing.

The public agreement's pricing section describes revenue sharing and transaction
charges; no separate fixed listing charge was found in the reviewed public
materials. That observation is not an individually confirmed zero-fee offer.
Record the actual publisher terms, zero upfront/recurring amounts and their
evidence in `publisherFees` in private release inputs. The release check rejects
unknown, nonzero and undocumented publisher fee declarations. Ordinary organizer
website tariffs are separate from what Wix charges us to publish the app.

## Proposed service model

The installer/widget is free to add. It connects an organizer's public
vstupenky.online ticket form. The service earns a fee based on tickets sold; the
face value of a ticket belongs to the organizer, rather than being our app
subscription revenue. We want to preserve the existing service checkout.
Actual rates and terms must come from the approved organizer pricing, not an
invented Wix listing price.

Keep three amounts distinct:

1. **Ticket gross value** collected for the organizer.
2. **Our service fee** earned by vstupenky.online.
3. **Payment-processing fees, refunds and chargebacks** and their payers.

Illustration only: for a 1,000 CZK ticket with a 50 CZK service fee, a 20% share
of 50 CZK is 10 CZK. A 20% share of 1,000 CZK is 200 CZK and is not an acceptable
basis for this product. The numbers are explanatory, not our published tariff.

## Public terms verified 2026-10-24

The [Partner Agreement effective 2026-06-30](https://dev.wix.com/app-market-partner-agreement),
section 9.3, provides a standard 20% share after the first twelve months from
App Market launch. The first twelve months have a 0% share. The 2.5% transaction
fee applies only to billing actions conducted by Wix. Partner Billed Apps also
have broad language covering other related app income; external billing does
not by itself eliminate revenue sharing or reporting.

Wix's [Partner Billed Apps documentation](https://dev.wix.com/docs/build-apps/launch-your-app/pricing-and-billing/report-revenue-for-partner-billed-apps)
requires approval for external app billing, revenue reports and External Billing
Events API reporting. The availability of usage-based Wix Billing must be
assessed before requesting an exception.

[App Market Guidelines](https://dev.wix.com/docs/build-apps/launch-your-app/app-distribution/app-market-guidelines)
require truthful pricing and disclosure when free installation connects to a
paid service. The [2.5% Wix Events ticket service fee](https://support.wix.com/en/article/wix-events-about-wix-ticket-service-fees)
belongs to **Wix Events**, and is not evidence of a fee automatically applicable
to our independently hosted service or an exemption from App Market terms.

## Exact points to confirm in writing before submission

- Can this widget retain the existing external vstupenky.online **ticket buyer
  checkout**? Distinguish it from billing the Wix site owner for our app service.
- Is our **service fee only** the revenue-share base, explicitly excluding the
  organizer's ticket face value and sums collected on their behalf?
- Which entity collects the ticket value, which collects our service fee, and
  what evidence supports the pass-through deductions or split settlement?
- Is partner billing approved, or must our service fee be charged using Wix's
  usage-based billing? Does our existing customer contract alter that answer?
- Which actual app revenue rate applies to us; when does the first-year period
  start, and what transaction, currency conversion or payout charges apply?
- How do refunds, cancellations, partial refunds and chargebacks affect the
  reported base and the share already invoiced?
- How should paid-ticket service pricing appear in the listing when installing
  the widget itself costs zero? Do not select a misleading fully-free model.
- How are users who already had our service account before installing the Wix
  app treated? Define acquisition/attribution and uninstall/reinstall effects.
- What instance identification and reporting are required? Do not treat a
  client-supplied instance ID or query parameter as authoritative attribution.

## Implementation boundary

The current source kit does not call billing, collect card data, send event
reports, bill a Wix site owner, create a second ticket fee or grant privileges
from a Wix installation. If Wix requires instance-linked external-billing
reporting, that is a separate authenticated backend implementation after the
commercial base is agreed. Its approval and implementation are release gates.

Retain the actual approval reference in private release inputs and record the
agreed model without secrets in review evidence. A contact template or these
questions are not a substitute for a response from Wix.
