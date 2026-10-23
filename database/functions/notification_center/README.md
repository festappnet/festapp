# Organization notification center

This domain is a private, personal administration projection. Existing news,
push, the outbound email queue, BankSync ingestion and payment matching retain
their owners. No client publishes events. No business triggers or network calls
run in checkout transactions.

## Ownership and ordering

- `create_ticket_order_internal_v1` publishes ordinary creations once, using the
  allocated order identity. Waitlist registration/acceptance/decline/withdrawal
  publish in the successful command transaction after its replay gate.
- `internal_storno_tickets_221` captures only actually changed ticket IDs before
  unlinking inventory, covering whole, partial and indirect cancellations.
- `expire_waitlist_form_internal` captures exactly the updated offer slots and
  original expiry timestamp, including the periodic expiry path.
- Finalization, allocation, cancellation, form/product/blueprint settings and
  inventory resizing observe canonical form snapshots, product link limits,
  canonical V2 blueprint seat bindings and per-context physical/commercial inventory limits.
  Temporary buyer holds do not generate attention. There is no invented
  occasion total. `product_types.maximum` is not enforced by the current product
  materializer; notifications use the actual `products.maximum` boundary.
- Paid/sent/recalculated/Stripe and acceptance-recovery state changes update
  existing order projections only. Acceptance never emits another creation.
- Shared email reducers observe every supported message kind, including new
  feedback after delivery. The bounded due evaluator covers delayed/uncertain
  messages. Original provider timestamps exclude late preactivation facts.
- The machine-proof health worker reads the existing authenticated BankSync
  status transport only, never a bank API or a new import path. Scope comes from
  explicit form accounts and actual order payment accounts, including aliases.

An organization advisory transaction lock serializes first activation, pause
and resume with producers, including the interval before an activation row
exists. Producers take the shared gate before source state/event writes;
activation takes it exclusively. Existing form/order/product/pool lock order
remains intact. No producer takes a personal delivery-state lock.

Publication snapshots currently eligible recipients. A genuinely new attention
revision refreshes eligibility and its verified author suppression; earlier
self-suppression cannot hide a later automatic failure. Projection rechecks
current rights and mute state. Recipients have per-revision processing cursors, so a
bounded retry resumes fanout without delivering skipped/muted history later.
The projector's transaction advisory lease prevents competing batches from
locking personal rows in conflicting orders. Row/transaction rollback is its
retry fence; no external delivery effect can escape it.

Delivery allocation and `open_notification_center` lock the same personal state
row. This orders commits rather than global sequence allocation or wall time.
Only open acknowledges, monotonically, through its captured upper sequence.
Pagination, group expansion, updates and badge reads never acknowledge.

## Access and private data

All projection tables have RLS and no client grants. Helpers are revoked from
public client roles. Only service-only entrypoints may activate, project,
observe or clean projections; user RPCs derive their recipient from `auth.uid()`.
Every read rechecks current tenant and domain rights, including grouped counts,
old pages and update hydration. Current occasion changes priority only.

Order/capacity access follows actual order-view rights. Email access follows the
reporting owner: tenant admins may inspect tenant mail, occasion order viewers
may inspect occasion-scoped mail. Organization-only security mail is never
shown to an occasion-only organizer. DTOs exclude recipient addresses, bodies,
provider payloads, tokens and internal bank mappings. Authorized order names
and current states are read at DTO creation, not copied into the event log.
Bank-account admins who also manage a linked unit receive their authorized account/unit target; organizers
receive only their affected event links and a safe reason class.

## Baseline, monitoring and retention

Activation starts disabled. `set_notification_center_activation` seeds existing
source states silently; resume preserves the first activation time and does not
replay the paused interval. The separate current collection-window timestamp
excludes late provider facts from a paused interval without changing the first
activation timestamp. Organization day grouping defaults to Europe/Prague,
matching `TimeHelper.setTimeZoneLocation`; the service activation boundary can
specify a valid IANA timezone.

Capacity uses 90% attention with an 85% reset and one full/reopen episode.
A full transition supersedes a warning from the same transaction; a later full
transition can add one attention revision to the same item. Cancellation carries
its form capacity consequence. Recovery does not add unread attention.

Bank status runs every five minutes, claims four connections per worker call,
uses the shared 20-second transport timeout, a two-minute fenced lease and a
ten-minute transport backoff. Confirmed token failure is immediate; transient
failures require at least two observations spanning fifteen minutes. Staleness
uses a conservative thirty-minute threshold; successful pull time proves
recovery. The local BankSync source defaults to a 30-second minimum fetch interval
and a minute scheduler. Production interval/rate limits still require release
verification. Suspend is not a new failure.

Email uncertainty/delay uses thirty minutes from the original due time, captured
before retry scheduling can move the queue target, with earlier attention
near an offer deadline. Existing recipient suppression is expected; a new
suppression is an incident. Complaint means provider-confirmed recipient spam
feedback. It makes no claim about automatic spam-folder placement or inbox
arrival. Repeated same-class feedback does not add attention; a new class can
advance the existing item's revision once. Bulk incidents group the same cause,
authorized scope and local calendar day while retaining one row per message.

Cleanup removes safe projections/deliveries older than ninety days in bounded
batches, preserving active problems and minimal source dedupe/baseline state.
Business records and email audit remain owned by their existing domains.

## Installation and verification

`automation/assemble-notification-center-migration.py` produces the explicit
forward migration; `--check` verifies parity. Production jobs are installed explicitly in the postgres scheduler using
`cron.schedule_in_database`, targeting the verified canonical application
database. The application database does not own pg_cron.
Release must verify the health job, proof route and scoped worker credentials.

Run the discoverable `database/tests/notification_center/*_test.sql` via the
normal SQL runner, plus the real two-connection Node tests in that directory.
The Flutter owner documents personal polling, snapshot hydration and navigation
in `lib/components/notification_center/README.md`. Actual execution receipts and
remaining release steps are in the dated plan; local implementation does not
activate production.
