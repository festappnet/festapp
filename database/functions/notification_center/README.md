# Organization notification center

A private personal projection, outside public sync, news/push delivery, the
outbound email queue and BankSync. Only trusted explicit domain owners publish;
there are no application triggers, second queues or client-side publishers.

## Canonical collection boundary

The published `20261024235000_notification_center_canonical_availability.sql`
retired activation/tenant rollout in favor of `notification_center_organizations`
and `initialize_notification_center_internal`. Organization creation initializes
collection once under `notification-center-organization:<id>`. Repeat
initialization is silent and does not reset personal history. No activation
setter, enabled column or compatibility activation helper is recreated.
A local 2026-10-24 release receipt establishes this prerequisite and a released
grouped client. See the [feed implementation record](../../../docs/plans/notification-center-feed-plan-2026-10-26.md).

## Publication, projection and acknowledgment

Publication captures eligible recipients and suppresses a verified administrative
author. The exclusive projector lease, bounded per-recipient revision work and
personal state row lock retain their original ownership. Delivery allocation
and explicit `open_notification_center` serialize on that same personal row;
only open advances the acknowledgment watermark. Pagination, badge, mute and
known-ID hydration are read-only with respect to acknowledgment.

All private projection tables have RLS and no client grants. Every read rechecks
organization/context and current event-specific rights before private DTO
hydration. The canonical bank account and program administration permission
rules remain intact. Email reporting retains its cancellation/recovery policy.

## Item feed and external serialization

`get_notification_center_feed` uses `notification_center_visible_internal` to
select the last delivered event revision at or below the personal snapshot.
Ordering is section ascending, historical event time descending, UUID descending.
A base64 JSON cursor validates organization, snapshot and occasion context plus
the exact sort tuple. Limits count items; no group preview limit truncates a page.
A late delivery of an older event is excluded from an already open snapshot.

`open_notification_center` adds `feedSupported`, `feedItems`, `feedNextCursor`;
the badge advertises capability without acknowledging. The published grouped
page/group RPCs and `groups/nextCursor` fields are external legacy serializers
over the same authorized selector. They are retained for the released grouped
client, never called by the new Flutter. Retirement requires a separate release
inventory and forward contraction of those RPCs, group columns and indexes.

Order contacts are hydrated from the authorized current order in the same tenant
and occasion. They are absent from the event log. Creation/waitlist counts are
captured from distinct actual ticket identities; cancellation/offer producers
supply their actual affected counts. Safe configured multiple-ticket context is
captured at publication, never inferred from remaining capacity or price.

## Form availability

`eshop_forms/form_availability.sql` owns the manual/time gate and preserves the
existing effective schedule precedence and inclusive end. Registration mode
calls it before its unchanged blueprint/capacity/waitlist decisions. Capacity
recovery never means a form opening and never adds a second unread episode.

Availability source keys are `form-availability:<id>`; capacity keys stay
`form:<id>`. Before-save draining consumes overdue OLD schedule boundaries;
only then does the same reducer compare the successful new configuration at the
same captured instant. Counter and event commit atomically. A missed start and
end produce both historical transitions at their configured times. End is due
one microsecond after its inclusive boundary. Manual changes outside a valid
window do not falsely open a form.

Lock order is organization gate, domain form/product/inventory locks, source,
then event/recipient snapshot. Existing save/delete/occasion command owners take
the gate before their form locks. Maintenance skips locked forms and rotates a
bounded cursor so a busy early form does not starve later due forms. It uses the
existing maintenance cron and separate family budgets; email, bank and projector
owners remain unchanged.

Initialization, upgrade, create, copy and same-transaction wizard authoring take
a silent baseline. A creation transaction marker prevents a later step of that
same authoring command from fabricating an opening. Deletion retires due state
without a close event. Existing events retain their historical facts and time.

## Migration and verification

