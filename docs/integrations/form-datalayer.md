# Form measurement contract

Measurement is off by default. The effective permission is the conjunction of
platform permission, organization permission, Unit permission, form intent,
a supported Unit runtime deployment, a safe public browser context, a valid
organizer HTTPS privacy policy URL, and saved visitor consent. Saving configuration or entering a GTM ID grants none of these.

## Configuration and ownership

- Organization: `organizations.data.FORM_MEASUREMENT_ENABLED`, boolean default
  false. Existing organization administrators can allow/deny measurement only.
- Unit: `units.data.measurement_enabled`, boolean default false;
  `measurement_gtm_container` and `measurement_scripts` contain the one shared
  destination configuration. Existing Unit managers edit it through the normal
  Unit settings aggregate/UI/MCP. Disabling preserves ID and script text.
- Form: `forms.data.analytics` contains only `{enabled:boolean}`. Existing form
  authors toggle it through the same form aggregate/UI/MCP as other settings.
  Form-level destination code and enhanced-conversion settings are rejected.

Organization denial dominates every Unit and form. Unit denial dominates its
forms. UI hides Unit and form measurement controls when organization permission
is absent and preserves stored choices. With organization permission, form
authors can save form intent even while Unit measurement is off; the editor
explains the Unit block without changing Unit permission. Public/catalog Unit readers
redact destination code; authorized Unit manager reads retain it. None of these
administrative switches edits platform deployment policy.

Form MCP example: `forms.save` with `settings.analytics.enabled`. Unit MCP uses
`units.settings.save` with `changes.settings.measurement_enabled`,
`measurement_gtm_container`, `measurement_privacy_url`, and `measurement_scripts`. Omission preserves a
value. Nullable Unit destination fields clear with null; form `enabled:null`
resets to off, `analytics:null` clears form intent. Copies reset form intent;
there is no copied per-form destination. The canonical Unit configuration JSON
also owns the script-length limit used by generated Dart/JS constants.

Units store nullable `measurement_privacy_url` as an absolute HTTPS URL without credentials (maximum 2048 characters). A valid URL is required for measurement, conversion recording/export and the consent notice, including host dataLayer transport; partial configuration can still be saved, and changing a valid URL does not replace the runtime frame.

## Database authority

The private `analytics` schema contains exactly these measurement tables:

- `analytics.organization_policy`: platform permission, revision and operator
  evidence. Missing means denied.
- `analytics.unit_runtime`: the approved deployment origin/profile, permitted
  parent/ancestor and collector origins, revision and operator evidence.
- `analytics.conversion_facts`: immutable finalizer facts with non-authorizing
  event UUIDs, keyed by order and conversion kind.

Browser/API roles, including service_role, have no direct schema/table access.
All functions remain in `public` under repository rules. The service-only
bootstrap RPC checks a typed predicate against stored form -> occasion -> Unit
-> organization and exact configured runtime/parent origin. Runtime deployment
credentials stay server-side. Browser renewal returns minimal effective policy,
not GTM IDs, scripts, contacts, JWTs or order capabilities.

A single SQL status owner supplies editor/MCP status and public runtime policy.
`organization_allowed` means platform permission; `organization_enabled` and
`unit_enabled` are administrator-owned gates. `eligible` is configuration
eligibility, never proof of visitor consent or a tag's delivery. Historical
mutation receipts remain immutable and labelled historical; UI/MCP refresh the
current status through existing authorized readers.

## Runtime, consent and transport

The event owner is `FormDataLayer`; it owns the checkout funnel and policy
renewal. The pure shared contract rebuilds payloads at every untrusted message
receiver. Embed and runtime assets are generated from that source; there is no
second funnel or manually maintained payload whitelist.

Each Unit runtime has its own canonical `PROJECT.pages.dev` origin, a separate
registrable site. The iframe permits scripts and its own storage but no top
navigation, popups, forms, nested frames or workers. Only its dedicated CSP
allows inline code, because GTM Custom HTML and Unit scripts are intentional
runtime capabilities. The main application CSP is unchanged; unsafe-eval and
attribute handlers remain forbidden. No third-party code executes in checkout.

Standalone forms dynamically load the actual Klaro manager/UI. The adapter
reads confirmed saved analytics consent, never an unsaved checkbox draft.
Consent is stored per organization/Unit. The same saved-choice adapter is
available to embedding hosts via `FestappEmbed.connectKlaro(frame, manager)`;
the manager must have a service named `analytics`.

Default embeds use the Unit runtime after a verified host consent lease.
`data-festapp-datalayer` is an explicit host-owned transport override: events go
only to the host's dataLayer and its own container, without also executing the
Unit container. This preserves host opt-in behavior and avoids fanout duplicates.
Neither markup alone nor an unverified message grants consent.

Policy is rechecked every 20 seconds with an at-most-60-second lifetime. Saved
consent renewal preserves the existing epoch; revoke/expiry/regrant and scope or
configuration changes replace it. The trusted parent removes the iframe on
revoke, policy failure/expiry, unsafe context, Auth activation, navigation/lifecycle
invalidation or disposal. A host lease's original deadline is carried into the
nested runtime rather than extended by a fresh 60 seconds. Unready frames have a
bounded handshake timeout. Timers remain subject to browser scheduling; already
sent requests cannot be recalled.

Pre-consent events and work spanning consent epochs are not replayed. Pending
reservations update only the baseline when their epoch changes. Conversion
callbacks observed before consent remain suppressed under a later grant.
Analytics errors cannot change checkout or payment results. A detached frame
cannot complete its handshake or report successful sends; renewal creates a fresh
browsing context and ignores messages from the removed one. Expired/unsafe ACKs
are rejected even when the corresponding timer has not run yet.

