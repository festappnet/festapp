# Order-created webhooks

Webhooks extend the existing `/integrations/v1/operations/` API and its personal
OAuth consent. Use an explicitly registered **operator** API client with these
scopes and all corresponding `webhooks.*` operations in its allowlist:

```text
festapp:ticket-layouts:read
festapp:orders:read
festapp:webhooks:read
festapp:webhooks:write
```

Existing Make/order-summary connections do not gain buyer-data access. The
subscription expires with the original consent, stops after revocation or loss
of live order-management rights, and does not transfer to a new connection.
The subscription freezes the connection deadline returned at creation (at most
the current 30-day idle deadline, bounded by consent expiry). Later OAuth refresh
does not extend that subscription; explicitly create a replacement before its
reported `expiresAt` when using longer consent. No worker activity extends it.
The original connection's configured resource, tenant and occasion selection
remain authoritative. This is not an autonomous organization service identity.

Create by POSTing to `/operations/webhooks.create` with a normal OAuth bearer
or DPoP credential according to the registered client's proof policy:

```json
{
  "occasionId": 7,
  "formId": 12,
  "commandId": "11111111-1111-4111-8111-111111111111",
  "expectedContractVersion": 1,
  "eventTypes": ["net.festapp.order.created.v1"],
  "url": "https://your-service.example/webhooks/festapp"
}
```

`formId` is optional; without it the subscription covers the selected occasion's
forms. Persist `data.subscription.id`, `version`, and the returned
`data.signingSecret` in your protected credential store. Secrets are returned
only by create/rotate, including an authorized replay of the identical command.
Preserve the exact command UUID/body after an uncertain result. A confirmed
conflict requires reading the current version and making a new explicit command.

| Operation | Additional input | Result |
|---|---|---|
| `webhooks.list` | `occasionId` | Subscriptions, versions, state and destination hostname; no secret or URL token |
| `webhooks.update` | Subscription ID, command UUID, expectedVersion, `state` (active/paused) and/or URL | Versioned configuration |
| `webhooks.delete` | Subscription ID, command UUID, expectedVersion | Stops future fanout/dispatch |
| `webhooks.rotate_secret` | Subscription ID, command UUID, expectedVersion | New secret; previous key accepted for one hour |
| `webhooks.test` | Subscription ID, command UUID | Queues one synthetic test event |
| `webhooks.deliveries` | Subscription ID, optional `before` UUID | Up to 50 safe delivery records, ordered by ID; use the last ID as the next page key |
| `webhooks.redeliver` | Subscription ID, delivery ID, command UUID | New attempt series for a completed/exhausted retained event |

All inputs include `occasionId`. An update changes state/URL; scope, form and
event type are immutable. Create another subscription to change its scope.
Rotating again during the one-hour overlap is rejected. A 410 receiver response
disables the subscription; list its latest version before explicitly reactivating
it. Paused subscriptions create no new events and pause existing pending work.
Reactivating does not backfill orders placed while paused. Redelivery cannot
reconstruct expired/deleted events or recall data already delivered externally.

A submitted order can contain several people. Creation does not imply payment,
attendance, account login, waitlist entry or offer acceptance. The payload is
structured CloudEvents JSON, with the original saved occurrence time, stable
order/form/occasion IDs, customer name/surname/email/phone, submitted responses keyed
by numeric field ID, field titles/types at submission time, and individual ticket
IDs/answers. No QR/admission symbols, form secrets, internal notes or payment
credentials are included. Subsequent edits do not change an event's saved body.

The operator OpenAPI reference includes a `webhooks` section with complete
order/test JSON schemas and required signature headers. The sender validates the
allowlist before delivery, so an unexpected future SQL field cannot silently
become another disclosure. Summary-profile references omit these receiver schemas.

## Receiving

Verify `webhook-id`, `webhook-timestamp` and `webhook-signature` using
[Standard Webhooks](https://github.com/standard-webhooks/standard-webhooks/blob/main/spec/standard-webhooks.md).
Decode the base64 key after `whsec_`, then HMAC-SHA256 the exact UTF-8 bytes of
`deliveryId.timestamp.body`. Signatures are space-separated `v1,BASE64` entries
during rotation. Check the send timestamp within five minutes and compare the
MAC in constant time. Parse JSON only after signature verification.

`event.id` and its canonical `source` identify the occurrence across recipients.
`webhook-id` identifies the delivery to one subscription and remains stable on
retry and manual redelivery. The send timestamp/signature is refreshed on every
attempt; the body and occurrence time remain unchanged. Do not assume ordering
or exactly-once effects. Deduplicate both delivery and source/event identity as
appropriate for your business action.

Acknowledge 2xx after durable acceptance, then perform your action asynchronously.
See [the runnable Node receiver](examples/webhook-receiver.mjs), which verifies
raw bytes and persists a deduplicated SQLite inbox before 202. It listens on
loopback for your HTTPS reverse proxy; point the subscription to the public
HTTPS URL, not this loopback listener. Supply the existing signing secret via
`FESTAPP_WEBHOOK_SECRET`; the example neither generates nor logs credentials.
Treat saved inbox content as personal data and manage its access/retention.

## Delivery and operations

- Public HTTPS on port 443 only. No userinfo, fragments, local/internal addresses
  or automatic redirects. Every attempt re-resolves DNS and pins a validated
  public address while checking the original TLS hostname.
- Total attempt timeout 10 seconds. At most 4 active subscriptions are drained
  per worker tick, with one leased delivery per subscription. Empty polls use
  one claim RPC. Paused, disabled and expired endpoints make no polling/Auth
  requests; pending management intents still reconcile. Retention runs only
  through the existing cron job.
- At most 16 attempts in 72 hours; exponential backoff begins at 5 seconds,
  jitters 75-125%, and caps at 6 hours. Retry-After is honored within that deadline.
  Unsafe destinations block a delivery. All other non-2xx responses retry except
  410, which disables the endpoint.
- The original order transaction stores the immutable event and recipient rows.
  Failed checkout/rollback emits nothing; command replay cannot create another
  occurrence. Leases recover on restart and stale completion tokens are rejected.
- Snapshot reads stop after 7 days. Existing pg_cron purges payloads on a bounded
  ten-minute schedule even after consent expiry. Safe delivery metadata lasts
  30 days. Order/form/occasion deletion removes associated private snapshots
  through foreign keys. The queue has a 100000-pending-delivery organization cap;
  capacity exhaustion fails atomically rather than silently losing events.
- The runtime's existing encrypted SQLite owner retains signing keys and
  command intents. Keys are persisted before SQL registration, so lost responses
  reconcile the same subscription/key. No new service/process is installed.

Apply the additive forward migration before deploying the updated integration
runtime, then explicitly enable the registered client policy and obtain new
consent for the new scopes. This local implementation does not deploy or change
existing clients automatically. Stop admission/dispatch for rollback; retain
outbox/key/receipt state until reconciliation instead of dropping queued events.
