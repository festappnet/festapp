# Notification center

The shared administration chrome mounts the bell. Its controller is personal to
the authenticated user and organization; route context only selects the current
occasion's priority. Unit routes do not inherit the previous occasion. Retained
inactive route instances and background apps stop polling.

Only `open_notification_center` acknowledges a snapshot, including unloaded
history. Badge reads, group expansion, pagination and foreground status refresh
never acknowledge. Successful open fences badge reads already in flight. User,
organization and rights changes invalidate pending responses and cached content.
Missing additive RPC capability hides the feature; there is no local inbox or
Realtime fallback.

An open panel keeps its group and row order. Every 15 seconds it reads the badge
and hydrates already loaded IDs through `get_notification_center_updates` in
sequential batches of at most 200. The server rechecks access and snapshot
membership. Missing IDs remove revoked rows; permission errors clear cached
content, while transport failures preserve it with an inline retry. Incoming
new IDs only appear after the user's explicit snapshot refresh. Closed panels
only poll the badge every 60 seconds.

Notification DTOs are presentation projections, never permission grants. Order
links use `?orderId=` on the canonical orders/current route, which selects from
the route occasion's authorized bundle before opening the existing order or
waitlist dialog. Email links use `?messageId=` on orders/email-history and the
existing scope-aware reporting owner; the target must exist in that authorized
scope before detail is opened. Organization-only email uses that same owner
with an organization scope and a concrete message target. Account connection
links require dynamically authorized account/unit IDs and use the existing
bank editor route. Organizers only receive safe affected occasion links.

Absolute navigation uses `pushRootPath`, preserving the existing draft guard.
No generated router source is hand-edited. The focused scenarios are registered
as `notification_center` in the existing shared default-locale Flutter root.


Temporary UI preview is controlled by
`NotificationCenterRollout.visibleToEveryone`. While false, only the signed-in
`bujnmi@gmail.com` identity sees the bell; tenant-prefixed login addresses are
normalized with the existing AppConfig helper. Hidden accounts do not start
notification polling. Set the flag to true in the next build to show the bell
to all otherwise eligible users. This flag changes neither RPC access nor
server delivery and is not an authorization boundary.
