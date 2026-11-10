# Payment provider connectors

The installed-method registry covers bank, cash and external connectors for both
payment directions. SQL owns installation, authorization, reservations and facts;
runtime registries provide explicit implementations of the installed capabilities.
Hosted checkout is optional. Barion remains sandbox-only with refund writes
unavailable. Unified payment operations are implemented locally; this does not
record a production migration or activation.

## Ownership

- `_shared/payments/checkout.ts` owns checkout orchestration, leases, safe retries,
  recovery pagination and normalized settlement observations. It does not import
  a provider SDK, know provider hosts or call provider-named SQL RPCs.
- `HostedCheckoutConnector` reads verified external state and maps it to checkout,
  payment, refund and dispute facts. `PaymentStore` owns the provider's atomic
  persistence, account/mode binding, capability storage and ingestion calls.
  The production Stripe implementation is `connectors/stripe.ts`.
- `_shared/payments/registry.ts` is a strict allowlist of lazy factories. Its
  composition root is `runtime.ts`. `PaymentConnector` is the shared identity;
  `PaymentMethodBinding.hostedCheckout` contains the provider-only dependencies.
  Bank/cash have no fake checkout URLs, mode or bearer-source implementation.
  Unknown IDs and mismatched connector IDs fail closed. Connection and webhook protocols belong to the connector.
- `_shared/payments/orderDelivery.ts` and `email.ts` handle common order delivery
  and confirmation rendering. Provider source fields, paths and URL policies are
  supplied by the registered binding.
- SQL's private `eshop.payment_providers` registry binds a provider key to one
  migration-owned `(text,jsonb) -> jsonb` handler. Registry tables and handlers
  have no client write/execution grants. The dispatcher resolves a catalog
  identifier and binds business values as parameters.
- `packages/festapp_core/lib/payments.dart` exposes provider descriptors and the
  Dart registry. The web client has its own browser registry with Stripe and sandbox Barion adapters.
  They include bank/cash. Shared views resolve the saved method and test its
  hosted-checkout capability, rather than assuming registration means a gateway.
- Flutter payment pages, gateway/connection API and native link inbox live under
  `lib/components/payments`. `payment_editor_registry.dart` is the composition
  root for provider-specific authoring capabilities, currencies and setup links.
  Form settings retain other providers' account bindings when editing one.

## Shared incoming and outgoing operations

`command_payment_operation(input_data,p_command_id)` owns `record_payment`,
`prepare_refund`, `cancel_pending` and `correct_record`. Context and amount-specific
previews come from `get_payment_operation_context` and `preview_payment_operation`.
They enforce typed, stored-scope policies before mutation and receipt replay.
The authenticated `payment-operation` Edge endpoint adds presentation only:
validated recipient, shared SPD/EPC encoding, and the original immutable reference.
The same registered SQL handlers supply incoming form availability/configuration
and operation capabilities. A capability is unavailable unless its actual source,
currency, identity, permission and adapter requirements hold.

| Method | Preparation/execution | Financial confirmation |
|---|---|---|
| Cash | Atomic authorized negative CASH row plus request/settlement | Local SQL commit |
| Bank | Immutable recipient instruction and reservation; no bank API transfer | Authenticated BankSync debit in the original physical-account namespace |
| External connector | Durable intent followed by leased dispatch or read-only recovery | Existing connector ledger and `apply_provider_payment_effects_internal` |

`refund_requests` record intent, immutable binding and reservation. They are not
a second ledger. Unique `refund_settlements.transaction_id` classifies existing
cash/bank movements, retaining raw bank identity and type. The shared movement
classification preserves historical signed manual corrections as corrections.
Financial projections expose received/refunded/net/pending separately. Net may
be negative after a real excessive debit; preparation never changes confirmed
received/refunded/net. Storno/expired orders retain their admission lifecycle.

Bank preparation requires canonical original reference ownership and active
account identity protection. CZK SPD uses the saved VS; EUR EPC uses the saved
RF. No refund allocator or extra matching token exists. USD has supported import
and manual instructions without pretending that SPD/EPC supports it. Invalid,
missing or changed bank references are explicit deviations requiring authorized
evidence-based repair. No amount/name/time heuristic selects the order.
Cancelling an instruction releases its reservation only after the operator
confirms no bank transfer was submitted; it cannot revoke an external bank order.
Later real debits remain visible, including repeated or excessive transfers.

External recovery is part of `payment-reconcile`, using service-only
`claim_payment_refund`/`complete_payment_refund` and the existing attempt ingestion.
A dispatch result is metadata until the matching provider refund movement exists.
Stripe validates the original PaymentIntent/account/mode/currency, uses one
stable key and recovers uncertain writes by reading. It never renews a write
after the retention window. Barion can observe external refunds but advertises
no application-initiated write capability. SQL `refund_write_enabled` defaults false for external connectors. Real merchant
permissions and live readiness must be independently verified before explicit
activation; offline transport-contract tests never enable writes.

Refund history blocks hard deletion before external cleanup; source disconnection
cannot remove a pending binding. General pairing/delete paths cannot bypass
refund classification, reserved-money checks or explicit cash correction audit.

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

1. Implement `HostedCheckoutConnector` and `PaymentStore`; register their factory in
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
assembler verifies history and refuses regeneration. Their historical bytes remain immutable. The current unified forward is
`20261110140000_payment_operations.sql`, assembled from the explicit ordered
`automation/payment-operations-migration.json`. Historical cash, integration,
hardening and Barion assemblers verify frozen historical source blocks only for
owners explicitly superseded by that manifest, then verify the entire current
forward. Other source parity checks remain active. They refuse regeneration of
installed history; evolve the current forward instead:

```sh
python3 automation/assemble-payment-operations-migration.py --check
```

Historical checks remain available:

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
sandbox protocol and `HostedCheckoutConnector`/`PaymentStore`. SQL storage is independent
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
