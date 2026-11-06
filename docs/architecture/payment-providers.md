# Payment provider connectors

Implemented 2026-11-06. Stripe is the first installed connector. The bank-transfer
ledger remains the existing bank domain. Barion has a sandbox-only connector,
with production sales disabled. No platform commission is introduced.

## Ownership

- `_shared/payments/checkout.ts` owns checkout orchestration, leases, safe retries,
  recovery pagination and normalized settlement observations. It does not import
  a provider SDK, know provider hosts or call provider-named SQL RPCs.
- `PaymentConnector` reads verified external state and maps it to checkout,
  payment, refund and dispute facts. `PaymentStore` owns the provider's atomic
  persistence, account/mode binding, capability storage and ingestion calls.
  The production Stripe implementation is `connectors/stripe.ts`.
- `_shared/payments/registry.ts` is a strict allowlist of lazy factories. Its
  composition root is `runtime.ts`. Unknown IDs and mismatched connector IDs
  fail closed. Connection and webhook protocols belong to the connector.
- `_shared/payments/orderDelivery.ts` and `email.ts` handle common order delivery
  and confirmation rendering. Provider source fields, paths and URL policies are
  supplied by the registered binding.
- SQL's private `eshop.payment_providers` registry binds a provider key to one
  migration-owned `(text,jsonb) -> jsonb` handler. Registry tables and handlers
  have no client write/execution grants. The dispatcher resolves a catalog
  identifier and binds business values as parameters.
- `packages/festapp_core/lib/payments.dart` exposes provider descriptors and the
  Dart registry. The web client has its own browser registry with Stripe and sandbox Barion adapters.
  Shared views resolve the saved payment method; they do not assume Stripe.
- Flutter payment pages, gateway/connection API and native link inbox live under
  `lib/components/payments`. `payment_editor_registry.dart` is the composition
  root for provider-specific authoring capabilities, currencies and setup links.
  Form settings retain other providers' account bindings when editing one.

## Financial and security invariants

A browser return is never proof of payment. Facts come from a verified webhook
or current provider state and must match the saved account, environment,
currency, amount and checkout attempt. Existing expiry, late-payment,
refund/dispute holds, admission and ticket-delivery rules still run in SQL.

Public projections do not reveal pay capabilities. Pay, return and single-use
handoff scopes remain distinct. Private links are captured before analytics,
removed from visible URLs, scoped to their provider and excluded from caches.
Checkout and onboarding redirects use each connector's explicit HTTPS host
policy. Generic endpoints still delegate authentication, origin checks and raw
webhook signature validation to their registered implementation.

## Installing another provider

1. Implement `PaymentConnector` and `PaymentStore`; register their factory in
   `runtime.ts` with the private order-source field. Add provider-specific
   onboarding and raw webhook validation. Match the provider's real account,
   settlement, retry, expiry, refund and dispute semantics.
2. Add connector-owned SQL persistence and register its private dispatcher.
   Operations are `initialize_payment`, `create_attempt`, `projection`,
   `attach_source`, `paid_guard`, `totals`, `movements`, `validate_form`,
   `form_availability`, `form_editor_fields`, `unit_feature` and `unit_fields`.
   Follow the actual arguments in `payment_providers/registry.sql` and the
   Stripe handler. Initialization must return payment info with the same saved
   provider, amount and currency; settlement must use the common SQL lifecycle.
3. Register Dart and web descriptors with their own safe redirect policies,
   source-field/quote binding and availability adapter. Register authoring
   policy in `payment_editor_registry.dart`, along with the provider's setup UI
   where its onboarding protocol requires one.
4. Store recipient bindings under `payments.providerConnections[providerId]`.
   Availability publishes `providers[providerId]` including configured recipient,
   supported surfaces and reasons. Each selected provider gets its own recipient;
   an uninstalled ID cannot become a selectable payment method.
5. Add executable provider contract tests and a forward migration. Never activate
   a provider just by accepting a client-supplied provider string.

This is an explicit connector integration contract, not a promise that every
provider supports Stripe's marketplace or expiry behavior. Commercial platform
approval, merchant onboarding and refund capabilities must be established for
each real connector before enabling sales.

## Compatibility and migration

The canonical endpoints are `payment-connect`, `payment-checkout`,
`payment-return` and `payment-webhook`. Browser requests include `provider`;
webhook routing uses a provider query parameter, then verifies the original body.
Generic private routes are `/payments/:provider/pay` and
`/payments/:provider/return`, with the existing `/app` hosting prefix supported.

Existing `stripe-*` endpoints, `/stripe/*` links, saved Stripe recipient fields
and connector-owned Stripe tables remain protocol/storage adapters for issued
links, configured callbacks, scheduled recovery and saved orders. They call the
same payment engine. There is no duplicate checkout implementation. Some legacy
report DTO keys retain their old names while their data comes from the provider
movement contract.

`20261106120000_payment_provider_connectors.sql` and its exact reproducible inputs
are frozen under `docs/plans/payment-provider-hardening/history/`. The original
assembler verifies history and refuses regeneration. New changes are assembled
from `automation/payment-provider-hardening-migration.json` into
`20261106160000_payment_provider_hardening.sql`:

```sh
python3 automation/assemble-payment-provider-migration.py --check
python3 automation/assemble-payment-provider-hardening-migration.py --check
python3 automation/assemble-stripe-migrations.py --check
python3 automation/baseline.py check
```

Common SQL owns bank availability and sales policy. Provider availability and
public/editor fields are namespaced by provider ID; released root fields derive
only from the Stripe compatibility projection. Stored configuration uses
`bankEnabled` and `providerConnections`. Modern snapshots require an original
form revision; released Stripe-only metadata preserves other providers' bindings.
Setup authors can read eligible recipients through `get_setup_payment_options`
without connection-management permissions.

