# Public Czech help

The approved outline is in `docs/plans/help-content-and-localization-2026-10-24.md`.
The implementation shares the homepage header/footer fragments, canonical
organizer CSS and account-header startup. The hub contains all six agreed areas
and twelve Czech task guides, with matching English preview articles and stable
topic IDs. Core guides cover event creation, form publication, ticket prices and
capacity, seating, ticket design/PDF, payments, order delivery and check-in.

New full-app screenshots show event creation, form/pricing setup, sales opening,
ticket settings/editor/PDF and payment prerequisites using a disposable loopback
backend. Seating, public payment instructions, report and native mobile-check-in
images reuse actual synthetic product recordings with explicit provenance.
The native check-in image is labelled separately from the current web controls.
English never substitutes Czech screenshots. English publication and full
Webnode verification remain separately gated; video tutorials are a later phase.

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

`categories.json` owns six localized category landing pages. Stable category and
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

Guide CTAs use `/login?redirect=/help-action/<intent>` rather than a hard-coded
occasion ID or link. The native login flow retains this return target, asks for
an event from permission-filtered organizer data, then enters the normal protected
administration route. Recent context is only a preference. The intent allowlist
contains fixed section paths, and the application boundary reloads permissions.
This mechanism uses the active tenant and locale and is shared with future global
help. English production publication remains explicitly gated.

Fresh application screenshots and reproducible video chapters are recorded in
`docs/development/public-help-walkthrough-2026-10-25.json`. It includes actual
capture timestamps, hashes, exact actions/results and unverified boundaries.
Raw failed attempts and local session logs stay private. Never replace an
unverified outcome with a fabricated screenshot or a successful-sounding caption.
