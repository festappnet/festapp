# Form measurement contract

Measurement is off by default. The effective permission is the conjunction of
platform permission, organization permission, Unit permission, form intent,
a supported Unit runtime deployment, a safe public browser context and a valid
organizer HTTPS privacy policy URL. Saving configuration or entering a GTM ID grants
none of these.

**Visitor consent does not gate measurement.** On an eligible form the frame loads
GTM and Unit scripts as soon as the form loads, and dataLayer is always filled. The
choice in the consent notice is only state for Google Consent Mode, evaluated by the
organizer's container. The organizer is responsible for its tag settings.

## Configuration and ownership

- Organization: `organizations.data.FORM_MEASUREMENT_ENABLED`, boolean default
  false. Existing organization administrators can allow/deny measurement only.
- Unit: `units.data.measurement_enabled`, boolean default false;
  `measurement_gtm_container` and `measurement_scripts` contain the one shared
  destination configuration. `measurement_consent_layout` (`bar` by default, or
  `modal`), `measurement_consent_title` (80 characters) and
  `measurement_consent_text` (500 characters) shape the consent notice. Existing Unit managers edit these
  through the normal Unit settings aggregate/UI/MCP. Disabling preserves ID and script text.
- Form: `forms.data.analytics` contains only `{enabled:boolean}`. Existing form
  authors toggle it through the same form aggregate/UI/MCP as other settings.
  Form-level destination code and the `enhanced_conversions` key are rejected.

Organization denial dominates every Unit and form. Unit denial dominates its
forms. UI hides Unit and form measurement controls when organization permission
is absent and preserves stored choices. With organization permission, form
authors can save form intent even while Unit measurement is off; the editor
explains the Unit block without changing Unit permission. Public/catalog Unit readers
redact destination code; authorized Unit manager reads retain it. None of these
administrative switches edits platform deployment policy.

Form MCP example: `forms.save` with `settings.analytics.enabled`. Unit MCP uses
`units.settings.save` with `changes.settings.measurement_enabled`,
`measurement_consent_layout`, `measurement_consent_title`,
`measurement_consent_text`, `measurement_gtm_container`, `measurement_privacy_url`, and `measurement_scripts`. Omission preserves a
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
eligibility, never proof of a tag's delivery.
`enhanced_conversions_unavailable` is false: contact is part of the conversion
events. Historical mutation receipts remain immutable and labelled historical,
with the value true; UI/MCP refresh the current status through existing authorized
readers.

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

Standalone forms dynamically load the actual Klaro manager/UI with two services:
`analytics` and `marketing` (advertising and sharing with advertising systems).
Both start off. Accept grants both, Decline neither, and consent settings keep
per-purpose choice available. The notice stays mandatory in both layouts: `bar` is
the same blocking notice docked to the bottom, `modal` sits in the center. It blocks
the page, not measurement.

An empty title or text uses the translation. A custom one applies to all languages
and is plain text: Klaro runs with `htmlTexts:false`, so markup is shown, never
parsed. Button labels, purposes and the policy link are fixed. The notice settings
reach the browser like `privacy_url`: only when the form is eligible, outside the
frame configuration and `configuration_revision`. Without a valid policy link
nothing runs and no notice appears.

The notice takes its colors and font from the form design that `ThemeService` sets on
`body`: `--card-bg`, `--text-color`, `--primary-color`, `--btn-text-color` and
`--font-family-base`. Both buttons have the same look. If text or button contrast
falls below 4.5:1, or a value is not a plain color, it keeps the standard colors.

The adapter reads confirmed saved choices, never an unsaved checkbox draft. A choice
saved before `marketing` existed counts as no choice and asks again. Choices are
stored per organization/Unit. Embedding hosts use the same adapter through
`FestappEmbed.connectKlaro(frame, manager)`, which reads `analytics` and, when
present, `marketing`. `setMeasurementConsent(frame, granted)` accepts
`{analytics, marketing}`; a boolean means analytics only. Both only pass state on.
Without a signal from the host the state is denied and measurement runs.

Before `gtm.js` loads, the frame queues `gtag('consent','default',...)` and an
identical `update`: `analytics_storage` from analytics; `ad_storage`, `ad_user_data`
and `ad_personalization` from marketing, all denied without a saved choice. A later
choice sends `gtag('consent','update',...)` and the dataLayer event
`festapp_consent_update` with `{analytics, marketing}` to the same frame. Neither
refusal nor revocation stops or replaces it. Every event also carries
`festapp_consent: {analytics, marketing}`.

Embeds use the Unit runtime unless the host opts out. `data-festapp-datalayer` is an
explicit host-owned transport: events go only to the host's dataLayer and its own
container, without also executing the Unit container, and they need no consent
signal. The host's own Consent Mode gates its tags. The form waits for the host
handshake to learn the transport; a page without the helper runs the frame after the
handshake attempts end.

Policy is rechecked every 20 seconds with an at-most-60-second lifetime. The trusted
parent removes the iframe on policy failure or expiry, unsafe context, signed-in
staff or disposal. Hiding the page does not remove it, so the container does not run
twice in one visit: timers are throttled in the background, so sends stop at expiry
and returning renews the policy or removes the frame. Unready frames have a bounded
handshake timeout, after which that configuration is not retried. Already sent
requests cannot be recalled.

