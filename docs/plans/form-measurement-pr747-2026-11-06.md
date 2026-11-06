# PR747 measurement completion

## Scope

Keep sale opening (`FormModel.startTime`, availability and countdown) separate
from analytics `form_start` (a visitor beginning to fill the available form).
Retain the existing consent/policy gates, one FormDataLayer event owner and the
two supported transports. Work in the isolated PR worktree and preserve the
other worktree's unfinished changes. Release scope is canonical main and only
`prod/festapptickets` / `vstupenky.online`, with full verification before release.
The current handoff integrates main only; production rollout is deferred for a
later unified release. No production SQL, tenant overlay or deployment is run.

## Implementation

1. Route meaningful visitor interaction through one optional renderer/widget
   callback. Native input/change and explicit custom answer/ticket/seat actions
   may invoke it; email blur, initialization, restored drafts and background
   session updates must not.
2. Keep `FormDataLayer.started()` as the only event and deduplication owner.
   Preserve once-per-form-load behavior and no replay of pre-consent activity.
3. Document the difference from scheduled sale opening and GA4's automatic
   session-level event. Keep shared contracts and generated artifacts canonical;
   avoid additional transport abstractions or unrelated cleanup.
4. Add integration regression coverage for real renderer/widget wiring,
   including untouched email blur, native input, custom actions, restoration,
   repeated input and consent gating.

## Verification

Use the complete repository gates with real disposable dependencies and isolated
muted browser sessions. Account for conditionally executed cases through their
complementary configurations. Source publication also requires the canonical CI
mirror; release requires all eight GitHub jobs on the exact merged main SHA.

## Completion

Implemented on `fix/pr747-form-interaction`, based on PR head `c020f8d52`.
The renderer owns native input/change detection and passes the same optional
callback through nested widgets. Radio clear, ticket add/remove, date selection
and blueprint seat/quantity intent notify the existing event gate. Schedule
opening and countdown behavior are unchanged. Duplicate GA4 setup prose in the
runtime README now links to the integration guide.

Verification on the final application sources:

- Complete web suite: 1024 passed with all database and local Auth/REST fixtures
  enabled, no skipped tests. Includes a real selector callback integration test
  for silent loading/presentation updates, selection attempts before reservation
  completion and quantity intent.
- `pnpm run test:form-interaction-browser`: passed in isolated headless Chrome.
  Uses the real renderer, FormSession, widgets and FormDataLayer with a local
  consent/transport stub. Covers blank email blur, native typing, repeated input,
  ticket add/remove, nested radio clear, calendar selection, silent date/draft
  restoration, synthetic events and consent/no replay.
- `pnpm run test:measurement-browser`: all four scenario groups passed.

The new browser regression is part of the canonical web-startup shell gate.
No changes to the other worktree.

## Complete release verification

The complete gates exposed stale fixtures and three existing backend defects.
Tests retain their cases and assertions against the current canonical contracts;
inventory accepts previously skipped cases executing, but never newly skipped
required cases. Database test files run sequentially while individual race tests
retain simultaneous SQL connections.

The image integration suite now uses guarded disposable local Auth/PostgREST,
the actual workerd Worker, R2, native Images processing and rate limiting.
Only the Cloudflare global purge transport is replaced with local Cache API
invalidation. It no longer requires a remote Worker or silently skips cases.

Backend forwards restore the existing authenticated ticket-batch command ACL,
rebuild reminders only for the reconciled payment, and allocate one new email
version when an in-place Fakturoid acceptance is aborted. The abort replay stays
idempotent and old confirmation intents remain immutable.

Verified so far on the final relevant inputs:

- SQL: 393/393 passed; focused payment/reminder/recovery regressions: 15/15.
- Web: canonical `pnpm test` executed all 1024 tests, no failures or skips.
- Edge Functions: 670 passed, no failures.
- Flutter: 2447 cases, no failures. Two conditional ticketing cases skipped in
  this configuration both executed in the complementary canonical CI variant.
- Core: 259 passed; adapters: 95 passed with an actual fresh local Auth session.
- Ticket raster evidence: 17 generated scenes, its enabled evidence test passed.
- Inventory: all 1219 baseline cases accounted for, 1582 added cases.
- Image Worker: 126 unit tests and 29 integration tests passed, no skips.
- Complete automation passed with all 31 image-migration Python tests executed,
  including the ten explicitly enabled PostgreSQL 17 cases.

The production target was verified read-only through its protected backend route
and public activation metadata: tenant `festapptickets`, canonical organization 3.
There are no configured Unit runtimes and no Unit has measurement enabled, so
there is no existing runtime project to upgrade. Do not create or enable one as
part of this release. Organization permission and organizer GTM remain unchanged.

Integration target is canonical main through PR747 and a clean local checkout of
that merged revision. The backend forwards are committed and tested only against
disposable fixtures. Production migrations, tenant overlay, build and direct
deployment with live probes belong to the later unified release.
