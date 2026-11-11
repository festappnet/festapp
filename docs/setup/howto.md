# Festapp setup and tenant guide

This guide covers a fresh developer checkout, local checks and the preparation
of a branded tenant on Festapp's existing backend. Flutter provides the mobile
app and web administration; `web_client/` provides public forms, checkout and
the browser scanner. They are combined for a production web release.

Festapp is configured from versioned inputs; do not hand-edit generated Dart,
web, Android or iOS configuration. Detailed database instructions are in
[local_development.md](local_development.md); tenant branch rules are in
[tenant_overlays.md](../architecture/tenant_overlays.md). A completely independent
production backend requires the additional work described under Server and
infrastructure below.

## Prerequisites

- Git, Node.js, pnpm, Python 3 (3.11 or newer for the local setup launcher),
  `jq`, Bash and FVM
- the Flutter SDK selected by `.fvmrc`, generated from `FLUTTER_VERSION` in
  `automation/project.conf`
- Docker-compatible runtime, Supabase CLI and `psql` for local database work
- platform tooling only when building Android or iOS
- Deno for Edge Function tests; Chrome/Chromium and the managed test browser
  for browser checks; GitHub CLI (`gh`) with repository access for release gates

Use the runtime requirements recorded in package metadata and
[CONTRIBUTING.md](../../CONTRIBUTING.md), rather than choosing tool versions
independently. Use pnpm for JavaScript packages and preserve their
`pnpm-lock.yaml` and `pnpm-workspace.yaml` files.

## Fresh checkout

```bash
git clone https://github.com/festappnet/festapp.git
cd festapp
git switch main
```

Run the following commands from the repository root:

```bash
fvm install
fvm flutter pub get
(cd packages/festapp_core && fvm dart pub get)
pnpm --dir web_client install --frozen-lockfile
```

Other JavaScript packages, such as Workers, have their own dependency installs;
install them in their package directory when working on that component.
If you change routes or generated JSON models, regenerate them with:

```bash
fvm dart run build_runner build --delete-conflicting-outputs
```

## Configuration

`automation/project.conf` is the public source of truth for application
identity, domains, Supabase public client configuration, feature defaults,
branding and version pins. Apply it with:

```bash
./automation/apply_config.sh
```

If you change `FLUTTER_VERSION`, apply configuration before running `fvm install`
and resolving Dart/Flutter dependencies again.

The command validates required values and generates the corresponding Flutter,
web, Android and iOS leaves. Tenant `FONT_FILES` lists explicit `.ttf`/`.otf`
sources directly under `fonts/`; without it the generator uses the shared
`automation/fonts/` fallback. `FONT_FAMILY_BASE` selects a family name, not the
source files. Brand/font inputs and legal Markdown must be allowed by the
tenant overlay policy.
Never put private credentials in `project.conf`.

Private local values belong in the ignored `.env.local`. Production secrets
come from the approved secret manager or deployment handoff described by
`automation/private-inputs.schema.json` and
`automation/tenant-external-services.schema.json`.

## Database and Edge Functions

Start the Docker-compatible runtime, then prepare the isolated local database
from the checked-in schema baseline and newer forward migrations:

```bash
./automation/bootstrap_local_db.sh
./automation/test_all.sh db
```

The bootstrap prepares or reuses a verified immutable base. Test wrappers acquire
their own disposable database clones; do not hard-code a shared database URL.
`--upgrade` performs a cold full replay, `--status` shows leases/cache state,
and `--stop` stops an unleased runtime. See
[local_development.md](local_development.md) for ownership, cleanup and supported
upgrade details. The `db` test scope also runs Edge Function tests and needs Deno.

This starts PostgreSQL only. Full application flows also need Auth, REST and
the relevant Edge Functions and external services. For the bounded local event
setup flow, the repository provides:

```bash
python3 automation/run_occasion_setup_local.py --enable-wizard
```

