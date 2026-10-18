# Consolidated October 18 release candidate

Selected deployment: `festapptickets`, `prod/festapptickets`,
`https://vstupenky.online`, canonical organization 3. The user authorized deployment
of the combined PR work on October 18 and selected this tenant explicitly.
The write-boundary contract is global across all organizations, including
occasions without sync readers. There is no tenant activation table or exception.
The original selected web is vstupenky.online. The user's subsequent global
cutover instruction expands the necessary web-client rollout to the eleven active
production branches listed below, all at one common version. Mobile store
publication and payment-reference registry activation remain separate steps.

Web branches in scope: prod/absolventskyvelehrad, prod/aksmcz,
prod/cavfotofest, prod/csmostrava2026, prod/doobiscup, prod/farnostopava,
prod/festapp, prod/festapptickets, prod/festivalslunovrat, prod/hvezdamorska,
prod/jubileum2025. Retired production branches are excluded.

## Integrated source

Base main: `8b1420ea1da7349db68b4a293bb37da049fb9047`.
Branch: `integration/open-prs-20261018`. The exact heads of PRs #460, #461,
#462 and #463 are merge ancestors, preserving their complete history.
The original checkout and its 1,616 dirty paths were preserved.

Cleanup/security conflicts remove the two genuinely unused helpers while
retaining the new context readers, minimal peer DTOs and scoped commands.
Integration also repairs numeric sign-in-code exchange, explicitly classifies
four previously unclassified client roots, and gives new reference tables their
canonical postgres owner after the hardened defaults migration.

The new `20261018210000_integration_contract_reconciliation.sql` restores existing
reception teardown and current order-deletion authorization/replay owners that
an older admission bundle overwrote. It restores the previously shipped bank-health
send-time guard and rejects retired overview mail even without an order ID.
The standalone order command is now its one source owner. Its canonical inventory,
source-parity fixture and new forward migration agree.

Already applied migration history is unchanged. The original admission migration
is checked by digest; superseded functions are checked against their forward
corrections instead of regenerating installed history. The still-unreleased
payment-reference migration includes the new table ownership correction.

## Verification

- Complete client runner passed: core, native adapters, Flutter, architecture and
  semantic discovery (1,246 baseline cases plus 299 added cases).
- All 219 SQL files passed on this task's freshly bootstrapped disposable server.
- All 419 enabled web tests passed, including actual PostgreSQL concurrency,
  rollback, full/split waitlist conversion, replacement, inventory and registry
  dump/restore. Nine conditional web tests are skipped.
- Deno: 359 passed. Existing image-worker integration has 27 skipped tests because
  provider fixture credentials are absent; this is not live integration evidence.
- Security/CSP browser fixture passed without CSP and with an enforcing fixture;
  real seat browser checkout passed through SQL reservation and ticket assignment.
- Targeted Dart analysis has no errors or warnings; one preexisting constant-name
  info remains. Diff/config generation and migration/contract checks passed.

State-machine email tests use an explicit rollback-only workload profile;
production recipient limits and their separate abuse suites are unchanged.
Committed concurrency fixtures now use distinct synthetic recipient addresses.
The reference test uses its own marker-verified template, separate from the
concurrent SQL/web database; only extension workers in that dedicated template
may be fenced for cloning, never an unexpected client session.

Local evidence: `/tmp/festapp-integration-gate.log`,
`/tmp/festapp-integration-security-browser.log`,
`/tmp/festapp-integration-seat-browser.log`. The task-owned server is project
`festapp-integration-20261018`, loopback port 59132, outside the user's running
local projects. These fixtures are synthetic; no production fixture/order/email
was created.

## Publication and production gates

GitHub main protection requires one approving review. The author cannot approve
his own PR; the user explicitly authorized administrative merge for this release.
Protection settings remain unchanged. After merge, use its
exact main SHA for the canonical tenant overlay and mandatory main-owned drift
check, then build locally and deploy via `automation/deploy_direct.sh`.
CSP remains Report-Only; enforcing CSP requires its separate compatibility matrix.

The live activation identifies `festapptickets`, generation 1, canonical backend,
and the selected production config identifies organization 3. The persisted SSH profile was reprovisioned to the selected festapptickets/
organization 3 assertions without changing transport credentials. Protected
read-only checks verified the expected host and database and organization 3.
No production migration has been applied yet.

The data-security read-ACL phase additionally requires concrete supported-client
compatibility evidence, as specified by its guarded driver. Local tests do not
attest installed Android/iOS compatibility. Do not set the compatibility flag
without that evidence. Registry history import and activation remain separate
operations; the payment migration stays dormant.

The release also needs the existing protected `FESTAPP_RELEASE_MANIFEST` on the
release workstation. It may be transferred using the existing encrypted
`local-release-input.yml` workflow; it must not be fabricated. That provisioning
workflow does not build or deploy production. Provisioning binds each encrypted manifest to its explicitly selected tenant.
The local-only build/deploy requirement applies to every branch in scope.

## Global write-boundary correction

The rejected tenant-specific compatibility experiment was removed before commit
or production execution. All organizations use the existing domain commands;
read projection capability does not select a second write implementation.
The new global ACL phase also revokes historical column privileges, which survive
ordinary table REVOKE, and drops the obsolete Slunovrat direct-write policies.
The runtime audit detects column-grant or tenant-policy reintroduction. An upgrade
regression injects old grants, applies the canonical phase and verifies their
removal while authenticated scoped readers remain available. The dormant payment
replacement's internal function now explicitly revokes inherited service-role
EXECUTE to match its existing internal-only contract.

Follow-up verification: all 219 SQL files, the complete client runner, 359 Deno
tests and automation checks passed in `/tmp/festapp-global-boundaries-full.log`.
The initially missing concurrency template was recreated on the verified owned
local server; the web batch then passed all 419 enabled tests in
`/tmp/festapp-global-boundaries-web.log`. Changed provisioning passed the
subsequent complete automation batch in
`/tmp/festapp-global-boundaries-automation.log`. Final boundary catalog/upgrade
and SQL tests passed in `/tmp/festapp-global-boundaries-catalog.log` and
`/tmp/festapp-global-boundaries-sql.log`. Manifest generation is reproducible.
