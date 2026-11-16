# Customer order self-service

`customer_order_change_gateway` is the service-only transport boundary for the
public Edge function. Service execution alone does not authorize an order:
challenge checks the existing order-view scope; resolve/preview/command recover
an independently issued, proposal-bound customer capability and its live parent.
The feature epoch, policy revision, order/form/organization, expiry, revocation,
operation and payload are checked before effects and receipt replay.

Sources are split by domain ownership:

- `policy*` owns disabled-by-default per-form rules, copied through no implicit grant.
- Applied schema migrations own private scoped credentials, encrypted sources, rate
  counters, minimal audit and support requests. Requests are working evidence, never money.
- `preview` projects permitted actions and current consequences and hashes the
  relevant order, policy, ticket, capacity and financial facts.
- `commands` fences payment policy, occasion, ordered forms, order, products,
  payment and tickets before revalidation. Receipts, consumption, domain effects,
  Client Sync and queued messages commit atomically. Retry the same UUID and bytes.
- `staff` independently checks current order/financial permissions, expected request
  timestamp and receipt ownership. Previously accepted work survives feature off.

Response edits call the same private response effects as the existing admin
boundaries. Cancellation shares existing admission and order cancellation owners;
refund preparation and dispatch stay in `payment_providers`. The provider engine
alone interprets settlement facts. No customer helper has a client execute grant.

The Edge handler bounds input and seals proposal/token delivery using the existing
email encryption and queue. The existing overview URL is retained. A short-lived
write credential lives in a fragment captured and removed before other browser
scripts; clients keep it only in memory. The native URI getter never serializes it.

The additive migration is assembled from canonical sources; regenerate it with
`python3 automation/assemble-customer-order-changes-migration.py` and then regenerate
canonical source parity. Migration does not enable the feature or its operations.

Selected-ticket cancellation is a separate scope of the same cancellation operation.
The preview rejects duplicate, foreign and cross-order shared ticket identities.
It binds exact IDs into the emailed proposal and receipt; support requests retain
those IDs for staff approval. Non-selected admission, QR identities and allocations
remain unchanged. `cancel_ticket_selection_domain_internal` is also the existing
staff bulk cancellation effect; its staff facade keeps locks and current rights.
Seats alone do not prohibit cancellation; indivisible selection-unit guards remain.
Partial online refunds require the provider's existing admission decision workflow
and produce support work. Bank/cash partial cancellation is automatic only under
the compatible configured policy; refund facts remain in the existing engine.

Release policy: all submitted answers are customer read-only, including contact
fields. `customer_order_operation_enabled_internal` supports only cancellation;
preview and command effects also reject edit. Legacy policy input remains
validated for compatibility but cannot persist an enabled edit rule. A stored
legacy enabled rule or credential does not override the server lock. Staff
response commands retain their independent typed authorization and shared effects.

Term moving has been fully retired by the guarded forward migration
`20261116010000_customer_cancellation_cutover.sql`. No move policy, target column,
form occurrence date or move function remains in the live contract. Actual event
dates are read from the occasion owner for email and Wallet. Migration aborts
without discarding any pre-existing term or moving history. Applied migration
bytes remain immutable history.
