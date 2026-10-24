# vstupenky.online - Wix release preparation

Status: **source kit prepared, not installed or submitted to Wix**. The working
widget is buildable locally; the real Wix SDK/host boundary is not yet tested.
No Wix account, app identifier or billing approval has been invented.

This is a self-managed **Site Widget (Custom Element)** with an editor settings
panel. It loads the existing public checkout and service-owned `/embed.js`.
Orders, prices, reservations, payments and confirmation stay in the canonical
vstupenky.online service. There is no second checkout or Wix customer-data store.

## What is ready

- `src/widget.js` registers `<vstupenky-online-form>` and uses the official
  `@wix/site-window` host API to confirm `Site` view mode before loading checkout.
- `src/element.js` validates the exact service origin and public form path,
  reuses the canonical helper, supports independent widget instances, and keeps
  an existing checkout alive when title or appearance changes.
- `src/settings.html` / `src/settings.js` use `@wix/editor` + `@wix/sdk` to load
  and persist three public properties. Writes are serial and read back before
  the next write, following Wix's documented settings-panel contract.
- Editor and Preview show a placeholder. They do not load a live checkout,
  helper, cookie store or reservation request. Public checkout is tested on a
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
pnpm run release:check
```

The last command deliberately exits 1 with the checked-in inputs: app ID,
hosting, billing approval and real editor receipts are missing. Copy
`release-inputs.example.json` into `.private/release-inputs.json` only when actual
values and evidence are available. Then run:

```sh
pnpm run release:check .private/release-inputs.json
```

Passing that check validates declarations. It is not proof of Wix acceptance,
a remote installation, payment authorization or completed public submission.
`dist/` contains the self-managed `widget.js`, `settings.html`, `settings.js` and
`settings.css`; it is not a Wix App Store ZIP or a registered CLI project.

## Registration and hosting

Read [SETUP.md](SETUP.md) for exact dashboard configuration and test steps.
No registration command is run automatically: the official CLI scaffolder also
registers a remote app and assigns real app/project IDs. An unregistered fake
`wix.config.json` would misrepresent that state, so this kit does not create one.
Self-managed hosting is a documented first-class Wix framework and requires no
invented CLI identity.

The built assets must be published to an approved HTTPS origin before connecting
them in the Wix app dashboard. They are not added to Festapp's production build
or routing by this change. Widget JS needs CORS for the Wix editor's opaque
sandbox origin. A specific public hosting path will be assigned during setup.

Public help: https://vstupenky.online/napoveda/vlozeni-na-web/.
Wix-specific public installation instructions must be written after the real
installation flow has been checked. The current help link is generic.

## Billing and submission

Read [BILLING-APPROVAL.md](BILLING-APPROVAL.md) before registering monetization.
The app is an installer/wrapper for a paid service. Its installation being free
does not make its revenue-sharing basis zero. Do not list it as an entirely
free product while charging usage fees through the connected service.

The review kit is [SUBMISSION.md](SUBMISSION.md). Required gates are reflected
in `release-inputs.example.json`; none is marked as already passed.