It prepares a separate owned Supabase workspace, local test data and Flutter
test entrypoint, then serves the UI at `http://127.0.0.1:56880/unit/1/edit`.
Use the local test login printed by the launcher. Its default workspace is
`../festapp-wizard-local`; stop Flutter before starting another Flutter task.
Stop its backend afterward with
`supabase stop --workdir ../festapp-wizard-local`.
This fixture supports event setup; it does not provision production email,
payment or image services for general end-to-end testing.

Active forward migrations live in `supabase/migrations/`; canonical function
sources live in `database/functions/`. Do not edit an applied migration or use
a browser installer, `supabase db push`, cloud Function deploy commands or
the removed `instance-install` function to install or upgrade the system.
Supabase CLI is used only for isolated local development in this guide.

Production schema, function and contract changes target only the canonical
self-hosted backend at `https://api.festapp.net`. Former cloud sources remain
frozen retention/reconciliation targets after the 2026-09-10 switch; do not
apply routine migrations there.

For a production tenant, require `BACKEND_ACTIVATION_PHASE=canonical` in
its `automation/project.conf` and verify the published
`WEB_LINK/backend-activation.json`: tenant ID, canonical generation and endpoint
must match the selected configuration. Verify
`BACKEND_ACTIVATION_CANONICAL_ORGANIZATION_ID` and any `FORCE_OCCASION_LINK`
in that same canonical database before reading event or user data. Stop on a
mismatch. `SUPABASE_URL` can be a compiled legacy mobile fallback; neither it
nor a project ref in `.env.local` selects the live database. The shared main
configuration is a development template, not evidence of a tenant's activation.

See [AI context](../architecture/ai_context.md) for backend authority and
[edge_functions.md](../backend/edge_functions.md) for authorization, tests and
canonical bundle deployment.

## Tenant creation or upgrade

Shared code is developed on `main`. A `prod/<tenant>` branch may contain only
the paths allowed by `automation/tenant-overlays/<tenant>.paths`, generated
leaves and an `automation/tenant-overlay.json` recording its exact main SHA.

Before publishing shared changes, run targeted checks of the affected behavior.
The canonical local CI mirror is available through `automation/test_ci.sh`;
GitHub owns authoritative full lane verification. After publishing main and
before creating or pushing a tenant overlay, require the exact main commit to
pass the release gate:

```bash
python3 automation/ci/release_gate.py --source-sha <full-main-sha>
```

All canonical GitHub CI jobs must succeed for that commit. Missing, pending,
failed or skipped jobs block release. The rules for verified reuse of unchanged
CI inputs are in [CONTRIBUTING.md](../../CONTRIBUTING.md).

For every tenant, start from a clean main tree, apply that tenant's source/data
overlay, run `automation/apply_config.sh`, then validate with the main-owned
drift checker. Never generate tenant B over tenant A's working tree. Detailed
steps and the checker command are in
[tenant_overlays.md](../architecture/tenant_overlays.md).

For a new tenant, prepare these inputs before attempting a release:

1. Select a unique tenant ID and add its narrow source/data allowlist on `main`.
   Prepare its public `project.conf`, brand/font assets and legal/support
   Markdown. An existing tenant's generated files are not a new tenant template.
2. Provision the intended organization/unit ownership and initial administrator
   through an authorized backend operation. Record the real IDs in the tenant
   configuration; a Git branch or `ORGANIZATION_ID` setting does not create data
   or grant permissions.
3. Provision the tenant's private service inputs, image access, domains and
   activation profile. Use the integration and infrastructure guides below.
4. Create the overlay over the verified main commit, record `baseMainSha`, apply
   configuration and pass the main-owned drift checker before publication.
5. Release only that tenant, then verify its activation, administrator sign-in,
   legal pages and the enabled public event/form journeys.

There is no generic command in this guide that provisions all tenant data and
services. Obtain the approved private inputs and backend provisioning handoff
before step 2; frontend configuration alone is insufficient.

## Integrations

- Push notifications use OneSignal. Keep public app IDs in tenant
  configuration and credentials outside Git.
