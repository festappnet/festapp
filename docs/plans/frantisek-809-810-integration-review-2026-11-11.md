# Review and local integration of František's measurement follow-ups

## Follow-up implementation

The confirmed defects below have now been corrected locally according to
[the implementation plan](measurement-request-hardening-plan-2026-11-11.md).
The findings remain as review evidence; production and source publication are
still separate steps. See the plan's execution result for final checks.

## Scope and outcome

Reviewed PR [#809](https://github.com/festappnet/festapp/pull/809), head
`762f5b0427c5a149707c1783d4b3c0a370edd8de`, covering issues #807/#808,
and PR [#810](https://github.com/festappnet/festapp/pull/810), head
`2e19d58d682a94dabe433ec1ca75f56e2c4c5283`, against canonical main
`5a01046df343d003eec4f3caf8f44f5011267c4c`.

The deeper review supersedes the initial no-blocker assessment: #809 has a
confirmed request lifecycle defect and two UX issues described below. Hold its
merge until these are fixed. No blocking defect was found in #810 within the
reviewed scope. Both PRs had eight successful required GitHub checks at their
individual heads; those passing checks did not cover the newly identified cases.
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

## Deeper review: findings

### Standards and code correctness

**P2 - A withdrawn website request can become permanently unrequestable.**
`database/functions/eshop_forms/unit_measurement_approval.sql:57-60` treats
historical requested_origins as an active request even when there are no
remaining deliverable notifications. On an already approved Unit, request B,
remove B before delivery, let delivery cancel the invalid request, then re-add B.
The request RPC returns its old revision and emits no new email. UI newSites
also compares against that historical snapshot and hides/disables the retry.
The ordinary idempotency rule therefore incorrectly spans a withdrawal.

The hardened disposable PostgreSQL reproduction used real request/status/intent
functions and actual public.claim_email() twice, each returning {"skipped":true},
followed by the real request RPC again after re-adding B. Result: revision 1,
two cancelled notifications, zero deliverable notifications. No direct workflow
state assignment was used for these messages. Other disposable fixture messages
were deferred and capacity configured only within the rolled-back transaction.
This is not a production test or an assertion that an email was actually delivered.
The worker cancellation branch is email_queue.sql:213-215. Durable script/log:
/Users/miakh/Library/Caches/festapp-reviews/809-810/request-lifecycle-repro.cjs
and request-lifecycle-repro.log. All reproduction writes were rolled back.

Fix direction: give the current request an explicit actionable lifecycle bound
to the saved proposal, distinguish it from historical requests, and allow a new
generation after withdrawal/cancellation while retaining idempotency for repeated
unchanged active requests. Keep request lifecycle in the canonical SQL command
boundary and expose its derived status to UI/MCP. Do not add a persistent trigger
or let the Flutter screen become a second authority for request eligibility.
Add regression coverage for remove/cancel/re-add and repeated active retries.

No hard documented architectural or authorization violation was found in the
Unit aggregate, platform-only approval boundary, SQL predicates, private table
ACLs, forward migration or CookieConsent adapter seam. Duplicating the origin
regex between Flutter and the shared contract is a maintenance concern rather
than a demonstrated standards violation; derive/reuse validation when revising
the field so changes cannot drift independently.

### Spec

The request lifecycle defect violates #809's promise that a newly added,
unapproved website can create another request. #807's two-state approved/pending
wording is insufficient for a multi-step save/request workflow: implementing it
literally produces the UX ambiguity below. #810 matches its stated opt-in,
revision, expiry, service-category, TCF and invalid-source behavior. No unrelated
scope expansion was identified.

### UX: adaptive Flutter surface

**P2 - The status UI conflates draft, unrequested, unknown and pending.**
`unit_measurement_settings.dart:148-150` calls every origin not present in
approvedOrigins “Čeká na potvrzení platformou”, even before Save or Request and
when loading approval failed. Moreover, lines 165-173 show “Měření zatím není
platformou povoleno” on an already approved Unit with a new website and no past
request. This incorrectly implies previously working measurement is disabled.
Separate Unit measurement approval from each website's draft, saved/unrequested,
requested, approved and unavailable states. Derive persisted request eligibility
from backend state; keep unsaved draft state local. Make the next action explicit.

**P2 - Invalid website input silently disables the request.**
`unit_measurement_settings.dart:146,179-184` disables Request for an invalid
origin but shows no field error while editing. Pasting the common full URL
https://poradatel.cz/vstupenky leaves a disabled button and a misleading pending
label. The six-state Flutter reproduction asserts the button is disabled while
the validation message is absent. Show validation after interaction and use the
same validator at submission; explain why the action is unavailable.

Visual verification used the actual Flutter component and ThemeConfig, Czech
catalog and Futura font assets at desktop width 1000 and mobile width 390,
including text scale 2. Six rendered states passed without layout exceptions:
desktop/mobile draft, invalid input, requested, approval-load failure and large
text. Captures are in
/Users/miakh/Library/Caches/festapp-reviews/809-810/.
This is a native/adaptive widget render review, not browser E2E; no live server,
browser overlay, markup detector or production operation was used. The harness
exercises the real component with controlled callbacks/statuses, not a live
request. Icon font rendering in the test engine is not production visual evidence.
The temporary rendering harness was removed after capture.

Native UX heuristic assessment (0 poor, 4 strong): status visibility 1; match to
user mental model 2; user control/recovery 1; consistency 3; error prevention 2;
recognition over recall 2; efficiency 3; visual restraint 3; error explanation 1;
help/documentation 3. Strengths: established field/button components, explicit
platform-only approval and bounded input. The main cognitive burden is separating
saving, requesting and actual approval when the screen presents them as one state.
Questions skipped: this is the requested bounded review, with no product decision
needed to establish the defects. No redesign is proposed.

### Recommended order

1. Correct #809's request lifecycle in SQL and expose authoritative request state.
2. Use that state for truthful origin labels and separate Unit approval messaging.
3. Make input validation visible and exercise retries, save failure and invalid data.
4. Retain #810's adapter boundary; no rewrite is justified by this review.
5. Rerun affected checks on corrected inputs before source publication and release.

## Integration and release sequence

1. Publish shared changes only after the applicable source-publication checks
   and a fresh comparison with authoritative main. Preserve issue/PR provenance.
2. Require all eight canonical GitHub checks on the resulting exact main SHA.
3. Prepare only the selected festapptickets tenant overlay with main-owned drift
   policy and a new version; preserve current production ancestry.
4. Apply the canonical forward migration 20261111150000_measurement_websites.sql
   through the protected backend workflow. Deploy the changed approval email
   renderer with its Functions owner, preserving pause/drain/restart/probe
   requirements. A frontend-only release would leave this workflow incomplete.
5. Build/deploy the selected tenant locally with its existing private release
   manifest and canonical direct-deploy gates. Verify live help/embed and the
   version. Runtime origin approval or other tenant rollout is separate scope.
