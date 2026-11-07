# Form measurement contract

Measurement is off by default. The effective permission is the conjunction of
platform permission, organization permission, Unit permission, form intent,
a supported Unit runtime deployment, a safe public browser context and a valid
organizer HTTPS privacy policy URL. Saving configuration or entering a GTM ID grants
none of these.

**Basic consent gates measurement.** Neither GTM/Unit code nor host events start
before both analytics and marketing are confirmed. A single purpose cannot start
the current mixed profile. Missing or broken consent sources fail closed while
checkout continues. No contact fields leave through measurement; enhanced
conversions are unavailable.

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
`enhanced_conversions_unavailable` is true. Immutable historical receipts may
contain historical status; UI/MCP inspect current policy through authorized readers.
SQL facts depend on permanent enablement and valid policy, not temporary runtime
availability. The browser additionally requires a current eligible policy and consent.

## Runtime, consent and transport

`FormMeasurementSession` owns role, policy renewal, consent, lifecycle, generation
and selection of exactly one transport. Its constructor has no I/O. `start()`
subscribes and starts reconciliation without waiting for consent. Errors recover;
only disposal is terminal. `FormDataLayer` owns catalogue, funnel, baseline and
visit deduplication. It has no policy/Auth/consent decisions or timer.

Standalone uses the real Klaro UI with analytics and marketing services, off by
default. Both are necessary for the mixed GTM/custom profile. The translated
notice keeps bar/modal styling, equal buttons, privacy URL and plain custom text.
Saved choice belongs to organization + Unit + `processing_revision`. A new revision
requires a matching saved choice; unknown role can attach CMP without running tags.
Staff is unmeasured. Signed-in visitors wait for a matching policy/role response.

A single in-flight Promise serves concurrent policy waiters. Identity changes
invalidate the generation before fresh policy is requested. Stale responses and
finally blocks cannot overwrite a newer request. Equivalent renewal preserves the
active grant; consent, identity, relevant configuration or transport changes revoke
it. Hidden/pagehide removes the frame and invalidates pending sends; BFCache return
rechecks sources. Policy and host leases last at most 60 seconds, renewed every
20 seconds. Expiry always detaches, including hidden pages. Browser throttling
precludes an instantaneous global backend kill guarantee.

Runtime protocol 2 (`festapp-measurement`) compares the actual SQL/Worker manifest
with the accepted policy before init can insert any Unit code. Scope, form link,
processing/runtime/policy revisions, profile and required purposes must match.
Ready/init/ACK bind source window, origin, instance and generation. Consent Mode
default/update precede GTM as supplementary state; `festapp_consent` is also supplied.
No always-on, catch-start, timeout-start or same-origin script fallback remains.

Each Unit retains its separate canonical `PROJECT.pages.dev` site, CSP and sandbox.
Scripts cannot access checkout DOM or backend credentials. Layout/scroll/theme
embed protocol 1 remains compatible; measurement protocol 1 grants are rejected.
A missing/old helper preserves checkout but cannot activate new measurement.

`data-festapp-datalayer` selects host-only transport; otherwise the Unit runtime is
used. Both require an approved host and a live revision-bound source through
`FestappEmbed.connectMeasurementConsent(frame, source)`. Source `read(context)`
synchronously returns a stored `{processingRevision, analytics, marketing}` or null;
its revision must come from the saved choice, never be copied from the context.
`subscribe(notify)` returns an unsubscribe function. Heartbeats reread this source
and renew a random local lease bound to scope/revision/instance. Receiver verifies
live choice, lease, expiry and generation before each push. Viewport cannot renew
permission. Disconnect, source errors or new revision invalidate the lease.
Legacy boolean `true` means analytics only; legacy setters/`connectKlaro` are not
revision-bound sources and do not authorize the mixed profile. See the
[runtime integration example](../../workers/form-measurement/README.md#host-cmp-integration).

`capture()` returns a sender bound forever to the original active grant; inactive
capture is forever no-op. `captureSubmission()` captures before submit; `observe()`
captures before awaiting reservations. Revoke/regrant cannot revive either callback.
Activation sets current cart baseline and page/catalog context without replaying
old interactions. Dedupe survives inactive periods. No queue replays old purchases
when a visitor later consents. Measurement failure never controls business success.

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

Profile `gtm-v1` permits intentional inline Unit code inside the separate runtime,
with CSP-restricted collectors. Unsafe-eval, nested frames, workers, popups and
checkout DOM scraping remain unsupported. Browser storage isolation/cookie rules
may reduce real attribution. Validated click IDs reach both dataLayer and the
runtime URL; no capability/query secrets are forwarded. Deterministic tests do not
prove Google/Meta delivery or arbitrary future container compatibility.

## Contact-free conversions

`analyticsPayload` rebuilds allowlisted events/items and discards all `user_data`,
contacts, private answers and extra fields at every receiver. No contact extraction
or hashing is performed. Clearing a later dataLayer entry would not erase history;
contacts therefore never enter that history. Public labels/allowlisted campaign
strings are not a general anonymity guarantee. Enhanced conversions and the old
form-level enhanced key remain unavailable. Already delivered data cannot be recalled.

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
performed by local implementation. Existing open always-on clients are not killed
by a new deployment or DB disable; an operational rollout must prove their end or
keep measurement disabled.
