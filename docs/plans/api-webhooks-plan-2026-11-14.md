# Webhooks in the existing Festapp integrations API

Date: 2026-11-14
Status: Implemented and verified locally; production not applied
Verification: standard (public contract, authorization, concurrency and migration)

## Outcome and scope

An authorized API consumer subscribes an HTTPS endpoint to a saved order being
created through an occasion's form. Festapp sends the submitted customer and
form answers, their stable field IDs, order/form/occasion identity and occurrence
time. The consumer can test, inspect, pause, remove and redeliver its subscription
through the existing integrations API. The order is the existing registration
aggregate: one order can contain multiple people; do not introduce a separate
registration/person ledger or emit one apparent registration per buyer.

This is an additive extension of the current API. First version covers
`net.festapp.order.created.v1` and a synthetic `net.festapp.webhook.test.v1`.
Successful order creation is distinct from payment, attendance, account login,
waitlist entry and offer acceptance. These need their own later event contracts.
Do not automatically expose any future event through wildcard subscriptions.
No frontend settings, arbitrary code execution, new message broker, standalone
server, cloud webhook provider, autonomous service identity or Make permissions
upgrade is in scope. Production publication/deployment is a separate operation;
this request authorizes the plan and local implementation.

## Confirmed existing owners

| Evidence | Architectural consequence |
|---|---|
| `tools/festapp/src/remote/api-transport.mjs: installApi`, `endpoints.mjs: API_PREFIX`, `PUBLIC_API_FACADES` | Keep both existing facades and `/integrations/v1`; no new API hostname/process. |
| `remote/hosted-runner.mjs: createHostedRunner` | Reuse request authentication, DPoP, rate limits, tenant/resource binding and audit. |
| `remote/delegation.mjs: DelegatedOwner.current`, `authorizeOperation`, `delegatedContext` | Subscription authority must be a currently valid, narrowed personal delegation; a stored subscription is not new authority. |
| `packages/festapp_contracts/mcp-permissions.mjs`, `remote/client-policy.mjs` | Add explicit operation/scope policy through the current registry; no bypass route or client-selected data profile. |
| `remote/storage.mjs: openRemoteStorage`, `revoke`, encrypted records and process lock | Keep secrets and delegation handles in this protected store, not plaintext SQL or an additional credential file. This store is not the order transaction owner. |
| `database/functions/eshop/create_ticket_order.sql: create_ticket_order_internal_v1` | This owns identity allocation and successful initial finalization. Insert the domain outbox record here after success, within the existing exception/transaction boundary. |
| `database/functions/eshop/finalize_ticket_order.sql: finalize_ticket_order_internal_v1` | Shared finalizer also handles offers; do not emit creation indiscriminately here. Order history already holds submitted input, which must not be copied wholesale into public webhook payloads. |
| `database/functions/eshop_orders/create_ticket_order_client_sync_v1.sql: create_ticket_order_command_internal` | Command replay returns an existing receipt before new creation. Outbox uniqueness additionally protects repeated producer calls. |
| `tools/festapp/src/operations/orders.mjs: orderDataSchemas`, `orderDescriptors`; `database/functions/eshop_orders/operator_orders.sql` | Reuse customer/response/field identities and delegated SQL access. Keep occurrence snapshots separate from current-state inspect results and transient allowedActions. |
| `remote/endpoints.mjs: normalizeClient`, Make `order-summary` policy | Current Make connection deliberately cannot receive buyer details. This feature must not silently widen it. |
| `docs/architecture/ai_context.md` | All SQL functions in public; typed predicates; no persistent application triggers; canonical SQL and forward migration, no rewriting installed history. |

Current creation path: client command -> command receipt/replay boundary ->
`create_ticket_order_internal_v1` -> identity allocator -> shared finalizer ->
existing notification center -> saved command receipt. Both anonymous public
forms and admin/API callers must reach the same producer. Before wiring it,
enumerate every call of the allocator/finalizer and waiting/offer pathways with
scoped `rg`; prove which ones create a genuinely new order. That bounded audit is
part of wave 2, not permission to add events for other workflows.

