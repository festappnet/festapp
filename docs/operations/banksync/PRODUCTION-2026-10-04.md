# BankSync production activation - 2026-10-04

The user explicitly authorized production cutover and verification of actual paid order 6501 (CZK 1). Scope is festapptickets, canonical organization 3, with the shared BankSync service upgraded compatibly. Other Festapp tenant branches are excluded. Mendelio webhook-v2 work remains authorized separately; it must not block the requested Festapp payment cutover.

Preflight: vstupenky.online activation resolves tenant festapptickets, generation 1, canonical backend. The protected SSH hostname and runtime database match the installed target assertions; canonical organization 3 exists. Migration timestamp changed to 20261004193000 because current upstream already uses 20261004180000 for product price waves.

Operational evidence and final results will be appended after verification. No credentials or bank tokens belong in this document.

## Production state verified at 2026-10-04 15:40 UTC

- Shared Worker is `@festapp/banksync@0.2.2`, deployment
  `bf1b49be-c2d3-49c8-b54c-677f51f88158`; schema 11 migration SHA-256
  `1733b14312978030c0f4c4ac8bed5a5cf60f7de1bcba0a765fdce15729d5cbe2`.
  Composition typecheck, unit test and dry-run passed. Deep health is green.
- A protected D1 export was encrypted with the existing independent backup key
  and decrypted successfully before migration. All 234 original transaction
  projections and 454 delivery identities/payload hashes match after migration.
  Existing terminal jobs were not replayed. Existing consumers remain v1;
  only new consumer `festapp` uses v2.
- Canonical Festapp migration `20261004193000` is installed. The production
  Function bundle and scoped credential/router configuration come from main
  `e40861b84883`; bundle archive digest is retained by the host installer.
  The new receiver returns 401 for unsigned input. The bounded control recovery
  cron is installed. Existing unrelated runtime configuration was preserved.
- Account 159 for organization 3 / occasion 100 / order 6501 maps to remote
  account 408. Its reviewed manifest has no aliases and an empty historical
  Festapp ledger. The remote account was created paused and tokenless; the token
  was then installed encrypted with fetching disabled. Local mapping and the
  canonical authority barrier committed before enabling ingress and polling.
  Fio's receiving-account check remains mandatory before any transaction import.
- **Payment verification remains blocked:** this account's Fio statement request
  times out from the canonical BankSync path; direct bounded diagnostics also
  failed. The connection is degraded and automatic retries are enabled. There
  is no successful bank pull or credited payment yet; order 6501 is not declared
  paid and no ticket email was forced. Existing shared-service API accounts
  continued successful pulls during this check.
- No other Festapp bank account or tenant branch was activated. Account 1 is
  linked to organizations 1 and 3; separate cross-tenant authority is required
  before migrating it. Some other stored token expiry dates are already past.
  This is not a claim of complete M1/M2 or all-account cutover.

## Bank account management hotfix

The live management RPC failed with PostgreSQL 42702 because bare `is_admin`
collided with its RETURNS TABLE output variable. Qualify the bank-admin and
connection subqueries. The existing management test reproduced that exact error
in isolated native PostgreSQL 17. Extended coverage verifies the manager summary,
full bank-admin connection details, CASH exclusion and non-manager denial. It
passes after the fix. Migration `20261004194000` carries the canonical function;
its production application and final read verification are recorded separately.
