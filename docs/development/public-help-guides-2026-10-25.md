# Public organizer help, 2026-10-25

The help hub has twelve task guides and six category landing pages. Czech and
English share stable topic IDs, renderer, navigation, search engine and application
link mechanism. English/global production publication remains gated; its preview
is usable independently and never falls back to Czech screenshots.

## Fresh real UI and reusable video evidence

[The capture manifest](public-help-walkthrough-2026-10-25.json) records 38 newly
captured Czech application screenshots and eight scenario chapters. Each image
has an actual capture timestamp, SHA-256, media identity and interaction-step
reference. Chapters contain exact UI actions, observed outcomes, relevant stills
and notes for later video scripting. No video is claimed to exist yet.

The walkthrough created **Slavnostní ples U Lípy** through the real setup wizard,
selected the silk ball ticket template and the round-table hall, changed hall
style, renamed a table and added a chair. Saving produced 97 places. It then
created the event, opened sales in its form editor, selected a seat through the
public web client, submitted one 350 CZK order, expanded real payment instructions,
corrected the buyer contact with **Pouze uložit**, recorded synthetic cash through
**Přidat platbu**, and checked the report. The web scanner first rejected admission
of an unpaid ticket; after the payment, it returned a valid ticket, a server
admission receipt and an already-used result on a repeated lookup. These are
actual data transitions, not screenshots populated with invented success states.

The bank account was a pre-seeded synthetic prerequisite, with synchronization
disabled. Its successful creation through the account form is not claimed.
No bank transfer or external customer email was sent; local queue records explicitly
showed messages waiting. Ticket-editor PDF preview used an actual generated PDF
with synthetic preview data. The sample-data menu was captured, but selecting its
long-data preset was not established as a success. Physical camera input and offline
admission/reconciliation were not tested; default scanner-code permissions did not
show offline preparation. The help describes that capability conditionally.

The owned Supabase project was `festapp-wizard-help-20261025`, API 56821, DB 56822;
Flutter ran on 56880 and the web client on 57981. Both used real Auth/REST and
canonical application modules. Only local runtime configuration, external push
callbacks and the immutable font-cache transport were adapted. Font bytes,
shaping, template rendering, orders, contact updates and scanner receipts were
real. External provider credentials were not loaded. The browser profile was
isolated and headless. A transient read of the production scanner landing page
failed its blocked API request and was excluded from the published images.

Eight obsolete Czech application images were removed; the former marketing poster
references were replaced with new application captures. Existing actual WordPress
and Webnode editor images retain their own dated provenance. Webnode Premium
publication remains unverified while trial activation is pending.

All owned browsers, Flutter/Vite/font/Edge servers and the disposable backend were
stopped. Backend data was retained in its owned local database volume for later video work;
private credentials and raw interaction logs are not publication artifacts. The stop command returned a legacy-container error, but readback confirmed every owned container stopped and the database volume retained.

## Product fixes and administration links

Opening a newly created closed-sales form reproduced a real crash in
`FormDefinition.startTimeUtc`: SQL stores `schedule.start_time = null`, while the
getter passed it to `DateTime.tryParse`. Both schedule getters now treat absent or
non-string values as unset. The exact null payload is covered by a core regression
test, and the real form editor subsequently opened and saved its availability.

Guide action links carry an allowlisted section intent, never a fixed event ID.
After login the user explicitly chooses a permission-filtered event, with recent
context shown first. Canonical administration entry rechecks access. Real browser
checks covered a signed-in seating link and a separate signed-out profile that
logged in and reached its form editor. The Flutter HTML shell now preserves the
login redirect query; its legacy clean-URL restoration remains available elsewhere.
The hosting test covers both application and ticketing tenant modes.

## Search and publication boundaries

