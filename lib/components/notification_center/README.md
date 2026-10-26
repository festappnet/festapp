# Notification center Flutter adapter

The controller owns one personal timeline, its opaque cursor and lazily loaded
children/cursors for temporal order groups. The
server owns ordering, delivery snapshots, recipient eligibility and permission
checks. The [SQL contract](../../../database/functions/notification_center/README.md)
is authoritative.

The panel maps sections to occasion-ID blocks in first appearance order. Each
block has one heading and one mute control. Orders from the last 24 hours stay
individual; older order actions share daily, then weekly buckets, irrespective
of action kind. Form/program/capacity/health events remain individual rows.
Counts are full authorized snapshot totals, never the number of loaded children.
Expansion is read-only, paginated and keeps existing authorized detail navigation.
Organization-only incidents keep their own scope and authorized
related links. Informational form/capacity rows have no fake detail action.
Order, email and bank targets retain the existing authorized navigation and
draft guards. Published occasion/program kinds remain recognizable.

`NotificationItemPresenter` owns row presentation. Both it and
`OrderModel.toCustomerData` use core `formatCustomerLabel`: trimmed nonempty
name parts, otherwise trimmed email, otherwise empty. Counts above one always
show; one shows only in captured configured multiple-ticket context. Missing legacy form context/count may be hydrated from the authorized live order;
captured historical values always win. Capacity text means capacity reached/places
available, without inferring a sale or form opening.

Only explicit open/snapshot refresh acknowledges, including unloaded history.
The controller rejects stale responses through generation, revision and badge
fences. Identity/context changes clear personal state. Every 15 seconds an open
panel hydrates loaded real event IDs in batches of 200 and separately rechecks
collapsed counts. Revoked groups and loaded contacts disappear together. Generation,
revision and per-state identity fences reject stale expansion responses. New arrivals appear after explicit refresh. Closed
panels poll the badge every 60 seconds; inactive routes/background apps pause.
Mute never acknowledges or removes already loaded history.

The badge must advertise `timelineSupported`; a server without it has one unsupported
state and no grouped fallback or detection open. New Flutter never calls the
external grouped serialization RPCs. The published canonical administration permissions govern visibility and
collection; the retired rollout flag is not restored.

Focused tests are registered as `notification_center` in
`default_locale_5_cases.dart`, through `shared_default_3_test.dart`. Full-app
checks use `test/browser/notification_center_e2e.dart`, the synthetic fixtures
and a separate loopback Supabase project with external delivery disabled.
See [verified receipts and limits](../../../docs/plans/notification-center-feed-evidence-2026-10-26/README.md).

Calendar intervals are generated from device-local midnight constructors, so DST
days can contain 23 or 25 hours. The acknowledged snapshot captures the anchor
time and oldest order event; all page/group requests reuse these boundaries.
