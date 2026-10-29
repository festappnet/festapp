# Wizard reliability - implementation and verified release

**Production update:** version `0.20.446+951` was deployed to `prod/festapptickets` after PRs #659/#660 merged. Compatible Edge/SQL, tenant ancestry/drift, build gates and three live version/assets/legal probes passed. See the [release receipt](releases/festapptickets-wizard-reliability-2026-10-29.json).

Initial local implementation was on `fix/wizard-reliability-20261029` in
`/Users/miakh/source/festapp-wizard-reliability-20261029`, based on fetched
`origin/main` `2095a9ba49bf1a7cd3a76f9e5be98d8407e95825`. The original dirty checkout
was preserved. The following local evidence predates the separately authorized
production release recorded above.

## Result

- Scoped wizard revision/bank-fingerprint conflicts now return `PT409`. True SQL
  serialization errors are unchanged. Edge and Dart recognize both the new code
  and the exact historical wizard conflicts. Existing signatures, permissions,
  save ownership and finalization receipts remain in place.
- One preview coordinator captures the confirmed revision and detached options,
  shares identical in-flight reads and rejects obsolete results. An obsolete
  failure cannot freeze a newer edit. The template catalog debounces changed
  snapshots, including asynchronously loaded sender defaults. Confirmed reload
  resets communication input controllers through the existing form epoch.
- One manifest references the existing ten immutable font identities and generates
  Dart/SQL mapping. All 18 presets pass SQL validation, with PDF/both/inline QR,
  disabled forms and negative unknown/mismatched-font cases. No font bytes changed.
- The ordinary wizard has no Random/Sequence or starting-number controls. One
  payment projection preserves explicit copy policy. Legacy invalid policy has
  an advanced repair before Create, and the advanced editor validates the range.
  The allocator and registry were not modified.

## Bounded conflict evidence

The isolated project was `festapp-wizard-backend-qa-20261029`, API `127.0.0.1:56921`,
DB `56922`, UI `56981`. The final controlled comparison checked the disposable
identity, paused queue, absent worker and disabled cron before executing.

| Boundary | Original 40001 | New PT409 |
| --- | --- | --- |
| Frontend invocations | 0 | 0 |
| Stale HTTP RPC requests | 1 | 1 |
| DB conflicts for that request | 957 | 1 |
| HTTP completion | timeout at 261 ms, hard stop | 409 in 21 ms |
| Single direct SQL call | 1 conflict | 1 conflict |
| Explicit read using current revision | separate baseline | HTTP 200 |

This reproducer invokes HTTP directly; zero frontend invocations means no
frontend ran in this comparison. DB errors are not HTTP counts. The fault
amplifies below HTTP. Local REST was restarted after the bounded legacy attempt.
Docker log observation subtracts a baseline to tolerate host/VM clock skew.
The first post-fix log read raced log visibility; the bounded observer corrected
that measurement, without changing the product response.

The repeatable tool is `automation/tests/wizard_preview_http.py`; it requires
private local context JSON with draft/actor/token and never prints credentials.
Its legacy mode requires the old SQL definition in the disposable project and
hard-stops/restarts only that project's REST container. Restore canonical SQL
before the new-code check. The recorded [before](wizard-reliability-2026-10-29/preview-before.json)
and [after](wizard-reliability-2026-10-29/preview-after.json) contain no credentials.

## Real UI results

| Local occasion | Verified persisted result |
| --- | --- |
| Ocean, 85 | Open Sans in form and exact ticket face; price 100 CZK; no explicit VS policy; custom Reply-to and informal tone; created successfully |
| Lavender, 99 | Lato; restored legacy incomplete Sequence draft; empty starting number rejected, repaired to 260002; created successfully |
| Gala copy, 101 | Copied form B; Roboto Slab; price changed to zero; tickets disabled, quantity remains 1; explicit Sequence 260001 preserved; Reply-to and tone restored to inheritance; custom subject/body persisted after reopening and creation |

Source B remains price 175 CZK, tickets enabled, quantity 3 and Sequence 260001.
All three created occasions stayed hidden. Readback assertions and screenshots
are in [saved results](wizard-reliability-2026-10-29/saved-results.json).

