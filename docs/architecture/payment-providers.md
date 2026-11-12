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

## Scoped product policy and collection

`payment_providers/method_policy.sql` owns organization permissions, unit
inherit/enabled/disabled overrides and the preferred method over the installed
registry. Organization denial always wins. Missing policy and unknown methods
fail closed; installation, configuration, readiness, operation support and RBAC
remain independent. Unit preferences never grant permission. New forms start as
closed drafts using this preference, without inventing a bank account or provider
connection. Global provisioning explicitly selects Stripe and disables bank.

`get_payment_method_policy`, `preview_payment_method_policy` and the receipted
`command_payment_method_policy` are connected to tenant/unit settings. Commands
re-authorize before receipt replay and require the current impact hash, covering
open collections, issued references, bank instructions, provider intent dispatch
states and obligations. Closing sales never cancels debts, revokes an issued URL,
settles a refund or discards financial facts. Cash corrections after disable must
reverse one actual manual cash source exactly once and preserve its audit.

The organization policy advisory lock is exclusive for policy/template writes
and shared for new collection/instruction actions. Acquire it before transaction,
capacity/order/payment/message locks. Template authoring uses the same fence;
a send permit either precedes an edit or rechecks its committed template epoch.
No database lock spans a remote provider call. The registered form projection
also attests `collectionAvailable`: normally the same technical eligibility as
public availability, with an explicit connector-owned private gate for an
already approved sandbox attempt. Barion keeps public `available=false`; its
private gate requires an enabled original connection, exact organization/unit,
saved binding and sandbox form allowlist. Policy/template denial still wins.
This does not expose a new public sales method or onboard a provider.

Refund dispatch uses the existing
durable lease and observes the independent connector write kill-switch.

`collection_action.sql` owns current purpose, method, source order, eligibility
and policy/template epoch for emails and customer reopen. Queue claim/send
rechecks that epoch without rewriting prepared snapshots. Re-enabling a method
cannot revive an old demand. The worker-only `get_order_details_for_email` definer reads private eligibility
through its service-only EXECUTE boundary; authenticated clients cannot call it.
Already-authorized contact repair shares the same read owner.
Explicit template/banner save and reset owners acquire the policy fence before hierarchy locks and advance a private monotonic epoch for affected occasions; no persistent application trigger is installed. Privileged authored-wrapper/data migrations must call `payment_template_write_scope_internal(context,true)` in the same transaction. New occasion initialization has no prior snapshots to invalidate;
unit A edits do not invalidate unit B. The template audit binds that epoch and
the inherited body/wrapper, reports authored bank instructions and requires exact clean review for
online-only collection. It never rewrites an organizer's custom text. New disabled-bank envelopes with authored fixed bank text are blocked too.
A-B-A edits cannot revive a prepared snapshot. Derived policy/template attestations
are excluded from the immutable business dedupe hash; changing actual business
content still conflicts. Old encrypted envelopes without a template attestation
are held from online/disabled-bank dispatch and require a fresh authorized resend.
Their audit payload is preserved.

Bank discovery, linking, management, setup and email authoring require an enabled
stored unit scope. `get_linkable_bank_accounts(unit)` is the authorized linking
picker. `get_bank_transaction_history(account,unit)` additionally verifies the
actual account link and both unit/account roles. Order finance does not enumerate
other admin accounts. Provider history merges existing movements and dispute
status facts with stable source identities; a dispute has `amount=null` and a
separate contested `heldAmount`. `ledgerComplete=false`/`invalidIdentity` must
remain visible as uncertainty rather than a fabricated zero balance.

Registry `refund_write_supported`, `partial_refund_supported` and
`refund_observation_supported` describe different operations. Unsupported writes
are rejected before intent creation; full-only connectors reject partial amounts.
Observation and original-payment servicing continue after new sales close when
support, readiness and current roles allow them. Gateway actions have no cash,
bank picker or QR fallback.

Email variables `paymentMethodName` and `paymentAction` are generated from the
shared contract. Legacy safe aliases remain defined but method-inapplicable
bank values are empty. Body, wrapper and legacy balance slots yield one action.
Payment QR owners require an explicit bank action; CZK uses SPD, EUR EPC, USD
uses manual instructions. Ticket, login and wallet QR owners are separate.
Unverified invoice/external attachment hooks are suppressed outside permitted
bank collection. Preview scenarios use the same production presenters.

The additive/contraction forwards are assembled from
`automation/payment-method-policy-migration.json`. Backfill is one-time: it
materializes historical implicit form selection, refuses unknown methods and
preserves hidden sibling Stripe settings. Contraction archives original policy
evidence, drops `stripe_unit_features`, removes `DEFAULT_FORM_PAYMENT_METHOD`
and retires unscoped account RPCs. Replaying additive backfill after contraction
is not a supported update path. Use a fresh bootstrap or normal forward history.
Financial ledgers, account/reference identities and immutable email audit remain.
See [the local implementation receipt](../plans/payment-method-policy-RESULT-2026-11-12.md)
for validation and explicitly retained protocol boundaries.

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

Order lists use `payment_method_contexts_internal` to aggregate selected ledger
facts and refund history once. `payment_operation_permissions_internal` resolves
distinct stored unit, occasion and bank scopes once per read; scalar policy
wrappers use that same owner. Private bank/cash capability handlers can consume
these prepared permissions within the read. This input has no client execution
grant and never authorizes a money command. Context, pending amount and stored
payment values are assembled in one SQL statement snapshot. Single-order readers
delegate to the same bulk projection; mutation entrypoints still re-authorize.

