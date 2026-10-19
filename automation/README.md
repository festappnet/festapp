# Automation & Scripts

This directory contains the central automation logic for the Festapp project. It
is the command center for configuration management, deployment, testing, and AI
integration.

## Configuration dependencies

Run scripts from the repository root unless a guide says otherwise.
`apply_config.sh` needs Bash, Node.js, Python 3, `jq` and the usual Unix text/file
tools. The font generator also needs the tenant's configured font sources.
Flutter builds need FVM/the pinned SDK; JS builds use the locked npm dependencies.
Docker, Supabase CLI and `psql` are needed for the isolated local database, not
for a Pages-only release. The backend host has its own
[server requirements](../docs/setup/server_deployment.md).

## Central Configuration (`project.conf`)

The `project.conf` file is the **Single Source of Truth** for the project. It
defines:

- Deployment domains.
- Public Supabase client settings and tenant backend activation (no private credentials).
- Theme colors.
- Android/iOS application identity and OneSignal public IDs.
- Brand asset paths and optional installation-generation cutover marker.
- Version numbers.

### Applying Configuration

To propagate changes from `project.conf` to all parts of the app (Flutter, Web,
Scripts), run:

```bash
./automation/apply_config.sh
```

Always start from a clean main template when switching tenants. Production
branches contain only source/data paths listed under
`automation/tenant-overlays/`; generated leaves are recreated by this command.
`automation/check_tenant_branch_drift.sh` must be extracted from the recorded
main SHA and compares generated content byte-for-byte, so a production branch
cannot supply its own allowlist or checker policy.

The public private-input interface is `automation/private-inputs.schema.json`.
It declares names only. Values come from private configuration repository or an approved secret
manager through an explicit build/deploy handoff and are never committed here.

## Flutter web font loading

`build_web_bundle.sh` runs `optimize_web_fonts.mjs` after Flutter compilation
and before version stamping and PWA generation. It removes automatic font
registrations only for known unused dependency families, checking both main
and every deferred JavaScript file for references. Font files and AssetManifest
remain intact; the current application typography and regular Lucide icons
remain registered.

The dynamic Google Fonts registry belongs behind
`lib/components/fonts/form_font_catalog.dart`. Do not add eager `google_fonts`
imports to forms or administration code: that restores roughly 10 MB of code
to the entry bundle. The PWA installer must continue caching every
`main.dart.js_<n>.part.js` atomically for first use offline.

## Web deployment

`automation/deploy_direct.sh` is the canonical production web deployment path.
It reads `CLOUDFLARE_PROJECT_NAME`, `DOMAIN`, and `VERSION` from
`automation/project.conf`, runs the shared build, uploads `build/web` directly
with Wrangler, and verifies that the custom domain repeatedly serves one
coherent release generation.

Git pushes never start a production build. `.github/workflows/deploy.yml` is an
explicitly dispatched fallback for running the same Cloudflare release path on
GitHub-hosted infrastructure.

See `automation/cloudflare/README.md` for the Cloudflare pipeline (worker
routing, build steps, env vars).

## Key Scripts

- **`apply_config.sh`**: Propagates `project.conf` into Flutter, web client,
  `web/index.html` title, CNAME, theme, fonts and version. Portable across
  GNU sed (Linux CI) and BSD sed (macOS dev).
- **`cloudflare_build.sh`**: Shared build script for Cloudflare Pages. Invoked
  by `deploy_direct.sh`. Emits `build/web/_worker.js` (single routing source).
- **`deploy_direct.sh`**: Builds, uploads, and verifies the configured
  Cloudflare Pages production release without a git push.
- **`test_all.sh`**: Broad test wrapper. Executes Web Client, database,
  all client roots (core Dart, VM adapters, Flutter), Deno Edge Function,
  image-worker integration and automation tests.
  Environment-dependent suites are skipped when their required local tools or
  credentials are absent; pass a scope such as `web`, `db`, `flutter`,
  `integration`, or `automation` for a targeted run. Web failures/timeouts and
  image integration failures currently produce warnings without setting a final
  failure status; inspect those lane results or run their commands directly.
  The `db` and `integration` scopes also select Deno tests. The automation scope
  runs its explicit list, not every file in `automation/tests/`.
- **`test_client.sh`**: Complete offline client entrypoint. Runs all three roots,
  validates purity, test registration/classification and semantic inventory, and
  propagates every failure. `core` and `flutter` are explicit partial modes.
- **`benchmark_client.py`**: One full warm-up plus three identical-input warm runs;
  records lane/whole timings, counts, source digest and sampled memory.
- **`bootstrap_local_db.sh`**: Rebuilds the isolated local PostgreSQL test
  instance from the versioned production-compatible schema baseline, records
  the baseline migration cutoff, applies newer forward migrations, and seeds
  test data. It never connects to or changes production.
- **`tests/apply_config.test.sh`**: Smoke test for `apply_config.sh` — runs
  against a fixture `project.conf` and asserts the substitutions land in the
  expected files.
- **`tests/tenant_config_matrix.test.sh`**: Fresh-template, three-tenant
  idempotence and cross-tenant identity test using synthetic public fixtures.
- **`check_tenant_branch_drift.sh`**: Rebuilds the expected tenant tree from a
  recorded main SHA and rejects shared, generated-content and policy drift.
- **`apply_sql.js`**: Low-level SQL helper using `DATABASE_URL`; it does not
  verify production identity and is not a production installer or migration
  workflow. Use the isolated local database for development and the protected
  backend access path for authorized production changes.

The old `sync_db.js` migration applicator and `instanceInstall` UI/Edge installer
were removed. Never install or upgrade a tenant through `supabase db push`, cloud
Function deploy commands, or browser-submitted SQL. Supabase CLI remains a local
development dependency of `bootstrap_local_db.sh`.