## Target architecture

### Canonical responsibilities

1. **Domain SQL** owns the occurrence and immutable, allowlisted snapshot.
   Add canonical SQL under `database/functions/integration_webhooks/`. An outbox
   insert commits or rolls back with the new order. No outbound HTTP in SQL.
2. **Existing integration runtime** owns subscriptions, per-client projection,
   delivery, retries and the connection to the existing delegated backend
   session. Run a bounded drain loop in the current remote service lifecycle,
   with shutdown cancellation; never add a daemon beside it.
3. **Existing encrypted SQLite owner** owns signing keys and management-command
   receipts tied to original grant/resource/profile/client. PostgreSQL owns
   subscription routing metadata and durable delivery leases; it never stores
   signing keys. Do not put an unbounded delivery journal into the existing
   20000-record credential store. Add a purpose-specific synchronous transaction
   method for local secret/intent writes, not a second database or async
   callbacks inside SQLite transactions.

### Durable domain outbox

Use `public.integration_webhook_events`: UUID `id`, organization/occasion/form/order
bindings, event type, original `occurred_at`, schema version and snapshot JSON.
Unique `(event_type, order_id)` for first-version creation. Snapshot is an
allowlisted projection of saved rows after successful creation, never request
JSON, payment-provider secrets, QR/admission symbols, auth data or raw history.
Keep numeric form-field IDs and preserve typed response values; include ticket
identity and its submitted answers separately where those answers belong to a
ticket. Include field title/type at submission time so later form edits cannot
change the meaning. Reuse the existing DTO vocabulary (`customer`, `responses`,
`formFields`); define a dedicated snapshot SQL projection rather than serializing
the live administrative DTO with actions, current prices or payment information.

No direct table grants to anon/authenticated/service_role. A delegated read RPC
must apply the canonical typed read predicate and stored organization/unit/occasion
binding in the same transaction returning the snapshot. Subscriptions require
`public.can_manage_webhooks` in `user_permissions/webhook_operations.sql`; it is
an explicit webhook-management predicate; it delegates existing order-management
facts rather than inventing another editor/admin role combination. Reads still
require `can_read_orders`. Deliveries must recheck current permissions using the
original actor's session, even when the creation was anonymous.

Choose durable SQL fanout, not cursor polling. Add
`public.integration_webhook_subscriptions` with immutable routing/owner/grant
metadata and expiry, and `public.integration_webhook_deliveries` with unique
`(subscription_id,event_id)`, attempts, next_due, lease token/deadline and result.
Initial creation inserts the event and all matching delivery rows in the SAME
transaction. Claim eligible rows with `FOR UPDATE SKIP LOCKED`; complete by exact
lease token and recover expired leases. PostgreSQL timestamps, sequences and UUID
order do not imply commit order, so no event high-water mark is used at all.
Serialize subscription routing changes and producer fanout with one short
per-organization advisory transaction fence, always taking domain resource locks
before the webhook fence. Routing updates must not acquire additional domain
locks after that fence. Test this lock order against creation/deletion/revocation.

Only active matching subscriptions cause a private event snapshot to be retained;
there is no collection of all tenants' answers before anyone subscribes. Persist
the validated structured event's exact JSON text once in SQL with the occurrence.
The sender signs that text without parse/reserialize. Snapshot retention and event
identity are shared across recipients; version one supports only the operator
projection. Schema-valid test events also persist their exact body before sending.

The SQL registry is necessary durable routing metadata, not a new authorization
authority. Claim/read must bind the authenticated actor and canonical predicates;
the runtime additionally checks the original live grant and exact encrypted local
subscription/key intent before any dispatch. Calling SQL directly cannot create
a usable integration without that runtime binding. No service-role worker may
read all customers' answers as a substitute for these checks.

