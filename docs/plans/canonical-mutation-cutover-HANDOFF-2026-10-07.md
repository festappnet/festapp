# Canonical mutation cutover - local handoff

Local implementation is complete on `feat/canonical-mutation-cutover-20261007`
in `/Users/miakh/source/festapp-canonical-mutation-cutover`, from fetched main
`eb1d94ac41b085218b8ed618814b9e0727525e62`. Publication was subsequently authorized and is proceeding through the required
main PR review. The wizard
and planning worktrees were not edited or incorporated. After the user selected
CSM Ostrava, read-only G2 inventory was captured from its verified canonical
activation, organization 12 and occasion `csmostrava2026`. No production write,
migration, revocation or deployment has been performed. Shared-code publication
is authorized; production deployment depends on the required main review and
mixed-client gates.

## Owners and callers

Existing group save/delete/import RPCs own complete membership and private place
persistence. Narrow leader reads keep existing permissions; admin list access is
not granted. Group-private move owns group/place clocks. Shared map save/move
invalidates member/companion profiles; map deletion rejects activity links.
`DbGroups`, addToGroup, event leader description editing, private-place save/move,
profile CSV/deletion and game guess call explicit commands regardless of read
sync selection. Import, reception, ticket lifecycle and privacy deletion take
the common occasion prefix before domain locks. Internals no longer depend on
retired group import/occasion-user deletion facades.

Creation intent is retained per new group model, including ambiguous responses.
A changed form first resolves the earlier creation, then saves its changed intent
against confirmed IDs/version. New rows with identical fields are separate
intents. Confirmed metadata does not overwrite newer editor fields.

Activities use one graph DML handler, history writer and receipt lifecycle for
draft/publish/discard. Editor session is one snapshot. Publish atomically stores
live graph/history, clears matching draft and advances clocks/private heads.
UTC and legacy occasion wall times share one normalizer; old stored history is
not rewritten. Global UUID conflicts cannot transfer ownership across occasions.
Undo/restore retain concurrency tokens; queued autosave, publish freeze/drain and
actor/generation checks protect delayed HTML work and replies.

Shared transport retains UUID/immutable payload through ambiguous retries and
single-flights duplicate requests. Activation validates metadata, ignores stale
context/revisions, remembers activated receipt components, preserves pending
search notification across partial repair and requests read refresh after failed
cache repair. Legitimate same-revision local private patches remain supported.

## Removed and prepared artifacts

Removed Dart legacy group/member/private-place DML and helper branches, split
activity publish/autosave orchestration and duplicate activity writer/history
reader source files. Legacy SQL names remain thin named G3 facades over the
same handlers. Ungranted obsolete companion wrappers were removed.

Three additive migrations are prepared: `20261007110000`, `20261007120000` and
`20261007130000`. They preserve issued public contracts and do not activate
readiness/capability. The current inventory/checker models forward sources rather
than relying on the historical expansion INSERT. Its seven scoped registry rows
include private_profile/places; history-only commands have no fake component.
The local baseline lacks historical registry rows, so the scoped migration uses
INSERT/ON CONFLICT. Global registry completeness is not asserted.

Bounded/full-places dry runs are available through `client_sync_cutover.mjs`.
`database/operations/canonical_mutation_contraction.sql` is gated source outside
the migration chain. Canonical target selection verifies activation/profile,
organization/occasion and existing protected access; former cloud selection is
rejected. Full registry activation requires separate scope/evidence/authority
and a canonical publisher origin. Mutation evidence cannot enable it.

## Verification

- 129 unique targeted Flutter tests passed across the owning batches. The final
  group batch has 17 tests and the repaired sync batch 50.
- 15 SQL suites passed on the verified disposable `festapp-canonical-mutation-pg15`
  at loopback 55452. Account deletion and source parity passed again after the
  final ordering adjustment. Clean baseline/forward schema load passed.
- Five real two-connection tests passed: group conflict/private move, leader
  revocation while waiting, activity publish/draft/session/discard races and
  global activity/assignment UUID ownership.