Two headless tabs editing the same draft produced one save HTTP 409, retained
`local-unsaved@example.test` in the losing window and did not overwrite the
server draft. Request counts stayed unchanged after waiting. Reload required
confirmation. A further foreign-revision fixture exercised confirmed reload
with the final form-epoch wiring.

A temporary browser-only 700 ms network delay produced exactly two preview
requests: old revision 409, new revision 200. The latest edit remained visible,
all five template cards loaded, and no reload-conflict banner was raised by the
obsolete request. [Metrics](wizard-reliability-2026-10-29/delayed-preview.json)
count HTTP calls, not UI invocations. The fetch wrapper was removed afterward.
A separate UI draft customized and then restored the default template; persisted
`emailTemplateOverrides` was `{}`. Subject/body changes were verified from saved
models; mere changes to accessibility input proxies were not counted.

## Checks

- Flutter: 21 appearance/preview/payment tests, 7 email-template tests, 8 copy
  tests and 33 story/communication tests passed in discovered entrypoints with
  `--concurrency=1`. Initial test-fixture compilation/HTTP-response mocks were
  corrected and affected suites passed afterward.
- Core: `fvm dart test test/forms/form_variable_symbol_policy_test.dart` passed
  missing/null/zero/bounds/fraction/type/default cases. The advanced widget also
  rejects eleven digits without silently truncating the entered starting number.
- SQL: ten setup suites passed: appearance, email preview, draft email templates,
  finalize, sales, drafts, copy configuration, ticket delivery, adaptive details
  and payment policy. The new paid wizard -> real checkout test verifies a
  reservation in the existing canonical registry. Explicit policy SQL negatives
  and copied Sequence/source preservation are covered.
- The unchanged canonical allocator reservation suite passed against the clean
  local disposable DB on port 55432. Its first run against the UI QA DB correctly
  rejected that DB's preexisting shared-account writer; no allocator rule was
  relaxed to accommodate polluted fixtures.
- Edge: 12 preview tests passed, including success, 403/400/409 mapping and
  distinguishing true serialization failures. The existing Dart SDK test proves
  a new 409 reaches an older direct RPC caller once. Audited old `_drain` retains
  dirty data and stops; its error suppresses automatic debounce. The existing
  occasion preview caller in ticket settings has no draft revision branch.
- Generated mapping, canonical SQL/migration parity and `git diff --check`
  passed. Targeted analyzer reported no errors or warnings, with 54 informational
  style/deprecation diagnostics. pnpm 11.24.0 and frozen lockfile installation
  were used.

The prepared migration is `20261029120000_wizard_reliability.sql`; digest and
machine-readable counts are in [verification](wizard-reliability-2026-10-29/verification.json).
The queue guard after the three created events recorded zero messages, paused
queue, unset worker and zero active cron jobs. No real email, bank sync, Stripe,
external push or paid delivery was tested. Push callbacks use the existing local
entry fixture. Bank UI was exercised; Stripe payment projection has unit coverage
and its existing SQL path remains unchanged.

The named browser, owned Flutter server, local Edge process and QA project were
stopped; QA data was retained in its local backup. Other projects were left running.

## Production release and cleanup

PRs #659/#660 are merged. Backend source `9a2076d3c67de05a8ffca9546c62c7549e54c1f8`
was applied with exact SQL/Edge fingerprints and ledger digest after a fresh
pgBackRest differential/archive check. All ten exact font IDs already existed.
The canonical Functions guard restarted the existing container; email pause was
restored to false, no health alerts appeared and the two preexisting unknown
outcomes stayed unchanged.

Web source `7d9f2ff628187053e4efe2a71a51be27a8ea48a4` adds the tested PWA recovery-script
cache correction to that backend source. Tenant commit
`83169e14699a25f4c8733601e235a12d9628c37e` was built locally and uploaded directly via
`automation/deploy_direct.sh` to version `0.20.446+951`. No other tenant or GitHub
Deploy dispatch was used. The live browser smoke rendered the homepage and
account-entry dialog without submitting an account or creating production fixtures.

Finished task branches/worktrees were removed after a verified Git bundle and
protected file archives. Unready work and final integration drafts were retained
on `archive/work-in-progress-20261029` and in the workstation recovery archive;
they were not silently included in the release. Release notes are a documentation
follow-up and do not require another build or deployment.
