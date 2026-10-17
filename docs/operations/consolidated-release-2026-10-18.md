# Consolidated October 18 release candidate

Selected deployment: `festapptickets`, `prod/festapptickets`,
`https://vstupenky.online`, canonical organization 3. The user authorized deployment
of the combined PR work on October 18 and selected this tenant explicitly.
Other tenants, mobile/store releases, BankSync deployment and activation of the
new payment-reference registry are outside this rollout.

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

GitHub main protection requires one approving review. The consolidated PR must
receive that review before merge; admin bypass is not used. After merge, use its
exact main SHA for the canonical tenant overlay and mandatory main-owned drift
check, then build locally and deploy via `automation/deploy_direct.sh`.
CSP remains Report-Only; enforcing CSP requires its separate compatibility matrix.

The live activation identifies `festapptickets`, generation 1, canonical backend,
and the selected production config identifies organization 3. The persisted SSH
profile instead asserts `festapp`/organization 1. Host identity matches, but the
profile must be provisioned for the selected scope before production SQL access;
no backend query or migration was performed after detecting the tenant mismatch.

The data-security read-ACL phase additionally requires concrete supported-client
compatibility evidence, as specified by its guarded driver. Local tests do not
attest installed Android/iOS compatibility. Do not set the compatibility flag
without that evidence. Registry history import and activation remain separate
operations; the payment migration stays dormant.

The release also needs the existing protected `FESTAPP_RELEASE_MANIFEST` on the
release workstation. It may be transferred using the existing encrypted
`local-release-input.yml` workflow; it must not be fabricated. That provisioning
workflow does not build or deploy production. Only the selected tenant may be
prepared or deployed.
