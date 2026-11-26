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
broken consent sources report denied state and measurement continues.
`purchase`, `meta_purchase` and `generate_lead` can carry available `user_data` on immediate delivery; contact-free
recovery is described below. See [Contact in conversions](#contact-in-conversions).

## Configuration and ownership

- Organization: `organizations.data.FORM_MEASUREMENT_ENABLED`, boolean default
  false. Existing organization administrators can allow/deny measurement only.
- Unit: `units.data.measurement_enabled`, boolean default false;
  `measurement_gtm_container` and `measurement_scripts` contain the one shared
  destination configuration. `measurement_consent_layout` (`bar` by default, or
  `modal`), `measurement_consent_title` (80 characters) and
  `measurement_consent_text` (500 characters) shape the consent notice. Existing Unit managers edit these
  through the normal Unit settings aggregate/UI/MCP. Disabling preserves ID and script text.
- Form: `forms.data.analytics` contains `{enabled:boolean,purchase_timing?:"order"|"paid"}` (timing defaults to `order`). Existing form
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

A changed stored GTM container, scripts, privacy URL, consent title/text or consent
version changes `consentRevision` (`unit_measurement_consent_scope_internal`); every
website consent binding then needs reconfirmation in Unit settings, and Meta CAPI
`website_ready` for a connector website that relies on such a binding is false until
then. The `units.settings.save` description states this. MCP reads binding state
(`units.websiteConsent.inspect`), the import text of a ready binding
(`units.websiteConsent.export`), dataLayer approval
(`units.measurementApproval.inspect`) and generates
the form embed code (`forms.embedCode`, the server port of `formEmbedCode`, checked
against `packages/festapp_contracts/form-embed-code-cases.json`). It can send the measurement
approval request (`units.measurementApproval.request`, organizer settings write) but never confirms, changes
or disables bindings.

Units store nullable `measurement_privacy_url` as an absolute HTTPS URL without credentials (maximum 2048 characters). A valid URL is required for measurement, conversion recording/export and the consent notice, including host dataLayer transport; partial configuration can still be saved, and changing a valid URL invalidates the processing revision and saved choice.

## Database authority

With Unit measurement enabled, Unit managers can request missing platform approval
once from **Měření** in Unit settings. The persisted request notifies every current
administrator of the Unit's organization with a delivery email; retries send no
additional notices. The settings show the localized request date while waiting.
Platform operators still approve manually through `analytics.organization_policy`
and `analytics.unit_runtime`; submitting a request grants no measurement permission.
The platform administrator handles initial approval manually and replies by email.
No standard processing time is specified.

The private `analytics` schema contains exactly these measurement tables:

- `analytics.organization_policy`: platform permission, revision and operator
  evidence. Missing means denied.
- `analytics.unit_runtime`: the approved deployment origin/profile, permitted
  parent/ancestor and collector origins, revision and operator evidence.
- `analytics.unit_measurement_request`: one request per Unit, with its timestamp
  and requesting user; deleted with the Unit.
- `analytics.conversion_facts`: immutable conversion facts with non-authorizing
  event UUIDs, keyed by order and conversion kind.

Browser/API roles, including service_role, have no direct schema/table access.
All functions remain in `public` under repository rules. The service-only
bootstrap RPC checks a typed predicate against stored form -> occasion -> Unit
-> organization and exact configured runtime/parent origin. Runtime deployment
credentials stay server-side. Browser renewal returns minimal effective policy,
not GTM IDs, scripts, contacts, JWTs or order capabilities.

### Shared measurement decisions

`form_measurement_decision_internal(form)` reads the stored form, its owning
Unit and organization, the provisioned runtime and its Meta connector. It
supplies the same configuration decision to checkout, payment, consent capture,
delivery and the editor. The editor and public runtime retain their existing
JSON projections.

| Output | What it decides | Additional checks |
| --- | --- | --- |
| `conversion_eligible` | The form, Unit and organization enable measurement, the platform permits it, and the privacy URL is valid. | Checkout or settlement provides the order and amount. The order's creation snapshot fixes its cohort and event ID. |
| `browser_eligible` | Conversion eligibility plus a supported browser runtime and a configured destination. | The browser applies current consent and the runtime's origin policy. |
| `capi_unit` and `purchase_timing` | The owning Unit's enabled connector sets paid timing even during a pause. A paused connector supplies no delivery destination. | Meta also requires current conversion eligibility, an eligible fully paid order, the saved advertising grant, and a matching connector and consent revision. |

Self-service connector settings belong to the Unit and use its authorized
organizer settings. Provisioning a browser runtime remains a platform
operation because it controls where organizer-supplied browser code runs.
Reporting on actual sales uses `get_report_ws` and the transactional order,
payment and inventory records. A sale counts there independently of website
measurement or the visitor's advertising preferences.

## Runtime, consent and transport

`FormMeasurementSession` owns role, policy renewal, lifecycle, generation and
selection of exactly one transport. It forwards the visitor's choice as state and
never uses it as a condition. Its constructor has no I/O. `start()` subscribes and
starts reconciliation. Errors recover;
only disposal is terminal. `FormDataLayer` owns catalogue, funnel, baseline and
visit deduplication. It has no policy/Auth/consent decisions or timer.

Standalone uses the real Klaro UI with analytics and marketing services, off by
default. The translated notice offers Decline, Accept and Settings in both bar and modal
layouts, with equal prominence for Decline and Accept, a privacy URL and plain
custom text. Settings opens the per-purpose dialog before any decision; the
floating Consent settings button remains available for later changes on top-level
pages, including a new tab opened through a consent link. It is never rendered
in embeds. Embedded forms use the host bridge directly for consent, renewal
and revocation; they never create a local Klaro controller or read a standalone
choice cookie. Unknown or disconnected host choices remain denied without
blocking checkout. The host website owns consent there.
The dialog also shows an always-on, disabled necessary-data row for form
operation, security and remembering the choice. This informational row is not a
Klaro service, adds nothing to stored consent and maps to no Consent Mode signal. The notice blocks the page, not measurement. Saved choice belongs to
organization + Unit + `processing_revision`. Staff is unmeasured. Signed-in visitors
wait for a matching policy/role response.

A single in-flight Promise serves concurrent policy waiters. Identity changes
invalidate the generation before fresh policy is requested. Stale responses and
finally blocks cannot overwrite a newer request. Equivalent renewal preserves the
active grant; identity, relevant configuration or transport changes revoke it.
A successful order response arriving after a grant replacement can recover only
its validated, contact-free conversion fact in the same page session. Recovery
refreshes server policy and waits for an active transport, checks current consent
and lease validity, and requires the same visitor identity, manifest, transport
selection and host instance. Stable transaction/event IDs deduplicate delivery.
Changed scope is discarded; disposal clears the in-memory pending facts. This
is not durable delivery across navigation, reload or an uncertain transport ack. A
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
GTM, optional types denied without a saved choice; every event also carries `festapp_consent`.
Every Consent Mode type is set explicitly: `functionality_storage` is always granted
(an explicit owner decision), `personalization_storage` follows marketing like the `ad_*` types.
Third-party tags and Unit scripts do not automatically inherit Google built-in
consent checks. Configure their supported consent integration or explicit tag
checks; custom code can consume `festapp_consent` and `festapp_consent_update`.
The website preset uses the official Meta gallery template, its mapped
`ad_storage` requirement and the website CMP's SDK revocation integration.

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
the switch. The switch is part of the manifest and processing revision. A missing or false switch preserves the pre-bridge fingerprint; only true adds the bridge marker.

When enabled, the helper reads `google_tag_data.ics.entries`, then only Arguments
`consent update` commands in `window.dataLayer` if ICS is unavailable.
Arrays are ignored. Neither global nor regional defaults establish visitor choice;
ICS entries without a boolean update also remain denied. Analytics
requires explicit granted `analytics_storage`; marketing requires all three of
`ad_storage`, `ad_user_data` and `ad_personalization` explicitly granted. Missing or
broken values mean denied. If `__tcfapi` is present, marketing is always denied;
TCF is never read or forwarded, while analytics follows Consent Mode.

ICS is polled every 250 ms; dataLayer every second, scanning only new entries and
resetting state when replaced or shortened. Withdrawal can therefore race a
conversion within the remaining 250 ms or 1 s window, and browser suspension can
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
those senders. Successful order submissions separately retain a contact-free fact
for verified recovery through `captureConversion()`; cart changes and page context
from stale callbacks are not replayed. Activation sets current cart baseline and page/catalog context
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

**dataLayer contains the readable e-mail and phone.** Immediate `purchase` and `generate_lead` delivery carries available `user_data: {email, phone_number}`, whatever the visitor chose,
so every tag and Unit script in the container can read them. Being in dataLayer is
not the same as being sent: Google tags honour `ad_user_data`, and the organizer is
responsible for how tags use the values and for describing it in its privacy policy.

The form document reads the answers it already holds: the e-mail trimmed and
lowercased, the phone in E.164. Every receiver rebuilds `user_data` and passes only
these two fields, an e-mail up to 254 characters and an E.164 phone. Anything else is
left out, including a national number whose country is not known. Other interaction events do not carry contacts. The Meta-only Purchase companion may carry the same bounded conversion contacts. Nothing is stored in `conversion_facts`, logged or put in a URL.
Recovery after a grant replacement deliberately omits contacts and retains only
the conversion fact in memory. Reading it cannot affect the order. The frame and host clear `user_data` after the
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

The browser reports the confirmation page when checkout succeeds. Organizers
select `analytics.purchase_timing`: `order` (the backwards-compatible default)
or `paid`. Order mode emits `purchase` for an accepted priced order, including
unpaid orders. Paid mode emits only after eligible bank or online funds cover
the full price. Deposits, cash and administrative settlements do not qualify.
Free registrations and waiting-list entries remain `generate_lead` events.
Authorized receipt replay projects the same immutable snapshot under current
form policy; repeated callbacks are deduplicated within the browser lifecycle.

Purchase timing is frozen in the immutable creation snapshot. Changing the form setting or enabling CAPI later does not change an existing order’s cohort or UUID. Legacy order-mode snapshots cannot become paid browser or CAPI purchases.

CAPI-connected forms require paid mode. The settings editor displays this
requirement and disables order mode; SQL enforces it even for older editors.
The private `order_fully_paid` fact retains exactly `{value,currency}`. Its UUID
is projected into browser top-level `event_id` and `ecommerce.transaction_id` (both must match); map that value to Meta's
`eventID`, as the supplied preset does. CAPI uses the same fact UUID as
`event_id`. Never generate a second Pixel ID or mix order-mode Meta Purchase
with paid CAPI for the same form.

Delayed payments can emit a browser Purchase when the buyer opens or refreshes
the authorized order overview. This uses the current visitor policy, CMP consent
and isolated runtime. Capability tokens and overview URLs are never exported.
An immutable `capi_required` flag also records whether CAPI was enabled at
creation. A waitlist offer has no CAPI consent capture and stays in the
browser-only cohort, with the form's purchase timing. Enabling CAPI later cannot
adopt existing browser-only orders.
The general `purchase` event remains available for GA4 and Ads even when
advertising consent is denied or CAPI fails. For the immutable CAPI cohort it
carries `meta_purchase_allowed:false`, so the preset excludes it from Pixel.
After successful CAPI delivery, a separate `meta_purchase` companion may fire
Pixel Purchase with the same UUID. That companion is available only within 47
hours of the paid fact, with the deadline rechecked before the browser hands it
to tags. It never fires GA4 or Ads tags. Non-CAPI purchases can
fire Pixel from the general purchase event. A browser event requires a visit
and is not guaranteed delivery. Configure other containers with the same routing
rules; do not map every ecommerce event to every destination. The website preset
targets embedded events; standalone overview events need corresponding triggers
in the isolated container (`form_embedded = false`).
Snapshots whose line totals/currency differ from the paid fact are suppressed.
The payment transaction and paid fact commit together; failed fact writes keep
payment processing retryable.

### Meta CAPI settings

Unit managers and organization administrators open Unit settings → Events and
consent → Meta Conversions API. This connector is configured separately for each
organizer. Turning it off stops capture and preparation, and disconnecting also
clears the stored token and matching data. The form and website consent settings
still determine eligible paid purchases.

Enter the dataset ID and access token, choose a saved website and optionally enter a
test event code. Save can enable delivery together with the token. Configure
website consent and enable measurement and Meta CAPI on each form you want to
track. In Meta
Events Manager, select the dataset → Settings → Conversions API → manual setup
→ Generate access token; paste it into the write-only token field and save.
The full saved token is never displayed. To replace it, enter and save a new token.
The field shows only the token's last ten characters and save date, stored when
it was saved; Meta tokens share their prefix and often their final characters.
Tokens saved before this hint existed show no suffix until replaced.
Under the dataset's Test events tab, copy the server test event code. While the
code is present, purchases go only to Test events. Remove it after testing.
See [Meta's setup instructions](https://developers.facebook.com/docs/marketing-api/conversions-api/get-started/).

The section shows active/off/paused, a 30-day queue summary and a redacted last
error. The last error distinguishes pending retries from final failures with no
further attempts. Credential errors pause sending and collection. Saving a replacement
token clears the pause. Browser Purchase keeps its paid timing while CAPI is paused. Orders already `failed` after six attempts are never
retried; pending orders remain eligible only within seven days of full payment.
Changing dataset, website or test code advances the connector revision: pending
orders captured for an earlier revision are invalidated and scrubbed by the
worker, never sent to the new destination. Disconnecting removes the token and
form switches, terminates pending deliveries and erases stored matching data.
Organization administrators may disconnect even after platform approval is removed.
A prepared delivery with a live lease retains only its receipt fence: finishing
without the connector still records `sent_in_flight` for success and never retries
or restores matching data. Unprepared or expired leases are cleared.

### Meta CAPI consent

Pilot forms use the existing saved CMP choice; there is no separate Purchase
checkbox. Capture requires all three advertising purposes (`ad_storage`,
`ad_user_data`, `ad_personalization`), the current semantic notice revision and
configured website origin. Managed embeds and linked visits also require the
exact effective website binding and version. Cookiebot, CookieConsent v3, Wix,
Klaro and Complianz use the same order snapshot model: `capturedAt` is aligned
to server capture time, independently of missing, invalid or skewed browser clocks; an available CMP date is optional `decidedAt` audit
metadata and never gates capture. A saved Klaro choice needs no decision record.
A decision predating website confirmation does not block CAPI. Ordinary browser
measurement retains its coverage windows and expiry checks.

Why: later server delivery after payment uses the grant saved with the order, so a
CMP without a decision timestamp can supply the same evidence. The organizer
must ensure that the banner and privacy policy cover advertising through Meta.
Supporting references:
- GTM4WP 2.1.1 stores the consent state with a browser capture time on the order
  ([AttributionCapture.php](https://github.com/duracelltomi/gtm4wp/blob/2.1.1/src/Modules/GoogleDataManager/AttributionCapture.php#L336-L347),
  [gtm4wp-attribution.js](https://github.com/duracelltomi/gtm4wp/blob/2.1.1/js/frontend/gtm4wp-attribution.js#L276-L281))
  and decides later refunds from that stored state
  ([WooCommerceRefunds.php](https://github.com/duracelltomi/gtm4wp/blob/2.1.1/src/Modules/GoogleDataManager/WooCommerceRefunds.php#L96),
  [ConsentPolicy.php](https://github.com/duracelltomi/gtm4wp/blob/2.1.1/src/Modules/GoogleDataManager/ConsentPolicy.php#L113-L139)).
- PixelYourSite Pro saves the buyer's consent on each order for server events
  ([changelog 12.6.8](https://www.pixelyoursite.com/pixelyoursite-pro-change-log#v12-6-8),
  [12.6.11](https://www.pixelyoursite.com/pixelyoursite-pro-change-log#v12-6-11)).
- Complianz category cookies hold only `allow`/`deny` without a decision time
  ([complianz.js](https://github.com/complianz/complianz-gdpr/blob/v7.5.7/cookiebanner/js/complianz.js#L384-L402)).
- The Conversions API has no consent-time parameter
  ([server event parameters](https://developers.facebook.com/docs/marketing-api/conversions-api/parameters/server-event));
  the Meta Business Tools Terms require the advertiser to obtain the necessary
  consents ([terms](https://www.facebook.com/legal/technology_terms)).
- The GDPR does not prescribe how consent is demonstrated
  ([EDPB Guidelines 05/2020, section 5.1](https://www.edpb.europa.eu/system/files/documents/files/file1/edpb_guidelines_202005_consent_en.pdf)).

The snapshot is stored privately with the order. The short renewable browser
connection authorizes capture, not the lifetime of the order snapshot. Closing
the visit normally does not withdraw durable consent. While the checkout stays
open, a current complete refusal in the same consent scope withdraws pending
delivery. A refusal observed before dispatch removes the grant from the request.
A refusal observed after dispatch is applied as soon as the order capability is
available. Only plausible CMP dates can establish that a refusal is older; a
date in the future when received, an equal date or a missing date cannot veto a
current complete refusal. The order overview
also checks the saved refusal against the scope captured for each order. A buyer
capability authorizes withdrawal, including the manual action available from the
confirmation email. Unknown, expired or disconnected choices cannot withdraw
durable consent. Withdrawal stops deliveries that the server has not yet prepared. A prepared event may still reach Meta after withdrawal. If Meta confirms receipt, it is recorded as `sent_in_flight`.
The commit of prepare is the irreversible send boundary.
Complianz can reload its host page immediately on decline, interrupting an
asynchronous withdrawal. The next order-overview visit can submit the saved
refusal again; closing or reloading a page alone does not revoke an order.
The RPC transport has no dedicated keepalive option.

The Edge worker claims only the original CAPI-enabled paid cohort after a full
payment fact exists. Before sending, it rechecks the saved snapshot, live binding,
destination and eligible balance. It sends the normalized email hash, checkout
user agent, canonical source URL, amount and currency with the first settlement
time and stable event ID. Retries keep that ID and time. With a valid saved
advertising choice, matching also includes a SHA-256 phone hash (digits including
the country code), validated `fbp`/`fbc`, and the checkout IP. A national phone
number needs one configured prefix. An ambiguous number is omitted. When a pilot
checkout is confirmed, the form checks the current notice and asks its bound host
for matching once. The host checks the live lease and the same saved advertising
decision before reading first-party `_fbp`/`_fbc`. A current `fbclid` can supply
`fbc` when the matching cookie is missing or belongs to an older click. Renewals
and withdrawals of the consent connection carry only consent. Matching stays out
of dataLayer, checkout receipts and the checkout command's identity.

Standalone forms derive `fbc` from a consented `fbclid` in the form URL. The form
origin is shared by multiple organizers, so their browser cookies are never read
there. The new-tab consent link transfers only consent.

The checkout Edge function forwards only `X-Festapp-Client-IP`, which canonical
Caddy configuration replaces from trusted proxy resolution and the gateway/router
preserves. SQL validates the address; JSON payloads and untrusted forwarded-IP
headers do not supply it. Raw IP expires after seven days, including unpaid and
paused deliveries. The database retention job runs every minute in the runtime
database independently of the Edge worker and still scrubs expired rows if
delivery is disabled. Delivery also checks IP expiry before returning a payload.
Snapshot, cookie IDs and contact hashes expire after 30 days. All matching data
are erased on terminal outcomes or authorized consent withdrawal. Operational
receipts without those identifiers remain for 90 days, with the server capture timestamp and optional CMP decision date
and a digest of its consent scope to check later refusals.

Deploy the forward database migration, the sending `process-meta-purchases`
Edge Function and the administration/web clients in the same canonical release.
On the canonical host install
`automation/hetzner-supabase/runtime/install-meta-purchase-schedules.sh` through
the backend operator workflow. The installer starts the independent PostgreSQL
retention job, waits for a successful recent sweep, then activates
`festapp_meta_purchase_delivery` and verifies both schedules are active. A new
delivery job stays inactive if the sweep cannot be verified. Re-running the
installer also activates an existing inactive delivery job after the same
retention check. Enable the connector after installation succeeds. Capture
closes when the last successful sweep is older than ten minutes. Retention runs
in PostgreSQL even if the delivery worker or Meta is unavailable.

Organizer managers and organization administrators configure Meta Conversions API
in organizer settings under Measurement and consent:
dataset ID, saved HTTPS website, optional test event code and access token.
`save_unit_meta_purchase` saves settings and the Vault credential atomically;
operators do not create connectors or tokens manually. The organizer configures
website consent, enables form measurement and selects forms for CAPI in the
administration. Verify the consent notice and privacy policy cover Meta and
retire earlier Festapp Purchase tags for the selected forms. Use Meta Test Events
to check a bank balance payment, a card payment and withdrawal before settlement.
Compare the stable event ID and value with the private settlement record.

Token errors pause the connector. The organizer saves a replacement token in
administration to clear the pause atomically. The overview shows pending, sent,
failed, revoked, invalid and expired counts over 30 days. Terminal receipts use
their completion time; pending rows use capture time. The last error includes
terminal reasons and distinguishes scheduled retries from outcomes without
further attempts. Invalid reasons are connector revision changes, ineligible
orders (including changed price or form configuration), invalid consent
(snapshot, revision or timing), payment older than seven days and exhausted
attempts. The worker skips forms with delivery disabled. A row that was already
claimed can be marked ineligible at preparation; unclaimed rows expire after
30 days from consent.
Reasons contain no matching data or credentials. A dataset, website or test-code
change requires fresh checkout consent and never backfills earlier orders.

Items carry `item_id`, `item_name`, `price` and `quantity`. Two optional public catalog labels
are added when they exist in browser ecommerce events:

- `item_category`: the product type title. Browser events read it from the form catalog or the
  seat/area product catalog.
- `item_brand`: the occasion title. GA4 `affiliation` means the supplying company or store, so
  the event belongs in the brand of what is sold. One Unit runtime is one organizer, and a Unit
  title can be a natural person's name, so no organizer value is exported.

Labels are limited to 100 characters. A label with controls or `@` is omitted while the item
remains. The labels never affect `value`.
`item_variant`, `coupon` and `discount` are not exported. Discounted cart items use
net prices from the server quote.
Discount codes themselves are never exported. A product is the selected option;
a seat section is not known consistently in the cart. The negative `meta_surcharge`
is informational and does not change the charged price.

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
leads do not create an order or an `analytics.conversion_facts` record. The SQL
ledger stores order leads and private settlement facts.


## Complete conversion payload examples

These example payloads use fictional contacts. Order leads use a
server-generated `event_id`; notification
subscriptions use a client UUID created for that submission. Replays keep the
same fact ID. Deduplicate by that ID; do not generate a new ID on retry. Product
IDs identify catalog products. Example IDs must be replaced with actual event
IDs, never reused for real conversions. `user_data` is optional when no usable
contact is available; sale-opening subscriptions provide email only. Successful
recovery after transport replacement contains the conversion fact without
`user_data`. Consent remains the current state passed to tags, including denial.

```json
{
  "event": "generate_lead",
  "lead_source": "free_registration",
  "event_id": "d5c624bd-01b6-4dcf-9bf9-00dcb73a7b44",
  "currency": "CZK",
  "value": 0,
  "user_data": {
    "email": "buyer@example.test",
    "phone_number": "+420601234567"
  }
}
```

```json
{
  "event": "generate_lead",
  "lead_source": "waitlist",
  "event_id": "e5c624bd-01b6-4dcf-9bf9-00dcb73a7b44",
  "currency": "CZK",
  "value": 0,
  "user_data": {
    "email": "buyer@example.test",
    "phone_number": "+420601234567"
  }
}
```

```json
{
  "event": "generate_lead",
  "lead_source": "sale_opening_notification",
  "event_id": "f5c624bd-01b6-4dcf-9bf9-00dcb73a7b44",
  "currency": "CZK",
  "value": 0,
  "user_data": {
    "email": "buyer@example.test"
  }
}
```

## Consent storage exceptions and keyboard behavior

All seven Consent Mode types are explicit. `security_storage` and
`functionality_storage` remain `granted`, including before a choice and after
Decline. Organizer tags requiring `functionality_storage` therefore run without
consent. Analytics storage follows analytics; ad storage, ad user data, ad
personalization and personalization storage follow marketing.
Mapping content personalization (`personalization_storage`) to marketing is an
intentional organizer choice; the organizer's privacy information must describe
this purpose together with advertising.

The initial central notice is blocking: Escape focuses the notice without saving
a choice or closing it. Decline is available for a decision without optional
consent. Escape in Settings discards the draft. Reopened Settings always offer
Decline; on top-level pages, after a saved decision focus returns to the floating
Consent settings button. The button is fixed at the bottom left, with reserved scroll clearance.
Custom notice text always retains a fixed explanation of how to change consent.

## Live consent transfer to a new tab

Explicit marked links can share a saved website CMP record with the standalone
form. The Unit must enable `measurement_consent_bridge` and confirm the binding for the exact
host origin. The website notice and its archived CMP configuration must cover
this Unit's form, purposes, destinations, recipients and applicable notice revision.
An opt-in switch is configuration, not evidence that a visitor confirmed a notice.

### Configured Complianz source

Configure the standard helper once for one organization/Unit and mark links:

```html
<script defer src="https://vstupenky.online/embed.js"
  data-festapp-consent='{"provider":"complianz","organization":1,"unit":2,"consentRevision":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","policyId":"42"}'></script>
<a data-festapp-consent-link target="_blank"
   href="https://vstupenky.online/form/your-form">Buy tickets</a>
```

These are example values. Obtain `consentRevision` from the form metadata's
`analytics.consent_revision`; use the actual organization/Unit IDs and the
Complianz policy ID whose archived notice covers that revision. The website owner
must verify that statistics/marketing categories cover the form's respective
purposes, destinations and recipients, including the isolated measurement domain.
This static configuration is a coverage assertion, not a visitor consent record.
Do not generate it from the incoming form request or auto-update it on a deploy.

The helper uses Complianz's prefix-aware `cmplz_get_cookie`, banner/category APIs
and consent events. Import requires opt-in mode, a dismissed banner, explicit
stored category values and matching configured, stored and current CMP policy IDs.
Only stored `allow` intersected with the category API can grant. Forced-statistics,
opt-out, per-service records, missing/broken APIs or expired cookies keep the local
notice. TCF marketing stays denied. Ordinary saved refusal transfers without
asking again. A close-only interaction without a stored decision grants nothing.
Sequential category writes are observed after the CMP transaction; polling also
detects expiration and changes from another website tab.

**Standalone links never infer a saved choice from GCM defaults or updates.** An
unconfigured site keeps the form's own notice, even with `default: granted` or a
Consent Mode update. Invalid configured sources remain denied. The existing
unconfigured iframe GCM fallback is unchanged; a configured Complianz source
supplies both links and automatic Unit iframe bindings through the shared registry.
A later explicit source replaces that source and retires its subscriptions.

### Configured CookieConsent v3 source (orestbida)

Supported standard sources are Complianz and CookieConsent v3. For CookieConsent,
expose the public API on the website, including when bundling via npm:

```js
import * as CookieConsent from 'vanilla-cookieconsent';
window.CookieConsent = CookieConsent;
// Run the website's complete CMP configuration with mode:'opt-in', revision:42.
```

```html
<script defer src="https://vstupenky.online/embed.js"
  data-festapp-consent='{"provider":"cookieconsent","organization":1,"unit":2,"consentRevision":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","revision":42,"categories":{"analytics":"analytics","marketing":"marketing"}}'></script>
```

For explicit developer configurations, use actual IDs and
`analytics.consent_revision` from form metadata. `revision` is a positive integer matching both `CookieConsent.getConfig('revision')` and
the saved cookie. New managed exports instead supply a server-issued coverage
window, checked against the saved last-consent timestamp. Archive that CMP notice and its mapping to the Festapp revision;
it must cover the form, both purposes, recipients and measurement domain. Increase
the CMP revision and obtain a new choice when coverage changes. Zero (revision
management disabled), opt-out and unknown/malformed configurations keep the local
notice and never fall back to GCM. One script supports one organization/Unit.

`categories` optionally maps both purposes to distinct website category names;
omit it for defaults `analytics` / `marketing`. Both categories must exist and
must not be enabled by default, read-only or have per-service definitions/choices.
These unsupported cases return `null`. A valid stored acceptance, refusal or
partial choice transfers. TCF presence (`window.__tcfapi`) denies marketing.

The adapter checks `validConsent()`, fresh `getCookie()` contents including
`expirationTime`, and `acceptedCategory()`. Events `cc:onConsent`, `cc:onChange`
and `cc:onFirstConsent` on window coalesce in a microtask. A one-second poll
checks expiry and other-tab changes. If storage and the instance disagree, the
import ends; reload the website to adopt a different tab's new acceptance. Cookie
and `useLocalStorage` storage are supported. API calls made by website code cannot
be distinguished from a visitor's action; the organizer must use the CMP correctly.
The underlying GCM iframe bridge and Complianz adapter are unchanged.

Sources and conservative boundaries: [adapter research](../plans/consent-link-cmp-adapters-2026-11-11.md).

### Configured Cookiebot source

Standard sources also include Cookiebot (`provider:"cookiebot"`). Map Cookiebot
statistics to analytics and marketing to marketing. The ordinary loader from the
Cookiebot Manager is enough; both automatic and manual blocking work:

```html
<script id="Cookiebot" src="https://consent.cookiebot.com/uc.js"
  data-cbid="12345678-1234-1234-1234-123456789abc" data-blockingmode="auto"></script>
<script defer src="https://vstupenky.online/embed.js" data-cookieconsent="ignore"
  data-festapp-consent='{"provider":"cookiebot","organization":1,"unit":2,"consentRevision":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","cbid":"12345678-1234-1234-1234-123456789abc","origin":"https://organizer.example","consentValidFrom":"2026-11-11T00:00:00.000Z","maxAgeSeconds":15552000}'></script>
```

Replace every example value. Use `analytics.consent_revision` from form metadata,
the actual organization/Unit, the website's exact HTTPS origin. An explicitly configured CBID must match the
loader (attribute or `?cbid=` query); it can be omitted in server-issued exports. Exactly one official `.com/uc.js` loader must
remain in the DOM. Both identifiers must agree if attribute and query are present.
Opt-in is read from the runtime state, not from loader attributes: the choice
must be explicit (`consent.method`), GDPR must apply and CCPA must not; implied
choices, a non-opt-in account mode and unknown state keep the local form notice.
The persisted `CookieConsent` record must carry this tab's consent ID, so a
choice in another tab or a removed record ends the transfer at the next one-second poll. Changing CBID or
origin invalidates the mapping. A configured CBID change also invalidates it. `data-blockingmode="none"` or an omitted blocking
attribute uses manual blocking; this does not change consent eligibility.
`data-cookieconsent="ignore"` keeps the helper available with auto-blocking.

**Cookiebot's public SDK provides no comparable saved/current policy revision.**
Neither consent ID/stamp nor the cookie's undocumented `ver` is treated as one.
For explicit configurations, required `consentValidFrom` is the UTC effective instant of the archived notice
and its mapping to Festapp's semantic revision (exact ISO format with milliseconds
and Z). Only choices at or after it can transfer. `maxAgeSeconds` is required,
positive and at most 31536000; set it no greater than the actual consent lifetime
configured in Cookiebot. The example uses 180 days. Managed exports instead use
the server confirmation time and server-owned age ceiling described below. When the notice, recipients,
purposes, CBID or scope change, archive the new notice, renew Cookiebot consents,
and update the cutoff and `consentRevision`. Never relabel old records. This
organizer assertion does not verify notice contents, bind a cookie cryptographically
to CBID or discover remote configuration changes automatically.

Import requires boolean `hasResponse`, explicit `consent.method`, consistent
boolean `consented`/`declined` and categories, and a valid SDK `consentUTC`.
`hasResponse:false` is allowed while renewing an existing saved choice. Both SDK
`consentID` and `consent.stamp` are required and must match the persisted cookie's
stamp. Categories and timestamps come from the SDK, not other cookie fields.
Missing, stale, malformed, expired, per-service or
unprovable records return `null`, remain configured and never fall back to GCM.
A saved refusal transfers without another notice. The cookie reader checks exactly one matching stamp field and never executes cookie
text. Other fields are not interpreted; they do not grant consent. Any missing or
mismatched stamp immediately denies a new transfer. An existing linked visit is
revoked at the next one-second poll. A non-atomic CMP write may therefore end the
import and restore the form notice instead of reusing a cached grant.

The five window events `CookiebotOnConsentReady`, `CookiebotOnLoad`,
`CookiebotOnAccept`, `CookiebotOnDecline`, `CookiebotOnDialogDisplay` coalesce in
a microtask and notify only on a changed result. A one-second interval detects
expiry/removal and other-tab changes. If storage and cached API disagree, the
visit import ends; reload the website to adopt the other tab's new choice.
TCF (`__tcfapi`, `data-framework="IAB"`/`"TCF"`, also the query form) always denies
marketing; vendor/purpose choices cannot become a blanket advertising grant.

Official sources and limits: [Cookiebot research](../plans/consent-link-cmp-adapters-2026-11-11.md#etapa-cookiebot--rešerše-před-implementací).
Live Cookiebot auto/manual blocking is verified by the website administrator;
repository tests model the documented SDK boundary without network requests.

`consent_revision` binds organization/Unit, destination code, privacy URL, notice
text/title, consent version, runtime profile, collector origins and purposes.
It excludes runtime build revision/origin and approved parent origins. Technical
changes still invalidate live leases through `processing_revision`. Increase
`measurement_consent_version` when remote GTM or privacy content changes at an
unchanged ID/URL; the digest cannot inspect those contents. Update the CMP notice
and, for ordinary measurement, require a new decision, then configure its new accepted policy ID and the new
semantic revision together. Never map an old CMP policy to newly added purposes.

Deploy the SQL projection and updated form/helper/runtime artifacts coherently.
Mixed peers that cannot carry the semantic revision fall back to local consent;
there is no permissive GCM fallback during rolling upgrades. Existing external
adapters returning `processingRevision` remain supported by updated peers. New
adapters can instead return a saved `consentRevision` matching the requested
scope's `consentRevision`; a runtime-only deploy then does not invalidate that
saved notice. Exact current technical scope still binds every live message.

### Explicit external adapters

For another CMP, register a live source after `embed.js` loads with
`FestappEmbed.connectMeasurementSource({read(scope), subscribe(notify)})`.
It uses the same record contract as `connectMeasurementConsent(frame, source)`.
`scope` contains `organization`, `unit`, `processingRevision` and the two
`requiredPurposes`, plus optional `consentRevision`. `read` must return null unless the visitor's **saved** CMP
record covers that exact organization, Unit and revision. A valid record returns
`{processingRevision, analytics, marketing}` or `{consentRevision, analytics, marketing}`. Read the revision from that saved
record; never echo the requested revision into an old decision. Subscribe must
return a disposer and notify after updates, withdrawal and record removal.
The source owner must also enforce the website record's own expiry in read.

```js
// Integrate these methods with your CMP's saved records and update events.
const disconnect = FestappEmbed.connectMeasurementSource({
  read(scope) {
    const saved = websiteCmp.savedPurchaseRecord();
    if (!saved || saved.organization !== scope.organization ||
        saved.unit !== scope.unit || saved.processingRevision !== scope.processingRevision ||
        saved.expiresAt <= Date.now()) return null;
    return saved;
  },
  subscribe(notify) { return websiteCmp.onSavedRecordChange(notify); }
});
```

`disconnect()` retires that source. Replacement, broken subscriptions and explicit
disconnect remain denied; they never restore Google's automatic fallback, for
iframes or links. Replacing the configured source ends its active linked visits. The
global source also supplies existing automatic Unit iframe bindings; explicit
per-frame adapters keep precedence. Existing embeds with no global source ever
registered retain their existing automatic bridge behavior.

The `festapp-consent-link` protocol 1 uses the clicked WindowProxy, exact origins,
a random nonce, normalized scope and increasing sequence. Only HTTPS is allowed
(loopback HTTP only during local HTTP development). The form captures and clears
its helper opener before policy loading. Unmarked windows do not participate.
The host accepts the initial request only within 60 seconds of the marked click;
the child waits at most 1500 ms without scroll locking, then shows local consent.
No URL tokens, cookies or new backend RPCs carry the choice.

A valid response establishes a renewable lease of at most 60 seconds. The host
rereads the saved scoped source on updates and every 20 seconds. Withdrawal
updates the choice; unknown records, source replacement/disconnect, page departure
or maximum 24-hour visit end terminate the channel. The form rejects old sequence,
wrong peer/origin/scope and expired responses. Visibility/pageshow also check the
absolute deadline. FormMeasurementSession limits runtime lifetime to both policy
and source deadlines, including renewals and shortened leases; delayed browser
timers cannot authorize another capture after expiry.

Klaro holds imported choices only in its visit model. Heartbeats preserve an open
draft; source changes clamp it and replace the Escape baseline. Missing source or
lease expiry revokes the import and restores the ordinary local notice. Reloads
and new tabs require a fresh marked click. Historical prototype source cookies
are retired before publishing choices. Explicit local saves use the existing
180-day cookie and atomically detach the remote channel and lease. Another tab's
saved local decision wins when the link checks it; ordinary open Klaro tabs are
not continuously synchronized.

After a successful order on the standalone consent-link form, “Back to form” in
the same tab preserves the existing measurement session and active consent link
for the same public form, without reloading or reconnecting. The form data and
cart observation are rebuilt, and subsequent orders use the current consent
choice. Withdrawal, disconnection and lease expiry continue to apply; an ended
link is not restored, and another form does not inherit it.

Successful transfer to a top-level new tab shows the floating settings button.
Saving there makes a local decision; Escape closes settings without saving. Link helpers preserve
modifier clicks, downloads, noreferrer and referrer policies. A bare noopener
does not opt out: browsers imply it for new tabs and CMS/SEO plugins (e.g. Rank
Math) add it to every external link. Remove the marker to opt a link out.
Without a referrer, opener or COOP-compatible connection, local consent remains
available. The click handler can suppress GTM Just Links validation triggers;
measure checkout with form events instead. See the
[link markup](embedded-checkout.md#převzetí-živé-volby-cookies).

## First-party attribution and CMS defaults

For website attribution, select website dataLayer mode and configure the host
GTM container. Host tags use the website's own native identity and CMP. Festapp
does not read, copy or extend GA/GCL/Meta cookies or set a global client_id.
The independent Unit runtime remains available with its existing isolation; it
does not guarantee continuity with the website's visitor/session attribution.

New WordPress inserter blocks explicitly serialize `measurement: host`, new
Joomla modules without a bound setting preselect host, and fresh Wix widgets
without an existing form URL select host. Existing blocks, legacy shortcodes,
modules and widgets retain their saved destination or the unit fallback. Native
website tags and consent must be configured before enabling host measurement.

A paused, importable website GTM preset and setup instructions are available in
[`integrations/measurement`](../../integrations/measurement/README.md). Configure
and preview merchant destinations before publishing. The preset has ten fixed
GA4 event tags, two Ads actions and six gallery-template Meta tags. The Ads
registration trigger selects `free_registration` only; waitlist/opening-interest
remain generic leads. Native Google User-Provided Data is mapped only on
conversion events, while the Meta adapter alone strips the E.164 leading plus.
Retire the previous four-tag preset before enabling its replacement; Google
consent behavior, Meta initialization/matching and account prerequisites are
explained in the linked setup guide.

### Organizer websites and measurement execution permission

Organizer settings store `measurement_websites` in `units.data`. The shared
settings contract accepts at most ten exact HTTPS origins (no path, query,
fragment or trailing slash). These are the canonical saved websites for managed
consent bindings, not proposals requiring platform review. Managers can confirm
and export bindings immediately. The URLs do not themselves prove ownership or
visitor consent. Saving a website confirms organizer operation. After initial
platform/runtime approval, one SQL effective-origin projection admits the saved
websites alongside explicit application origins without rewriting
`analytics.unit_runtime.parent_origins`. Only canonical browser origins are
admitted; the settings editor normalizes casing/default ports before saving.

`get_unit_website_consent_bindings` owns saved-origin membership for consent setup
and external CMP probes. `get_unit_measurement_approval` separately reports
measurement execution permission/runtime availability and notification history.
`request_unit_measurement_approval` sends a request only if that execution policy
or runtime is missing. Adding/changing websites cannot trigger another request
when measurement is already allowed. Origin snapshots in existing request/email
records remain historical metadata, not consent authorization.

An eligible administrator's queued/preparing notification, accepted delivery or
ambiguous sending/unknown outcome prevents duplicate requests. Terminal undelivered
or expired queued work permits retry; the Unit row lock and revision serialize
it. Once runtime/policy permission is present, delivery validation retires pending
measurement requests regardless of differences in saved websites.

Platform policy and runtime execution are provisioned separately through the
controlled SQL release procedure. No consent-authoring RPC writes those tables.
External unmanaged adapters retain the same effective approved-host boundary;
all managed CMS integrations use the single binding authority.

### Managed CMS consent configuration (schema 1)

SQL in `website_consent_bindings.sql` owns one durable binding per Unit and exact
saved website origin. `get_unit_website_consent_bindings(p_unit)` returns current
`consentRevision`, `saved_origins` and bindings. Managers save through
`save_unit_website_consent_binding(p_unit,p_website_origin,p_platform,p_provider_config,
p_expected_version,p_expected_consent_revision,p_confirm)`. Version 0 creates;
every write increments version, clears old confirmation and optionally records
an explicit new confirmation. Stale version or notice raises SQLSTATE 40001.
`disable_unit_website_consent_binding(p_binding,p_expected_version)` retains the
row. `export_unit_website_consent_binding(p_binding,p_expected_version)` only
exports effective, confirmed bindings. All four RPCs require the canonical Unit
configuration capability and authenticated identity; no direct table access.

Export: `{schemaVersion:1,serviceOrigin,websiteOrigin,binding:{id,version},
providerConfig:{provider,organization,unit,consentRevision,...}}`.
`serviceOrigin` comes from the stored organization's `DEFAULT_URL`. Complianz
requires a pinned `policyId`: its supported category API has no saved-choice
timestamp to prove coverage. The configured, current and saved policy must agree.
Organizer settings automatically read `current_policy_id` from the saved
website's inline WordPress `complianz` JSON configuration. Multisite cookie
prefixes do not change this field; visitor cookies still use the prefix-aware
adapter. See [Complianz's integration guide](https://complianz.io/help/wordpress/configuration/developers-guide-for-third-party-integrations/).
The authenticated `probe-complianz` function checks configuration-management
permission and saved exact-origin membership through the manager-only binding RPC.
Only the exact HTTPS origin is fetched, without cookies, using the existing
DNS-vetted, TLS-identity-preserving pinned fetcher, a 15-second request timeout,
a 1 MiB body ceiling and same-origin redirects. HTML tokenization and JavaScript
syntax parsing select only active inline, top-level localized JSON declarations.
Comments, inert containers, external/module/data scripts, executable config and
incomplete or conflicting candidates cannot establish a policy ID. Website code
is never executed; malformed candidates are parsed once, without suffix rescans.
The UI starts probing for saved origins without loading measurement approval.
Unsaved changes cannot start a probe. Pending detection uses
a static loading message and releases the editor to manual fallback after
20 seconds, including when the transport never completes. Website, platform and
provider selectors stay available during detection. The dedicated
`ComplianzPolicyProbe` owns only request state, the deadline and invalidation;
the settings widget owns the editable draft and the stored binding. Scope changes
and disposal cancel the UI deadline and invalidate late results.
Missing, ambiguous, blocked or unsupported configuration offers a collapsed manual
entry fallback when automatic detection is unavailable.
Failed reloads retain manual values and stored drafts; the saved pin stays visible
separately from a newly detected ID. Reload clears coverage confirmation. Automatic confirmation
fetches again on the server and saves only if the detected ID still matches the
organizer's reviewed ID. A `policy_changed` conflict is a typed recoverable outcome:
the editor explains the conflict, detects again and requires fresh coverage
confirmation. Successful saves do not immediately start another probe. The existing manual
save RPC remains supported. This does not attest notice contents or replace the
organizer's explicit coverage confirmation, and never updates an existing pin
without confirmation. No saved-choice timestamp is inferred.

CookieConsent v3 optionally adds distinct `categories:{analytics,marketing}`
(1-128 UTF-16 units each, Unicode/spaces preserved), defaulting to
`analytics`/`marketing`. Its live positive revision must match the saved cookie.

For each new confirmation of CookieConsent v3, Cookiebot or Wix, the server
stores `consentValidFrom` at confirmation time and a `maxAgeSeconds` ceiling of
31536000. Client-supplied cutoff, age and CookieConsent revision are not adopted.
For ordinary browser measurement, the persisted choice timestamp must be at or after confirmation, no more than
60 seconds in the future, and younger than that ceiling; CMP expiry also applies.
CookieConsent uses the saved `lastConsentTimestamp`, Cookiebot `consentUTC`,
and Wix `createdDate`. Scope and the Festapp semantic revision remain server owned.
Cookiebot needs exactly one official HTTPS uc.js loader with a valid, internally
consistent UUID CBID and a matching persisted stamp; new managed exports do not
require a manually configured CBID.

Publish the matching notice, confirm coverage, import the new export, then
require new visitor decisions through the CMP. Repeat this sequence and increase
`measurement_consent_version` when the processing scope changes. For Complianz,
publish and confirm the new matching policy ID. Banner validity alone cannot
prove that a historic choice covers newly introduced Festapp purposes.
Cookiebot requires an [operator-triggered renewal](https://support.cookiebot.com/hc/en-us/articles/26380933353372-Renew-existing-user-consents-in-the-Cookiebot-Manager);
changing banner information alone is not proof that consent was renewed.

Existing schemaVersion 1 exports keep every restriction, including policy ID,
CBID, revision, cutoff and shorter maximum age. The forward migration updates
functions only; it does not rewrite stored configs, versions or confirmations.
A new save follows normal version and confirmation rules, so superseded exports
fail closed. CMS envelope parsers already accept these fields; no plugin release
is needed. Deploy SQL and the hosted helper coherently. An older helper rejects
new CookieConsent exports without a configured revision, leaving local consent.

The public form policy carries `website_consent_bindings` with only `id`,
`version`, `websiteOrigin`, `effective`, including disabled tombstones. An origin
with a row requires matching binding identity/version on every transferred
choice. Removing binding fields cannot fall back to an external adapter there.
External adapters on unmanaged origins retain their existing contract. Binding
changes affect `processing_revision`, never the semantic `consent_revision`.
Refresh retires a changed grant; policy loss never extends the 60-second lease.
CMS import status indicates local acceptance only. Cookie choice transfer does
not promise continuity of an analytics visitor identity.

The same schema also covers `platform: wix` and `platform: html` (including
Webnode). Platform changes update the existing Unit/origin row; they do not create
a second consent policy. Wix settings and the HTML generators import the same
export, with transfer off by default. Their own fallback links can participate;
unrelated page links remain untouched. Wix checkout provenance and the signed
`checkout_origin` flow remain separate and unchanged.

The native `wix` adapter reads the public synchronous
`window.consentPolicyManager.getCurrentConsentPolicy()` boundary exposed by
`@wix/site`'s consentPolicyManager module. It requires `defaultPolicy === false`,
a valid top-level `createdDate`, `essential === true` and boolean purpose fields.
Analytics maps to `analytics`; marketing requires both `advertising` and
`dataToThirdParty`, and is clamped when TCF is present. Both the confirmed
coverage window and Wix saved-policy validity apply. Missing timestamps, default
policy, pre-confirmation/future/expired records and unavailable APIs never import. No
consent cookie values or visitor identifiers are exported to CMS configuration.

Each read rechecks the current native API; event, polling, focus and visibility
updates catch resets, other-tab changes and expiry. The installed SDK's
`@wix/consent-policy-manager@1.15.0` is a thin public API wrapper. The existing
public development site was tested in an isolated browser on 2026-11-14: deleting
the exact `consent-policy` cookie and resetting from a second tab immediately
returned `defaultPolicy: true` in the first tab without reload. That observation
covers the tested live host; modeled SDK tests are not a claim of live hosting
coverage for every Wix editor or account.

Primary Wix contracts: [consent requirements](https://dev.wix.com/docs/build-apps/launch-your-app/legal-and-security/gdpr-compliance/implement-cookie-consent-requirements),
[consent apps and default policy](https://dev.wix.com/docs/build-apps/launch-your-app/legal-and-security/about-consent-apps),
[consent policy manager](https://dev.wix.com/docs/sdk/host-modules/site/consent-policy-manager/introduction).


### Automatic measurement on saved websites

After the organizer's initial platform/runtime approval, every exact HTTPS
website saved by its manager is automatically eligible as a measurement host.
Saving confirms that the organizer operates those websites; it never grants
visitor consent. The existing organization/Unit/form switches, privacy notice,
runtime and consent checks remain. No additional domain-approval request is sent.
Removing a saved website withdraws its self-service grant on policy renewal.
Explicit operator-owned application origins remain separately configured.

### Administrator-confirmed bank email payments

An email counts toward paid conversion after an administrator confirms and pairs
the receipt. The existing eligibility check still requires full net bank receipts,
a paid or sent order, and live measurement policy. Purchase cohort, consent, age
and connector checks still apply.

The Meta worker rechecks eligibility in `prepare_meta_purchase_delivery`.
Unpairing can make the order ineligible up to that check. A send already in
flight can finish, and successful sends retain their existing event identity.