- Twenty Node gate/checker tests, registry checker and local preflight passed.
  Forward/current SQL bodies and all 56 effective owner bodies match.
- Contracted fixture injected PUBLIC column and inherited role DML, denied old
  authenticated/anon DML and old publish RPC, verified canonical writes/reads,
  then rolled back. Additive readiness remains false.
- Targeted analysis found no errors or new warnings. Group and response modules
  are clean; EventPage retains two existing warnings (mutable ID and set literal).
  No build, browser QA or production rehearsal was performed.

Commands, result counts and log hashes are in
`evidence/canonical-mutation-local-validation.json`. The disposable project is
stopped at handoff. Bootstrap it with its task-specific workdir/project/port,
install web_client dependencies, and use the guarded mutation runner with an
explicit DATABASE_URL; the ordinary runner resets sequences globally.

## Exact pending contraction and gates

Production cutover is blocked by G2-G4, not completed. CSM Ostrava is selected;
live activation/schema/function hashes and effective ACL inventory are captured
in `evidence/canonical-mutation-csm-g2-inventory.json`. The deployed database has
180 migrations through `20261006204500`; none of the three new migrations is
applied. All nine legacy writers remain executable by authenticated users;
`activity_history` has effective direct client DML. Eleven enabled occasions
share this database. The hashed deployment proposal is
`evidence/canonical-mutation-csm-rollout-proposal.json`. Remaining evidence includes
deployed source parity after corrections, dated shared-consumer usage, enforced
write minimum builds, complete token/offline observation and separate authority
for the exact shared SQL SHA-256. Restrict affected editor writes during the final
mixed-client transition; distribute the selected client, contract, then reopen
canonical editing. Other tenants are evidence scope, not rollout permission.

These exact legacy writer overloads remain callable until G3/G4:

- `update_activities(bigint,jsonb)`
- `save_activity_history(bigint,jsonb,text,bigint,text)`
- `delete_autosave_history(bigint)`
- `import_user_group_assignments(bigint,jsonb)`
- `import_occasion_users_from_csv(bigint,jsonb,jsonb)`
- `delete_occasion_user_ws(uuid,bigint)`
- `delete_occasion_user(uuid,bigint)`
- `game_guess(bigint,text)`
- `save_place_location(bigint,double precision,double precision)`

Read overload `update_activities(bigint)` and history/editor readers are retained.
Effective INSERT/UPDATE/DELETE/TRUNCATE and column grants remain subject to the
shared contraction proposal on user_group_info, user_groups, activities,
activity_assignments, activity_assignment_places, activity_assignment_events,
activity_history and places. Places requires closure of every shared map consumer.
The dry run excluding places explicitly cannot pass the complete ACL gate.

Named adjacent operational boundaries also require G2/G3 classification:
schedule shifting, occasion duplication/teardown, image HTML repair, raw ticket
and auto import, registration cancellation and account privacy lifecycle.
Their current authorized lifecycle paths are preserved; no whole schedule/map
migration or service bypass approval is inferred. Pending evidence template is
`evidence/canonical-mutation-G2-G4-template.json`, deliberately unable to pass the
gate. Read-only production ACL evidence proves bypasses still exist, not that
contraction is complete. The follow-up target fix uses `api.festapp.net` and the
protected SSH alias with hostname, active runtime and current database checks;
read operations run in a PostgreSQL read-only transaction. Twenty-one targeted
Node tests passed, including four new target regressions. See the ordered
remaining steps in `canonical-mutation-cutover-COMPLETION-2026-10-07.md`.

Publication validation is in evidence/canonical-mutation-publication-validation.json:
1169 Flutter tests, 136 SQL suites, 271 Deno tests and 213 web tests passed.
Two initial full-run failures were resolved: inline HTML save now skips command
cache queuing when read sync is disabled, and worker dependencies were installed.
Worker tests passed (21), with 27 remote integration cases intentionally skipped
on a disposable database. The new active-registry guard passed both owning tests.
Production metadata migration 130000 is deferred: the real 41/41-ready registry
serves eleven enabled occasions and must not be downgraded by this slice.
