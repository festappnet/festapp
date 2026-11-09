# Isolated form measurement

`FormMeasurementSession` is the only owner of visitor role, eligibility, freshness,
generation and transport selection. It forwards saved consent as state. `FormDataLayer` owns
catalogue/funnel semantics, baseline and visit deduplication. Construction is
inert; `start()` subscribes synchronously and resolves policy asynchronously.
Policy errors recover; disposal is terminal. Captured senders belong permanently
to their original active grant. They never queue or replay earlier activity.

Measurement does not wait for consent: on an eligible form the runtime loads GTM and
Unit code at once. Consent Mode is set before GTM and later choices reach the frame
as an update, so the organizer's container decides what its tags may do. Missing or
broken CMP reports denied state. Absent/old embed helper or an unapproved host leaves
measurement off while checkout/layout continue. No same-origin script fallback.

The isolated `gtm-v1` frame sets Google's `cookie_flags` to
`SameSite=None;Secure` before loading the container so Google collection works in
this cross-site context. Consent Mode still determines whether storage is granted;
the cookie setting does not grant either purpose.

`purchase` and `generate_lead` carry `user_data` with the buyer's e-mail and E.164
phone, allowlisted at every boundary and cleared after the event. Nothing else from
form answers leaves, and contacts do not enter SQL conversion facts. Purchase means
an accepted order, not a settled payment. SQL facts retain stable event IDs on
authorized replay and remain independent of temporary runtime outages. Browser
delivery is best effort, not exactly-once or proof of delivery to Ads/Meta.

## Revision and handshake

`processing_revision` fingerprints stored organization/Unit switches, destinations,
privacy URL, profile, collectors, approved recipients, deployment/policy revisions
and `measurement_consent_version`. Cosmetic notice changes do not change it.
The positive Unit consent version defaults to 1 and can only increase through the
existing authorized aggregate mutation with optimistic concurrency. Increase it
when purposes, remote GTM content or privacy text at the same URL change. Festapp
cannot detect remote content changes at an unchanged ID/URL.

The public policy and service-only runtime RPC share the SQL projection. Worker
serializes an explicit manifest from the actual fetched configuration. Protocol 3
`festapp-measurement` ready/init/ACK bind that manifest, source window, origin,
instance and generation before any Unit script is inserted. Parent policy A and
Worker configuration B fail closed. Layout/scroll/theme `festapp-embed` stays at
protocol 1; old measurement messages never grant protocol 3 permission.

Pagehide/BFCache, role/identity changes, expiry or relevant policy changes invalidate
grant and pending sends, then remove the runtime. Hiding the page and consent changes
do not, so the container runs once per visit. Equivalent policy renewal preserves
the grant. Browser scheduling cannot promise instantaneous backend
revocation in a suspended process. Already delivered data cannot be recalled.

## Host CMP integration

New generated snippets explicitly opt into the host page's `window.dataLayer`
with `data-festapp-datalayer`; its GTM and CMP control the tags. Unit mode omits
the attribute, preserving existing embeds and working with older helpers.
Live attribute changes reinitialize transport. WordPress/Joomla expose the same
choice and retain Unit mode for missing or invalid settings.
Both modes still require an approved host and show no consent bar inside the embed.
Direct visits keep the Unit runtime and Klaro bar.

For Unit runtime measurement, the helper measures on its own. A host CMP adapter is
optional and only reports the choice (without one, runtime consent stays denied):

```js
const disconnect = FestappEmbed.connectMeasurementConsent(frame, {
  read(context) {
    // Stored record for organization + Unit, confirmed for its saved revision.
    const saved = cmp.readSavedChoice(context.organization, context.unit);
    return saved && {
      processingRevision: saved.processingRevision,
      analytics: saved.analytics,
      marketing: saved.marketing,
    };
  },
  subscribe(notify) { return cmp.subscribe(notify); },
});
```

A read returning null, or another revision, reports denied state. Simpler hosts use
`connectKlaro(frame, manager)` or `setMeasurementConsent(frame, {analytics, marketing})`;
a boolean means analytics only. The lease is random, local and lasts at most 60
seconds; it proves a live helper and carries no permission from the visitor.

## Isolation and operation

Each Unit runs on a separate canonical `*.pages.dev` site. The service credential
stays in Worker environment, never HTML or messages. The CSP restricts collectors,
rejects frames, workers and form actions; sandbox remains `allow-scripts
allow-same-origin` on the separate site. No new origin, collector or runtime is
provisioned by this change. Deterministic test tags demonstrate execution/network
boundaries, not live Google/Meta attribution.

Forward migration is generated by
`automation/assemble-form-measurement-consent-migration.py`. Historical migrations
remain immutable. Production application, compatible runtime/helper rollout,
source publication and enabling measurement are separate operations.

## Canonical protocol and choice ownership

Measurement protocol 3 denotes advanced execution with bounded conversion
contacts. SQL includes `measurement_protocol: 3` in the policy and processing
fingerprint; the shared contract requires it in every manifest. Layout/embed
protocol 1 is independent. The registered `gtm-v1` deployment profile stays the
same. Production has no protocol 2 fallback. Frozen protocol 2 code lives only in
negative compatibility fixtures with an exact source SHA.

`consent_required: true` in status/MCP means the visitor must have notice and
choice controls. It is not an execution gate. `required_purposes` lists the
reported analytics/marketing choices; both need not be granted to run.

All three public host choice adapters replace one active binding. A disconnected
or failed source reports denied, and an old disposer cannot change its successor.
Setter/Klaro choices bind to organization, Unit and processing revision; a setter
before the first context binds once when that context arrives. A new scope
requires a new choice. Revision-aware sources reread the new scope. Teardown
owns the source, lease, heartbeat and load listener. Pagehide stops liveness;
BFCache resume starts current liveness again, and a retired record stays inert.
Consent updates publish a fresh nested `festapp_consent` snapshot in the update
event itself, retaining its top-level analytics/marketing fields.

A rollout updates canonical SQL first, then the Worker, host helper and selected
web client. Unsupported mixed peers leave measurement off while checkout stays
available. A fully old client/helper/Worker group can temporarily retain its old
limited behavior against the new SQL; this does not prove protocol 3 delivery.
Never reuse an old saved choice under the new processing fingerprint. Applying
the forward migration twice preserves its hash, configuration, enablement and
conversion facts. Existing disabled measurement is never enabled by migration.
See the protocol fixture matrix and the dated implementation plan for the exact
compatibility cases. `/runtime` and `/runtime.js` must be one immutable build;
a dynamic policy hash alone does not identify the executing JavaScript.


## Stable page-event contract

`page_view` is the protocol 3 wire event. The shared contract's
`measurementDataLayerPayload` owns the sole destination projection, producing
`form_page_view` for embeds and `page_view` for direct visits, with a strict
`form_embedded` marker. Neither the embed bridge nor the runtime transport
changes event names. Receivers retain their own page context and the shared
projection attaches it to each event. Host frame context is cleared on revocation
and grant-generation changes. The host resets the embedded marker after each
push so native website events do not inherit it. Frozen pre-change protocol 3 receiver tests protect the
rolling-upgrade boundary. Existing receivers accept new senders and retain their
previous page-event name until upgraded. Deploy receivers before the client to
establish the new destination semantics without losing events.