The shared documentation toolbar opens an accessible localized search dialog.
The build indexes complete authored article sections; results rank titles,
aliases, headings and body text and deep-link to sections. Tests cover diacritics,
word forms, spelling variants, category filters, zero results, safe excerpts,
keyboard/focus behavior, English labels and static file preview URLs.
Category pages and articles carry their own metadata, breadcrumb schema and
crawlable links. Preview pages are noindex. Physical search-engine indexing or
ranking is not asserted.

Use `node automation/release/preview_help.mjs` and append `--en` for English. Both
produce standalone file previews. Production publication is a separate step.

## Final validation receipt

- 21 targeted automation/hosting/CSP/cache/search tests passed.
- 9 browser-UI unit tests passed (global search and embed generator).
- 1 Flutter help-intent allowlist test and 10 core form metadata/definition tests passed.
- Both new native files analyze without diagnostics; the existing router retains
  its pre-existing informational diagnostics outside the added help branch.
- 76 static page/locale/viewport/theme checks passed without overflow, missing
  images or duplicate H1s. The Astra Medium UI/UX pass separately exercised the
  global dialog at desktop/light and 320px/dark, focus/keyboard behavior and
  opaque results surfaces. The mechanical design detector returned no findings.
- Fetched main was 928f15349, with no upstream commits missing from this branch
  immediately before publication preparation. Production was not deployed.

## Inline actions and mobile follow-up

Application links now sit inside the opening step for that task and use explicit
localized labels, such as **Otevřít plánek v aplikaci**. They open a new tab so the
reader can keep the guide and administration side by side. Czech and English
sources use the same authored action-token mechanism and intent allowlist.

Nine additional real mobile-view captures bring the curated collection to 47.
They show seat selection, a filled form, the summary with its visible submission
action, and manual ticket lookup/already-used results. English has its own new
form and scanner captures. The presentation is a 390 × 844 desktop Chromium
viewport, not a claim of physical iPhone, Safari or camera testing. The second
purchase demonstration stopped before submission. Its selected seat was a local
temporary hold. The video manifest preserves these details as a ninth chapter.

The failed remote startup check was an outdated VM harness: it removed the
`initAccountHeader` import from the landing entry without evaluating the extracted
shared module. The harness now executes the real shared module and its real
caller together. The complete `automation/test_web_startup.sh` gate passed locally,
including its seven isolated Chromium access/provider-handoff cases. The new
inline-action assertions and the 76 page/locale/viewport/theme checks also passed.

## Scanner platform correction

The scanner guide uses the responsive webclient in a phone browser, as explicitly
selected by the user. A native iOS capture experiment was rejected and its images
are removed from the help assets and curated video manifest. Both CS and EN
articles use only existing real mobile webclient captures (390 x 844 Chromium);
no desktop scanner or Flutter images remain in those articles. Text follows the
webclient manual-code entry, separate confirmation and conditional offline tools.
These captures do not certify physical camera input or mobile Safari. A targeted
media contract enforces mobile webclient evidence for both locales.

## Scanner errors and shared display settings

Twelve fresh 390 x 844 responsive webclient captures cover CS and EN invalid
scanner access, missing ticket, fixed/core display settings, form-field options,
advanced behavior and draft ticket preview. All use the existing owned local
Supabase fixture and actual RPC responses. No result injection or camera mocks.
A nonexistent access code and ticket symbol produced distinct real errors.

The seeded administrator was authenticated through the real AuthService as a
fixture prerequisite (not a claimed UI login recording). Its actual scanner menu
exposed the editor-only display settings. Product selection and adding the form's
email answer were performed through the UI. Field options and advanced controls
were inspected, then an already-used ticket was previewed without admission.
The actual settings save succeeded; reopening the event and its menu settings
retained email visibility and selected-products mode. The manual-search option
was also enabled through UI. No horizontal overflow was observed at 390 px.

Both localized articles now explain that settings apply across the event, which
core fields cannot be hidden, selected products, order versus ticket answers,
labels, hiding empty fields, ordering, optional search/prices/internal notes,
offline authorization up to 12 hours, draft preview, save and renewal of access.
No physical QR camera or offline sync claim is added. The timestamped private
interaction log and tenth video chapter preserve the actions and outcomes.

