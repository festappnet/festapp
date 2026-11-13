# Organization notification center

A private personal feed, independent of public sync, news/mobile push delivery,
the outbound email lifecycle and BankSync facts. Trusted explicit domain owners publish;
there are no application triggers, parallel queues or client publishers.

## Canonical serving and read ownership

`get_notification_center_view` owns open/preview/page/refresh/close/close_all.
`get_notification_center_prepared_badge` reports readiness and unread state.
Settings, muting and `mark_notification_center_view_item_read` retain their
existing typed contracts. Every read checks current organization/context rights
and private subject visibility. No client receives direct projection-table grants.

Only a successful open advances the seen watermark. Preparing, denied, preview,
pagination and refresh cannot acknowledge new arrivals. View tokens bind the
user, organization, occasion, snapshot, captured slots and sequence envelopes.
New deliveries require a new view; privacy/source repairs can redact an existing
slot until its exact captured membership is ready again. Quotas never evict a
live view silently.

Order selection accepts only a server-issued view token and item ID. It reads
all eligible captured members, independently of the three contact previews or
page size, and applies live order/privacy authority. `get_orders_tab_data`
intersects those IDs with its independently authorized order response and calls
the canonical view read owner after successful selection. Failure rolls back
read state. The client closes its view only after a successful orders response.

`shared.sql` owns classification, DTO hydration and receipt batching. Exact
captured ticket counts, safe form context and retained same-occasion ticket
identities remain their existing owners. Contacts are hydrated live from the
authorized order and are never copied into event-log payloads.

Read receipts preserve both sequence bounds, gaps, reverse-tab retry and imported
baselines. `read_through_sequence`, read batches, `:legacy`/`:self` identities,
group keys and their indexes remain valid persisted history. The serving
contraction deletes functions, not that history or its source facts.

## Publication, projection and workers

Received-payment facts remain in the financial history and optional email
digests. The prepared in-app policy excludes them from the panel and bell;
email category settings do not enable them in the app. Optional email remains
off until the recipient explicitly opts in. Payment problems remain actionable
in-app notifications.

Publication captures eligible recipients. Hidden membership suppresses personal
participant enrollment; authorized order/waitlist activity and its delivery
incidents remain visible for hidden buyers. Unrelated hidden personal email stays
private. Own order actions require explicit prepared read receipts too.

Collection initializes once under `notification-center-organization:<id>`.
Repeated initialization is silent and never resets personal history or fabricates
notifications. Delivery allocation, worker leases, user-state locks and source
invalidation remain existing owners. Source rollback rolls notification intents
back in the same transaction.

Projection/backfill and retained-view repair execute as separate bounded commits.
Indexed authorized scope aliases select at most 100 frozen slots. Opening does
not aggregate historical deliveries. Idle scopes sleep until expiry or explicit
source invalidation; service-only health/retry/pause expose no contact payloads.

The protected `process-notification-center` Edge worker dispatches delivery,
projection and view repair independently. Its request secret is mandatory.
After-commit hints and scheduled recovery use the existing wake owner. Production
cron registration remains an authorized operation through
`automation/hetzner-supabase/runtime/install-notification-center.sh`; no rollout
or worker configuration is performed by the local code reduction.

## Form availability and domain policy

`eshop_forms/form_availability.sql` owns manual/time opening, effective schedule
precedence and the inclusive end. Registration checks this before its existing
blueprint/capacity/waitlist rules. Capacity recovery is not a form opening.
Availability keys use `form-availability:<id>`; capacity keys use `form:<id>`.
Before-save draining consumes overdue old boundaries before comparing the new
configuration at the same captured instant. Missed start/end transitions retain
their configured times; end is due one microsecond after its inclusive boundary.

