# Isolated form measurement runtime

One Pages project per Unit uses the same advanced-mode `_worker.js`.
Only canonical `https://PROJECT.pages.dev` origins are supported by profile
`gtm-v1`. Projects have separate registrable sites on the Public Suffix List;
sharing a workers.dev account or a parent custom domain is not this isolation.

Build using `pnpm --dir web_client exec node scripts/build_measurement_runtime.mjs --pages`.
The output is `workers/form-measurement/dist`. No deployment is triggered by build.
Configure server-only `ORGANIZATION_ID`, `UNIT_ID`, `FESTAPP_API_URL=https://api.festapp.net`
and secret `SUPABASE_SERVICE_ROLE_KEY` on that Pages project. The scoped SQL
reader verifies form, organization, Unit, stored deployment origin and parent origin.
Never put the service credential into a static configuration file or client.

Protected `analytics.unit_runtime` holds the canonical runtime origin, `gtm-v1` profile,
approved parent/ancestor and collector origins plus revision/operator/reason. Unique
runtime origins prevent Units sharing a Pages cookie site. Administrator
organization/Unit/form switches never authorize changing that deployment policy.
A valid organizer HTTPS privacy policy URL is required alongside the existing platform, organization, Unit and form gates, including host dataLayer transport. Without it, no consent notice, runtime frame or measurement conversion is produced.
No runtime publication or organization activation is part of a local build.

The dedicated runtime intentionally permits inline scripts (including GTM Custom
HTML), as Unit-authored arbitrary JavaScript is its purpose. The application CSP
is unchanged. Runtime CSP still forbids eval and attribute handlers.
The frame permits scripts and its own storage, but no top navigation, popups,
forms, nested frames or workers. CSP explicitly denies worker registration so
third-party code cannot persist a service worker after frame destruction.
Cookies/storage work only when permitted by the browser; no storage-access prompt
or same-origin fallback is installed. Cookie-blocked tags may lose attribution.

The frame loads as soon as an eligible form loads, without waiting for the consent
notice, and runs GTM and Unit scripts. It is removed on policy failure or expiry, an
unsafe context, signed-in staff or disposal, never because of a visitor's choice.
Configuration changes recreate it. No JWTs, order capabilities or raw URLs enter it.
`purchase` and `generate_lead` carry the readable e-mail and phone, so every tag in the
container can read them, and the organizer is responsible for that use and its policy.
Custom JavaScript variables that need unsafe-eval, DOM-scraping checkout tags and
tags needing popups/nested frames are unsupported.

The bootstrap queues Consent Mode before `gtm.js`, as `gtag('consent','default',...)`
and an identical `update`, so containers need no consent template. Without a saved
choice everything is denied. A later choice sends a `consent update` and the event
`festapp_consent_update` to the same frame. The container evaluates consent and the
organizer is responsible for its tag settings. Remove the former Festapp template from
containers that imported it. Each event carries `festapp_consent: {analytics, marketing}`
for Custom HTML tags and Unit scripts, which do not read Consent Mode and otherwise run
before any choice.

## Collector origins

`collector_origins` are exact origins, at most 16, added to `script-src`,
`connect-src` and `img-src`. `https://www.googletagmanager.com` is always allowed.
A missing origin is blocked silently.

| Destination | Origins |
| --- | --- |
| GA4 | `https://region1.google-analytics.com`, `https://region1.analytics.google.com`, `https://www.google-analytics.com` |
| Google Ads conversions, remarketing, enhanced conversions | `https://www.googleadservices.com`, `https://googleads.g.doubleclick.net`, `https://pagead2.googlesyndication.com`, `https://ad.doubleclick.net`, `https://www.google.com`, and the visitors' country domains, for example `https://www.google.cz`, `https://www.google.sk` |
| Meta Pixel | `https://connect.facebook.net`, `https://www.facebook.com` |

With the Ads and Meta origins, real tag libraries with invalid IDs ran under this CSP
without a violation. That run covers requests, not responses of a live account.

These stay blocked by design and collector origins cannot change that:

- Anything loaded in an iframe (`frame-src 'none'`): Google's `www.googletagmanager.com`
  frame, including its service worker helper for enhanced conversions and user data
  beacons, Protected Audience remarketing frames, Floodlight custom scripts and
  Meta's iframe form fallback for oversized events (`form-action 'none'` too).
- Service workers (`worker-src 'none'`), styles and fonts, and `eval`, which GTM
  Custom JavaScript variables need.
- A country domain that is not listed loses only that remarketing request.

Tags read the frame's own URL, which contains only `form` and `parent`. Google Ads
and Meta therefore report the `pages.dev` address and do not pick up `gclid` or
`fbclid` on their own, although dataLayer has them. Register `PROJECT.pages.dev`
where the platform restricts domains.

For nested embeds the stored ancestor list must include both the immediate app
origin and each approved external host origin; CSP checks every ancestor.

Before any separately authorized production activation, inspect the exact
organization/Unit/forms whose saved switches are already true. Apply the DB
migration first, provision the Unit runtime with a unique project origin, verify
its profile/config/consent matrix, then record the deployment and platform
permission with revision, operator and reason. No bulk tenant rollout is implied.

See the [form measurement integration guide](../../docs/integrations/form-datalayer.md)
for GA4 cookie flags, collector origins, event mapping and verification limits.