`apply_provider_payment_effects_internal` binds stored attempt/payment/order/
connection scope through a validated provider context, refreshes ledger totals,
and applies order/ticket, refund admission and email effects in one transaction.
Adapters implement `effect_context`, `effect_lock`, `effect_state`, `effect_decision`
and `setup_recipients` in addition to the operations listed above. They never
write order/ticket state or ticket email consequences themselves. Financial facts
must be complete; missing totals are not accepted as zero.

The engine consumes typed decoded claims and commit receipts. Account maintenance
is separate from attempt persistence. Recovery returns `found`,
`definitively_absent` with protocol evidence, or `unresolved`; vendor cursors stay
in the connector's opaque state. An empty Stripe list is unresolved. Expired
inventory can be released without asserting financial absence, including during
lookup pagination. Late verified money never revives released admission.

`payment-reconcile` is the generic machine-authenticated recovery entrypoint.
Providers have independent bounded queues; Stripe retains its request timeout
and durable backoff. Within a provider, financial attempts run before account
maintenance and expired-source cleanup. Each phase reports its own failure, so
an unavailable maintenance query cannot suppress payment recovery. A claimed
attempt must match the queued provider, attempt ID and account before remote
work or lease release; a claim that consumes the remaining budget is deferred
through its owned lease instead of starting a remote operation. `stripe-reconcile` and `request_stripe_reconciliation`
delegate for installed callers. The existing installation script replaces the
legacy job with one generic job; migrations install no network schedule.

No production migration, activation or deployment was performed. Barion now has
a registered sandbox-only adapter and real sandbox evidence; sales remain closed.
See the [current execution receipt](../plans/payment-provider-hardening/RESULT-2026-11-06.md)
and [capability matrix](../plans/payment-provider-hardening/capability-matrix.md).

## Previous connector-cutover verification

The following counts describe the earlier connector cutover. Current hardening
validation and remaining gates are recorded in the execution receipt above.

- 143 affected Deno tests pass, including a second connector executing the real
  common checkout/recovery engine, connector identity checks, connection routing,
  safe public configuration errors, Stripe webhooks and endpoint smoke tests.
- 20 local SQL test files pass on a disposable database bootstrapped from the
  current baseline and forward migrations. The second SQL connector executes
  actual order commands, totals, projection, source privacy and paid guards.
- 85 Flutter payment/startup tests pass; a subsequent form-editor run also passes
  its new second-provider save test and preservation of other account bindings.
- Five core Dart payment tests pass. Targeted browser-controller, callback,
  hosting and policy tests pass. Service-worker tests exercise private paths.
- Broader existing web-form checks also encountered unrelated rich-description
  sanitization and translation-artifact expectations in the already modified
  workspace. Full architecture validation also reports unclassified test roots
  unrelated to payments. These are not waived release gates.

Production rollout still requires the repository's normal selected-tenant release
checks, forward migration, Edge Function/config deployment, hosting/native link
updates and live verification. This document records implemented code and local
verification; it is not production-release approval.


The [recovery follow-up receipt](../plans/payment-provider-hardening/FOLLOWUP-2026-11-06.md)
records seven additional regression cases and the current 155-test Deno result.

## Barion sandbox boundary

`_shared/barion/{provider,facts,adapter,environment}.ts` implements the bounded
sandbox protocol and `PaymentConnector`/`PaymentStore`. SQL storage is independent
under `eshop_barion/`. All financial effects delegate to the existing common SQL
owner; no second paid/storno/admission/email implementation exists. SQL/Edge/Dart/
JS register `barion` explicitly. Browser paths use `/payments/barion/{pay,return}`
and existing private generic hosting rules. Redirects accept only the sandbox
Barion host with one valid GUID ID; live Barion is never accepted.

The SQL service boundary checks the service role, immutable account/order/payment
scope and current fenced lease. Connection setup is operator-owned with explicit
form allowlists and a disabled default. POSKey/payee are server secrets, never
stored in SQL or accepted from a client. Runtime requires explicit
`BARION_SANDBOX_ENABLED` and one configured sandbox merchant. Public sales and
setup recipient discovery remain unavailable until separate activation gates are
satisfied; installing the migration creates no account or activation.

Checkout writes durable dispatch intent before one remote Start. An unknown
PaymentId never triggers another Start. Read-only Barion recovery declares
`recoveryRequiresSource=false`, so it works independently of expired browser
bearers. Stripe retains its existing source/retry behavior. A callback durably
schedules a known-ID read and returns promptly; the recovery worker reads current
state with POSKey. A return page cannot mark an order paid. Unknown-ID callbacks
do not bind a payment based on untrusted query/body data.

Payment timing uses `CompletedAt`, since original `TransactionTime` already exists
at preparation. Only the single bound original payment and successful linked
refunds become customer movements. Processing fees are excluded. External partial
and full refunds are normalized even when PaymentStatus remains Succeeded.
Unknown/review/reversal transactions, pending refunds and missing previously
stored movements create a persistent admission hold. They never retract stored
money or automatically release a disputed/reversed refund. Complete chargeback/
refund-reversal release semantics and production merchant eligibility remain
closed activation gates. Application-initiated refunds are unsupported; the
sandbox operator probe is separate and never retries uncertain refunds.

Additive source-owned migration:
`20261106180000_barion_sandbox_connector.sql`, assembled by
`automation/assemble-barion-sandbox-migration.py`. Existing migration history is
unchanged. Real sandbox and disposable database evidence:
[Barion integration result](../plans/payment-provider-hardening/BARION-INTEGRATION-RESULT-2026-11-06.md).