## Help action destination verification

The scanner settings step now links to `/login?redirect=/help-action/scanner-settings`
(encoded in generated HTML). After login and the explicit event chooser, the
router reloads the selected event's rights and resolves its numeric occasion ID.
It opens `/scan/settings?occasion=...&returnTo=...` in the actual webclient on the
current browser origin, retaining shared Auth storage and the selected event's
ticket-list return path. A help URL cannot supply its own event ID. Normal
scanner session/settings APIs still enforce event editor permissions. Missing
context falls through the regular protected ticket administration boundary.

An isolated local browser exercised the generated link in its own new tab:
signed-out password login, actual event choice, webclient settings and matching
back link; a second signed-in run skipped the password prompt and reached the
same event's settings. A separate tickets help link reached the selected Tickets
tab. Flutter event choice used its real accessibility click handler, not injected
routing or server results. The original documentation tab stayed intact. The
local full-app bootstrap isolates notification callbacks; Google OAuth and live
push are outside this check. Private timestamped actions and source hashes are
recorded in the walkthrough manifest's helpActionVerification entry.

Validation: 9 targeted help/login/settings Node tests, 2 Flutter intent tests,
4 existing post-login navigation tests and a fresh local Flutter web build passed.
Targeted analysis reported no errors, with 11 existing informational router lints.
The UI detector reported no findings. This change must ship with both Flutter
administration and the generated help; it is not yet verified in production.

## Organizer journey, banking and wizard separation

The help now has fifteen task guides plus its overview and eight category pages
(24 documents per locale). The shared order is setup wizard, existing-event
administration, tickets/seating, banking, website publication, orders, admission
and troubleshooting. The overview first offers three explicit entry choices:
new event, existing-event edits and banking. Integrations follow sales/payment
preparation instead of leading the directory.

New guides cover existing-event settings, organizer bank-account setup and Fio
API token authorization/connection. Workflow metadata creates a localized
context note and the renderer rejects marked wizard captures in administration
articles. Wizard-only account selection, seating-template/save and initial
appearance instructions now live in the wizard guide. Existing-form payment
settings have their own actual CS/EN administration captures and a Forms action,
replacing the misleading event-settings action on the old banking paragraph.

Nine new bank/form/event administration captures use the actual local Flutter
organizer UI. One original wizard dates capture was newly curated to replace an
existing-event screenshot previously shown in the wizard. The scanner continues
to use mobile webclient screenshots exclusively. The local fixture selects the
installed current v219 unit-dashboard contract through the existing bootstrap
initialization seam because loopback activation otherwise selects legacy v218.
A synthetic unused Fio account was added without credentials or fetching; no
live token, bank connection, bank pull, order or payment was created/verified.
Bank detail/tab routes were opened directly. Retained-underlay pointer activation
was not qualified by this headless walkthrough; do not claim an interactive bank
account creation or token-save E2E. The manifest preserves this limitation.

The YouTube upload session of 2026-10-22 identifies corrected public v4 as
https://www.youtube.com/watch?v=px9MCABSQbI; the older upload is private. Official
YouTube oEmbed readback verified title and channel vstupenky.online. `videos.json`
provides locale-specific links/copy; English explicitly identifies the video as
Czech. Fio authorization and five-minute activation instructions were checked
against its official API documentation linked next to those instructions.

The main update was merged at a5056dd0b before this documentation change. Its only
merge conflict was generated web/organizers-page, regenerated from the combined
canonical renderer and shared shell. Organizer/analytics/help/login checks passed
16 tests; the final affected help/search/public-SEO batch passed 28 tests. The
rebuilt local Flutter fixture passed after correcting its bootstrap caller to
startApplication. All 96 localized page/viewport/theme cases passed; a final
four-case bank-guide check covered its last copy refinement. The design detector
reported no findings. Private browser sessions and the owned backend were closed;
backend data was preserved for future screenshots. English remains preview-only.

