# vstupenky.online - Wix release preparation

Repository entry point: [all platform integrations](../README.md).

Status 2026-10-25: **app and widget registered, public assets hosted; real Wix
qualification in progress; not submitted to the App Market**.

The owner completed signup/login for `info@festapp.net`. The assigned app ID is
recorded in [wix-app.json](wix-app.json), and the widget extension ID and free
development site are in the [registration receipt](evidence/registration-20261025.json).
The [hosting receipt](evidence/hosting-20261025.json) records exact public asset
hashes and URLs. No paid plan or listing fee has been accepted.

Twelve tests, build and sealed public-asset packaging pass. The actual bundled
entry now initializes the self-managed Site host using the assigned application
ID; its regression test runs the real pinned Wix SDK against a synthetic host
boundary. This does not replace real Wix qualification. The built settings panel
was inspected at 320 px with no horizontal overflow and correctly disables saving
outside the Wix editor. The earlier CAPTCHA attempt is historical account evidence.

This is a self-managed **Site Widget (Custom Element)** with an editor settings
panel. It loads the existing public checkout and service-owned `/embed.js`.
Orders, prices, reservations, payments and confirmation stay in the canonical
vstupenky.online service. There is no second checkout or Wix customer-data store.

## What is ready

- `src/widget.js` registers `<vstupenky-online-form>` and initializes `@wix/site`
  + `@wix/sdk` with the actual app ID before using `@wix/site-window` to confirm
  `Site` view mode. Missing host context fails closed before loading checkout.
- `src/element.js` validates the exact service origin and public form path,
  reuses the canonical helper, supports independent widget instances, and keeps
  an existing checkout alive when title or appearance changes.
- `src/settings.html` / `src/settings.js` use `@wix/editor` + `@wix/sdk` to load
  and persist three public properties. Writes are serial and read back before
  the next write, following Wix's documented settings-panel contract.
- Editor and Preview show a placeholder. They do not load a live checkout,
  helper, cookie store or reservation request. Public checkout must be tested on a
  published **development** site before submission.
- The helper uses light DOM for discovery, shared protocol 1 for height/scroll,
  and an independent source/origin/instance handshake for each iframe.
- A direct public-form link remains available on published widgets when the
  helper is unavailable. Cross-site storage/payment behavior still needs real
  Wix + browser qualification.

## Local commands

Use Node >=24.22.1 and pnpm 11.24.0:

```sh
cd integrations/wix
pnpm install --frozen-lockfile
pnpm test
pnpm run build
pnpm run package
pnpm run release:check
```

The last command deliberately exits 1 with the checked-in example inputs. The
assigned app/extension IDs and hosting are now known; billing approval, verified
zero-fixed-fee terms and real editor receipts remain release requirements. Copy
`release-inputs.example.json` into `.private/release-inputs.json` only when actual
values and evidence are available. Then run:

```sh
pnpm run release:check .private/release-inputs.json
```

Passing that check validates declarations. It is not proof of Wix acceptance,
a remote installation, payment authorization or completed public submission.
`dist/` contains the self-managed `widget.js`, `settings.html`, `settings.js`,
`settings.css`, bundled dependency notices, public-asset `_headers` and a SHA-256
`manifest.json`. `pnpm run package` verifies those hashes before creating the
public-assets-only deployment ZIP in ignored `artifacts/`. It is not a Wix App
Store installer or a registered CLI project.

## Registration and hosting

Read [SETUP.md](SETUP.md) for exact dashboard configuration and test steps.
The app and extension were registered through the Wix dashboard. Build/package
commands do not register anything remotely. `wix-app.json` records the assigned
self-managed identity; it is not a CLI project manifest. Self-managed hosting is
a documented first-class Wix framework and requires no invented CLI identity.

Assets are published at `https://festapp-wix.pages.dev/widget.js` and
`https://festapp-wix.pages.dev/settings`. Pages redirects `settings.html` to the
extensionless URL. The dedicated static project uses the existing Cloudflare
account and free static hosting; no tenant Flutter build, DNS change or paid
subscription is needed. Widget JS has public CORS for the editor's opaque sandbox.

Wix-specific public help: https://festapp-wix.pages.dev/help.
The guide follows the verified Editor/Studio installation and settings flow and
explicitly marks the addon as preparation-only pending qualification/approval.
Widget placeholders and the settings panel link directly to this guide.

## Billing and submission

Read [BILLING-APPROVAL.md](BILLING-APPROVAL.md) before registering monetization.
The owner requires zero fixed publisher registration/listing/retention costs;
sales commissions are acceptable. The release check requires zero upfront and
recurring publisher fee declarations plus actual terms evidence.
The app is an installer/wrapper for a paid service. Its installation being free
does not make its revenue-sharing basis zero. Do not list it as an entirely
free product while charging usage fees through the connected service.

The review kit is [SUBMISSION.md](SUBMISSION.md). Required gates are reflected
in `release-inputs.example.json`; none is marked as already passed.

Real Wix Editor checks now confirm widget insertion, all three saved settings
after a cold browser reopen, and no checkout iframe/helper in Editor or Preview.
See [editor receipt](evidence/editor-20261025.json).

A published Wix Editor development site also passed a synthetic checkout through
the real production client/helper and a guarded disposable backend: one order,
auto height, 320 px layout, validation, visible summary/receipt and exact summary
scroll restoration. [Evidence and limits](evidence/published-checkout-20261025.json).
Production CORS/routing, payment returns, other editors and commercial approval
remain pending; see the [qualification procedure](SETUP.md).

Wix Studio installation, persisted settings and Editor/Preview isolation also
passed. [Studio evidence](evidence/studio-20261025.json) records a live shared
helper contrast defect and its verified repository candidate; the service release
and live contrast recheck remain required. The compact settings panel now has
its own keyboard-accessible scroll area and visible save status.
