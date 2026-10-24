# Public Czech help

The approved outline is in `docs/plans/help-content-and-localization-2026-10-24.md`.
The first implementation slice shares the homepage header/footer fragments,
canonical organizer CSS and account-header initialization. Six Czech guides
and matching English preview articles use stable topic IDs and grouped navigation.
HTML generation and WordPress first-use/block/Custom HTML steps have actual
localized screenshots; Webnode has verified Czech free-plan screenshots only.
The English content is explicitly preview-only until its remaining capture and
content qualification is complete. No Czech screenshot substitutes for English.
The detailed event/form, ticket/seating, payment/order and check-in guides from
the approved outline are still outstanding. Videos remain a later phase.


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
