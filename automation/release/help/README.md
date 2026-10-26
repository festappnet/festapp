# Public Czech help

The approved outline is in `docs/plans/help-content-and-localization-2026-10-24.md`.
The implementation shares the homepage header/footer fragments, canonical
organizer CSS and account-header startup. The current outline supersedes the
initial ordering: eight areas and sixteen task guides, with matching English
preview routes and stable topic IDs. Start with the new-event wizard, then
existing-event administration, tickets/seating, banking, website publication,
order management, check-in and troubleshooting. The hub has separate entry
choices for creating an event, editing an existing one and preparing banking.

The wizard owns draft-only instructions and captures. Administration articles
start at the relevant tab of an existing event. Organizer-level bank accounts
are separate from selecting an account for a form. `pages*.json` marks these
contexts with `workflow`; `ui.json` localizes the visible context note. Marked
wizard-only screenshots are rejected in administration articles by the renderer.
Scanner guides show only responsive mobile webclient images, never native
Flutter screens. Bank and event administration screenshots remain actual
Flutter organizer UI because that is the administration used by the product.
English never substitutes Czech interface captures. English publication and
full Webnode verification remain separately gated.

`videos.json` owns localized video references. The Fio guide embeds the verified
public v4 video on our YouTube channel; the earlier upload is private. English
explicitly labels the existing video as Czech. Future English video URLs can be
supplied independently without changing article or topic structure. New video
production remains out of scope.

Source content for `https://vstupenky.online/napoveda/`. `pages.json` owns the
routes and SEO metadata; each route has an authored HTML body. Keep real UI
names and external-platform instructions verified. The Wix-specific guide is
added only after its actual installation flow is qualified.

`render_help_pages.mjs` generates `web/napoveda/` and
`web_client/public/napoveda/` only for the vstupenky.online organizer site.
The build ships the same static HTML, hashed assets and plugin download.
Cloudflare binds each guide to its generated CSP profile and includes it in the
sitemap. Help documents/assets are network content, outside the installed app
cache. No checkout is loaded by the HTML code generator.

The downloadable WordPress ZIP is built through its canonical packager and
must match the reviewed digest in `download.json`. When releasing a new plugin
version or receiving directory approval, update this manifest and the factual
installation/status copy in `wordpress.html` together. Do not describe a
pending submission as an installable directory listing. The current ZIP was
submitted 2026-10-24; automated scanning passed, manual review is pending.

Generate a disposable static preview without a server:

```sh
node automation/release/preview_help.mjs
node automation/release/preview_help.mjs --en
```

The preview commands emit complete file:// links with embedded fonts, styles,
scripts and screenshot images under `.private/help-preview/{cs,en}/napoveda/`.
They require no server. The lower-level renderer owns a dedicated output
directory named `napoveda`. Production generation accepts `--built-index` to
include the same account header and theme assets as the homepage.

## Webnode capture status (2026-10-24)

A new free test account/project was created with synthetic content. Credentials
are in the encrypted agent-browser profile `festapp-webnode-help`; project/session
metadata are local-only under `.private/webnode/` (never commit these files).
The project has not been published and no paid service was purchased.

`media.json` records real Czech screenshots, dates, dimensions and accessible
text. The renderer copies their content-addressed files into both help outputs.
The new project's HTML action requires Premium. The package selection page
offered purchases. Official support offers a free trial on request at
https://www.webnode.com/support/free-trial/. A request was submitted from the
account on 2026-10-24; support receipt 2001921 acknowledges it and activation
is still pending as of 2026-10-25. Consequently the HTML paste,
script preservation, automatic height and live published result are still
unverified on Webnode. Do not describe the integration as end-to-end verified
until a suitable Premium test project is available.

## Categories, global search and application links

`categories.json` owns eight localized category landing pages. Stable category and
article IDs are shared by Czech and English; titles, slugs, SEO descriptions and
screenshot references are localized. The hub links to areas, and the sidebar
expands only the current area. Articles and category pages expose canonical
addresses, descriptive metadata, hierarchical breadcrumbs and structured data.
No ranking or rich-result appearance is guaranteed.

