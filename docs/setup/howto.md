# Festapp setup and tenant guide

Festapp is configured from versioned inputs; do not hand-edit generated Dart,
web, Android or iOS configuration. For local development, start with
[local_development.md](local_development.md). For an existing production tenant,
also read [tenant_overlays.md](../architecture/tenant_overlays.md).

## Prerequisites

- Git, Node.js/npm and FVM
- the Flutter SDK pinned by `FLUTTER_VERSION` in `automation/project.conf`
- Docker-compatible runtime and Supabase CLI for local database work
- platform tooling only when building Android or iOS

```bash
fvm install
fvm flutter pub get
npm install --prefix web_client
```

## Configuration

`automation/project.conf` is the public source of truth for application
identity, domains, Supabase public client configuration, feature defaults,
branding and version pins. Apply it with:

```bash
./automation/apply_config.sh
```

The command validates required values and generates the corresponding Flutter,
web, Android and iOS leaves. Fonts come from `automation/fonts/`; tenant-owned
brand assets and legal Markdown must be listed by the tenant overlay policy.
Never put private credentials in `project.conf`.

Private local values belong in the ignored `.env.local`. Production secrets
come from the approved secret manager or deployment handoff described by
`automation/private-inputs.schema.json` and
`automation/tenant-external-services.schema.json`.

## Database and Edge Functions

Build the isolated local database from the checked-in schema baseline:

```bash
./automation/bootstrap_local_db.sh
./automation/test_all.sh db
```

Active forward migrations live in `supabase/migrations/`; canonical function
sources live in `database/functions/`. Do not edit an applied migration or use
the operator-only `instance-install` function as a production deployment path.

Until the self-hosted cutover is complete, every schema, function and data
contract change must be applied and verified on the self-hosted target and both
cloud sources (`default` and `a`). Resolve a live target from `SUPABASE_URL` in
the selected tenant's `automation/project.conf`, never from a project ref in
`.env.local`. See [edge_functions.md](../backend/edge_functions.md) for function
authorization, tests and deployment constraints.

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
- SMTP setup is documented in [aws_ses.md](aws_ses.md).
- Bank import setup is documented in [bank_import.md](bank_import.md).
- Participant CSV format is documented in
  [csv_user_import.md](csv_user_import.md).
- Public and private images use the R2 control plane described in
  [image_worker.md](../backend/image_worker.md).

## Running and testing

```bash
fvm flutter run -d chrome
npm run dev --prefix web_client
./automation/test_all.sh
```

The full runner reports environment-dependent skips. Use the targeted scopes
`web`, `db`, `flutter`, `integration`, or `automation` while developing, and
follow [CONTRIBUTING.md](../../CONTRIBUTING.md) for the security checklist.

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
