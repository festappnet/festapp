# Global MCP metadata readiness - 2026-11-13

> Historical preparation snapshot. Current production and directory status is recorded in [live-verification.md](live-verification.md).

Read-only research. No registry submission or change to public material was made. Live endpoint and client authorization remain separate release gates.

## Publisher and support

- [Festapp Tickets terms](https://tickets.festapp.net/terms/) identify the system provider as Michael Bujnovský, registration number 06455361, Přívozská 1704/24, Moravská Ostrava, 702 00 Ostrava, Czech Republic. [Czech terms](https://vstupenky.online/terms/) identify the same provider for Festapp and Vstupenky.online. Use Festapp as brand/publisher display and the identified individual as legal operator; do not invent a company.
- [Global support](https://tickets.festapp.net/support/) and [regional support](https://vstupenky.online/support/) give `info@festapp.net` for technical support. The [regional landing page](https://vstupenky.online/) also gives `info@vstupenky.online` for sales/contact. [Festapp.net](https://festapp.net/) provides `info@festapp.net`.

## Legal, documentation, pricing

- [Global Tickets privacy](https://tickets.festapp.net/privacy/) and [regional privacy](https://vstupenky.online/privacy/) describe the account, organizer responsibilities and optional **ChatGPT** connection with a restricted read-only profile. Neither inspected page explicitly describes a general third-party MCP client ecosystem or broader write profiles. The existing general [global Tickets terms](https://tickets.festapp.net/terms/) and [regional system terms](https://vstupenky.online/terms/) do not explicitly name those MCP flows either. Their applicability and adequacy for a broader global connector cannot be inferred solely from their existence; obtain accurate published disclosures for the actual profiles before representing those pages as MCP-specific. Global Tickets pages should not be assumed to govern every independently configured Festapp tenant.
- [Global organizer help](https://tickets.festapp.net/help/) and [website integration guide](https://tickets.festapp.net/help/integrations/) are live, but the latter concerns embedded sales forms, not MCP setup. The [public repository](https://github.com/festappnet/festapp) is accessible. No public general MCP setup guide was verified.
- [Festapp Tickets](https://tickets.festapp.net/) says service pricing is agreed per event; card payments are by arrangement. [vstupenky.online](https://vstupenky.online/) says an account is needed to create an event, creation is free, QR transfers have zero transaction fee, and service price is agreed separately. These are not evidence that organizer service, all accounts, or MCP use is universally free or of a specific MCP quota. Use account/service pricing as agreed and avoid inventing a free tier or limit.

## Logo assets

- [vstupenky.online media page](https://vstupenky.online/pro-media) offers an official downloadable logo ZIP. The currently accessible regional wordmark is [brand-logo.svg](https://vstupenky.online/brand-logo.svg). The repository's `integrations/chatgpt/README.md` calls `integrations/chatgpt/assets/logo.png` and `logo-dark.png` canonical square listing logos for the regional connector.
- [Festapp Tickets wordmark](https://tickets.festapp.net/brand-logo.svg) is live; the repository has `assets/icons/fstapplogo.svg` and `assets/brand/festapp-tickets/festapp-tickets-logos.zip`. These establish existing brand resources, not a verified compliant square logo for a particular directory; check each directory's format requirements before upload.

## Official registry schema

`integrations/mcp-directories/festapp.server.json` and `vstupenky-online.server.json` each passed Ajv 8.20.0 with ajv-formats 3.0.1 against the official [2025-12-11 Draft-07 server schema](https://static.modelcontextprotocol.io/schemas/2025-12-11/server.schema.json), fetched 2026-11-13 (SHA-256 `3fba09590c99f61735d234822279f4223fab9e300c0a81e81c91ab62a4114de0`). This checks the schema, including URI formats; it does not establish ownership of `net.festapp`, remote availability, OAuth compatibility, or publication acceptance. Both files use the same Festapp-owned namespace and point to separate remote URLs. No live endpoint verification is implied.
