# Existing-admission seating implementation - local execution evidence

Date: 2026-11-01
Status: Complete and integrated into canonical main. Production unchanged.
Base: `2a2f66af6ce91616810eed35d19c96f728a550f8` with preserved unrelated working-tree changes.

Organizer-managed seating is a complete operating mode. Existing admissions can
be assigned, moved or explicitly released without changing purchased snapshots,
order/item/ticket identity, QR, payment or waitlist state. Optional public selection
uses a separate whole-cohort preview and atomic publication. Participant credentials,
routes and automatic assignment are absent.

| Wave | Implementation and evidence |
|---|---|
| 1 | Configuration history/RLS, typed capabilities, current admission classification, explicit target reader, safe enable/detach, start/resume/cancel, protected disabling/deletion and copy behavior. |
| 2 | Exact mapping preview/commit, explicit source-parent and complete unit locks, existing mutation receipts/quotas, PIC exchange/reconciliation and generic allocation preservation. |
| 3 | Astra medium implemented the persistent summary/worklist, scoped plans, exact review, queue/compatibility states, recovery, Save/Discard/Cancel, responsive canvas/worklist and six localized catalogs. |
| 4 | Optional cohort publication, full current coverage/catalog/capacity fingerprints, preserved schedules, materializer/source-authoring no-bypass guards and normal notification/private-sync completion. |
| 5 | Source-matched forward migration, canonical source/operation inventories, prototype removal and isolated UI-to-real-SQL evidence below. |

Validation uses the existing marked localhost disposable backend, with owned
clones for concurrency/clean-upgrade/browser fixtures. No server rebootstrap,
vendor archive rebuild, production Flutter build, commit, push or deployment.

- SQL: 8 selected files passed: seating transition/assignment/publication,
  form capacity/schema, order seating, blueprint finance and canonical source parity.
  Coverage includes unchanged commercial JSON, unpaid tickets, used/printed
  protection, standing/PIC coverage, ambiguous dual modes, mixed-form atomic
  units, stock exclusion, precise release and stale/direct materializer rejection.
- Concurrency/upgrade: `DATABASE_URL=... pnpm --dir web_client exec node --test
  ../database/tests/blueprint/seating_concurrency.test.mjs`: 10 tests (parent,
  clean predecessor upgrade/source parity and 8 actual two-connection races).
  Races cover competing organizers, cancellation, role revocation after waits,
  scan/use, checkout, layout save, normalized Stripe provider ingestion and partial
  offer acceptance with stable ticket ownership after order split. Provider network
  signature/fetch boundaries are fixture data; actual SQL owners commit effects.
- Flutter: occasion command suite10/10 and final seating suite15/15 passed
  using `fvm flutter test --concurrency=1` and explicit file selection.
  The final selection includes actual review Cancel/Escape, shared draft guard,
  recovery, responsive layout, correct own-commit notices and suppression of
  impossible setup on existing public plans. Targeted analysis across13 UI files
  found no errors/warnings; primary-owned command/navigation files had no issues.
- Browser: Terra used production widgets/controllers and real local PostgREST/SQL
  in isolated muted sessions. Desktop9/9 exact assignments and mobile reload
  retain1 waiting; authoritative readback confirms9 original ticket/item placements,
  purchased price42/title/state unchanged and regular capacity10+waitlist active.
  Optional publication is blocked with waiting; a separate2-admission fixture
  reviewed capacity10->12 and10 available, then published successfully. SQL readback
  confirmed the exact active blueprint, removed capacity/waitlist settings, preserved
  open state and2 placements. Real51-row pagination exercised50+1 pages and keyboard
  search reset the cursor. Actual geometry edits exercised Cancel preserving the
  draft and Discard opening the saved plan. Final mobile and legacy-public-plan
  smoke passed, including no impossible retrofit action without transition rows.
  Astra reviewed desktop/mobile/publication captures. All browser sessions closed.

