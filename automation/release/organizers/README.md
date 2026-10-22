# Marketing document and application routing

`render_organizer_page.mjs` owns the static marketing document for the
`vstupenky.online` tenant. Its only public page is `/`; the catalog is `/events`.
The Worker redirects the former `/pro-poradatele` page and root `create=1`/`q`
queries without dropping query parameters. Ordinary campaign queries stay on
marketing. Other tenants retain their existing root and forced occasion routing.

The document remains readable without JavaScript or backend access. The Vite
`src/marketing/landing.js` entry shares pure legacy URL normalization with the
application, and imports the local video and motion managers without importing
application bootstrap. Release rendering resolves its fingerprinted filename
from Vite's manifest. The internal `organizers-page` asset is not a public alias.

The PWA manifest keeps its established `/` start URL. When the marketing document
exists in the bundle, the service worker precaches it as an install-critical
resource and selects it for offline `/`, while `/events` uses the catalog shell.
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
posters, CTA, catalog, references and FAQ remain usable. No browser analytics
are added.

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
