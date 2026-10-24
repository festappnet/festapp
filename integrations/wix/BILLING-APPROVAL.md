# Ticketing revenue basis - approval required

Status: **no Wix-specific billing or checkout approval obtained**. This document
is a draft brief/questions for an authorized operator, not a message already sent.
No new agreement, paid product or marketplace application was accepted.

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
