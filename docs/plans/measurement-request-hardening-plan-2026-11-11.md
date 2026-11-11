# Measurement request lifecycle and UX implementation plan

## Outcome and scope

Implement the confirmed #809 lifecycle and UX defects on local integration
ab7072a4e plus review d07c5db57. Preserve #810's reviewed adapter and the existing
Unit aggregate, platform-only runtime approval, email queue, authorization and
semantic consent scope. Standard verification applies (SQL/public contract).
Production deployment and upstream publication are not part of this implementation.

## Evidence and target contract

Fact: historical requested_origins is currently the only retry dedupe input.
The real claim_email worker cancels withdrawn intents; re-add then cannot create
a new request. Fact: the widget labels drafts as pending and silently disables
requests for invalid input. Evidence is in the integration review and cache repro.

Decision: public.unit_measurement_approval_internal owns request_state
(not_requested/requested/retry_available), can_request and saved_origins.
The latest notification generation is active if an eligible platform recipient
has a nonterminal, unexpired notification, an accepted delivery, or an ambiguous
sending/unknown outcome. Terminal cancelled/expired/dead/suppressed notifications
cannot permanently dedupe a retry. Preserve idempotence under the existing Unit
row lock. Historical requested_at/origins remain history, never proof of activity.
No persistent trigger or alternate request table/endpoint is added.

Decision: saving and requesting are explicit separate steps. A draft must be
saved and authoritative approval status refreshed before Request is available.
The backend remains the final eligibility authority. UI labels distinguish
unsaved, saved/unrequested, requested, approved and unavailable; overall Unit
approval is independent of a newly proposed website. Field validation appears
after interaction. Generate the Flutter website regex from the shared contract.
Missing new status fields fail closed; deploy SQL before the new frontend.

## Waves

1. SQL status and request eligibility: replace historical-snapshot dedupe with
   authoritative current-generation actionability; preserve recipient checks,
   revisioned notifications, row locking and no-recipient rollback. Index the Unit
   notification-generation lookup so status reads avoid global email history. Add a scoped
   forward migration; freeze the previous website migration bytes in its checker.
   Exit: real worker cancellation/re-add creates one new generation, repeated
   active requests create none; accepted/ambiguous sends do not duplicate.
2. UI/model: consume explicit fields, remove newSites eligibility reconstruction
   and request-time autosave. Refresh approval after successful Save. Expose draft
   guidance, truthful labels, separate Unit approval, visible validation and
   retry/loading states. Generate regex with configuration contract generator.
   Exit: unsaved/invalid/unknown cannot request; saved/retryable can; save failure
   cannot submit and old approved sites remain approved.
3. Regression and documentation: SQL real-worker lifecycle tests, model/widget
   states and real screen save/request cases; update localized catalogs and help
   so Save then Request is explicit. Regenerate only owning artifacts. Preserve
   all original migrations and #810 behavior. Exit: affected SQL, Flutter,
   generator parity, email/consent/help checks pass in one final batch.

## Completion and remaining release boundary

No placeholders, duplicated eligibility policy or new compatibility implementation.
Record executed checks and any limits. Local implementation is complete when the
plan's invariants and affected tests pass. A later authorized release must still
pass source CI, apply the scoped migrations and approval email renderer, then
build/deploy only the selected tenant with all existing gates.

## Execution result

Implemented locally on the review integration branch. Canonical SQL status now
owns notification-generation actionability and can_request. Accepted, sending
and unknown outcomes remain deduplicated; cancelled/expired/dead/suppressed
outcomes permit explicit retry. A partial Unit/generation index bounds lookup
work. The new scoped 20261111160000 forward migration preserves all historical
migration bytes; the previous website assembler checks its fixed SHA.

The model fails closed for missing/unknown lifecycle fields. The screen explicitly
requires Save before Request, refreshes status after Save, blocks overlapping
save/request operations, separates overall Unit permission from origin status,
and validates edited origins visibly. Flutter's origin pattern is generated from
the same JSON contract used by SQL and MCP. No CookieConsent implementation change
was needed.

Executed verification:
- 35 targeted Flutter settings tests passed, including real-screen save failure
  and recovery, ten lifecycle/responsive states, missing contract, invalid input
  and request eligibility. Captures of real widgets use the current light theme,
  Czech examples and actual font assets; desktop, mobile and 2x text tested.
- SQL approval lifecycle, runtime semantics and canonical source parity passed
  against the disposable local owner. The lifecycle regression calls the actual
  claim_email twice, verifies a new generation after cancellation, idempotent
  retries, accepted/ambiguous dedupe and terminal/expired retry.
- 137 consent/help regressions and 3 email renderer tests passed.
- Migration/contract/embed generation checks and git diff --check passed.
- Targeted Dart analysis exited successfully, with no errors/warnings and three
  pre-existing informational diagnostics in unrelated screen code (two braces,
  one BuildContext async-use in deletion). No new analyzer diagnostics remain.

The initial regression run exposed an outdated exact JSON expectation after the
contract expansion and a capture attempted before button ripple paint settled.
Both test boundaries were corrected; the final affected runs passed. A final SQL
run included the added lookup index and passed.

Logs: /tmp/festapp-measurement-hardening-{flutter-final,analyze-final,sql-final,
sql-retry,js,email}.log. Render evidence:
/Users/miakh/Library/Caches/festapp-reviews/809-810/fixed/.

No source publication, production migration, Functions reload or deployment was
performed. Full source CI and release gates remain required for publication and
the separately authorized selected-tenant release. No live browser E2E claim is
made for the widget captures.

## Authorized integration and release

The user's subsequent instruction explicitly authorizes publication to main and
deployment to prod/festapptickets only. Preserve the canonical local/GitHub CI
and protected backend/Functions release gates. Main advanced to b6c46e476 with
scanner/bank fixes and migration version 20261111140000. To avoid a ledger version
collision, the unpublished website migration was renamed to 20261111150000 with
its bytes unchanged; the lifecycle forward remains 20261111160000. Regenerate
source parity and validate the reconciled tree before publication.

Full local CI additionally exercised large text without loaded font assets and
exposed the consent layout dropdown's unconstrained intrinsic width. Setting
DropdownButtonFormField.isExpanded bounds it to the available form width. The
exact previously failing 2x-text case now passes without captures or custom fonts.
The local parallel mirror also exposed a pre-existing test race between a
temporary checkpoint migration and a generator read; rerun affected lanes after
the database runtime mutation test completes, preserving passed unchanged lanes.
