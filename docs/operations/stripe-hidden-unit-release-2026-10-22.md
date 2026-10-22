# Stripe hidden unit activation and production release

Scope authorized by the user: publish the prepared Stripe integration with the current main changes, deploy only `prod/festapptickets` / `https://vstupenky.online`, and enable discovery for unit 8, `Testovací organizace`, under tenant organization 3. No open PRs remained at preflight. Main was refreshed to `e069a11b7`; the two intervening occasion setup commits were merged intact.

## Activation contract

`eshop.stripe_unit_features` is a private RLS table with no client or service-role direct grants. All units default to hidden. `set_stripe_unit_feature` requires the canonical tenant organization administrator predicate, rejects another tenant and demo units, and serializes with checkout/setup on the unit lock. Unit managers cannot activate it. Removing a unit cascades its feature setting.

The organization settings screen exposes the collapsed `Skryté funkce` section only to a tenant administrator. Its Stripe switch affects that unit alone. The current app context projects `stripe_preview_enabled`; Flutter no longer uses a build-wide preview define. Changing context or losing it defaults to hidden. New OAuth setup and form availability enforce the setting on the server. Turning discovery off preserves existing payment facts and recovery paths.

Visibility is separate from permission to take money. `stripe_runtime_policy.new_payments_enabled` stays false/absent, verified surface lists stay empty, no Stripe recovery scheduler is installed, and this release performs no provider payment/refund/OAuth calls. Missing Stripe environment inputs fail closed and do not block bank checkout.

## Evidence

- Rebased scope: prior standalone integration commit plus current main, with no merge conflicts. Original mixed dirty checkout preserved.
- Targeted Flutter: two unit activation/rights context cases, three existing form settings cases and two canonical quote refresh cases pass. Targeted analyzer has no errors; existing style/context diagnostics remain.
- Deno: 119 Stripe, exact email money and actual Edge entrypoint cases pass. Six Stripe endpoints are included in the canonical production inventory; the 42-function executable coverage contract passes.
- Fresh canonical replay and upgrade from current main use the actual repository migration runner and the final three Stripe migrations. Upgrade preserves a real paid bank fixture byte-for-byte apart from the two added payment columns. All 12 Stripe SQL files plus canonical parity pass on upgrade. The earlier old-main upgrade experiment hit an owner error in upstream migration `20261022052000`; current-main upgrade, matching the deployed prerequisite ledger, passes.
- Six held-lock SQL races pass after explicit unit opt-in. Historical readiness evidence continues to describe its original revision; new receipts supplement it.
- Full client wrapper still references absent upstream `tool/check_architecture.dart`; no full client wrapper pass is claimed. The canonical production build, startup, image/legal, tenant drift and coherent live release probes remain required.

## Production sequence

Publish verified main, then use that exact authoritative revision for the three migration digests and the clean canonical Edge bundle. Preserve protected rollback evidence, update SQL and ledger atomically, notify PostgREST and read back the resulting owners, RLS and disabled sales. Stage the canonical runtime policy/bundle preserving the host router and its signature/capability proof routes. Enable only the selected unit feature as an audited operator configuration change.

Prepare one fresh main-based festapptickets overlay retaining the previous production tip as an ancestor. Increment its version, run configuration generation and main-owned tenant drift validation. Build locally and deploy with `automation/deploy_direct.sh`, using the existing protected release manifest and Wrangler authentication. Completion is recorded in the release handoff with exact main/tenant revision, version and live verification; this source document is preparation, not deployment success.
