# Festapp

Festapp is an event platform for festivals, conferences and community events.
Organizers manage registration, tickets, payments and staffing; attendees use
schedules, maps, news and their personal program on Android, iOS and the web.

It also powers [vstupenky.online](https://vstupenky.online), the ticketing and
registration service. Try the event app at [live.festapp.net](https://live.festapp.net)
or visit [festapp.net](https://festapp.net).

![Festapp app screens](repo-data/festapp-showcase.png?raw=true)

## What it does

- Event schedules, workshops, maps, news, songbooks and group games
- Registration forms, seat selection, ticket PDFs and QR scanning
- Order administration, bank payment matching and email communication
- Volunteer shifts, participant groups, accommodation and reception
- Tenant branding and feature settings for each occasion

Previously synchronized data can be read offline. Authentication, payments and
server-confirmed writes need a connection; native offline maps require a prepared
map bundle. See [features and screenshots](docs/overview/features.md) for more.

## Start here

| I want to... | Read |
|---|---|
| Develop the app locally | [Developer and tenant setup](docs/setup/howto.md) |
| Run an isolated test database | [Local database development](docs/setup/local_development.md) |
| Prepare a backend server | [Server deployment](docs/setup/server_deployment.md) |
| Publish a tenant web release | [Cloudflare deployment](automation/cloudflare/README.md) |
| Configure Cloudflare services | [Cloudflare infrastructure](docs/setup/cloudflare.md) |
| Build or publish mobile apps | [Android](automation/release/android_play_release.md), [iOS](automation/release/ios_howto.md) |
| Change code and run checks | [Contributing](CONTRIBUTING.md) |

## How it fits together

Flutter handles the mobile app and web administration. A separate vanilla
JavaScript client handles public forms, checkout and the browser scanner.
PostgreSQL RPCs own business rules and permissions. Deno Edge Functions connect
those commands to email, ticket generation and external services.

Production uses self-hosted Supabase at `https://api.festapp.net`. Cloudflare
Pages hosts the combined web bundle; Workers and R2 provide image and sync
services. Server setup, application configuration and web publication are
separate steps.

| Path | Contents |
|---|---|
| `lib/` | Flutter application and feature modules |
| `packages/festapp_core/` | Portable Dart domain and sync contracts |
| `web_client/` | Public JavaScript client |
| `database/` | Canonical SQL functions, schema sources and tests |
| `supabase/` | Local baseline, forward migrations and Deno functions |
| `workers/` | Cloudflare image, sync and monitoring services |
| `automation/` | Configuration, builds, deployments and backend operations |
| `docs/` | Setup guides, architecture, runbooks and historical records |

Shared code lives on `main`. Production branches carry approved tenant overlays.
`automation/project.conf` supplies public configuration; `apply_config.sh`
generates the corresponding app and platform files. Private credentials stay
outside Git and browser assets. A tenant's activation document identifies its
live backend, organization and generation.

For details, use the [documentation map](docs/README.md),
[architecture context](docs/architecture/ai_context.md) and
[tenant overlay policy](docs/architecture/tenant_overlays.md).

## Local development

Install Git, Node.js/npm and FVM. Use the Flutter version specified by
`FLUTTER_VERSION` in `automation/project.conf`. From the repository root:

```bash
fvm install
fvm flutter pub get
(cd packages/festapp_core && fvm dart pub get)
pnpm --dir web_client install --frozen-lockfile
```

Complete the [configuration and backend setup](docs/setup/howto.md) before
running against event data. Then choose a frontend:

```bash
fvm flutter run -d chrome
# Or, in another terminal:
pnpm --dir web_client run dev
```

For client checks, run `./automation/test_client.sh`. JavaScript checks use
`pnpm --dir web_client test`; SQL tests require the isolated local database.
The wider `test_all.sh` wrapper has environment-dependent skips and warning-only
lanes, so its exit status alone is not an all-suite pass. The exact commands and
limits are in [Contributing](CONTRIBUTING.md#1-testing-workflow).

## Project history

Festapp began with volunteers building an app for
[Absolventský Velehrad](https://absolventskyvelehrad.cz) in 2023.
[CHANGELOG.md](CHANGELOG.md) records development history. Updates are also
shared in the [Czech WhatsApp channel](https://whatsapp.com/channel/0029Vb64lj91CYoUWARKf80R).

## JavaScript dependencies

Use pnpm 11.24.0, matching the Mendelio workspace. Run `pnpm install --frozen-lockfile` in the directory containing the relevant `package.json`, then `pnpm run <script>`. Each package keeps its own `pnpm-lock.yaml`; pnpm shares package content through the user store across repositories and worktrees. Keep the local virtual store enabled for compatibility with direct Node scripts and container builds. Do not use npm installs or commit npm lockfiles. Approved native build scripts are declared in each `pnpm-workspace.yaml`.
