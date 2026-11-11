# Issue #804 - GTM preset architecture and adoption plan

Status: implemented and verified locally plus actual nonproduction GTM import. Source publication and merchant activation remain separate.
Verification: standard (customer data, consent and a public integration contract).
Reviewed main: c6afb3fcec757bd9964d49aedd628e8bb2b82c7a. Implementation base: 32032baa7 (#806 order reads retained).
Request: https://github.com/festappnet/festapp/issues/804 (2026-11-11 05:08 UTC).
This plan reviews the complete proposal, not the inaccessible local commit.

## Outcome and scope

Produce one deterministic, paused GTM import for an organizer's website, with
native Google tags and the official gallery-linked Meta template. Respect the
existing Festapp event meanings, contact allowlist, host consent ownership and
merchant destination setup. Do not redesign consent-link #803 or Unit runtimes.
Do not publish GTM versions, unpause merchant tags, accept account data policies,
modify production data, or change financial/VAT semantics during this work.

Issue #804 says one local commit on `feat/gtm-preset-doku` already contains the
implementation. Neither local refs, origin heads, open PRs, issue references nor
the author's repository fork expose it. The user subsequently authorized writing and executing this plan despite that
unavailable branch. Implement against current main using the issue requirements
and the reviewed upstream template. Do not claim to have reviewed or adopted the
author's unavailable code. If it becomes available, compare rather than duplicate
its valid work.

## Confirmed current ownership

- `web_client/src/components/forms/form_datalayer.js` produces event facts from
  existing form/order results. `analyticsPayload` in `form_measurement_contract.js`
  validates and rebuilds each event. SQL finalizer snapshots own charged amounts.
- `measurementDataLayerPayload` selects the destination event name and context.
  `host_measurement.js` forwards to approved host dataLayers and clears ecommerce,
  contact state and the embedded marker. Preserve those owners and invariants.
- `integrations/measurement/build_gtm_preset.mjs` owns the GTM representation;
  `festapp-host-gtm.json` is its deterministic generated artifact. No second event
  schema, consent engine, identity store, checkout DOM scraper or cookie copier.
- `web_client/tests/core/host_gtm_preset.test.js` currently enforces the four-tag
  design, Google additional gates and no GA4/Meta contacts. Those requirements
  must be replaced explicitly, not merely bypassed to accept a new JSON file.
- `automation/release/render_help_pages.mjs` copies the canonical preset to the
  public download. Existing help tests verify byte identity. Update docs and
  generation together; do not create a separate downloadable preset copy.

## Review decisions

| Proposal | Assessment and target |
| --- | --- |
| Remove additional Google consent gates | Adopt for the selected advanced Consent Mode profile. Native Google tags consume the host's consent state; use explicit `NOT_NEEDED` additional-check status. This is not a claim that basic Consent Mode is universally wrong. Host CMP must establish defaults before Google tags. |
| No `ad_personalization` gate on conversion firing | Adopt. Keep reporting every Consent Mode v2 state; do not conflate personalized ads with whether a conversion tag may run. Built-in consent logic governs cookie/contact handling. |
| Ten GA4 tags with fixed event names | Adopt as the project convention for readable per-event configuration. A dynamic `{{Event}}` tag is not inherently nonstandard or prohibited by Google. Generate tags from one event specification instead of maintaining ten copies. |
| Shared triggers and names/folder/constants | Adopt. Require strict `form_embedded = true`, constant destination IDs/labels, one Festapp folder and paused tags. Rename does not alone prove correctness. An additional subtype trigger is justified where event meanings differ. |
| Add Google Ads registration conversion | Adopt with a correction: `generate_lead` also means `waitlist` and `sale_opening_notification`, not only `free_registration`. Restrict the registration action to `lead_source = free_registration`. Keep the shared generic lead trigger for GA4/Meta; allow an extra registration-specific trigger. Never silently relabel all leads as completed registrations. |
| Native Google User-Provided Data for purchase/lead | Adopt conditionally. Use the supported native manual variable, only canonical email/phone fields, and the documented `user_data` integration. Account feature activation, appropriate consent and customer-data terms are required. This is not ordinary GA4 event-parameter PII collection. |
| Official Meta Pixel v2.0.9 | Adopt pinned, unmodified upstream source with license/digest and real gallery metadata. Avoid a locally forked substitute while advertising gallery updates. Actual linked-template import remains a gate. |
| Six Meta standard event tags | Adopt ViewContent, AddToCart, InitiateCheckout, AddPaymentInfo, Purchase and Lead. Public object/contents allowlists remain explicit; no implicit eventModel or automatic ecommerce harvesting. |
| Meta Advanced Matching on Purchase/Lead | Adopt explicit category/recipient coverage and a documented SDK lifecycle. Remove only the leading plus from already validated E.164 for Meta; keep canonical E.164 for Google. No country inference or global source-field rewriting. |
| Meta requires `ad_storage` | Treat it as a GTM enforcement hook mapped by the merchant CMP to Meta marketing and matching purposes, not universal evidence authorizing all contact transfers. CMP owns revocation, including queued SDK work. Do not let the preset invent grants. |
| Meta CAPI explicitly false | Required on every Meta tag. Upstream 2.0.9 treats missing `optInMetaCAPI` as opt-in. Test the serialized boolean, not only the checkbox label. |
| Remove Meta eventID | Accept as a browser-only preset choice. Keep canonical `event_id` and transaction identities in Festapp. An event ID does not itself enable CAPI; duplicate prevention still requires correct event production and overlapping-tag cleanup. |
| VAT/net revenue and estimated lead value | Separate follow-ups, as the issue requests. Never divide prices by an assumed tax rate or put an invented lead value into the preset. Existing lead value is zero and enforced by the shared contract. |

## Material corrections before adoption

### 1. Registration is a domain subtype, not the generic lead event

`analyticsPayload` accepts exactly `free_registration`, `waitlist`, and
`sale_opening_notification`. A single Ads action called Registration must not
count all three. Prefer the narrowly filtered registration trigger; alternatively
an explicitly named generic Lead action is a different product decision. The
18/10/20 entity counts in the issue are descriptive, not an architectural gate.
A correct subtype filter may increase the trigger/variable count.

`purchase` currently means an accepted priced order, not confirmed bank/card
settlement. Preserve this documented meaning and use an order-creation conversion
name; do not describe the action as money received or emit it again on payment.

### 2. GA4 user_data is a supported feature with prerequisites

Google's native GTM setup attaches `user_data` through a User-Provided Data
variable. The GA4 property must enable the feature and accept its policy; the
current docs label it open beta and describe Google Ads linking. Do not send
email/phone as ordinary custom dimensions, event parameters or URLs, and do not
enable automatic DOM detection as a shortcut. Google receives the existing
canonical E.164 value; normalization for Meta belongs in the Meta adapter only.

### 3. Meta template owns SDK initialization and matching state

Pinned upstream v2.0.9 is commit `08b9bbba509d6f10f6ad2bd39207ed814e96cbbe`.
The actual template creates/reuses `fbq`, initializes IDs and reinitializes with
customer matching data. Therefore the issue's statement that initialization is
simply outside the preset is incomplete. Choose and document one coherent site
pixel setup: use the same configured pixel ID and a supported initialization
path, preserve the site's baseline PageView, and prove no duplicate conversion
or PageView. Do not write `_fbq_gtm_ids` or other SDK-private globals to mask
initialization conflicts.

The template's code reads `advancedMatchingList` whenever it is populated, even
apart from the editor's `advancedMatching` checkbox. Omit matching lists from
nonconversion tags; event-scope all contact variables. Disable
`useGA4Ecommerce` and legacy automatic ecommerce mapping and supply explicit
allowlisted object properties. Otherwise the template can pull `eventModel`
contact/item fields outside our intended projection.

Clearing `user_data` from the host dataLayer does not clear Meta SDK matching
state. Promise bounded input to matching on the two conversion tags, not that
Meta can never associate subsequent SDK events with that identity. Verify and
document that lifecycle and consent withdrawal with the shared site pixel.

Explicit CAPI opt-out prevents the template's `optinMetaEnabledCapi` opt-in call.
It does not prove that the template loads no additional scripts: source v2.0.9
can load its client parameter builder from jsDelivr/unpkg after an SDK gateCheck,
independently of that opt-in field. Record actual dependencies/permissions; do
not silently patch official template internals or claim unsupported isolation.

## Target module shape

Keep one small generator interface: an internal declarative event specification
and destination builders produce one GTM container artifact. Event definitions
carry fixed name, ecommerce classification and contact eligibility; the existing
shared wire contract remains authoritative for accepted runtime data. No new
runtime public API or database migration is needed for #804.

Destination differences stay in the generator/adapter functions: native Google
UPD mapping, Meta E.164-to-digits projection, Meta contents allowlist and lead
subtype trigger. Constants own merchant IDs/labels. Copy neither consent state
nor customer data into global caches. One canonical upstream Meta template file
with provenance supports the gallery-linked custom template record.

## Implementation waves

1. **Establish current source and executable evidence.** Implement the #804
   requirements on current main in the isolated worktree. Retain #803 consent
   integration and #806 order-read improvements. Replace the unavailable-commit
   prerequisite with an explicit implementation decision. Acquire actual GTM
   native UPD/gallery export shapes and pin pristine upstream Meta 2.0.9.
2. **Finalize generator semantics.** Adopt the decision table, add the Ads lead
   subtype distinction, verify constants and native UPD shapes from a real GTM
   export. Remove old grouped GA4 tags, Meta Custom HTML/export `metaHtml`, old
   variable names and obsolete consent-gate expectations. No permissive fallback
   tags, old/new parallel downloads or duplicate business event producers.
3. **Verify imported template behavior.** Pin pristine upstream and gallery
   identity, use explicit CAPI false, bounded contents/matching configuration and
   documented initialization ownership. Exercise the actual upstream sandboxed
   template with captured public SDK calls; do not replace it with a handwritten
   Meta mock that already assumes desired behavior.
4. **Update consumer docs and proof.** README and CS/EN help describe Merge,
   Rename conflicting, constants, account prerequisites, advanced consent profile,
   Meta matching formats/lifecycle and staged unpause. Update current VALIDATION
   with artifact/template digests and actual evidence; preserve earlier validation
   as a dated historical record instead of calling old evidence current.

## Acceptance and validation

- Generator `--check`, reference/folder integrity, all tags paused, constant
  destination ownership and canonical public download byte identity.
- Assert fixed GA4 event names; ecommerce absent on non-ecommerce events;
  scoped page context/lead fields; Google consent additional checks NOT_NEEDED.
- Purchase and generic lead go to intended GA4/Meta actions, Ads Registration
  only gets free_registration. Waitlist and opening-interest never count as
  completed registration. Amounts/currency/order identity retain current meanings.
- Contact exists only on conversion inputs, is absent from generic tags, and
  cannot inherit an earlier website/other-form contact or ecommerce object.
  Invalid/missing phone/email is omitted; Google E.164 and Meta digits differ
  only at their adapter. No DOM inspection, extra fields or URL/log copies.
- Real pinned Meta template execution: standard events and contents, actual
  init/re-init calls, explicit CAPI opt-out, no automatic eventModel capture,
  missing pixel ID behavior and asynchronous SDK readiness/withdrawal.
- Import the exact final JSON into a disposable/nonproduction GTM workspace,
  Merge + Rename conflicting. Confirm all references, native UPD rendering,
  gallery link/update identity, constants and paused tags. Do not publish it.
- Preview with tracking network intercepted: denied/granted/withdrawn consent,
  delayed SDK, native website events and two interleaved embeds, purchase/lead
  followed by a generic event, and existing-pixel integration. Assert consent
  transitions/absence of prohibited payloads, not merely the editor tag count.
- Run affected existing preset/help tests and required canonical CI lanes
  selected from final changed paths before publication. Browser interaction
  belongs to the authorized Terra operator, headless/isolated/muted; no user's
  current tabs, production publishing or approved-account policy changes.

## Definition of ready and limits

Merge-ready means the adopted implementation matches these event/consent/data
rules, final gallery-linked import is proven and current validation distinguishes
import/preview from real conversion delivery. Account delivery, attribution,
policy acceptance and merchant unpause require their normal authorized setup.
The author's unavailable commit is no longer a dependency for this authorized
implementation. Actual gallery-linked import and account access remain evidence
gates; complete all independent implementation/tests even if an external login
is unavailable, and report an import gap rather than inventing validation.

## Sources inspected

- Issue and status: https://github.com/festappnet/festapp/issues/804
- Google consent modes: https://developers.google.com/tag-platform/security/concepts/consent-mode
- Native/additional checks: https://support.google.com/tagmanager/answer/10718549?hl=en-GB
- Native GA4 UPD mapping: https://support.google.com/analytics/answer/14179229?hl=en
- UPD prerequisites/status: https://support.google.com/analytics/answer/14077171?hl=en
- Meta source: https://github.com/meta/GoogleTagManager-WebTemplate-For-FacebookPixel/blob/08b9bbba509d6f10f6ad2bd39207ed814e96cbbe/template.tpl
- Meta version history: https://github.com/meta/GoogleTagManager-WebTemplate-For-FacebookPixel/blob/main/metadata.yaml
- Google ecommerce: https://developers.google.com/analytics/devguides/collection/ga4/ecommerce

Meta's standalone developer advanced-matching page returned HTTP 429 during this
review. Template behavior conclusions above are from the pinned official source,
not a claimed successful read of that unavailable page. No implementation tests,
imports or production actions were performed during this proposal-only review.

## Execution scope update

The user explicitly requested a written plan followed by implementation. This
plan is now executable without waiting for the author's local commit. Source
publication/deployment and merchant production changes are not implied. Start
with a meaningful failing preset contract case; batch generator, tests and docs
changes, then run final targeted checks and canonical affected lanes where
publication is requested. Browser import remains nonproduction and all tags
remain paused. No account/customer-data policy acceptance is authorized.

## Execution result

Implemented in worktree `festapp-gtm-preset-804-review-20261111`, branch
`feat/gtm-preset-804-20261111`, based on current main `32032baa7`. No unavailable
author code was claimed adopted. Canonical application/SQL/Worker source did not
change: only the preset generator/artifacts, official template sources, tests,
documentation and changelog were updated.

The replacement has 18 paused tags, 11 triggers, 28 variables, one Festapp folder
and one gallery-linked Meta 2.0.9 template. The extra trigger enforces the approved
free-registration distinction. Native Google UPD schema and gallery identity
were acquired from actual GTM exports, not guessed. CAPI opt-in is explicitly
false; automatic Meta eventModel/ecommerce inheritance is disabled.

Completed all independent implementation waves and exact linked-template import.
Targeted tests passed 25/25 plus 3/3 help contracts, generator parity and whitespace
checks. Actual GTM round-trip comparison preserved parameter values, consent
settings, firing-trigger mappings and subtype filters. Representative native
editors interpreted the intended configuration. See
`integrations/measurement/VALIDATION.md` for digests, observations and limits.

Activation clarification: the delivered artifact and test workspace remain paused.
Network Preview, actual SDK revocation/delivery and account eligibility require
merchant activation with real destinations; they were not performed or claimed
by the import-only proof. No GTM/source production publication, tag unpause,
account/customer-data policy acceptance or production data changes were made.
Future source publication requires the canonical affected CI mirrors; conservative
selection currently requests all eight jobs for these integration source paths.

## Authorized integration and release

The user subsequently explicitly authorized integration into main, deployment
and automatic approval. Scope: only `prod/festapptickets` / vstupenky.online.
Run mandatory affected canonical mirrors before source publication, fetch current
main immediately before the push, and require exact-main all-eight GitHub CI via
`automation/ci/release_gate.py` before creating/pushing the tenant overlay.
Delegate routine build/deploy monitoring to the cheaper release agent. Preserve
main-owned drift checks, selected tenant ancestry, local Flutter resource slot,
local build/direct Cloudflare deployment and coherent live-version/legal probes.
This authorizes source/web publication; it does not authorize unpausing merchant
GTM tags, publishing customer containers or accepting their account policies.