## Attribution and GTM profile

The runtime validates a canonical public form URL without query/hash and a
referrer origin only, then adds only allowlisted campaign parameters to the
`page_location` query sent to dataLayer. Campaign/click values use one bounded allowlist
(`campaignKeys` in the shared contract): `utm_source`, `utm_medium`, `utm_campaign`, `utm_term`,
`utm_content`, `gclid`, `gbraid`, `wbraid`, `fbclid`, `sznclid`, `ttclid` and `msclkid`. Each value
has 1 to 256 characters, without controls or `@`. Any other query parameter keeps a standalone form
outside measurement. Host
campaign data is separately rebuilt during the pinned embed handshake; the raw
host URL, unknown query values and capability URLs are never forwarded.
Containers must map `page_location`, `page_referrer`, campaign/click data and
approved ecommerce events from dataLayer, and avoid duplicate automatic pageviews.

Profile `gtm-v1` includes the supplied Consent Initialization template using
Google's `setDefaultConsentState` API: analytics granted only inside the already
consent-gated frame, all three advertising states denied. Actual GTM event
execution and `isConsentGranted` state readback were verified in an unpublished
nonproduction workspace. Arbitrary Unit code still has to respect its declared
purpose; a profile label is not a general audit of every future third-party tag.

Supported: dataLayer consumers, tested GTM Custom HTML/custom templates and
Unit script consumers. Browser-permitted storage is isolated by Unit; browser
cookie restrictions may reduce attribution. No storage-access prompt or
same-origin fallback is added. Checkout DOM scraping, unsafe-eval variables,
popups/nested-frame tags, Ads/enhanced contact export and cross-reload exactly-once
delivery are outside this profile. Contacts are always stripped.

## Conversions and migration

`form_start` is sent once per form load on the first visitor answer change or
ticket/seat action after consent. It carries no field names or values. Merely
focusing or leaving a field, opening the seat picker, rendering defaults and
restoring a draft do not count. Pre-consent actions are not replayed.
This event is independent of the scheduled sale-opening time (`start_time`)
and its countdown. GA4's automatic form-interaction event uses a session-level
scope and cannot observe the form from our isolated runtime. Map the supplied
event once in GTM; do not add another collector for the same interaction.

`purchase` means an accepted paid-price order, not proof of payment. Finalizer
snapshots own charged prices/items/currency. Client receivers reject totals
that cannot be represented with exact, safe integer-cent arithmetic. Existing authorized command replay
returns the same immutable facts under current stored gates; the browser
suppresses duplicate callbacks within its lifecycle. Free registration/waitlist
use distinct lead identities, including later paid waitlist acceptance.

Items carry `item_id`, `item_name`, `price` and `quantity`. Two optional public catalog labels
are added when they exist, in browser events and in the server `purchase`:

- `item_category`: the product type title. Browser events read it from the form catalog or the
  seat/area product catalog, `purchase` from `type_title` in the finalizer's snapshot.
- `item_brand`: the occasion title. GA4 `affiliation` means the supplying company or store, so
  the event belongs in the brand of what is sold. One Unit runtime is one organizer, and a Unit
  title can be a natural person's name, so no organizer value is exported.

Labels are limited to 100 characters. A label with controls or `@` is omitted while the item
remains. They never affect `value` or the `total=o.price` check, and they do not split a charged
line. Conversion facts recorded earlier stay immutable without these labels and remain valid.
`item_variant`, `coupon` and `discount` are not exported. Festapp has no variant, discount code or
voucher entity. A product is the selected option, a seat section is not known consistently in the
cart, and the negative `meta_surcharge` is informational and does not change the charged price.

The forward migration relocates the earlier public tables into `analytics` and
moves unambiguous legacy form destination configuration to Unit. It preflights
conflicts and enhanced-conversion preparation without logging code; ambiguity
fails atomically instead of discarding or merging scripts. It locks stored
occasion scope and upserts aggregate versions so stale snapshots, including
version zero without a prior version row, cannot erase migrated configuration.
Historical migrations remain unchanged; no legacy runtime/read/write fallback
is retained.

## Verification and deployment

Run the affected lanes through `automation/test_ci.sh`; measurement-specific
browser checks are available as the `test:measurement-*` scripts in
`web_client/package.json`. Runtime build/deployment instructions and the exported
GTM consent template are in `workers/form-measurement/README.md`.
Implementation and local verification do not publish a runtime, migrate a live
database, enable an organization/Unit, or publish a GTM workspace. Those steps
remain unperformed; no domain purchase or setup was requested.

For GA4 in this cross-site frame, set `cookie_flags` to `SameSite=None;Secure`
in the Google tag. Map `page_location` and `page_referrer` from dataLayer and
turn off the duplicate automatic pageview. The validated form URL receives only
allowlisted campaign query parameters; arbitrary query values and fragments
are never forwarded. Include GA4 regional endpoints in collector origins:
`https://region1.google-analytics.com`, `https://region1.analytics.google.com`
and `https://www.google-analytics.com`, or CSP silently blocks their requests.
GTM Preview cannot reach the runtime without the Tag Assistant Chrome extension,
because Tag Assistant only pings the window it opened. Try it with the extension
in a clean Chrome profile, keeping Tag Assistant in a separate window: hiding the
form tab destroys the frame. The form accepts `gtm_debug` and does not forward it.
This path is not verified live yet. GA4 Realtime and DebugView always work. Signed-in visitors are excluded from measurement and never see the
consent notice; test in an incognito window.
