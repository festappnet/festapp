# Cloudflare Pages Deployment

Universal, conf-driven deploy used by `automation/deploy_direct.sh`. To add a
new project, create a `prod/<name>` branch and set the Pages project in
`automation/project.conf` on that branch:

```ini
CLOUDFLARE_PROJECT_NAME=<exact CF Pages project name>
```

Run `automation/deploy_direct.sh`; it builds locally, uploads through Wrangler,
and verifies the custom domain before reporting success. For an existing
project whose custom domain is already active, `--wrangler-oauth` uses
Wrangler's encrypted credential-store login and first proves that the exact
project contains both its `pages.dev` hostname and configured custom domain.
It cannot create or attach a project/domain; first activation still requires
the scoped API-token path.

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
npx --yes wrangler@4.131.0 r2 bucket cors set festapp-public \
  --file automation/cloudflare/festapp-public-cors.json --force
```

Then use `wrangler r2 bucket cors list festapp-public` and make a browser GET
from the changed origin to an artifact URL returned by its public-sync head.
The bucket policy must cover every active web origin because fresh browser
installs fetch catalog and live artifacts directly from `assets.festapp.net`.

## Cloudflare Pages project setup

Both the manually dispatched `.github/workflows/deploy.yml` fallback and
`automation/deploy_direct.sh` run
`ensure-pages-project.mjs` before upload. The first activation uses a token
carrying Pages Write and Zone DNS Write to
idempotently create a missing Direct Upload project, pin its production
branch, set the three public Worker variables, and attach `DOMAIN` as the
custom hostname. It also creates the exact proxied CNAME from `DOMAIN` to the
project's `pages.dev` origin. An existing conflicting DNS record fails closed;
unrelated variables, records, and domains are retained.

After Cloudflare Pages reports the custom domain `active`, later deploys need
only Pages Write. The active Pages binding is the routing proof, so routine
deploys do not unnecessarily require or exercise zone-wide DNS permissions.

The branch configuration owns:

1. **Project name** in `CLOUDFLARE_PROJECT_NAME`.
2. **Production branch**, resolved from the pushed `prod/<name>` branch.
3. **Production runtime variables**:
   - `SUPABASE_URL`
   - `SUPABASE_ANON_KEY`
   - `ORGANIZATION_ID`
   These are read by `_worker.js` at runtime for the dynamic `/sitemap.xml` and
   the `/form/<slug>` OG inject. Without them the worker falls back to a
   minimal sitemap and uses default meta tags.
   The values come from the legacy profile while
   `BACKEND_ACTIVATION_PHASE=legacy` and from the complete pinned canonical
   profile when the branch advances to `canonical`, so Worker-rendered content
   and both browser clients switch together.
4. **Custom domain** from `DOMAIN` (for example `csmostrava.festapp.net`).
5. **Release credentials**:
   - `CLOUDFLARE_API_TOKEN` — token with `Cloudflare Pages:Edit` and
     `Zone DNS:Edit` for the Festapp account/zone.
   - `CLOUDFLARE_ACCOUNT_ID` (optional; the Festapp account is the default).

## How routing works (`_worker.js`)

`automation/cloudflare_build.sh` generates `build/web/_worker.js`. This single
worker owns all routing. CF Pages Functions (`functions/...`) are NOT deployed
when `_worker.js` is present, so anything route-related lives in the worker.

Three HTML entry-points are renamed to extension-less names during build:

| Source                              | Renamed to (in build/web) | Why                                                   |
|--                                  |--                          |--                                                     |
| Flutter `web/index.html`            | `flutter`                  | CF auto-strips `.html`; extension-less avoids the 308 |
| Web client `web_client/dist/index.html` | `webclient`            | Same                                                  |
| `web_client/public/auth_bridge.html`| `auth_bridge`              | Same; RouterService still posts to `/auth_bridge.html`, worker accepts both spellings |

Worker routes:

| Path                                    | Behavior                                                                                       |
|--                                      |--                                                                                              |
| `/sitemap.xml`                          | RPC `get_available_occasions` -> generated XML; fallback to minimal sitemap on error           |
| `/form/<slug>`                          | Fetches `/webclient`, RPC `get_occasion_seo_data`, rewrites `<title>` + OG/twitter/canonical   |
| `/`                                     | Serves `/webclient` as `text/html`                                                             |
| `/auth_bridge` and `/auth_bridge.html`  | Serves `/auth_bridge` as `text/html`                                                           |
| `/flutter` and `/flutter.html`          | Serves `/flutter` as `text/html`                                                               |
| `/login`, `/admin`, `/transfer` (+sub)  | Serves `/flutter` as `text/html`                                                               |
| Real static asset                       | Passed through (`ASSETS.fetch`)                                                                |
| Anything else                           | Fallback to `/flutter` so the Flutter SPA router can handle deep links (e.g. `/csmostrava2026`) |

Why a worker (instead of `_redirects` + Pages Functions):

* CF Pages applies `_redirects` BEFORE static assets, so a catch-all
  `/* /flutter 200` would hijack `/favicon.ico`, `/web-assets/*`,
  `/main.dart.js`, etc.
* CF strips `.html` from URLs (308) before serving. `/index.html` would 308 to
  `/`, which a `_redirects` rule then sends back to `/flutter` — a loop.
* Pages Functions and `_worker.js` are mutually exclusive, so we cannot mix.

## Build flow (`cloudflare_build.sh`)

1. Install Flutter ${HOME}/flutter if missing (no-op in GitHub Actions, which
   already has Flutter via `subosito/flutter-action`).
2. Run `automation/apply_config.sh` — propagates `project.conf` into Flutter
   `lib/app_config.dart`, web client `app_config.js`, `web/index.html` title /
   `apple-mobile-web-app-title`, CNAME, theme, fonts, version.
3. `flutter build web --release --base-href / --no-web-resources-cdn` so the
   installed PWA always uses its bundled renderer.
4. Rename `build/web/index.html` -> `build/web/flutter`.
5. `npm run build` in `web_client/`, copy `dist/*` over `build/web/`.
6. Rename merged `build/web/index.html` -> `build/web/webclient`.
7. Rename `build/web/auth_bridge.html` -> `build/web/auth_bridge`.
8. Replace Flutter's deprecated worker with the versioned Festapp app-shell
   worker after both frontends have been merged.
9. Remove any `_redirects` / `_headers` shipped from `web_client/public/`.
10. Emit `build/web/_worker.js` (see above).

## Adding a new CF Pages project

1. Branch off main: `git checkout -b prod/<name>`.
2. Edit `automation/project.conf` on that branch:
   ```ini
   CLOUDFLARE_PROJECT_NAME=<name>
   APP_NAME="Display Name"
   APP_TITLE_SHORT="Short"
   DOMAIN=<host>
   SUPABASE_URL=https://<ref>.supabase.co
   SUPABASE_ANON_KEY=...
   ORGANIZATION_ID=<n>
   FORCE_OCCASION_LINK=<slug>
   ...
   ```
3. Export `CLOUDFLARE_API_TOKEN` (or pass `--env-file`) and run
   `./automation/deploy_direct.sh`. From a detached release worktree, pass the
   exact branch explicitly (for example `--branch prod/cavfotofest`); the tool
   never guesses it from a Pages project name such as `clovekavira`.