### API fit and authorization

Expose operation-style endpoints, consistent with the current API:

```text
POST /integrations/v1/operations/webhooks.list
POST /integrations/v1/operations/webhooks.create
POST /integrations/v1/operations/webhooks.update
POST /integrations/v1/operations/webhooks.delete
POST /integrations/v1/operations/webhooks.test
POST /integrations/v1/operations/webhooks.deliveries
POST /integrations/v1/operations/webhooks.redeliver
POST /integrations/v1/operations/webhooks.rotate_secret
```

Add descriptors through the existing operation catalog, explicit scopes and
client operation allowlists. Readiness stays unsupported until real SQL/HTTP
revocation/replay tests qualify the complete workflow. Management needs a
dedicated `festapp:webhooks:write` scope requiring order-read access; list/history
needs a dedicated read scope. Domain event access also requires existing order
read scope and the original occasion consent. Preserve existing read-scope
ceilings and fail closed for `order-summary` clients for version one. Extending
Make is a separate reviewed contract change.

Creation requires a command UUID, one occasion, optional saved form ID, explicit
event type array, HTTPS URL and expected contract version. Form scope must bind
to that occasion. Limit to 10 active endpoints per client/grant/occasion, 10 KiB
URL/config and 256 KiB serialized event. Commands are receipt-backed and identical
command replay cannot create another key or subscription. Return a signing key
only in the authorized create/rotate receipt; receipt replay needs live authority.
Use a recoverable management saga across the existing SQLite and PostgreSQL
owners: atomically persist a new encrypted key and command intent first; then
idempotently register the same subscription UUID/command in SQL; reconcile its
receipt and finalize the local intent before returning success. SQL registration
must be replay-safe and immutable-command-hash checked. A crash after SQL commit
leaves durable deliveries and the already saved key, so retry reconciles instead
of creating another subscription. Failed registration never dispatches. Deletion
fences local admission first, then idempotently disables SQL routing/deliveries.
Rotation first persists both keys and its intent, then reconciles versioned SQL
configuration; old-key retirement happens only after successful reconciliation.
List/history never return keys, customer data, full target query strings or
response bodies. Receipts containing secrets remain encrypted in the existing
store and expire with the grant. No secrets in audits or operational receipts.

Subscriptions bind actor, original grant, client, resource facade, tenant,
organization, consent selection, occasion and optional form. They freeze the current `connectionDeadline(grant)` at creation and cannot
outlive that grant. The returned expiresAt is authoritative; later OAuth refresh
does not extend an existing subscription. Longer-lived consent requires an
explicit replacement before that deadline. Worker activity never extends consent. Revocation, expiry,
client disablement, lost backend authorization or deleted/moved resource blocks
dispatch, redelivery and receipt replay. An in-flight request already sent
cannot be recalled; fence authorization immediately before network dispatch.
Reconnect does not adopt old subscriptions automatically. No promise of an
independent forever-running organization identity.

### Wire protocol and delivery lifecycle

Use structured CloudEvents JSON (`application/cloudevents+json`), specversion
`1.0`, durable event UUID `id`, canonical source
`https://api.festapp.net/integrations/organizations/{organizationId}`, versioned
type, `orders/{orderId}` subject, original RFC 3339 occurrence `time`, and `data`.
`remote/webhook-events.mjs` owns strict order/test payload schemas, validated
before sending. The current API generator publishes these as signed outbound
OpenAPI webhooks only for operator projections; summary projections omit them.
Regional and global facades do not create two source identities for one fact.
Synthetic tests have their own type and cannot be mistaken for real orders.

Sign exact stored UTF-8 body bytes using Standard Webhooks HMAC-SHA256:
`webhook-id`, `webhook-timestamp`, `webhook-signature`. The signed value is
`deliveryId.timestamp.body`. Delivery ID is stable for a subscription/event pair;
the event ID is stable across all subscriptions. Each attempt gets a fresh send
timestamp and signature, while occurrence time and payload remain unchanged.
Keys are `whsec_` plus canonical base64 32 random bytes. Rotation supports a
bounded overlap with both v1 signatures; retired keys must be removed on deadline.

