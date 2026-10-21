# Repository size cleanup - release PR, 2026-10-21

The release change is based on canonical `main` at
`6f6c5aa5108f0f67e150fb915d4c8bad9612c66c`. The original dirty feature checkout
and unrelated work remain untouched. No production SQL writes or deployment ran.

## Installation and recovery

[`supabase/baseline/manifest.json`](../../supabase/baseline/manifest.json) owns
one schema-only baseline through `20260906140000`, provider prerequisites,
reference seed, covered ledger and checksummed upgrade stages. It replaces the
old August baseline and 111 covered migrations. The obsolete account-deletion
generator is removed as well: 113 tracked deletions, each listed with its original
checksum in the [deletion manifest](repository-size-cleanup-deletions-2026-10-21.tsv).

The historical manifest pins recoverable Git objects, including the original
baseline, migration chain and correctly dated email fixtures. Its source commits
are ancestors of canonical main. Recovery verifies every byte before writing,
refuses conflicts and needs the pinned Git objects locally. CI's database job
therefore checks out full history. Git history is not rewritten.

The local bootstrap, setup launcher, PG17 rehearsal builder, source contracts,
operation inventory and migration-history inventory consume this contract.
`baseline.py upgrade-local` supplies a temporary complete history to Supabase
CLI, preserves recorded versions and runs the order-symbol backfill before its
contract migration. It accepts only a loopback port owned by a local Festapp
Docker database. See [local development](../setup/local_development.md).

Production was inspected only with separately approved read-only queries. All
111 versions through K were recorded; several newer repository versions were
absent from the live ledger. The boundary therefore remains K. Every newer
migration stays active, including current main's blueprint and seating changes.
MapLibre overrides, fonts and active inventories remain intact. The earlier
85 local scratch deletions were untracked/ignored and contribute no PR savings.

## Release regressions resolved

- Remove the duplicated price-wave materialization block from the setup source,
  making it match the already-installed current-main definition.
- Restore the team-invitation password guard overwritten by the operations
  foundation. The new `20261021120000_restore_team_invitation_password_guard.sql`
  forward migration and canonical email source retain the existing advisory/row
  locks and reject team password resets before replay or password mutation.
  Applied historical migrations remain byte-for-byte unchanged.
- Reuse the SQL identity/body parser for overloaded abuse functions. The negative
  test still rejects an unassembled function change.
- Refresh discovered-route/admission metadata and canonical-only adapter evidence.
  A retained installed group helper is covered by the existing release fingerprint
  contract rather than incorrectly claimed as an authored current function.
- Recover the security-containment regression fixture from the immutable
  historical baseline, preserving its pre-retirement definitions.
- Update setup tests to use the current layout/seat-binding contract and the
  current protected-seat error, preserving their permission and atomicity checks.

## Verification

Baseline K parity was established independently on PostgreSQL 15.8 and 17.6:
complete same-major schema dumps, owners/ACL/default ACL, function security,
constraints, indexes, views, policies, triggers, reference rows and sequence
values match. Only separately verified migration bookkeeping is excluded.
The baseline and historical SQL inputs in this PR are byte-identical to those
parity-tested inputs. Matching schema hashes:

- PG15: `8487dcfd9fa28d3da5f2d9da5dfbd26b6e83e591dbb5e73324092a18ce777ca1`.
- PG17: `7d534b8799853f969a10487d1af56e25090ebf88ac002d10981ec90915a9484c`.

The current-main integration was separately tested with disposable PG15/PG17:

- Clean baseline installation plus all current forwards; final ledger has 321
  versions through `20261021120000`.
- Original August baseline plus representative organization/unit/event,
  order/payment, pending email and audit data upgraded to that same ledger;
  identity/audit assertions pass and repeating the upgrade applies zero files.
  The disposable fixture includes the existing reference-tenant prerequisites.
- 13 targeted SQL suites on each major pass, covering source parity, email roles,
  bank sync, seating/assignment boundaries, all six setup suites and price waves.
- 55 Node contract tests, 4 canonical inventory tests, 9 source-parser tests and
  3 historical recovery/safety tests pass. Layout/rehearsal safety, deterministic
  generators, client registry and repository-only preflight pass.

The database-backed registry-transition suite requires its separately named
`festapp-canonical-mutation-pg15` environment on port 55452 and was not run against
these differently named targets. Flutter was not run: client code is unchanged.
Production application of the new guard remains part of the normal release.

## Measured PR delta

Across every changed path, including replacement SQL, tooling, generated
inventories and this documentation: 9,836 -> 9,927 bytes
and 130 -> 131 LF-delimited lines. Net reduction:
**-91 bytes and -1 lines**.
No savings from ignored scratch files or unrelated concurrent work are included.
