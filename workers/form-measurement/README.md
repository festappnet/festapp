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
No runtime publication or organization activation is part of a local build.

The dedicated runtime intentionally permits inline scripts (including GTM Custom
HTML), as Unit-authored arbitrary JavaScript is its purpose. The application CSP
is unchanged. Runtime CSP still forbids eval and attribute handlers.
The frame permits scripts and its own storage, but no top navigation, popups,
forms, nested frames or workers. CSP explicitly denies worker registration so
third-party code cannot persist a service worker after frame destruction.
Cookies/storage work only when permitted by the browser; no storage-access prompt
or same-origin fallback is installed. Cookie-blocked tags may lose attribution.

GTM containers using this profile must include the supplied consent-initialization
template (analytics granted, Ads denied) on Consent Initialization - All Pages.
The complete frame loads only after a saved analytics grant and is removed on
revoke, visibility/lifecycle invalidation, policy failure or expiry. Configuration
changes recreate it. No contacts, JWTs, order capabilities or raw URLs enter it.
Custom JavaScript variables that need unsafe-eval, DOM-scraping checkout tags,
Ads/enhanced conversions and tags needing popups/nested frames are unsupported.

Import [the exported Consent Initialization template](gtm/festapp-test-consent-defaults.tpl)
into the Unit container and trigger it on Consent Initialization - All Pages.
It was tested against Google template API readback in the nonproduction workspace.
The export contains no Preview authentication credential.

For nested embeds the stored ancestor list must include both the immediate app
origin and each approved external host origin; CSP checks every ancestor.

Before any separately authorized production activation, inspect the exact
organization/Unit/forms whose saved switches are already true. Apply the DB
migration first, provision the Unit runtime with a unique project origin, verify
its profile/config/consent matrix, then record the deployment and platform
permission with revision, operator and reason. No bulk tenant rollout is implied.

See the [form measurement integration guide](../../docs/integrations/form-datalayer.md)
for GA4 cookie flags, collector origins, event mapping and verification limits.