- Outbound SES and the global email queue are documented in [aws_ses.md](aws_ses.md).
- BankSync integration and bank email evidence gates are documented in
  [bank_import.md](bank_import.md).
- Payment-provider ownership and credential configuration are described in
  [payment providers](../architecture/payment-providers.md). The separate
  [Barion sandbox probe](../../automation/payments/README.md) is an operator
  diagnostic, not a production provider installer.
- Google sign-in uses the [broker operation guide](../operations/auth/google-sign-in.md).
- Participant CSV format is documented in
  [csv_user_import.md](csv_user_import.md).
- Public and private images use the R2 control plane described in
  [image_worker.md](../backend/image_worker.md).

## Running and testing

Development servers use the generated application configuration. Verify the
selected backend before signing in or modifying data; starting a local frontend
does not switch it to a local backend. Run the servers separately as needed,
and allow only one Flutter task on the workstation at a time.

```bash
fvm flutter run -d chrome
pnpm --dir web_client run dev
```

Stop the Flutter development server before running the client suite:

```bash
./automation/test_client.sh
./automation/test_all.sh web
```

The wrapper acquires an owned disposable database when no explicit
`DATABASE_URL` is supplied and never loads a production environment file.
For a direct web test command that needs a database, use the same workspace owner:

```bash
python3 automation/local_db/runtime.py exec -- pnpm --dir web_client test
```

Required prerequisites fail closed; some individual runners retain optional
skips. For broader validation, use the targeted scopes
`web`, `db`, `flutter`, `integration`, or `automation` while developing, and
follow [CONTRIBUTING.md](../../CONTRIBUTING.md) for each lane's additional
dependencies, canonical CI checks and security checklist.

For canonical browser lanes, install the declared managed browser after the
frozen web-client dependency install:

```bash
pnpm --dir web_client exec playwright install --only-shell chromium
python3 automation/ci/run.py list
```

Use `./automation/test_ci.sh <job-name>` for the relevant canonical lane, or omit
the job name for all lanes. Install the additional prerequisites from Contributing
before running them. These checks do not deploy the application.

## Server and infrastructure

An existing tenant uses the shared canonical backend. A new host needs its own
runtime, schema/data, secrets, recovery and activation preparation; follow
[server deployment](server_deployment.md). The host tooling includes historical
migration-specific identity and evidence gates; it is not a portable one-command
installer for an independent production backend. Cloudflare Pages, Workers, R2, DNS
and protected administration are covered by [Cloudflare infrastructure](cloudflare.md).

## Publishing

Web releases use `automation/deploy_direct.sh`, which builds, uploads to
Cloudflare Pages and verifies the configured custom domain. It checks the
exact-source CI release gate before building and immediately before upload.
`--skip-build` still requires that gate and a valid build receipt matching the
current source inputs and output files. A Git push does not start a deployment.
Build locally and deploy directly; the GitHub Deploy workflow requires an
explicit request. See the
[Cloudflare deployment guide](../../automation/cloudflare/README.md).

After its prerequisites and tenant drift checks pass, run from the selected
tenant's release checkout, with a scoped token stored outside Git:

```bash
./automation/deploy_direct.sh --env-file /absolute/private/cloudflare.env
```

The private file supplies `CLOUDFLARE_API_TOKEN`; account selection and existing
Wrangler OAuth usage are covered in the deployment guide. Keep the private
`FESTAPP_RELEASE_MANIFEST` available when required by the release preflights.
Retain the exact source/tenant revisions and verification results. If upload
succeeds but live verification fails, inspect that deployment before retrying;
a failed final check does not roll the upload back.

Android publishing uses
[android_play_release.md](../../automation/release/android_play_release.md).
Its canonical candidate builds and Google Play operations run through the
documented GitHub-hosted workflows and require the exact private release manifest.
iOS candidate and upload steps are in
[ios_howto.md](../../automation/release/ios_howto.md). Release only the tenant
branch explicitly selected for the current task.
