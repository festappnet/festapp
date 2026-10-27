# Notification center Flutter adapter

The controller owns a personal overview and one opaque cursor. The server owns
ordering, complete snapshot counts, delivery and current permissions. See the
[SQL contract](../../../database/functions/notification_center/README.md).

The panel groups the overview by occasion ID in first appearance order, with one
heading and mute menu per occasion. Same-name occasions remain distinct. Order
actions of each kind are one row per occasion, across the authorized retained
snapshot. The count means events of that kind, not seats or paid orders. A single
action retains its contact/place details; a summary previews the latest contact
with an explicit label rather than inventing distinct customers. Selecting either
opens the occasion's existing order overview, without expansion or an order modal.

All rows use a leading kind icon, title, optional detail and a trailing unread dot.
The list has no timestamps or unread filter. Email/bank incidents remain separate
and retain their authorized detail and recovery state; their problems never merge
with order actions. Organization-only incidents keep their scope and related
links. Informational form/capacity rows have no fake navigation affordance.

`NotificationItemPresenter` and `OrderModel.toCustomerData` use the shared core
customer label rule. Counts for individual tickets retain their existing historical
meaning, and capacity recovery does not imply that a form or sale has opened.

Acknowledgment deliberately retains the existing contract: explicit open/snapshot
refresh confirms the snapshot, including unloaded history. Rows retain the pre-open
watermark for unread styling during that opening. This is not persistent per-item
read tracking. Generation/revision/badge fences reject stale results after identity,
context, foreground or snapshot changes. Pagination and mute never acknowledge.

Every 15 seconds an open panel rechecks loaded IDs in batches of 200 through the
same authorized overview query. Counts and contacts update; revoked IDs disappear;
positions and unread sequences stay fixed, and new arrivals wait for explicit
refresh. Closed panels poll the badge every 60 seconds; background routes pause.

The compact overview RPC requires migration
`20261027210000_notification_center_overview.sql` before deploying the client.
The released older timeline RPCs remain available for older clients; this adapter
has no temporal child state or expansion calls. There is no fallback data path.

Focused tests are registered as `notification_center` in
`default_locale_5_cases.dart`, through `shared_default_3_test.dart`. The real themed
panel can be inspected with `test/browser/notification_visual_preview.dart`, which
uses synthetic data without backend calls. Full-app fixtures remain in
`test/browser/notification_center_e2e.dart` for an isolated local Supabase tenant.