Lock order is organization gate, domain locks, source and recipient snapshot.
Maintenance skips locked forms and rotates a bounded cursor. Create/copy/setup
establish a silent baseline; deletion retires source state without a fake close.
Existing domain and e-mail send guards, provider fencing and bank-account rules
remain unchanged. Recovered bank episodes cannot produce duplicate actionable
incidents.

## Local contraction and verification

`automation/notification-center-feed-manifest.json` and its assembler own the
new forward migration. Historical migration bytes remain immutable and may
create older functions before the final contraction explicitly drops their exact
signatures. No CASCADE or persistent compatibility trigger is used. Current
canonical sources, grants and security inventories cannot reinstall those APIs.
`serving_contraction_test.sql` verifies absence of all retired overloads.

The Slunovrat exception concerns messages pushed to Android/iPhone from the news
workflow. That separate delivery path is unchanged. The user explicitly allowed
retiring old editor/admin-center APIs; this does not authorize production rollout
or propagation to a tenant branch.

Current measurement commands are `automation/notification-center/benchmark.mjs`,
`sustained.mjs` and `maintenance_benchmark.mjs`, with guarded disposable connection
and fixture lifecycle in `benchmark_support.mjs`. Set `NOTIFICATION_BENCH_SMOKE=1`
for the benchmark's nonempty three-order smoke. Sustained and maintenance append
to its receipt. Prefix receipts now produce compacted read history plus unread
activity, rather than thirty presentation rows. These SQL timings are not a
production-capacity or browser-latency claim.

Admin notification email uses the existing deliveries as its durable input.
`collect_notification_center_emails` advances a per-organization/recipient sequence
cursor and commits membership independently of feed projection.
`enqueue_notification_center_emails` closes a recipient's fixed 300-second window
in a separate commit through the single `email_messages` queue. A terminal or
unknown intent is never replaced to compensate for an uncertain provider result.
Profiles lock before source cursors, dispatches and the existing queue locks;
feed projection never acquires a profile lock. Recipient settings only write
preferences, without mutating queued messages.

Captured facts, domain relevance, display metadata and current permission scope
vectors are shared with UI preparation. Email creates no UI projection scope,
read receipt, prepared-facts cache or new financial calculation. The final send
statement validates the same authorized context/fingerprint and changes both
attempt and message atomically. Failed snapshot validation rolls back send
metering/capacity and prepares the same intent again. A changed address cancels
that intent permanently.

`admin_notification_digest` is the only recipient-scoped, tenant-null kind.
Tenant reports exclude it. Its owner sees only self delivery status in the
existing settings panel; operational diagnostics remain service-only.
Bank incidents use BankSync's incident UUID and readiness across tenant
projections. There is no independent center bank poller or bank email producer.
The forward migration refuses legacy in-flight/unknown bank messages until the
original queue reconciliation resolves them with evidence. Historical accepted
message content and audit remain intact. See the
[local implementation receipt](../../../docs/plans/admin-notification-delivery-RESULT-2026-11-12.md).


`email_policy.sql` is the sole owner of the fixed aggregation interval. Envelope
creation, the database deadline CHECK and the settings projection use it; the
localized panel caption derives its duration from the same server metadata.
This is product policy, not a recipient setting. Future interval changes need a
forward migration accounting for existing envelopes.

Bank email is required only for canonical administrators of the affected account
(`bank:<connection>`, never `bank-occasion:<occasion>` alone). Optional stop,
subscriptions and event muting do not disable it. `email_policy.sql` owns the
required-kind policy; settings expose required kinds without editable toggles.
Captured required work can enroll an optional-off profile using the shared
profile-creation advisory fence. Current permissions, tenant activation, domain
readiness and the sole email queue/provider gate remain mandatory.

`provider_problem` is the corresponding required connection-administrator alert
for Stripe/Barion. Connector registry adapters project their existing state and
worker failures into one serialized connection episode. Prepared views and
email reuse the episode and the same live scope vector (`provider-unit:<unit>`),
with no connector-health or financial recalculation while serving or sending.
