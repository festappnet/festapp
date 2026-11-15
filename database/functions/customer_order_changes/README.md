# Customer order self-service

`customer_order_change_gateway` is the service-only transport boundary for the
public Edge function. Service execution alone does not authorize an order:
challenge checks the existing order-view scope; resolve/preview/command recover
an independently issued, proposal-bound customer capability and its live parent.
The feature epoch, policy revision, order/form/organization, expiry, revocation,
operation and payload are checked before effects and receipt replay.

Sources are split by domain ownership:

- `policy*` owns disabled-by-default per-form rules, copied through no implicit grant.
- `runtime_schema` owns private scoped credentials, encrypted sources, rate counters,
  minimal audit and support requests. Requests are working evidence, never money.
- `preview` projects permitted actions and current consequences and hashes the
  relevant source/target, policy, ticket, capacity and financial facts.
- `commands` fences payment policy, occasion, ordered forms, order, products,
  payment and tickets before revalidation. Receipts, consumption, domain effects,
  Client Sync and queued messages commit atomically. Retry the same UUID and bytes.
- `move` transfers supported equal-price allocations and the same order/ticket/
  payment identities, rotates QR symbols and uses canonical PDF/Wallet delivery.
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

Automatic moves require explicit actual form terms and product/answer mapping,
same occasion/price/currency, compatible payment configuration and free capacity.
Seats, discounts, inventory, deposits, invoice repair and uncertain finance produce
staff requests. A request does not reserve capacity, invalidate admission or prove
refunded money. The current rules and verification record are in
`docs/plans/customer-self-service-plan-2026-11-15.md` and its RESULT companion.

The additive migration is assembled from canonical sources; regenerate it with
`python3 automation/assemble-customer-order-changes-migration.py` and then regenerate
canonical source parity. Migration does not enable the feature or its operations.