Store delivery states pending/leased/succeeded/exhausted/blocked, attempt count,
lease token/deadline, next attempt, response status and safe error category.
No saved response body. Recover expired leases on restart; stale lease completion
cannot overwrite the next claimant. At-least-once delivery, no ordering guarantee,
and no exactly-once claim. Consumer acknowledges 2xx only after durable acceptance
and deduplicates webhook ID; business effects should also deduplicate event ID.

Default: 10-second total timeout, global concurrency 4, per-subscription concurrency
1, maximum 16 attempts within 72 hours. Retry all non-2xx/network failures with
exponential backoff capped at 6 hours and 75-125% jitter. Honor valid Retry-After
only within the delivery deadline; no automatic redirect following. 410 disables
the endpoint. Record terminal failure; explicit redelivery creates a fresh attempt
series for the same immutable event/delivery ID and rechecks authority. A test
delivery uses synthetic data and the same network/security path.

URL validation: HTTPS only, no userinfo/fragments, default port 443, no localhost,
IP literals, private/reserved/link-local/metadata networks. Resolve before EVERY
attempt; reject any mixed public/private answer set; pin the selected validated
address into the actual TLS connection while verifying the original hostname.
No second implicit DNS lookup, proxy-from-environment, redirect, cookies or user
Authorization header. DNS resolution is bounded by the same total timeout. Apply
egress restrictions as defense in depth. Network failure is not a reason to expose
an unsafe destination. Test rebinding, IPv4-mapped IPv6, alternative IP syntax and
redirects through the real sender seam.

### Retention and operational limits

Retain payloads at most 7 days; retry horizon is 72 hours. Redelivery requires the
retained snapshot. Retain safe attempt metadata for 30 days, bounded per
subscription. Delete snapshots and recipient rows through order/form/occasion foreign-key
cascades in the existing deletion paths. Redelivery requires the retained event
row, and existing command receipts cannot recreate a deleted occurrence; data already delivered externally cannot be recalled. Use the deletion-only retention job in the existing pg_cron scheduler as the
single cleanup owner, so expired consents cannot leave payloads indefinitely.
Dispatch performs no per-tick retention scan and skips inactive/expired endpoints. Queue saturation must be observable and cannot
silently drop a committed event. The measured first-version organization cap is 100000 pending/leased
recipient rows, including prospective fanout. A real disposable 100000-row fixture
verifies atomic rejection without a partial order (about 2.5 seconds for fixture
creation plus rejection on this workstation);
do not make storage-full handling silently skip the transactional producer.

## Implementation waves and exit gates

### 1. Protocol foundation (complete)

Implement CloudEvents envelope validation, bounded serialization, Standard
Webhooks signing/key generation and deterministic-testable retry decisions in
`tools/festapp/src/remote/webhook-protocol.mjs`. Tests belong to the existing
`tools/festapp/test/*.test.mjs` discovery. Do not mount an unauthenticated or
non-durable demonstration endpoint. Regenerate existing API source provenance
and docs with the current generators; no advertised webhook routes yet.

Exit: independent HMAC verification, tamper tests, retry/deadline boundaries and
invalid input tests pass. This is a foundation, not a working subscription API.

### 2. Domain snapshot, transaction and authorization

Trace all initial-order/offer/waitlist writers; prove the selected same-transaction
SQL fanout/lease and advisory-fence ordering with a real concurrency test. Implement canonical
outbox/schema/predicates/RPC files and an additive forward migration following the
current canonical-source registry/assembler contract. Emit only after successful
initial order creation. Freeze field/ticket answers from saved data. Add explicit
deletion integration, retention and direct-write revocation. Do not edit frozen
historical migrations or add domain triggers.