Events are not queued before the frame is ready. A cart observed before then becomes
the baseline. Analytics errors cannot change checkout or payment results. A detached
frame cannot complete its handshake or report successful sends; renewal creates a
fresh browsing context and ignores messages from the removed one. Expired/unsafe ACKs
are rejected even when the corresponding timer has not run yet.

Signed-in ordinary visitors are measured. Organization administrators and managers
of the Unit that owns the form are not. The browser only knows that a session exists,
so `get_form_measurement_policy` returns `visitor_role` from the caller's JWT:
`anonymous`, `visitor` or `staff`, using the existing `can_manage_organization_settings`
and `can_manage_unit_configuration` predicates. With a session, nothing runs until
the role is `visitor`; a failed check or any other answer stays unmeasured. A sign-in
during the visit pauses measurement until the new role is known, and `staff` stops it
for that page. Tokens never enter messages, the frame or dataLayer: payloads are
rebuilt from allowlists and the frame is on another site.

## Attribution and GTM profile

The runtime validates a canonical public form URL without query/hash and a
referrer origin only, then adds only allowlisted campaign parameters to the
`page_location` query sent to dataLayer. The same values are copied into the frame URL, because Ads and Meta tags read click IDs from the document. Campaign/click values use one bounded allowlist
(`campaignKeys` in the shared contract): `utm_source`, `utm_medium`, `utm_campaign`, `utm_term`,
`utm_content`, `gclid`, `gbraid`, `wbraid`, `fbclid`, `sznclid`, `ttclid` and `msclkid`. Each value
has 1 to 256 characters, without controls or `@`. Any other query parameter keeps a standalone form
outside measurement. Host
campaign data is separately rebuilt during the pinned embed handshake; the raw
host URL, unknown query values and capability URLs are never forwarded.
Containers must map `page_location`, `page_referrer`, campaign/click data and
approved ecommerce events from dataLayer, and avoid duplicate automatic pageviews.

Profile `gtm-v1` needs no consent template in the container: the frame sets
Consent Mode itself, in the order Google documents for pages that cannot use a
template. Reading the state back from a real `gtm.js` confirmed it. A container
template or CMP that sets a later default cannot replace the saved choice,
because the queued `update` takes precedence.

Consent Mode is the only consent check in the frame. Google tags adjust to it but
send cookieless pings while denied; add the consent requirement in GTM's Additional
Consent Checks to stop them. Custom HTML tags such as Meta Pixel and Unit scripts do
not read Consent Mode and run before any choice unless the organizer requires
`ad_storage` on the tag, or reads `festapp_consent` and `festapp_consent_update`.
A profile label is not a general audit of every future tag.

Supported: dataLayer consumers, tested GTM Custom HTML/custom templates, Google
Ads conversion and remarketing tags, Meta Pixel and Unit script consumers.
Browser-permitted storage is isolated by Unit; browser cookie restrictions may
reduce attribution. No storage-access prompt or same-origin fallback is added.
Checkout DOM scraping, unsafe-eval variables, popups/nested-frame tags and
cross-reload exactly-once delivery are outside this profile.

Tags see the frame document, not the form. Its URL carries only `form` and
`parent`, so Google Ads and Meta report a `pages.dev` address and do not read
`gclid`/`fbclid` from it; these values reach tags only through dataLayer. Map them
where the tag allows. `frame-src 'none'` and `worker-src 'none'` also block
everything that needs a frame or worker. See the runtime README for the list.

## Contact in conversions

**dataLayer contains the readable e-mail and phone.** Every `purchase` and
`generate_lead` carries `user_data: {email, phone_number}`, whatever the visitor chose,
so every tag and Unit script in the container can read them. The organizer is
responsible for how they are used and for describing it in its privacy policy.

The form document reads the answers it already holds: the e-mail trimmed and
lowercased, the phone in E.164. Every receiver rebuilds `user_data` and passes only
these two fields, an e-mail up to 254 characters and an E.164 phone. Anything else is
left out, including a national number whose country is not known. No other event
carries contact. Nothing is stored in `conversion_facts`, logged or put in a URL.
Reading it cannot affect the order. The frame and host clear `user_data` after the
event.

The host transport has one more condition. Any site can embed a public form and set
`data-festapp-datalayer`, so contact goes to a host only if its origin is in the
Unit's approved `parent_origins`, delivered as `approved_hosts`. Other hosts still get
the event without it. Runtime frames already enforce that list through
`frame-ancestors`.

The form-level `enhanced_conversions` key remains rejected. In GTM, map
`user_data.email` and `user_data.phone_number` to the tag's user-provided data.

## Conversions and migration

`form_start` is sent once per form load on the first visitor answer change or
ticket/seat action. It carries no field names or values. Merely
focusing or leaving a field, opening the seat picker, rendering defaults and
restoring a draft do not count.
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
`web_client/package.json`. Runtime build/deployment instructions and required
collector origins are in `workers/form-measurement/README.md`.
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
in a clean Chrome profile, keeping Tag Assistant in a separate window. The form
accepts `gtm_debug` and does not forward it. This path is not verified live yet.
GA4 Realtime and DebugView always work. Administrators and Unit managers are not
measured; test while signed out or with an ordinary account.
