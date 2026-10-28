# Verified checkout origin

Status, 2026-10-28: implemented and tested locally; not deployed. This records
where an order originated. It grants no Festapp rights and does not, by itself,
make service income eligible for Wix reporting.

## One checkout path

1. The published-site widget obtains its host token through the Wix SDK's access
   token injector. Editor and preview rendering do not request checkout proofs.
2. `wix-checkout-context` verifies that token at Wix's fixed token-info endpoint,
   including app, installation, site, active status and expiry. Browser-supplied
   installation IDs cannot replace those claims.
3. A service-role SQL issuer resolves the canonical form link and checks its
   open state and configured organization. Demo forms are rejected. A private
   database key signs a form-bound context valid for 24 hours. The endpoint
   exposes neither that key nor a Festapp credential.
4. The iframe and its direct-link handoff receive the same context. Stale async
   responses cannot replace a newly selected form. Failure to establish origin
   shows the unavailable state instead of silently losing attribution.
5. The existing public web order client includes the context before claiming
   its mutation identity. The purchase fingerprint excludes the renewable proof;
   a pending command retains its original proof until its outcome is terminal.
   Retries therefore send the exact original SQL payload even after the widget
   renews its proof, and cannot reattribute an uncertain ordinary purchase.
   `create_ticket_order_client_sync_v1` verifies it and
   records `eshop.order_checkout_origins` in the order's own transaction. The raw
   proof is stripped from stored order data. A committed replay returns its
   original result even if the proof expires or its key rotates later.

Ordinary orders without a context follow their existing path and acquire no
Wix attribution. No payment producer, Stripe application fee, persistent trigger
or separate financial ledger is introduced.

## Individual organizer agreements

The owner confirmed that the percentage can differ by organizer contract.
Reporting therefore requires the actual agreement reference and historical
`organizerFeeRateBps`, without a default. It consumes settled service-fee amounts;
it does not calculate collectible fees from ticket payments. Each charge also
requires evidence that the customer originated through Wix. Pre-existing
non-Wix customers are excluded even if an order has a valid Wix context.

## Verification and deployment boundary

Passed: 28 Wix tests, widget build/package, 77 targeted Edge tests, 13 web
client tests, function coverage and route-patch coverage. A fresh disposable
database applied the migration and passed the origin transaction test plus the
existing client-sync runtime and Stripe order-creation tests. The unrelated
full policy-suite failure concerns the pre-existing missing occasion-lifecycle
inventory entry; it is not a successful full-suite gate.

Deployment must coordinate these artifacts:

- Canonical table/function SQL and migration
  `supabase/migrations/20261028140000_wix_checkout_origin.sql`.
- The Edge handler, coverage/policy entries and production proof-route patch.
- The selected `prod/festapptickets` public web client and Wix static widget.

Apply the database and backend before publishing the dependent widget. Preserve
the protected Functions restart procedure, including email pause/drain, worker
health and resume. No Functions container recreation or new runtime environment
variables are needed. Deploy the public client through the repository's normal
single-tenant release gates. Do not publish the new widget while its endpoint
is unavailable.

Still required for operational Partner Billed reporting: an authoritative
settled-fee export, customer-acquisition evidence, durable event delivery and
reconciliation, signed sole-trader terms and verified Partner Billed activation.
No real billing event, report or contract signature was submitted by this work.
