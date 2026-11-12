# Admin notification delivery

No production activation is implied by installing the schema or shared worker.
Activate only a specifically authorized organization through
`activate_notification_center_emails`. First activation baselines its existing
scope cursors once; repeated activation never resets them. Notification global
send policy must fit at most 10% of freshly verified provider daily allocation.
The canonical abuse backend retains recipient 288/day and 2/minute bounds,
global intent/send/preparation/backlog bounds, payload limits and all existing
SES capacity, pause, suppression and unknown handling.

Diagnose in this order, using privileged service access:

1. `get_notification_center_email_health()` reports cursor lag, oldest unscanned
   delivery, expired catch-up, oldest due envelope, active/unknown queue counts
   and missing-address envelopes. The collector consumes at most 500 deliveries
   per selected scope and 20 scopes per recipient pass.
2. Inspect the affected `notification_center_user_state` sequence cursor and
   activation boundary. Unread/seen state never controls external delivery.
3. Follow `notification_center_email_items` and normalized `item_sources` to the
   recipient's dispatch. Its opened/due times differ by exactly 300 seconds.
   Backpressure allows one collecting catch-up envelope beside one active queue
   intent. Missing addresses defer rechecks for five minutes. Enqueue quota deferral uses the original abuse backend release time and preserves the collecting envelope; it does not spin an immediate wake loop.
4. Follow `dispatches.message_id` to the original `email_messages`, attempts and
   provider events. `queued` means committed handoff, not provider delivery.
   Reconcile unknown through `reconcile_unknown_email` with original evidence;
   never create a replacement digest. Tenant reports deliberately omit this
   private cross-organization message.

The standard center worker calls collect and enqueue as separate HTTP RPCs.
Email phase failures have separate counters and do not roll back the feed or
stop its prepared-view phase. The existing wake scheduler discovers due work;
a future 300-second deadline does not justify an immediate wake loop.

Deployment requires the normal exact-main CI gates, selected tenant scope and
Functions pause/drain/restart workflow. Before replacing old bank runtime code,
resolve all `BANK_SYNC_WARNING` sending/preparing/unknown rows through the old
worker and evidence protocol. The migration cancels unstarted legacy rows and
rejects any remaining active legacy intent atomically. It adopts historical
recipient incident identities as baseline, preserves accepted audit and migrates
serialization profiles with optional mail stopped. Bank alerts are mandatory only for the current canonical administrators of that account (`bank:<connection>`); order-reader scopes never authorize bank email. Required alerts bypass optional stop/subscriptions/muting, but retain activation, readiness, live authorization and the single provider gate. Captured required deliveries can create an optional-off profile under the same advisory lock as self-save. No bank subscription is migrated. Tenant email
collection remains off until explicitly activated. A rollback disables collection
and self delivery and invalidates unsent intents through the queue; it never
restores the retired bank producer or erases unknown evidence.

Connection operational alerts (`provider_problem`) are likewise required for
the affected unit's canonical connection managers. `bank-occasion` and ordinary
order-reader/organization-admin roles alone authorize neither required email.
Diagnose Stripe state/status_failures or Barion attempt reconcile_failures first,
then `eshop.provider_connection_notification_incidents`, the captured delivery
and the same recipient item/dispatch/queue chain. The adapter registry owns the
health projection; the episode owner serializes one connection across workers.
Three consecutive transport failures use one shared policy constant. Confirmed
Stripe restriction/revocation can alert directly; verified recovery closes the
episode. Intentional disconnect/disabled sandbox connection is not an outage.
No independent provider-health scheduler or outbound email path is installed.
