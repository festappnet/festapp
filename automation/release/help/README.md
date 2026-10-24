# Public Czech help

This is the first content/UI prototype. The next scope decision is documented
in `docs/plans/help-content-and-localization-2026-10-24.md`: integrations first,
task-oriented basics, actual localized screenshots, a shared CZ/EN content
model, and the same public header/footer/buttons as the main website. The
current simplified help header/footer are not the final agreed site shell.
Videos are a later phase. Confirm the outline before expanding the articles.

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
node automation/release/render_help_pages.mjs --output /tmp/help-preview/napoveda
```

The output must be a dedicated directory named `napoveda`; the renderer owns
and recreates that directory. Site-root URLs in this production-shaped output
need conversion to local file URLs for browsing directly from disk.