| Method | Preparation/execution | Financial confirmation |
|---|---|---|
| Cash | Atomic authorized negative CASH row plus request/settlement | Local SQL commit |
| Bank QR | Read-only recipient instructions, no reservation or transfer | Existing bank movement processing |
| External connector | Durable intent followed by leased dispatch or read-only recovery | Existing connector ledger and `apply_provider_payment_effects_internal` |

`refund_requests` record intent, immutable binding and reservation. They are not
a second ledger. Unique `refund_settlements.transaction_id` classifies existing
cash/bank movements, retaining raw bank identity and type. The shared movement
classification preserves historical signed manual corrections as corrections.
Financial projections expose received/refunded/net/pending separately. Net may
be negative after a real excessive debit; preparation never changes confirmed
received/refunded/net. Storno/expired orders retain their admission lifecycle.

The admin bank QR action uses `get_bank_refund_instructions` through the
`bank_instructions` Edge operation. Its separate `instructions` capability
requires order-read permission, supported currency and the saved reference.
It does not require bank administration, synchronization or reference-registry
activation. It never enters the mutation transport, creates a refund request,
reserves funds, changes accounting or confirms a transfer. Cash and hosted
connector refund commands retain their typed financial authorization.

Previously reserved bank requests remain readable and cancellable through their
existing authorized recovery flow. That mutation path requires canonical
original reference ownership and active account identity protection. CZK SPD uses the saved VS; EUR EPC uses the saved
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

`20261106120000_payment_provider_connectors.sql` retains its exact historical SQL
inputs in ordered `SOURCE` blocks. The original assembler reconstructs them in
memory and checks the original hashes in
`docs/plans/payment-provider-hardening/frozen-inputs.json`; `history/` retains only
the small source manifest. The original
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

## Runtime reload and migration ownership

`method_policy.sql` contains repeatable function/ACL declarations only. Its one-time schema and historical backfill remain in the checksum-pinned160000 migration; contraction170000 is immutable too. Reloading functions after contraction never reads retired Stripe feature storage or materializes defaults again. Refinement180000 owns the subsequent authoring change.

`automation/migration-forward-owners.json` declares frozen digests, source manifests, explicit later owners and current forwards. The shared checker reads these records without importing assembler scripts. Frozen source text must still match unless a registered later owner supersedes it; every current function must match effective migration head. `functionOnlySources` explicitly records the method_policy boundary whose DDL/backfill is retained solely in frozen history. Existing assembler CLI names are checked adapters, not independent ownership engines.

Authoring acquires the existing policy/hierarchy fence even for no-op requests. Only actual template/wrapper insert/update/delete advances the epoch. Identical saves and resets without a local override preserve prepared intents and reviews; actual A-B-A edits still invalidate them. The settings widget consumes typed policy/impact/change DTO through DbPaymentPolicy; JSON/RPC stays inside that boundary.


### Released bank-reader transition (2026-11-12)

Issued web versions through 0.20.590 call the no-argument
`get_my_admin_bank_accounts()` and account-only
`get_bank_transaction_history(account)`. These two signatures are temporary
protocol adapters in `payment_providers/released_bank_readers.sql`. They derive
one unambiguous real managed unit from stored membership/link relations and
immediately delegate to the canonical explicit-unit readers. Multiple possible
units, demo units, missing rights and disabled bank policy fail closed. Disabled
units participate in ambiguity detection, so another unit cannot be inferred by
filtering policy first. The adapters own no bank or policy business logic.

Current Dart clients use only the explicit-unit signatures. Remove both legacy
signatures and the private scope resolver when supported deployed/cached client
versions no longer call them; keep their parity/ACL and ambiguity tests until
that consumer is retired. This is the narrow released-client exception allowed
by the payment policy plan, not a second policy authority.

The release operator may run
`automation/payment-policy-release/transition_legacy_email_metadata.sql` for the
explicitly selected organization while the queue is paused. Dry-run is default.
Only unprepared, never-attempted pending bank demand envelopes receive current
server policy metadata. Business data, hash, recipient, dedupe, state and sealed
snapshots are preserved. Prepared, unknown, attempted and foreign envelopes are
untouched; repeated execution is idempotent and performs no send or resend.

Administrative notification facts use the existing connector registry operation
`notification_facts(attemptId)`. Each connector returns immutable positive
payment movement identities, amount, currency and occurrence time from its own
stored ledger. The shared effects owner publishes these facts through the
notification center; it does not branch on provider names or infer income from
paid state. Refunds, repricing and callback revisions create no payment-received
identity. `eshop.payment_notification_incidents` retains the payment domain's
problem episode and recovery; delivery does not evaluate that domain again.

Operational connection alerts use the same registry with
`notification_connection_health(connectionId)`. Stripe reads its confirmed
connection state and status-worker failure count; Barion reads the failure
counts persisted by its existing recovery worker. The shared threshold owner is
`payment_provider_connection_failure_threshold_internal` (three consecutive
failures). There is no second health poller or provider request from email.
`provider_connection_notification_incidents` owns only episode identity and
recovery, not financial facts. Reason changes preserve the episode; recovery
closes it and a new failure opens a new UUID. Intentional Stripe disconnection
is excluded using its existing actor audit. Barion stays sandbox-only.

`payment_provider_unit_manager_internal` owns connection-administration identity
for both Stripe commands and notification scopes; existing demo guards remain.
Only current connection administrators receive mandatory `provider_problem`
email, independently of optional summary stop, subscriptions and occasion mute.
The existing recipient capture, prepared center, SQL authorization context and
single email queue/SES gate deliver it. The digest never computes connector
health, payment totals or ticket counts again.