The explicit forward manifest is
`automation/notification-center-feed-manifest.json`; the assembler verifies
historical prerequisite digests and canonical table parity. It never regenerates
applied history. Only the new delta is generated. The restored 2026-10-24
prerequisite files are byte-for-byte copies of their published Git source.

Actual SQL, concurrency, Flutter, clean/upgrade rehearsal and isolated full-app
receipts live in the [execution evidence](../../../docs/plans/notification-center-feed-evidence-2026-10-26/README.md).
Local implementation is separate from production migration and release.

## Temporal order history (2026-10-26 follow-up)

`get_notification_center_timeline` combines recent individual entries and older
order-action counts per occasion and calendar period. The client constructs
contiguous day/week UTC intervals using its local calendar, anchored at
`open_notification_center.snapshotAt` down to `oldestOrderAt`. The server validates
coverage/non-overlap and binds its keyset cursor to recipient, organization,
occasion, snapshot, anchor and calendar. Private DTO/contact hydration happens
only for actual page rows. No new projection table or delivery system is added.

`get_notification_center_timeline_group` pages all mixed order kinds in one period;
`get_notification_center_timeline_group_updates` rechecks full counts under live
permissions. Neither pagination nor expansion acknowledges. Forms and other
non-order events never enter these groups. All readers share the existing
latest-delivered-revision selector and current event-specific authorization.

The single-place label uses captured configured multi-place context when present.
Older events missing context/count hydrate only those missing fields from the
authorized live order/form; captured counts and configuration are never rewritten.
`order_context.sql` is the shared owner used by publication and legacy hydration.
The new forward migration is `20261026150000_notification_center_order_periods.sql`;
all previous migration bytes, including the flat feed, are sealed prerequisites.

## Category overview and one-request operations (2026-10-28)

The current client uses `get_notification_center_daily_overview`; the installed
RPC name remains stable while the grouping is now per occasion and kind across
all dates. One RPC returns complete order counts, place totals, at most three
recent authorized contacts, pagination and the unread badge. All non-error
occasion events are rolled up; email and bank incidents stay separate. Each
row's date is the most recent occurrence, converted using the validated display
timezone and PostgreSQL `AT TIME ZONE`. Canonical IDs are `occasion-kind:<id>:<kind>`
and do not contain a date. Cursor context binds recipient, organization,
occasion, snapshot, anchor instant and zone. The current grouping migration is
`20261028013000_notification_category_rollups.sql`.

`p_open=true` locks the existing personal state row, captures its pre-read watermark
and delivery snapshot, includes occasion preferences and acknowledges only after
all data succeeds, within the same transaction. A failed request never confirms
unseen data. Other operations share the same selector without acknowledging.
Known-ID refresh accepts at most 10,000 IDs and returns only those IDs in one RPC;
normal pages remain bounded to 200 overview rows. Revocation removes summaries
and contact previews together. The closed-panel badge RPC remains an independent
cheap eligibility/sequence check, without aggregation or contact hydration.

Place totals use captured positive historical event counts only and appear only
when every group member has a known count and multiple places are meaningful.
Unknown values suppress the complete total; current order size never rewrites a
historical multi-order sum. Single-place application flows omit redundant totals.
The earlier overview RPC remains for already released clients. The forward-only
migration is `20261027220000_notification_center_daily_overview.sql`.

Group totals retain captured counts and form context. Missing legacy fields are hydrated in batches from the authorized same-occasion orders, retained distinct ticket identities and distinct form contexts, matching the individual DTO contract. Multi-place applicability is returned even when the exact total is unavailable; clients show an explicit unavailable label rather than silently omitting places or inventing zero. No additional client RPC is needed.

Category rollups group all non-error events by occasion and kind across dates; email and bank incidents stay independent. The latest event supplies time/context, while all authorized delivered order activities in the frozen snapshot contribute counts and the latest three contact previews. Canonical IDs omit dates. The existing RPC name remains installed-client compatible; old day IDs accepted during loaded-row refresh resolve to one rollup under the first caller alias, never restore day grouping. New opens/pages use canonical occasion-kind IDs. Group selection uses the same entire category and snapshot.

