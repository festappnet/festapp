# Notification center Flutter adapter

The controller owns one personal daily overview and opaque cursor. The server owns
complete authorized counts, bounded contact previews, ordering and acknowledgment.
See the [SQL contract](../../../database/functions/notification_center/README.md).

The panel has one heading and mute menu per occasion ID, with continuous rows
below. Age belongs to each row as small secondary metadata: Today, Yesterday,
relative days within the last week, or older local dates. There are no day subheads.
Read/unread rows share the same neutral surface; unread state uses the trailing
dot, stronger title weight and primary-colored age. Same-name occasions remain distinct. Only the same action
kind on the same day of the same occasion combines. Selecting a summary opens the existing common order
page directly; there is no expansion, unread filter or exact time in the list.

A summary shows its activity count and an exact historical place total when all
underlying counts were captured and multiple places are meaningful. One-order =
one-application flows omit the redundant place total. Missing legacy counts never
turn into a partial sum; singleton facts retain their existing presentation.
The server previews at most three latest authorized contacts. The client uses the
shared customer label rule, removes duplicates/empty values, and measures actual
text width at the current text scale to choose how many names fit. Place totals
have priority and wrap independently when a name needs its own line.

One RPC (`get_notification_center_daily_overview`) opens and acknowledges the
snapshot, fetches another page, or refreshes all loaded IDs and badge state. Opening
uses `p_open=true`; the watermark commits only after all overview data succeeds.
Other reads never acknowledge. The new function requires migration
`20261027220000_notification_center_daily_overview.sql` before deploying the client.
Released clients retain their original overview/temporal APIs.

Web uses the browser's IANA timezone; native uses the application's selected zone
from the shared time owner. The zone, snapshot instant and returned snapshot day
are frozen for pagination/refresh and relative labels. PostgreSQL computes day
boundaries in that zone, including DST; UTC offsets are never guessed.

When closed, only the lightweight existing badge RPC runs every 60 seconds: it
checks for an eligible unread delivery without hydrating contacts or computing
summary/place totals. Open panels refresh loaded data every 15 seconds through
one RPC. Background/inactive routes pause. New arrivals wait for explicit refresh,
and generation/revision/badge fences reject stale identity or snapshot responses.
Email/bank incidents remain separate, with authorized detail/recovery behavior and
safe organization-only affected links. Informational rows have no fake navigation.

Focused tests register as `notification_center` in `default_locale_5_cases.dart`
through `shared_default_3_test.dart`; relative labels have the existing standalone
time test. `test/browser/notification_visual_preview.dart` renders the real themed
panel with synthetic data. Full-app fixtures remain in
`test/browser/notification_center_e2e.dart` for isolated local Supabase testing.
