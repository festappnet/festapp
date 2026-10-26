# Slunovrat administration recovery - 2026-10-07

Status: completed for web administration and the authorized Slunovrat account.
Scope: `prod/festivalslunovrat`, organization 19. No other tenant deployment,
mobile release, identity merge or image infrastructure mutation.

## Failure and repair

`/2025we/admin/info/information` loaded `2025-copy-98cf835a` because the
Flutter rights loader unconditionally applied `FORCE_OCCASION_LINK`.
The administration boundary rejected the mismatch as `Access denied`, even
though this tenant's user had unit-level administration visibility.

The urgent tenant configuration removes the override. The database's
`DEFAULT_OCCASION=1072558` retains the same `2025-copy-98cf835a` landing action.
Shared source repair [PR #337](https://github.com/festappnet/festapp/pull/337)
keeps configured startup defaults while honoring explicit occasion/unit
contexts. It remains pending the main branch's required review; the deployed
tenant configuration repair does not depend on that merge.

The user explicitly requested highest administration privileges for Slunovrat.
The [scoped SQL](../../../../database/recovery/2026-10-07-slunovrat-administrator-access.sql)
sets organization administration, unit management/editor rights and management,
editor, order, approval and reception roles on all five existing tenant events.
It targets the existing profile in organization 19 joined to Auth email
`19+bujnmi@gmail.com`, not the unprefixed legacy Auth account. Existing profile
data and non-role flags are preserved. Thirteen same-address organization
profiles were verified to use thirteen distinct IDs and their respective
prefixed Auth emails. No cross-organization identity was merged or reassigned.

The initial diagnostic using unprefixed email incorrectly suggested no tenant
membership; that conclusion was corrected before the role assignment. The
tenant account already had unit-level visibility, but not organization admin.
The newly assigned privileges follow the user's separate explicit instruction.

## Production receipts

- Canonical source base: `89dab29985aa09369a7f5e1ccd545eb190cb72ef`.
- Tenant release: `8b67e16ea0e67fda6ecc4561c091cad999d83a4b`, `0.20.135+619`.
- [Successful Deploy run](https://github.com/festappnet/festapp/actions/runs/37619939566).
- Live manifest: `main.dart.0.20.135-619.js`, version `0.20.135+619`.
- Runtime identity: `festapp-supabase-rehearsal-01`, database
  `festapp_rehearsal_20260909220601`, canonical activation generation 1.
- Role SQL SHA-256:
  `f67cb701780fbe7e1acd485e1597dfb3867e2302fceae545b09efa74e311bf5d`.
- Private pre-change role snapshot and prepared rollback are retained in the
  workstation's Git metadata under `operator-evidence/slunovrat-admin-20261007`;
  they are not repository content or deployment artifacts.

## Verification and limits

The original forced-context regression failed before the shared fix. Twenty-five
targeted Flutter tests passed with the Slunovrat landing configuration; the
final three regression cases and targeted Dart analysis passed. The tenant
release passed nine context/deep-link tests, legal validation, canonical overlay
drift and the production workflow's build/deployment verification.

After assignment, server permission checks returned true for administration,
occasion visibility and unit visibility on all five Slunovrat events. The real
`get_app_config_v219` RPC, run with the verified tenant user subject in a
transaction rolled back afterward, returned code 200, `occasionLink=2025we`,
`isAdmin=true`, `unitManager=true`, administration visibility true. An implicit
startup call still returned `2025-copy-98cf835a`. No authenticated browser session
was reused; the user's logged-in browser rendering was not independently tested.

The separate image project mismatch and R2 delivery cutover remain tracked in
[the image work item](../open/image-delivery-cost-cutover-2026-08-24.md).
