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