Validation: marked disposable PostgreSQL tests for rollback/no emission on failed
checkout, successful creation, command replay, concurrent creation/dispatch,
offer acceptance exclusion, actor/tenant/form mismatch, live permission loss,
payload allowlist and resource deletion. Use the existing `test/postgres.mjs`
guard and canonical current-SQL loader, never production or simulated SQL.
Exit: one immutable fact per new order, no lost committed facts, no unauthorized
read, and tested producer and migration order. No destructive migration.

### 3. Subscription operations in the current API

Implement `operations/webhooks.mjs` descriptors and add them to the existing
catalog and permission/client-policy registries. Add encrypted atomic SQLite
intent/receipt/secret lifecycle methods and the recoverable SQL registration saga.
Reuse `createHostedRunner`/`DelegatedOwner`; never create a separate bearer-token
parser. Introduce a typed management capability through the canonical permission
projection if needed, without frontend controls. Keep readiness gated until wave
4 qualifies delivery. Generate OpenAPI/examples/docs with existing generators.

Validation: existing API fixture through real HTTP, active and expired grants,
resource/profile/client/occasion fences, immutable receipts, create retry,
cross-client access, secret rotation, deletion and order-summary rejection.
Exit: management operations work only for explicitly enabled operator clients,
with no widening of current Make or existing consents.

### 4. Safe sender and runtime lifecycle

Implement `remote/webhook-delivery.mjs` with pinned HTTPS, timeouts, exact-byte
signing, bounded dispatcher and durable claim/complete semantics. Register the
drain lifecycle with the current service start/close owner after storage and
configuration initialization. No HTTP sends during SQL transactions. Recheck
grant plus SQL authorization before each send; recover leases on crash.

Validation: real local TLS transport with test-only DNS pinning, plus dependency
injection for DNS/rebinding faults; 2xx, network/timeout, 3xx, 410, 429 Retry-After,
5xx, large/slow response, restart after send before acknowledgement, revoked
grant, stale lease, concurrent claims and duplicate receipts. No paid/external
endpoint calls. Exit: real submitted disposable form creates one signed webhook
and retry/redelivery preserve its identity and occurrence snapshot.

### 5. Qualification and completion

Run the affected current API/SQL/auth tests, generated contract/docs checks and
compatibility checks. Before source publication, run affected canonical
`automation/test_ci.sh` lanes. Add concise operator/developer documentation and
an example receiver which verifies raw body/signature/timestamp, durably accepts
and deduplicates before returning 2xx. Update readiness only after all owning
tests pass; keep existing projections/Make fixtures passing unchanged.

Exit: the full first-version subscription journey is verified, no bypass path
exists, retention and failed deliveries are inspectable, and production status
is accurately recorded. Deployment remains separate unless requested.

## Decisions, assumptions and adversarial review

- Decision: reuse order identity and DTO terminology; a new registration entity
  or parsing email history would create a competing domain owner.
- Decision: keep personal-grant lifetime. An unattended organization integration
  would require the separate service-identity design, not a hidden worker token.
- Assumption: the requested registration is saved form checkout. First-version
  event naming accurately describes order creation regardless; account login,
  waitlist and schedule signup are not included implicitly.
- Decision: same-transaction SQL fanout and SQL leases avoid commit-order cursor
  loss; encrypted key-first intent/reconciliation bridges existing PostgreSQL
  and SQLite owners without pretending they share a transaction. Their real
  concurrent/restart tests gate completion of waves 2-4.
- Adversarial pass: initial checkout versus shared offer finalizer, command
  replay, timestamp/commit ordering, SQL-to-SQLite crash, grant expiry, secret
  receipt replay, regional/global duplication, unsafe DNS and order deletion are
  explicitly addressed by owning waves and gates above.
- No new credentials are persisted in wave 1. Later real signing keys must use
  the existing encrypted store; no plaintext key files or logs.
