# Festapp & vstupenky.online

This project powers **[vstupenky.online](https://vstupenky.online)**, an event
registration and ticketing service, and **[Festapp](https://festapp.net)**,
an attendee app for festivals, conferences and community events.

With vstupenky.online, organizers publish registration forms, sell tickets,
offer seat selection, track orders and bank payments, and check tickets at the
door. Attendees register or buy tickets through the website and receive their
PDF tickets by email.

Festapp extends the experience during the event with schedules, personal
programs, maps, news and event information on Android, iOS and the web.
[Open the event app](https://live.festapp.net).

Both services share this codebase and backend. An event can use registration
and ticketing on their own or combine them with the attendee app.

![Festapp app screens](repo-data/festapp-showcase.png?raw=true)

## From registration to the event

Organizers can create registration forms, offer products and seats, match bank
payments, customize PDF tickets and emails, and scan tickets at entry. Event
administration also covers workshops, volunteer shifts, participant groups,
accommodation and reception.

Attendees can browse the schedule, build a personal program, view maps and read
updates. Previously synchronized event data remains readable offline; available
content depends on the device's cache. Native offline maps use a prepared map
bundle.

Features are selected for each event. Branded applications and websites share
the platform while using their own identity and configuration.
See [features and screenshots](docs/overview/features.md) for a closer look.

## Working on the project

This repository contains the Flutter app, the JavaScript client for public
forms, checkout and browser scanning, and the backend and deployment tooling.
Business rules and permissions live in PostgreSQL RPCs. Supabase provides Auth,
Storage and Deno Edge Functions; Cloudflare hosts the web clients and the image
and sync services.

Start with [developer setup](docs/setup/howto.md) for dependencies and
configuration, then use [the local database guide](docs/setup/local_development.md)
for an isolated backend. [Contributing](CONTRIBUTING.md) explains how to change
code and run the relevant checks.

For a particular task, use the [documentation index](docs/README.md).
[Architecture context](docs/architecture/ai_context.md) explains the shared
contracts, backend ownership and repository conventions.

Festapp began in 2023 with volunteers building an app for
[Absolventský Velehrad](https://absolventskyvelehrad.cz).
Development history is in [CHANGELOG.md](CHANGELOG.md); updates are shared in
the [Czech WhatsApp channel](https://whatsapp.com/channel/0029Vb64lj91CYoUWARKf80R).

## JavaScript dependencies

Use pnpm 11.24.0, matching the Mendelio workspace. Run `pnpm install --frozen-lockfile` in the directory containing the relevant `package.json`, then `pnpm run <script>`. Each package keeps its own `pnpm-lock.yaml`; pnpm shares package content through the user store across repositories and worktrees. Keep the local virtual store enabled for compatibility with direct Node scripts and container builds. Do not use npm installs or commit npm lockfiles. Approved native build scripts are declared in each `pnpm-workspace.yaml`.
