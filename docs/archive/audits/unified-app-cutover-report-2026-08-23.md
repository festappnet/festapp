# Unified application cutover report — 2026-08-23

## Current state

The canonical runtime cutover base and primary tenant cutover commits are:

- `main`: `3e7a31ab39a3f913367985bcb2bb6fe137ac2418`
- `prod/csmostrava2026`: `c36d704976ba1b4fbe0b000c4d39253646eb1cea`
- `prod/hvezdamorska`: `b4afe7f8ff3030ed3f2a8f749b977b949402877e`

Both primary production commits have the canonical runtime main SHA as their
second parent and contain only their main-owned tenant overlay plus regenerated
leaf files. A later report-only main commit may be synchronized into the tenant
branches with the same drift proof; its SHA is deliberately not recorded inside
its own self-referential report. No push, production migration, deployment,
store release, backup-ref push, force push, or production write has been
performed.

## Source results

- All 450 divergent commits are classified exactly once: 260 CSM and 190 HM.
- The original dirty CSM worktree is detached at its original
  `84c1d5de5277d4388c25d07235700a93668345c4` commit. Its tracked patch checksum
  (`968dfa3210db147f817e6927162876f8d2102a812d3a05eddcbb16b8ef343f90`) and
  untracked-inventory checksum were identical before and after detaching. Its
  external recovery snapshot remains `/tmp/festapp-unified-cutover.p9Dm64`.
- `main` is the sole owner of shared Flutter, web, SQL/RPC, Edge Function,
  worker, PWA, map, release-tooling, account-deletion, product-description, and
  order-agreement implementations.
- Tenant branches are constrained to the source paths in main-owned overlay
  manifests plus the exact generated write-set. Synthetic tamper tests reject
  shared-source drift, generated-output drift, policy replacement, and base-SHA
  spoofing.
- The historical `generate-hvezdamorska-agreement` source path and caller are
  absent. `generate-order-agreement` is the canonical endpoint and reads its
  tenant contract from `AGREEMENT_PDF` external-service configuration.
- The colliding CSM migration was preserved as the new idempotent forward
  migration `20260823120000_reconcile_reception_manual_login_code.sql`; main's
  historical `20260806142000_manage_occasion_users_permission.sql` remains
  unchanged.

## Verification evidence

| Gate | Result |
|---|---|
| Commit-ledger generation and exact coverage | pass, 450/450 |
| Tenant config matrix, idempotence, and cross-tenant checks | pass |
| Main-owned tenant drift and adversarial tamper fixtures | pass |
| Web client tests | pass, 165 passed / 0 failed |
| Web client production build | pass |
| Flutter tests | pass, 571 passed / 0 failed |
| Flutter web production build | pass; existing wasm dry-run warnings remain |
| CSM tenant Flutter/Vite production builds | pass |
| HM tenant Flutter/Vite production builds | pass |
| Final CSM/HM canonical drift checks | pass |
| Final tree and complete unpushed-history credential scan | pass for main, CSM, and HM |
| Edge/Deno tests | pass, 80 passed / 0 failed, including DB integrations |
| Automation suite | pass, including private-input schema and PWA contracts |
| Disposable local database baseline and migrations | pass via temporary Colima runtime; latest hardening migration applied |
| Database tests | pass, 76 passed / 0 failed |
| PowerShell parser/readback | skipped: `pwsh` unavailable; scripts were generalized and inspected |
| Production readback/deploy/release | pending separate authorization |

The Flutter suite initially exposed one CSM-specific expectation in the
canonical startup test. The test was made tenant-neutral and the full suite
then passed. The first database run exposed a later reception migration that
had narrowed the already-correct manager/admin QR contract; the forward
migration was reconciled with the canonical source, the disposable database
was rebuilt, the focused regression passed, and the complete 76-test DB gate
then passed. Colima was started only for this local gate and stopped afterward;
no remote database was used.

A clean post-cutover Flutter resolution exposed that the permissive
`adaptive_theme: ^3.7.2` constraint now selects incompatible 3.8.0. Main pins
the previously verified 3.7.2 release, after which clean main, CSM, and HM web
builds passed. Release credential hardening now ignores key artifacts globally,
rejects App Store and Google Play credential paths inside the repository, and
documents external provisioning.

The final standards/spec review then tightened the cutover without changing its
tenant model: canonical SQL sources now use explicit `public` qualification,
active SECURITY DEFINER entry points use the approved search path, cleaning
reports require approved occasion membership, and the hardening is delivered by
a forward-only migration. Production logs no longer emit recipients, order or
payment identifiers, the account-deletion page is generated from each tenant's
configuration, and the repository now tracks the verified root `pubspec.lock`.
The focused cleaning regression, tenant configuration matrix, generated-page
test, enforced lockfile resolution, and disposable migration replay passed.

## External boundaries and blockers

- The private configuration repository was inspected without recording its
  locator or revision in this public report. It provides a tested, fail-closed
  CSM Play/App Store provisioning contract, canonical store metadata and
  approved screenshot/artwork inputs with platform-specific local adapters,
  authority checks, artifact hashes, and Android certificate fingerprint
  verification. Its committed tree contains no release credential.
  No private value was copied into Festapp. Concrete credential population and
  store readback remain explicit external gates.
- The private repository audit found three legacy tracked runtime env files
  containing
  OneSignal REST, SMTP/AWS, and internal auth credentials. They were removed
  from its current tree without deleting the ignored local operator copies.
  Their historical values must be rotated before the incident is
  considered contained; no history rewrite or external credential mutation was
  performed.
- Required-check branch protection and other GitHub policy are external state.
  The workflow contains the main-owned drift job, but it must not be described
  as unbypassable until separately authorized external readback confirms branch
  protection.
- Production migrations in
  `unified-production-database-deployment-manifest-2026-08-23.json` are ordered
  and marked `apply: false`. They remain unapplied.
- Local pre-cutover refs preserve CSM at
  `backup/prod-csmostrava2026-pre-cutover-20260823` and HM at
  `backup/prod-hvezdamorska-pre-cutover-20260823`. They have not been pushed.

## Next authorized transition

After this report update is reviewed, committed, and synchronized into both
tenant branches, obtain explicit approval before pushing `main`, either
production branch, or backup refs. Production deployment, database writes,
external-service provisioning, and store releases remain separately authorized
operations.
