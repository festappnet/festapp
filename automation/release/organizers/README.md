# Marketing document and application routing

`render_organizer_page.mjs` owns the static marketing document for the
`vstupenky.online` tenant. Its public documents are `/` and the configured topic paths; the catalog is `/events`.
The Worker redirects the former `/pro-poradatele` page and root `create=1`/`q`
queries without dropping query parameters. Ordinary campaign queries stay on
marketing. Other tenants retain their existing root and forced occasion routing.

The document remains readable without JavaScript or backend access. The Vite
`src/marketing/landing.js` entry shares pure legacy URL normalization with the
application, and imports the local video and motion managers without importing
application bootstrap. Release rendering resolves its fingerprinted filename
from Vite's manifest. The internal `organizers-page` asset is not a public alias.

The PWA manifest keeps its established `/` start URL. When the marketing document
exists in the bundle, the service worker keeps marketing network-only;
`/events` uses the installed catalog shell.
Existing release-version cache retirement remains authoritative. MP4/WebM files
are excluded from both critical and general precache; posters remain available.
Publish the Worker, document, assets and service worker as one version.

Validation: routing and metadata use `automation/tests/public_seo.test.mjs`,
rendering uses `automation/tests/organizer_page.test.mjs`, and offline resource
selection uses `automation/tests/pwa_manifest.test.mjs` plus
`automation/tests/pwa_offline.test.mjs`. These describe local contracts, not
production deployment evidence.

Content is explicitly projected from `content.json.publicProjection`; research
notes and availability observations are never serialized into the document.
`clips.json` owns the eight feature clips, their desktop/mobile exports and
posters. Only web exports live in `web/organizers-media`; capture masters and
comparison assets remain outside Git. The static hero combines two clearly
labelled real product views; feature clips supply the interactive evidence.

The player assigns a video source only when playback is requested. It starts
one settled, visible clip, preserves deliberate pauses and completion, and
requires a manual start for reduced motion or Save-Data. Failed media keeps
its poster and offers retry/download. With JavaScript disabled the document,
posters, CTA, catalog, references and FAQ remain usable. Cloudflare Web Analytics is owned by public Pages responses,
not the shared app shell. See [public web analytics](../../../docs/operations/public-web-analytics.md).

Media provenance, checks and local-only limitations are recorded in
`docs/plans/vstupenky-landing-evidence-2026-10-22/`. The order overview shows
actual ticket-table export; the application has no order-table export control.
The editor/picker demonstration has synthetic prices and is not a payment or
reservation proof.

The marketing palette is independent of application theme colors. References
are dated public event cards with original cover images; source URLs and the
verification date live in the public content projection. Review that curated
selection before a later release. Mobile cards stay in one horizontally
scrollable row. Motion stages heading, product and caption, and keyboard focus
always reveals its containing section.

## Search metadata

`content.json.publicProjection.seo` owns the organizer title, description and
social image, plus distinct catalog title/description. The marketing generator
emits absolute apex canonical/social URLs and linked WebSite, WebPage, Service
and the actual sole-trader Person in JSON-LD. It does not invent ratings, free
service pricing, FAQ enhancements, Event data or video-rich-result eligibility.
JSON-LD serialization escapes `<` to keep content inside its script boundary.
The catalog shell keeps its canonical `/events` and the shared WebSite identity;
it no longer advertises the retired sitelinks search-box action.

The live router already owns the dynamic canonical sitemap. The static fallback
also includes `/events` only for this tenant. Other tenant metadata continues to
come from apply_config; a WebSite without optional SearchAction is valid.

Regenerate the actual 1200x630 sharing PNG with
`python3 automation/landing_capture/review/build_social_card.py --output <owned-directory>`.
It uses repository-native vector hall geometry and existing local Futura fonts,
not an external design service. `build_seo_preview.py` creates a server-free
comparison of three proposed snippets at desktop/mobile widths. These previews
are not a guarantee of what Google will display. Publish and then validate the
real URLs/Search Console before reporting any indexing or ranking result.


## Search growth pages

`context.mjs` validates the explicit content profile and locale; `page_definitions.mjs`
provides stable document IDs/assets. The resolved `organizer-pages.json` drives
rendering, Worker routing, static/dynamic sitemaps, CSP and PWA navigation. Czech
profile `vstupenky-cs` adds the ball-sales and seating-reservation pages. Existing
shared header/footer, account controls, help, analytics and immutable application
cache remain owned by their current implementations. Marketing documents and
media stay outside the installed app cache; topics return the standard offline
error rather than an unrelated Flutter/catalogue shell. This preserves the newer
production streaming fix introduced after the original search-growth plan.

`festapp-en` retains the existing English content/media and recording gate with
explicit profile selection; no English tenant is activated. A synthetic EN fixture
proves an optional topic and empty reference behavior. Missing profile, locale,
media, duplicate/reserved paths or required text fail before accepting documents.
References are dated examples, while `/events` owns current listings.

Search Console coverage/crawl/canonical/performance remain unknown without a
read-only console session or private export. Keep source exports private and use
the latest complete 28 days, CZ/Web and separate mobile/desktop. Measure brand,
generic `vstupenky online` and organizer topics separately. Record D0 at actual
release, then compare D7/D14/D28 with the same filters; a CTA click is not a
completed organizer signup. No new analytics service or schedule is introduced.

The account header initializes the existing localization service with the
rendered document locale and `persist: false`. Browser language or the saved
application preference cannot retag a Czech marketing document as English;
ordinary application startup still uses the saved preference.

## Organizer guide and seating feature

The ball-sales URL is a practical seven-chapter organizer guide, with linked
application help and a printable pre-sale checklist. Checklist state stays in
the current document; it does not create orders or store personal data. Print
styles isolate the checklist. The seating URL explains the feature with real
layout templates and existing editor/buyer clips. Native radio inputs select
examples; without JavaScript all examples remain readable. Both compositions
reuse the original typography, palette and vector ticket/hall geometry.

`topic_pages.mjs` owns these distinct compositions, while shared chrome and
application help retain their existing owners. `topic_tools.js` only enhances
the checklist and examples. The homepage remains the service overview.
