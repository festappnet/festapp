# Festapp setup and tenant guide

Festapp is configured from versioned inputs; do not hand-edit generated Dart,
web, Android or iOS configuration. For local development, start with
[local_development.md](local_development.md). For an existing production tenant,
also read [tenant_overlays.md](../architecture/tenant_overlays.md).

## Prerequisites

- Git, Node.js/npm, Python 3, `jq`, Bash and FVM
- the Flutter SDK pinned by `FLUTTER_VERSION` in `automation/project.conf`
- Docker-compatible runtime, Supabase CLI and `psql` for local database work
- platform tooling only when building Android or iOS

```bash
fvm install
fvm flutter pub get
(cd packages/festapp_core && fvm dart pub get)
npm ci --prefix web_client
```

## Configuration

`automation/project.conf` is the public source of truth for application
identity, domains, Supabase public client configuration, feature defaults,
branding and version pins. Apply it with:

```bash
./automation/apply_config.sh
```

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

Build the isolated local database from the checked-in schema baseline:

```bash
./automation/bootstrap_local_db.sh
DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:55432/postgres?sslmode=disable' \
  ./automation/test_all.sh db
```

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

For every tenant, start from a clean main tree, apply that tenant's source/data
overlay, run `automation/apply_config.sh`, then validate with the main-owned
drift checker. Never generate tenant B over tenant A's working tree. Detailed
steps and the checker command are in
[tenant_overlays.md](../architecture/tenant_overlays.md).

## Integrations

- Push notifications use OneSignal. Keep public app IDs in tenant
  configuration and credentials outside Git.
- Outbound SES and the global email queue are documented in [aws_ses.md](aws_ses.md).
- BankSync integration and bank email evidence gates are documented in
  [bank_import.md](bank_import.md).
- Google sign-in uses the [broker operation guide](../operations/auth/google-sign-in.md).
- Participant CSV format is documented in
  [csv_user_import.md](csv_user_import.md).
- Public and private images use the R2 control plane described in
  [image_worker.md](../backend/image_worker.md).

## Running and testing

```bash
fvm flutter run -d chrome
npm run dev --prefix web_client
./automation/test_client.sh
npm test --prefix web_client
```

The broad runner has skips and warning-only lanes documented in Contributing.
For broader validation, use the targeted scopes
`web`, `db`, `flutter`, `integration`, or `automation` while developing, and
follow [CONTRIBUTING.md](../../CONTRIBUTING.md) for the security checklist.

## Server and infrastructure

An existing tenant uses the shared canonical backend. A new host needs its own
runtime, schema/data, secrets, recovery and activation preparation; follow
[server deployment](server_deployment.md). Cloudflare Pages, Workers, R2, DNS
and protected administration are covered by [Cloudflare infrastructure](cloudflare.md).

## Publishing

Web releases use `automation/deploy_direct.sh`, which builds, uploads to
Cloudflare Pages and verifies the configured custom domain. A Git push does not
start a deployment. See the
[Cloudflare deployment guide](../../automation/cloudflare/README.md).

Android publishing uses
[android_play_release.md](../../automation/release/android_play_release.md).
iOS candidate and upload steps are in
[ios_howto.md](../../automation/release/ios_howto.md). Release only the tenant
branch explicitly selected for the current task.