Task-local visual evidence: `/tmp/seating-nine-desktop.png`,
`/tmp/seating-final-mobile.png`, `/tmp/seating-publication-review.png`,
`/tmp/seating-final-legacy-public.png`. The harness authenticates a synthetic local
principal directly to PostgREST; this does not claim a production login, live card
provider, external font provider or real email-delivery test. Intermittent isolated
browser/daemon hangs were not reproducible in fresh sessions; actual review
Cancel/Escape passed both focused widget and browser checks.

The migration contains 26 canonical SQL sources. Digest:
`6cd453799f9c035d36a14ee626a4f218f723656ae9104eabc9d0db5d82b85909`.
`python3 automation/assemble-seating-transition-migration.py --check` and
`python3 automation/generate_canonical_source_contract.py --check` verify parity.
The SQL parity failure on the initially reused database was due to four missing
pre-existing October31 dependency migrations; those were advanced on the marked
disposable target before the passing final checks. No production target was used.

The prototype dialog, flag, obsolete translation keys/tests, fictitious activation
and automatic unlimited/bounded form attachment are removed from current owners.
The original uncommitted prototype migration is preserved conservatively: its local
ledger was absent, but main has no selected canonical tenant activation assertions,
so no claim of worldwide ledger absence is made. The forward migration supersedes
its definitions. A later authorized backend release must apply final SQL and ledger
dispositions atomically, never expose the prototype as an intermediate release.
The schema2 empty-plan creation correction and unrelated vendor/font/web work remain.

Production migration/deployment and live-tenant verification are separate,
unperformed operations. There is no participant-link release or retrofit onto an
already-public shared target. Used/printed placement changes, ambiguous historical
entitlements and unresolved publication queues retain the specified typed blockers.

Configuration receipts deliberately store aggregate context without private holder
rows; an actual role-revocation replay regression proves a configuration operator
cannot recover formerly visible holders after losing order-read authority.

The source parity, migration/source assembly and `git diff --check` gates passed.
Owned Flutter/PostgREST processes and disposable browser/race databases were cleaned
up after evidence capture. The original marked SQL dependency database is retained.


## Final integration on canonical main

Integration merge: `676bce68c`, joining this feature with the previously unmerged
application-only checkout fix `a8c5a2dd0`. Its base `2a2f66af6` already contains
the font recovery/custom-chair snap and complete occasion-copy changes, plus the
previous payment, form recovery/margins/colors and notification fixes. Existing
squashed changes were not reintroduced from stale feature/release branches.

Three actual regressions were demonstrated through real SQL entrypoints and fixed:

- A different ordinary form could attach a target still managed by another form,
  activating seat sales before publication. Generic form save now rejects that
  target with `MODE_CHANGED`.
- A single item moving between two couch members could masquerade as complete
  unit coverage. Before and after units are checked independently. Retained
  unchanged members are permitted inside a genuinely changed exact batch; an
  entirely unchanged batch is rejected.
- After combining application-only checkout with seating, hiding ticket issuance
  and selecting only a fee could create a seatless admission in active seat mode.
  The active plan now retains its admission requirement. Ordinary application-only
  fee checkout without active seating continues to pass.

Final integrated checks: 9 SQL files passed; 10 clean-upgrade/concurrency tests
passed after the merge; 36 Flutter tests passed across seating, font recovery,
table seating, capability navigation and occasion copy; 3 portable formatting
tests and 5 actual isolated Chrome preference tests passed. Architecture and test
registration, client-sync registry, 5 inventory checks, 5 CI contract tests,
migration/source parity and whitespace checks passed.

The clean-upgrade runner now pins the actual predecessor instead of current HEAD,
so committing the feature cannot silently invalidate its upgrade proof. Its dump
path uses PostgreSQL15-compatible flags for CI. Newly added SQL/race and browser
preference tests are wired into the existing CI contract/local mirror. Missing
registrations from the recent shared changes are completed; the pure number
formatting tests live with their portable owner.

No production migration, tenant branch update, production build or deployment was
performed. These remain operational release steps, outside the requested source
completion and merge. The main working tree is left clean after publication.
