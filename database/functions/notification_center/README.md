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