## Seen, active and bounded history (2026-10-28)

The center is a recent-activity overview, not a task-resolution queue. A successful
open acknowledges the personal organization delivery snapshot; it does not alter
orders, resolve delivery/bank problems, or delete history. Read labels/dots keep
the pre-open watermark during that visit. Failed opens do not acknowledge.

Ordinary activity is limited to the30 days preceding the frozen snapshot anchor.
Email and bank incidents are eligible regardless of age until their source status
is recovered/resolved; viewing or clicking is not resolution. The same private
policy controls badge eligibility, overview rows and selected order membership.
The center returns at most100 latest relevant items (complete category counts,
not100 member events), exposes truncation explicitly and terminates pagination.
Older records remain available in their authoritative order/email histories.

Selection scope is captured before dismissing the notification overlay and
includes snapshotAt. Native grid readiness is awaited without a two-second render
deadline, and controller replacement remounts its own grid state. Automatic clean
refresh preserves checked model IDs, including selections made while fetch was
in flight, while existing filters still clear hidden selection.


## Personal read batches (2026-10-28)

`read_state.sql` owns the server classification and per-recipient closed batch
receipts. The legacy `read_through_sequence` remains a frozen transition baseline;
`seen_through_sequence` advances when the center opens. Opening does not read the
items. Own `order_created`/`order_cancelled` activity is history, never new for its
actor, while eligible colleagues still receive it as unread.

Batch IDs end in `:batch:<afterSequence>` and remain stable when reading seals
the bounded receipt. Legacy history and own activity use
`:legacy`/`:self`. The server returns `isRead`/`isSeen` and precise sequence bounds.
Counts, contact previews and selected orders use the same eligible batch. The
existing orders RPC records an explicit `markRead` within its successful
transaction, not a per-order client request. Errors remain separate incidents;
reading never resolves them. New arrivals beyond the captured bound remain new.

Migration `20261028130000_notification_personal_read_batches.sql` installs the
schema/helpers and producer, overview, badge, selector and orders RPC changes
before the Flutter release. No historical customer-event backfill is required.

## Deleted applications and orders

Hard deletion removes the matching `occasion_joined` or order notifications in
its existing domain command transaction. Order deletion also removes email
problem attention and email source observations before deleting the messages.
Recipient and delivery rows cascade, so summaries, contact previews and badges
all derive from the remaining events. Cancellation alone retains its history.
The service-only `notification_center_purge_deleted_internal(organization)`
repairs historical orphan attention for one explicitly selected tenant; it
never deletes an application, order, live message or another tenant's history.

## Current source and immutable history

The forward manifest now targets
`20261031120000_notification_center_source_alignment.sql`, including the shared
current-membership policy for participant attention. The prior personal-batch,
deleted-entity and current-participant migrations are sealed prerequisites with
verified digests. The assembler checks current canonical SQL against the new
forward output and refuses to replace any differing existing output, including
its default destination. Historical migrations are never regenerated after a
source change; advance the manifest to a new forward migration instead.

Hidden organization members (`organization_users.is_hidden`) never publish
`occasion_joined` activity. Item authorization and the live center policy also
exclude historical joins for currently hidden members, including frozen panels,
group counts and unread badges. Membership and administration access remain intact.

Personal subject visibility is shared by publication, item authorization, DTOs
and live center membership. It covers membership IDs, email recipient IDs and
normalized tenant-scoped email identities, and order/waitlist buyer identities.
Hidden operators do not suppress visible customers' orders; operational capacity
and form facts retain their normal meaning. This does not erase accounting or
security audit records.

The explicit privileged `purge_hidden_notification_history_internal` maintenance
boundary removes existing hidden-subject events and cascades recipient/delivery
projections. It clears event-specific read receipts and source-state event links,
while preserving business entities, shared read batches and sequence watermarks.
The forward cleanup is scoped to organization 3; publication already rejects
new hidden-subject activity before an event row exists.