- No external-state blocker to local implementation. Current broad dirty worktree
  is existing work and must be preserved; do not commit it as this feature.

## Deletion ledger, rollout and rollback

This is additive. Retain existing notification-center, BankSync and email queue
owners; none is a replacement webhook pipeline. Do not reuse the outbound email
queue for arbitrary HTTP. No old route/table requires deletion. Remove any
temporary test-only dispatch bypass before readiness (enforce by API tests).

Apply additive schema/predicates and disabled producer compatibility first; deploy
the qualified current runtime, then enable explicit client policy/subscriptions.
If a producer references a new helper, both definitions must be in the same
forward migration and installed before producer use. Rollback stops subscription
admission/dispatch, preserves committed outbox and receipts, and restores only a
compatible producer definition; never drop undelivered events to roll back.
Production Functions restart rules apply if any Functions code is changed.

## Completion checklist and current receipt

- [x] Evidence-backed architecture and executable scope recorded.
- [x] Protocol foundation tests and current generated provenance verified.
- [x] Commit-order-safe outbox and real SQL authorization/concurrency verified.
- [x] API management and secret/receipt lifecycle integrated and verified.
- [x] Real TLS sender, retries, restart recovery and retention verified.
- [x] End-to-end form submission, docs and feature API/SQL contract checks pass.
- Not in this execution: source publication / production deployment; require a separate request and release gates.

Local completion: all eight webhooks operations are integrated and qualified in
the existing API, with the worker started/stopped by the existing remote main.
See `api-webhooks-RESULT-2026-11-14.md` for current verification and remaining
release gates. The initial wave-1 receipt below is retained as earlier evidence;
it is not the final completion state. No production effects were performed.

The two earlier local blockers were resolved in the authorized follow-up: the
strict operator payment decoder accepts SQL `net`/`pending`, and a generated
readiness refresh is installed through forward migration
`20261114130000_ticket_layout_contract_refresh.sql`. Original order integration,
all ten canonical owner checks, five real SQL test files and the real MCP layout
save/replay/conflict test pass. The API release-baseline remains `unreleased`;
published compatibility is not claimed.
The working checkout is the existing dirty `docs/festapp-tickets-readme-20261107`
branch; publication must reconcile the feature into canonical main and run its
required affected CI mirror/GitHub gates before any selected-tenant release.

Wave 1 local verification receipt (2026-11-14):

- `pnpm exec node --test --test-reporter=dot test/webhook-protocol.test.mjs`:
  15 tests passed, including independent WebCrypto verification and a fixed Python
  HMAC fixture, exact UTF-8 bytes, tampering, overlap rotation and retry boundaries.
- `pnpm exec node --test --test-reporter=dot --test-concurrency=1 test/api-contract.test.mjs test/api-transport.test.mjs test/api-docs.test.mjs`:
  passed; existing HTTP authorization, API contract and documentation tests.
- `pnpm run api:generate` and `pnpm run api:docs`: regenerated source provenance
  and existing offline references, without advertising new webhook operations.
- `pnpm run api:check`: schema parity, examples, lint and deterministic offline
  documentation passed for all 8 existing projections.
- No SQL migration, browser, Flutter, production, publish or external webhook send
  was executed. This receipt qualifies wave 1 only.

## Primary protocol references

- [Standard Webhooks 1.0](https://github.com/standard-webhooks/standard-webhooks/blob/main/spec/standard-webhooks.md): signed exact body, stable message ID and attempt timestamp.
- [CloudEvents 1.0.2](https://github.com/cloudevents/spec/blob/v1.0.2/cloudevents/spec.md): structured event identity, source, type and occurrence time.
- [Stripe webhook documentation](https://docs.stripe.com/webhooks): practical retry, duplicate and ordering behavior.
- [OWASP webhook security](https://cheatsheetseries.owasp.org/cheatsheets/Webhook_Security_Cheat_Sheet.html): receiver authentication and outbound destination protection.