## Embedded Fio tutorial

The localized video renderer now produces the actual responsive 16:9 YouTube
privacy-enhanced iframe, with a title, lazy loading, full-screen support and an
explicit strict-origin-when-cross-origin referrer policy. The ordinary YouTube
link remains in the caption. CS and EN use the same verified tutorial; English
continues identifying its Czech language. Rendering tests cover the video ID,
iframe boundary and referrer policy; other guides still reject unexpected frames.

A real YouTube player thumbnail and controls loaded in isolated Chrome from the
HTTP help preview. At 320px, the player measured 284 x 159.75 and the document had
no horizontal overflow. The standalone file preview returned YouTube error 153
(missing web referrer); this is a preview transport limitation, not evidence of
blocked embedding on the site. The user-requested playable embed is therefore
previewed via owned loopback HTTP on port 57982 instead of file://. Only that
preview server remains running for the user; the automated browser was closed.
Two affected renderer tests passed and the CSS detector reported no findings.

## Independent content/context critic pass

Two independent agents reviewed the frozen 13c41b7 help: assessment A checked
all original task guides/categories in CS and EN against actual UI source and
representative rendered pages; assessment B independently inspected browser,
accessibility and detector evidence. A finished before B's findings were released.
The archived dual-agent report is under .impeccable/critique; B evidence is in
.private/help-critique-20261025/evidence-b.json. Both isolated browsers and B's
injection server were closed; the user's HTTP preview remains available.

Corrected six material content/UX findings: account routing uses the first
organizer account supporting the currency by priority, not a per-form picker;
EN seating uses existing-event administration; Form handles availability while
Settings handles address/payment details; saving WordPress block attributes is
separate from installing plugin updates; organizer scanner settings moved to
their own guide; irrelevant cautions and QA narration were removed. The context
of bank-account changes and their effect on new orders is now explicit. A's
focused readback confirmed these corrections, with one remaining payment-lead
verb corrected before validation. No improved numeric score is invented.

There are now sixteen task guides, the overview and eight categories (25 pages
per locale). Door staff get an uninterrupted scan/results/recovery procedure;
organizers get a separate settings guide retaining its existing help action,
permissions, shared-event scope and preview/save boundaries. Existing scanner
anchors remain as links to the settings guide. Images remain real responsive
webclient captures. Reading measure is bounded without changing the shared site
header/footer or introducing a new visual style.

Final validation passed 28 help/search/public-SEO tests and 100 localized
page/viewport/theme cases. The final scoped design detector had no findings.
The earlier whole-stylesheet CLI findings were not reproduced in rendered
inspection and were recorded as false positives instead of changing unrelated
homepage styling. Questions skipped: the user had already authorized corrections.

## Visual previews in guide directories

Every task guide and category now selects a real localized screenshot through
its preview metadata. The hub's three entry choices, eight category links and
all category guide lists show those previews before opening an article. The
renderer reuses the existing hashed screenshot assets with lazy loading; no
invented illustrations or additional screenshots were introduced. English uses
its own interface captures. Where an English platform-specific editor capture
is unavailable (Webnode), the preview shows the relevant English embed-code
preparation step rather than substituting a Czech editor screenshot.

Preview crops emphasize the relevant form region or account list instead of
blank viewport space. Originals and their provenance/hash remain unchanged.
Desktop guide rows pair the preview with title and summary; narrow mobile rows
place the title, a larger preview and then the summary in one column. Images are
decorative within the already descriptively named link, avoiding duplicate screen
reader announcements and extra image-only focus stops. Existing guide text,
workflow distinctions and help-action destinations are unchanged.

Renderer/search tests passed five cases and all 100 locale/page/viewport/theme
cases passed. A final targeted two-test batch covered the last media selection
refinement. Desktop and 390px preview composition were visually inspected; the
final design detector reported no findings. The task-specific automated browser
was closed; the user-requested HTTP preview remains running for the video.
