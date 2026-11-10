# Form measurement contract

Measurement is off by default. The effective permission is the conjunction of
platform permission, organization permission, Unit permission, form intent,
a supported Unit runtime deployment, a safe public browser context and a valid
organizer HTTPS privacy policy URL. Saving configuration or entering a GTM ID grants
none of these.

**Visitor consent does not gate measurement.** On an eligible form the frame loads
GTM and Unit scripts as soon as the form loads, and dataLayer is always filled. The
choice in the consent notice is state for Google Consent Mode, evaluated by the
organizer's container, which the organizer configures and answers for. Missing or
broken consent sources report denied state and measurement continues. `purchase` and
`generate_lead` always carry `user_data`; see [Contact in conversions](#contact-in-conversions).

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
`measurement_consent_text`, `measurement_gtm_container`, `measurement_privacy_url`, `measurement_scripts`, and `measurement_consent_version`. The positive integer consent version defaults to 1, can only increase, and rejects null/decreases through the same authorized aggregate. Increase it when remote tag/policy contents or purposes change. Omission preserves a
value. Nullable Unit destination fields clear with null; form `enabled:null`
resets to off, `analytics:null` clears form intent. Copies reset form intent;
there is no copied per-form destination. The canonical Unit configuration JSON
also owns the script-length limit used by generated Dart/JS constants.

Units store nullable `measurement_privacy_url` as an absolute HTTPS URL without credentials (maximum 2048 characters). A valid URL is required for measurement, conversion recording/export and the consent notice, including host dataLayer transport; partial configuration can still be saved, and changing a valid URL invalidates the processing revision and saved choice.

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
events. Immutable historical receipts may contain historical status; UI/MCP inspect
current policy through authorized readers.
SQL facts depend on permanent enablement and valid policy, not temporary runtime
availability. The browser additionally requires a current eligible policy.

## Runtime, consent and transport

`FormMeasurementSession` owns role, policy renewal, lifecycle, generation and
selection of exactly one transport. It forwards the visitor's choice as state and
never uses it as a condition. Its constructor has no I/O. `start()` subscribes and
starts reconciliation. Errors recover;
only disposal is terminal. `FormDataLayer` owns catalogue, funnel, baseline and
visit deduplication. It has no policy/Auth/consent decisions or timer.

Standalone uses the real Klaro UI with analytics and marketing services, off by
default. The translated notice keeps bar/modal styling, equal buttons, privacy URL
and plain custom text. It blocks the page, not measurement. Saved choice belongs to
organization + Unit + `processing_revision`. Staff is unmeasured. Signed-in visitors
wait for a matching policy/role response.

A single in-flight Promise serves concurrent policy waiters. Identity changes
invalidate the generation before fresh policy is requested. Stale responses and
finally blocks cannot overwrite a newer request. Equivalent renewal preserves the
active grant; identity, relevant configuration or transport changes revoke it. A
consent change does not: it reaches the frame as `gtag('consent','update',...)` plus
the `festapp_consent_update` dataLayer event with `{analytics, marketing}`. Hiding the
page keeps the frame, so a tab switch does not run the container again. Pagehide
removes it and BFCache return starts a new grant. Policy and host leases last at
most 60 seconds, renewed every 20 seconds. Expiry always detaches, and a page that
stayed hidden past it starts a new frame on return. Browser throttling precludes an
instantaneous global backend kill guarantee.

Runtime protocol 3 (`festapp-measurement`) compares the actual SQL/Worker manifest
with the accepted policy before init can insert any Unit code. Scope, form link,
processing/runtime/policy revisions and profile must match. Ready/init/ACK bind
source window, origin, instance and generation. Consent Mode default/update precede
GTM, all denied without a saved choice; every event also carries `festapp_consent`.
Custom HTML tags such as Meta Pixel and Unit scripts do not read Consent Mode: require
consent on the tag in GTM, or read `festapp_consent` and `festapp_consent_update`.

Each Unit retains its separate canonical `PROJECT.pages.dev` site, CSP and sandbox.
Scripts cannot access checkout DOM or backend credentials. Layout/scroll/theme
embed protocol 1 remains compatible; measurement protocol 1 grants are rejected.
A missing/old helper preserves checkout but cannot activate new measurement.

New snippets generated by the admin dialog and public generator select the host
transport by default and explicitly include `data-festapp-datalayer`. Removing
that attribute selects the Unit runtime. Existing snippets without the attribute
retain their Unit runtime; upgrading `/embed.js` never silently opts them into
sharing conversion contacts with host-page scripts. The attribute is a presence
flag, not a string-valued switch: all helpers use its presence to select host
mode. Unit mode removes it.
Changing the attribute live reinitializes the selected transport. Direct visits
continue to use the Unit runtime and Klaro. Embeds show no consent bar in either mode. Both embed transports require an
approved host and the current helper, nothing else: the helper
issues a random local lease that only proves it is alive, and renews it on a heartbeat.
A host CMP is optional. `FestappEmbed.connectKlaro(frame, manager)`,
`setMeasurementConsent(frame, granted)` and
`connectMeasurementConsent(frame, source)` all pass the choice on as state and
always replace the automatic source, including after disconnection. Automatic reading
requires the organizer's Unit setting `measurement_consent_bridge: true`, disabled
by default for new and existing organizers. Enable it with “Use consent from my
website banner” only when the organizer operates the host website as the same
controller and its banner explicitly covers the embedded vstupenky.online form.
The banner must identify the organizer, purposes, services in the organizer's GTM,
the isolated `*.pages.dev` runtime and Festapp as processor, and explain withdrawal.
The organizer retains consent evidence in the website CMP. A partner's banner
cannot be assumed to cover the organizer. Explicit adapters remain independent of
the switch. The switch is part of the manifest and processing revision.

When enabled, the helper reads `google_tag_data.ics.entries`, then only Arguments
`consent default/update` commands in `window.dataLayer` if ICS is unavailable.
Arrays are ignored. Regional defaults stay denied until a CMP update. Analytics
requires explicit granted `analytics_storage`; marketing requires all three of
`ad_storage`, `ad_user_data` and `ad_personalization` explicitly granted. Missing or
broken values mean denied. If `__tcfapi` is present, marketing is always denied;
TCF is never read or forwarded, while analytics follows Consent Mode.

ICS is polled every 250 ms; dataLayer every second, scanning only new entries and
resetting state when replaced or shortened. Withdrawal can therefore race a
purchase within the remaining 250 ms or 1 s window, and browser suspension can
extend it. Already delivered data cannot be recalled. Switching to website mode
unsubscribes the source; returning to Unit mode subscribes again. Choices bind to
the first organization, Unit and processing revision; a changed scope stays
denied until a fresh binding (for example, a newly loaded embed).
The read-only bridge changes no eligibility or approved-host checks and writes no
Google state. Measurement runs regardless
of the choice. In the host transport the host's own Consent Mode gates its tags;
the automatic bridge does not apply. See the
[runtime integration example](../../workers/form-measurement/README.md#host-cmp-integration).

`capture()` returns a sender bound forever to the original active grant; inactive
capture is forever no-op. `captureSubmission(payload)` captures before submit;
`observe()` captures before awaiting reservations. A replaced grant cannot revive
either callback. Activation sets current cart baseline and page/catalog context
without replaying old interactions. Dedupe survives inactive periods. Measurement
failure never controls business success.

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
`form_embedded` is a strict boolean in the initial context push and every
measurement event in both transports: `false` for direct visits and `true` for
embeds (`?embed=1` / EmbedBridge), including sale-opening pages. Missing or
non-boolean runtime context input becomes `false`; host transport always sets `true`.
Direct visits emit `page_view`; embeds emit `form_page_view` instead in both host
and Unit runtime transport, with the same once-per-`page_type` deduplication and
page context. They never emit both for a page view. Host pushes add no
`page_location` or host URL data. Ecommerce and `user_data` clearing pushes remain
unchanged. Host pushes reset `form_embedded` to `false` immediately afterward,
so subsequent website events do not inherit the embedded marker. Page context
is stored per frame and grant, and every event carries its own validated
`page_type`, `user_type` and language (or null when unknown), preventing
interleaved embeds from borrowing another form's context. The runtime uses
the same projection within its isolated layer. The wire event remains `page_view`; only the final receiver applies
`measurementDataLayerPayload` from the shared contract to select the destination
name and strict embedded marker. Mechanical transports do not rename events.
Older protocol 3 receivers still accept every wire event and temporarily retain
their previous `page_view` output until upgraded. There is no silent event loss.
Deploy receivers first for consistent destination semantics during rollout.

WordPress and Joomla expose an explicit `measurement` choice (`unit` or `host`).
Missing or invalid settings retain `unit`, preserving existing installed blocks,
shortcodes and modules. Website mode forwards bounded conversion email/phone and
transaction identifiers to page scripts; its editor and privacy notice disclose
that boundary. It installs no tags and does not grant consent or enable
measurement. The approved-origin, eligibility, staff and live-lease gates apply
to both choices. Website tags and the website CMP own consent in host mode;
Unit mode reads website Consent Mode only after the organizer opts in; an explicit adapter replaces it.
Containers must map `page_location`, `page_referrer`, campaign/click data and
approved ecommerce events from dataLayer, and avoid duplicate automatic pageviews.

Profile `gtm-v1` permits intentional inline Unit code inside the separate runtime,
with CSP-restricted collectors. Unsafe-eval, nested frames, workers, popups and
checkout DOM scraping remain unsupported. Browser storage isolation/cookie rules
may reduce real attribution. Validated click IDs reach both dataLayer and the
runtime URL; no capability/query secrets are forwarded. Deterministic tests do not
prove Google/Meta delivery or arbitrary future container compatibility.

## Contact in conversions

**dataLayer contains the readable e-mail and phone.** Every `purchase` and
`generate_lead` carries `user_data: {email, phone_number}`, whatever the visitor chose,
so every tag and Unit script in the container can read them. Being in dataLayer is
not the same as being sent: Google tags honour `ad_user_data`, and the organizer is
responsible for how tags use the values and for describing it in its privacy policy.

The form document reads the answers it already holds: the e-mail trimmed and
lowercased, the phone in E.164. Every receiver rebuilds `user_data` and passes only
these two fields, an e-mail up to 254 characters and an E.164 phone. Anything else is
left out, including a national number whose country is not known. No other event
carries contact. Nothing is stored in `conversion_facts`, logged or put in a URL.
Reading it cannot affect the order. The frame and host clear `user_data` after the
event, which stops it reaching later events but does not erase dataLayer history.

Host transport delivers to approved `parent_origins` only, like every measurement
event. The form-level `enhanced_conversions` key remains rejected. In GTM, map
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

Local tests verify deterministic tags and the actual network/execution gate.
Live Google/Meta attribution requires separately authorized external evidence.
No configuration changes, production migration, publication or deployment are
performed by local implementation.

## Measurement protocol 3 cutover

The shared measurement contract is protocol 3, with a required
`measurement_protocol: 3` in SQL policy and manifests. Its version is part of
`processing_revision`, so saved choices from the prior behavior do not carry
forward. Layout protocol 1 and the registered `gtm-v1` site profile are distinct
interfaces and remain unchanged. `consent_required` denotes the required notice
and choice controls, not permission to execute; `required_purposes` describes
the choices reported to tags.

Host setters, Klaro and revision-aware sources share one active binding. New
sources retire old callbacks and disposers; disconnect/failure yields denied
without stopping the live helper lease. Legacy setters and Klaro cannot carry a
grant across organization, Unit or processing revision. A setter before the first
context binds once. Record removal/origin replacement clears its heartbeat and
subscription. A nested `festapp_consent` snapshot accompanies every consent
update before any later conversion, without mutating a previously pushed object.

See [the runtime cutover contract](../../workers/form-measurement/README.md#canonical-protocol-and-choice-ownership)
for ordered deployment, unsupported cached peers, and the intentionally retained
historical test fixtures. New production code only accepts protocol 3.

## Sale-opening notifications

A BEFORE_START page with an actual notification sign-up (`canSubscribe`) uses
`FormPage.startMeasurement`, the same policy, staff exclusion, entry rules and
consent source as an open form: Klaro for direct visits, embedBridge for embeds.
Preview, unavailable/full pages and sale-opening scope/unsubscribe pages do not
start this stack. Presale content without an active sign-up stays unmeasured.

| Event | Presale behavior |
| --- | --- |
| Initial push | `page_type: 'sale_opening'`, `user_type: 'b2c'`, language |
| `page_view` | Direct visits only, once per page type (including sale-opening) |
| `form_page_view` | Embeds only, both transports, once per page type (including sale-opening) |
| `form_start` | First e-mail input, once per visit |
| `generate_lead` | Successful notification subscribe only, once per submission |

The `generate_lead` allowlist is `free_registration`, `waitlist`, and
`sale_opening_notification`. Notification leads carry `value: 0`, the first
available form currency (the same default as checkout, CZK if none), a fresh UUID
`event_id` and `user_data: {email}` trimmed and lowercased. The sender is captured
before the request; a revoked/replaced measurement grant cannot send its result.
Failures, preview and unsubscribe never emit a lead. These client subscription
leads do not create an order or an `analytics.conversion_facts` record; that SQL
kind constraint applies only to immutable order finalizer facts.