The shared documentation toolbar opens global search. `search_index.mjs` extracts
actual article sections at build time, omitting scripts, forms and image captions.
The cached, hashed script combines the localized public index with `search_engine.js`
and `search_ui.js`. No external search provider, model or per-query network call
is used. Ranking combines article titles, authored aliases, headings and body text;
normalization handles diacritics, related word forms and one-character misspellings.
Results link to the relevant section. The same UI works in static file previews.

Guide CTAs use `/events?help=<intent>` rather than a hard-coded occasion ID or
link. The web entry point retains the intent through sign-in and the Flutter
handoff to `/help-action/<intent>`. Event actions ask for an event from
permission-filtered organizer data; `organization` opens the organizer event
workspace, and `bank-accounts` opens organizer banking without an event chooser.
Multiple organizers require an explicit choice. Each organization target reloads
its current server capabilities before routing. Recent context is only a preference. The intent allowlist
contains fixed section paths, and the application boundary reloads permissions.
This mechanism uses the active tenant and locale and is shared with future global
help. English production publication remains explicitly gated.

Fresh application screenshots and reproducible video chapters are recorded in
`docs/development/public-help-walkthrough-2026-10-25.json`. It includes actual
capture timestamps, hashes, exact actions/results and unverified boundaries.
Raw failed attempts and local session logs stay private. Never replace an
unverified outcome with a fabricated screenshot or a successful-sounding caption.

Application actions are authored inline with `{{APP_LINK:forms}}` (or another
allowlisted intent) in the exact step that enters that screen. Labels live in
`ui.json` for both locales; the renderer rejects unknown intents. Links explicitly
open a new tab, preserving the guide beside the administration. There is no
separate generic application-action panel at the bottom of each article.

Mobile captures use `device: "mobile"` in `media.json`. The shared renderer gives
these real portrait screenshots a readable phone-width presentation in either
locale. Capture metadata distinguishes a desktop Chromium mobile viewport from a
physical iPhone or Safari/camera qualification. Keep that distinction in video
scripts. The October 25 follow-up adds nine CS/EN mobile-view images and a ninth
scenario chapter; the additional mobile purchase stops before submitting an order.

The video iframe requires an HTTP(S) parent origin for YouTube client identity.
The file:// export remains useful for the documentation UI, but video playback
needs a web preview; an HTTP preview is justified for this explicit player
request. Do not claim file:// playback or a deployed production check.

Content audit: organizer scanner configuration is separate from door-staff
check-in and recovery. Receiving accounts in existing forms are automatic by
currency and organizer account priority; do not invent a per-form account picker.
Keep QA narration and pixel dimensions in provenance metadata, not captions.

Directory previews: each task page and localized category selects a `preview`
media identity. The renderer uses existing content-addressed assets. Optional
`previewCrop` on the media entry selects the curated detail/upper thumbnail crop
without changing the full screenshot. Keep previews relevant to the article and
its workflow, localized, and decorative within the descriptive guide link.

## Repeatability and capture theme

All Festapp help screenshots use light mode. The canonical scenario catalogue
and repeat procedure are documented in `automation/help_capture/README.md`.
`automation/help_capture/scanner_light.py` regenerates twelve real CS/EN scanner
error/settings screenshots and updates hashes in both provenance registries.
Other catalogue chapters currently have manual replay steps, not an automated
end-to-end runner. Private interaction logs are supplementary evidence.

## Canonical action routing

All CS/EN article `APP_LINK` tokens use `helpActionWebPath` from
`web_client/src/services/help_action_routes.js`. This same pure policy owns web
login return paths and is embedded in the Cloudflare worker at build time.
Legacy `/login?redirect=/help-action/<intent>` links are a thin redirect into
`/events?help=<intent>`; they do not implement another allowlist or login flow.
The signed-in handoff enters `HelpDestination` in Flutter, which owns actual
organizer/event selection and permission checks. It is a platform adapter, not
an alternate public login. A contract test checks both localized action sets,
the shared web allowlist and Flutter destinations for agreement.
