# Notification center Flutter adapter

The controller owns one personal batch overview and opaque cursor. The server owns
complete authorized counts, bounded contact previews, ordering and acknowledgment.
See the [SQL contract](../../../database/functions/notification_center/README.md).

The panel has one heading and mute menu per occasion ID, with continuous rows
below. Age belongs to each row as small secondary metadata: Today, Yesterday,
relative days within the last week, or older local dates. There are no day subheads.
Unread rows precede read history within each occasion and use a restrained tint,
trailing semantic dot and stronger title. Same-name occasions remain distinct.
Only unread activity of the same occasion and action kind combines; reading seals
that batch, so later arrivals create another notification across calendar dates. Selecting a summary opens the existing common order
page directly; there is no expansion, unread filter or exact time in the list.

A summary shows its activity count and an exact historical place total when all
underlying counts were captured and multiple places are meaningful. One-order =
one-application flows omit the redundant place total. Missing legacy counts never
turn into a partial sum; singleton facts retain their existing presentation.
The server previews at most three latest authorized contacts. The client uses the
shared customer label rule, removes duplicates/empty values, and measures actual
text width at the current text scale to choose how many names fit. Place totals
have priority and wrap independently when a name needs its own line.

The current controller uses only `get_notification_center_view`, the prepared
badge and lazy settings RPCs. Successful ready `open` acknowledges its delivered
snapshot as seen; preview/preparing/page/refresh never acknowledge new arrivals.
The server owns opaque recipient/context/timezone-bound tokens, at most 100
frozen slots per view, four live views per recipient and a 30-minute lease.
Expired/quota/preparing states are explicit. The user can release their older
views at the quota; no automatic eviction changes another tab's selection.

Refresh passes one confirmed revision, never loaded ID arrays. A server-confirmed
unchanged response retains rendered rows after current permissions, privacy and
bounded display facts have been checked. Private data is cleared while repairs
run. Source repairs retain slots and captured ranges. Settings load only when
requested. The feed and settings have independent retained scroll positions;
progress does not change the panel viewport.

Related-order selection carries only the token and row ID. The server reconstructs
and validates its captured group/range and writes the read receipt through the
canonical orders owner. The client releases that lease after a successful orders
response; failed navigation remains retryable. Other actionable items use
`mark_notification_center_view_item_read`. There is no legacy fallback.
Migration `20261105120000_notification_center_prepared_views.sql` and the protected
`process-notification-center` Edge worker must be available before this client.
Released clients retain their existing overview/temporal APIs.

Web uses the browser's IANA timezone; native uses the application's selected zone
from the shared time owner. The zone, snapshot instant and returned snapshot day
are frozen for pagination/refresh and relative labels. PostgreSQL computes day
boundaries in that zone, including DST; UTC offsets are never guessed.

The bell clears its private state while the shared context refresh is pending,
then reads the badge after the authoritative context completes. Context invalidation
and browser resume share one scheduled update, including when frames were paused.

When closed, only the lightweight prepared badge RPC runs every 60 seconds: it
checks for an eligible unseen delivery without hydrating contacts or computing
summary/place totals. Open panels refresh loaded data every 15 seconds through
one RPC. Background/inactive routes pause. New arrivals wait for explicit refresh,
and generation/revision/badge fences reject stale identity or snapshot responses.
Email/bank incidents remain separate, with authorized detail/recovery behavior and
safe organization-only affected links. Form opening/closure rows resolve their stored form ID through the authorized
occasion catalog and open its current editor URL. Missing forms stay unavailable.
Informational rows without a supported target have no navigation.

Focused tests register as `notification_center` in `default_locale_5_cases.dart`
through `shared_default_3_test.dart`; relative labels have the existing standalone
time test. `test/browser/notification_visual_preview.dart` renders the real themed
panel with synthetic data. Full-app fixtures remain in
`test/browser/notification_center_e2e.dart` for isolated local Supabase testing.
