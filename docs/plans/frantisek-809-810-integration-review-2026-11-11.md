# Review and local integration of František's measurement follow-ups

## Scope and outcome

Reviewed PR [#809](https://github.com/festappnet/festapp/pull/809), head
`762f5b0427c5a149707c1783d4b3c0a370edd8de`, covering issues #807/#808,
and PR [#810](https://github.com/festappnet/festapp/pull/810), head
`2e19d58d682a94dabe433ec1ca75f56e2c4c5283`, against canonical main
`5a01046df343d003eec4f3caf8f44f5011267c4c`.

No blocking correctness issue was found in the reviewed changes. Both PRs
had eight successful required GitHub checks at those individual heads.
The combined local integration preserves both implementations and resolves
the changelog conflict. Its Czech and English recommendation now lists both
Complianz and CookieConsent v3, removing the stale Complianz-only statement
introduced by #809 alongside #810's adapter documentation.

## Architecture assessment

- Website proposals use the existing Unit configuration aggregate and shared
  UI/MCP contract. They do not write approved runtime origins or alter either
  technical or semantic consent revisions. Requests lock the Unit, snapshot
  proposed origins and revision the notification so unchanged retries remain
  idempotent and superseded notifications fail delivery validation.
- CookieConsent uses the existing read(scope)/subscribe adapter seam and the
  existing link transport. It requires an opt-in stored choice, matching CMP
  revision and semantic Festapp scope, fresh storage, expiry and agreement with
  the live category API. Unsupported or invalid records retain the form notice.
  Complianz and the GCM iframe bridge retain their implementations.
- Proposed websites remain different from platform-approved runtime origins.
  Adding a website does not itself authorize any runtime deployment.

## Combined local verification

- 137 consent adapter/link and help tests passed, zero failures or skips.
- 25 targeted organizer settings Flutter tests passed, concurrency 1 under the
  workstation Flutter resource lock; selection included the bundled
  unit_measurement_settings cases and organizer settings save tests.
- Two SQL suites passed on the canonical disposable local DB owner:
  form_measurement_approval_request_test.sql and form_measurement_runtime_test.sql.
- Three measurement approval email renderer tests passed with the frozen Deno lock.
- Forward website migration, frozen access membership migration and generated
  embed parity checks passed. git diff --check passed.

Logs: /tmp/festapp-frantisek-809-810-{js,flutter,sql,email}.log.
The first Flutter selection used a literal name expression and collected no
cases; the corrected regular-expression selection executed all 25 cases above.
No browser visual verification was performed. No production changes were made
for this follow-up review; the currently deployed release remains 0.20.568+1079.

## Integration and release sequence

1. Publish shared changes only after the applicable source-publication checks
   and a fresh comparison with authoritative main. Preserve issue/PR provenance.
2. Require all eight canonical GitHub checks on the resulting exact main SHA.
3. Prepare only the selected festapptickets tenant overlay with main-owned drift
   policy and a new version; preserve current production ancestry.
4. Apply the canonical forward migration 20261111140000_measurement_websites.sql
   through the protected backend workflow. Deploy the changed approval email
   renderer with its Functions owner, preserving pause/drain/restart/probe
   requirements. A frontend-only release would leave this workflow incomplete.
5. Build/deploy the selected tenant locally with its existing private release
   manifest and canonical direct-deploy gates. Verify live help/embed and the
   version. Runtime origin approval or other tenant rollout is separate scope.
