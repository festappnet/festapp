# vstupenky.online - Wix release preparation

Current continuation: [Partner Billed execution prompt](../../docs/plans/wix-partner-billing-EXECUTION-PROMPT-2026-10-28.md)
and [authoritative plan](../../docs/plans/wix-partner-billing-plan-2026-10-28.md).

Repository entry point: [all platform integrations](../README.md).

The current objective is the native App Market listing, with installation and
the widget settings panel. See [the current portal receipt](evidence/portal-20261028.json)
for progress following Wix's Partner Billed App reply. A generic iframe embed
does not satisfy this objective.

Current release state is recorded in the [execution result](../../docs/plans/wix-partner-billing-RESULT-2026-10-28.md)
and [production receipt](../../docs/operations/releases/festapptickets-wix-foundation-2026-10-28.json).
The canonical origin, service-fee source and delivery journal are deployed, and
`prod/festapptickets` serves `0.20.444+949`. A real Wix SDK token passed the
production CORS/issuer flow, and SQL validated the returned signature. No order,
hold, fee receipt or billing event was created by that read-only probe.

Wix hosting still serves the previous widget assets. The last authenticated
native receipt records unlisted version 1.1 and a DYNAMIC Custom pricing draft;
marketplace publication and Partner Billed activation have not been verified.
The service-fee-only revenue basis, exclusion of organizer proceeds, external
checkout and zero separate fixed publisher fees are already confirmed by Wix.
Do not reopen those resolved questions or treat them as executed terms.

The existing DocuSign request contains Michael Bujnovský's saved sole-trader
identity, IČO 06455361 and registered office. It is unsigned, and Wix has not yet
answered the request to correct the fixed corporation/incorporation wording.
The signer must complete the signature personally. Billing stays disabled and
widget/marketplace release stays held until the actual remaining gates pass.

The owner completed signup/login for `info@festapp.net`. Assigned app and widget
identities are in [wix-app.json](wix-app.json) and the
[registration receipt](evidence/registration-20261025.json). The
[hosting receipt](evidence/hosting-20261026.json) describes the currently hosted
asset set, not the held candidate bundle. No paid publisher plan or listing fee
has been accepted. [Billing ownership](billing/README.md) and the
[delivery runbook](billing/DELIVERY.md) define the deployed boundaries and the
remaining operator setup.

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
- The candidate widget obtains tenant/form-bound provenance with its native Wix
  SDK token before mounting checkout. Its iframe and direct form link retain the
  same context. Customer acquisition and settled fee evidence remain separate
  requirements for revenue reporting.

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
passed. [Studio evidence](evidence/studio-20261025.json) records the initial shared
helper contrast defect. The fix is now live on 0.20.402+903 and verified in the
actual published Studio, including 320 px layout and a second isolated order.
See [current qualification](evidence/published-checkout-current-20261025.json) and
[shared service release](evidence/service-release-20261025.json). The compact settings panel now has
its own keyboard-accessible scroll area and visible save status.

Harmony now also has an actual owned free-site installation, saved settings after
a full editor reload, Editor/Preview checkout isolation and published 320 px
summary verification against the disposable backend, using client 0.20.404+905.
The template required native Desktop and Mobile width adjustments. No order was
submitted in this run. See [Harmony qualification](evidence/harmony-qualification-20261025.json).
Wix version 1.0 is released unlisted for this owned QA installation; this is not
Marketplace publication, billing approval or an access-private release.

The [recovery fixes](evidence/recovery-fixes-20261026.json) lock settings while
loading/saving and permit a later render to retry a failed helper request.
Published Editor recovery preserved the checkout iframe and loaded one helper;
14 regression tests pass. This does not resolve native Wix portal/install errors
or qualify commercial submission.
