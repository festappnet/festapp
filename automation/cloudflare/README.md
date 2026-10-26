# Cloudflare Pages deployment

Publish one tenant's combined Flutter and JavaScript website with
`automation/deploy_direct.sh`. It builds locally, uploads `build/web` with
Wrangler and checks the custom domain for a coherent release.

For first-time account, DNS, R2 and Worker setup, read
[Cloudflare infrastructure](../../docs/setup/cloudflare.md).
Backend preparation is in [server deployment](../../docs/setup/server_deployment.md).

## Before you start

- Use the selected tenant's release checkout, with validated shared code from
  canonical `main`, its approved overlay and the recorded `baseMainSha`.
- Run the main-owned [tenant drift check](../../docs/architecture/tenant_overlays.md).
  The upload script validates its branch tag, but does not itself enforce a
  clean checkout, ancestry or the drift policy.
- Have Bash, Git, Node.js/npm, Python 3 and the Flutter SDK selected by
  `FLUTTER_VERSION` available. Use FVM on macOS; the builder's SDK download
  fallback is Linux-only. `apply_config.sh` also needs its
  [configuration dependencies](../README.md#configuration-dependencies).
- Provision a scoped Cloudflare token, or an existing Wrangler OAuth session
  for an already configured project/domain. Keep private credentials outside Git.
- Confirm `CLOUDFLARE_PROJECT_NAME`, `DOMAIN`, `WEB_LINK`, `VERSION`, image settings,
  canonical backend activation, legal content and brand inputs for this tenant.

A branch push does not start a production build. The GitHub `Deploy` workflow is
an alternative only when the user explicitly requests that execution path.

## Build and publish

Run from the selected release checkout after completing its validation gates:

```bash
./automation/deploy_direct.sh --env-file /absolute/private/cloudflare.env
```

The env file must contain a simple `CLOUDFLARE_API_TOKEN=value` entry. It is not
sourced as a shell file; other settings are not loaded from it. Supply
`CLOUDFLARE_ACCOUNT_ID` separately when using an account other than the script's
Festapp default.

For a detached release checkout, specify the exact tenant branch:

```bash
./automation/deploy_direct.sh \
  --env-file /absolute/private/cloudflare.env \
  --branch 'prod/<tenant>'
```

Replace `<tenant>` before running. The branch can differ from the Pages project
name. Its tag must match the project's production branch for a production upload.
The token path reconciles that setting before the build.

For an existing project/domain with current public runtime variables:

```bash
./automation/deploy_direct.sh --wrangler-oauth
```

OAuth checks project/domain membership and uploads using the existing setup.
It does not create DNS or refresh the Pages runtime variables. See the
[infrastructure guide](../../docs/setup/cloudflare.md#pages-project-and-dns)
when the backend profile or organization changes.

`--skip-build` uploads the existing `build/web` after its image-service preflight.
Use it only for a verified bundle matching the exact current source and tenant;
the flag does not establish that provenance or rebuild stale assets.

## What happens during a release

1. The token path creates/reconciles the Pages project, production branch,
   public runtime variables and domain. This can change Cloudflare before a
   later build failure.
2. `cloudflare_build.sh` calls `build_web_bundle.sh`: image-service preflight,
   pinned Flutter selection, configuration generation and client-cutover preflight.
3. The shared builder compiles Flutter, optimizes fonts, stamps versions, builds
   the JS client with `pnpm install --frozen-lockfile`, merges assets and renders legal/organizer pages.
4. It generates the PWA app-shell worker and enforces its cache budget.
   The wrapper removes conflicting redirects/headers, emits `_worker.js` and
   verifies the completed bundle.
5. Wrangler uploads the combined directory. `verify_web_deployment.mjs` then
   requires repeated coherent version/asset and legal-page probes on `DOMAIN`.

An uploaded deployment can exist even when the final probe fails. Inspect the
exact deployment and domain responses before retrying; an exit failure does not
prove the upload was rolled back. Application smoke checks and backend activation
verification remain part of the release handoff.

## Routing

`automation/cloudflare_build.sh` generates the Pages `_worker.js`; edit routing
there. Pages Functions are not combined with this advanced-mode Worker.

| Path | Handler |
|---|---|
| `/` | Public JS catalog; the web shell resolves any forced tenant home |
| `/form/<slug>` | JS form with server-rendered SEO metadata |
| Scanner routes | JS scanner with `no-store` and `no-referrer` |
| `/google-auth`, `/app/google-auth` | JS/Flutter OAuth adapters |
| `/auth_bridge`, `/auth_bridge.html` | Auth bridge |
| `/login` | Web client login |
| `/admin`, `/unit` and other Flutter routes | Flutter SPA |
| `/pro-poradatele` | Organizer page on `vstupenky.online`; 404 for other tenants |
| `/sitemap.xml` | Public occasion catalog RPC, with a minimal fallback |
| `/flutter`, `/webclient`, `/organizers-page` | Internal assets redirect to `/`; `?pwa-cache=1` permits app-shell caching |
| Static assets | Pages asset binding |
| Remaining paths | Flutter deep-link fallback |

The build keeps HTML entry assets extensionless to avoid Pages `.html`
redirects. Do not add a global `_redirects` catch-all: it can intercept runtime
assets before the Worker/SPA receives the intended request.

## Private release inputs

Canonical-backend builds also require `FESTAPP_RELEASE_MANIFEST` pointing to
the existing private tenant release manifest. For `festapptickets`, the manual
`local-release-input.yml` workflow can seal the existing GitHub release secret
to a workstation RSA public key (at least 3072 bits). It neither builds nor
deploys. The encrypted artifact expires after one day; keep the decrypted
local input outside the repository with mode 600 and use it for direct builds.
This copies the approved input unchanged, including its recorded canary proof.

Pushing a `prod/*` branch does not start a production build. The GitHub
`Deploy` workflow is a manual fallback and must be explicitly dispatched for
the exact production branch; this prevents intermediate overlay commits from
creating failed build notifications.


## Public client-sync CORS

The canonical browser-origin allowlist for immutable client-sync artifacts in
the `festapp-public` R2 bucket is tracked in
`festapp-public-cors.json`. Apply it after adding or changing a production web
origin:

```sh
pnpm dlx wrangler@4.131.0 r2 bucket cors set festapp-public \
  --file automation/cloudflare/festapp-public-cors.json --force
```

Then use `wrangler r2 bucket cors list festapp-public` and make a browser GET
from the changed origin to an artifact URL returned by its public-sync head.
The bucket policy must cover every active web origin because fresh browser
installs fetch catalog and live artifacts directly from `assets.festapp.net`.
