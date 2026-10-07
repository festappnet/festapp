# Canonical mutation cutover - completion sequence

Local G0/G1 and waves 1-4 are complete. Wave 5 has a prepared SQL proposal and
passing local contracted-schema tests; it has **not** been applied to production.
The execution prompt and the user's initial instruction still prohibit production
operations and publication. The user subsequently selected CSM Ostrava and
read-only G2 inventory was captured. This does not supply production usage
evidence or permission to revoke shared access.

## Reviewable change

Working branch: `feat/canonical-mutation-cutover-20261007` in
`/Users/miakh/source/festapp-canonical-mutation-cutover`. Wizard changes stay in
their original worktree. No commit or push has been made.

- Additive migrations: `20261007110000_canonical_group_mutations.sql`,
  `20261007120000_canonical_activity_mutations.sql`, and
  `20261007130000_canonical_mutation_registry.sql`.
- Final shared ACL proposal: `database/operations/canonical_mutation_contraction.sql`.
- Proposal inventory: `evidence/canonical-mutation-contraction-manifest.json`.
- Reviewed SQL SHA-256:
  `136cae6ca89197d5e7651fea693457bd6d987eac589db6fcefac3c51fc5fabe6`.
- Local behavior, concurrency and ACL evidence:
  `evidence/canonical-mutation-local-validation.json` and the handoff.

The final proposal covers eight shared tables including `places` and drops the
nine exact writer signatures listed in the manifest. It preserves read overloads,
canonical commands and internal owners. It neither enables read sync nor marks
the full registry ready. The proposal excluding `places` cannot complete this
cutover.

Regenerate the full proposal offline:

```bash
node automation/release/client_sync_cutover.mjs --mutation-dry-run --include-shared-places
```

## Remaining work, in order

| Step | Concrete action | Exit evidence | Current state |
| --- | --- | --- | --- |
| G2 | Verify CSM Ostrava activation, organization 12, generation 1 and occasion `csmostrava2026` through protected backend access; review source drift and external candidates. | Applied migration list, function hashes, effective table/column/function ACL, enabled occasions, registry and external writer inventory. | Read-only inventory captured; correction parity and external closure pending. |
| Expansion | Review live drift against the three additive migrations and approve their exact apply scope. Apply only the approved corrections. | Updated live function hashes and migration history; compatibility still preserved. | Prepared locally; production apply unapproved. |
| Client distribution | Approve publication/release for that one tenant. Keep affected editor writes restricted across the mixed-client transition. | Selected release/build, distribution evidence and real server-side write restriction. | Publication and write restriction unapproved. |
| G3 | Inventory every consumer of the shared tables, including map writers, PWA caches, mobile and background/service integrations. Observe the complete supported token/offline/scheduled-writer window. | Enforced minimum write builds, contiguous request/audit evidence with zero legacy writes, hashed consumer matrix and resolved adjacent boundaries. | No production observation evidence. |
| G4 | Review the final SQL against fresh G2/G3 evidence and obtain separate authority for its exact hash and shared scope. | Dated evidence and separate authority files accepted by the fail-closed tool. | Template only; not approval. |
| Contraction | Apply the approved proposal atomically through the canonical target tool. | Nine old signatures absent and no effective authenticated/anon table or column DML on all eight tables. | Local negative/positive fixture passed; production apply unapproved. |
| Source cleanup | After confirmed G3/G4 contraction, remove the compatibility facade definitions and retired current inventory labels from authoring sources. Add a forward migration recording the contraction using the repository migration procedure. Preserve applied additive migrations. | Current sources cannot recreate retired writers; internal callers still use canonical owners; source parity and contracted tests pass. | Intentionally deferred until the public contracts may be retired. |
| Reopen and close | Perform read-only postchecks of hashes, effective ACL and genuine canonical receipts/private heads. Reopen approved canonical editing and close the removal ledger. | Production evidence proves closure; no direct grants or split-publish routes restored. | Pending preceding steps. |

For the selected tenant and approved read-only access, the existing read-only entry
point is `node automation/client_sync_preflight.mjs --remote`. Read
`festapp-backend-access` before accessing the protected backend. Target selection
comes from canonical activation in the selected tenant config. The G2 capture
used `origin/prod/csmostrava2026:automation/project.conf` in a private temporary
file with the explicit `configFile` option, preserving main configuration in the
implementation worktree. A compiled
`SUPABASE_URL` is not production authority.

The gated contraction command, **not authorized to run yet**, is:

```bash
node automation/release/client_sync_cutover.mjs --mutation-apply --include-shared-places --evidence=/absolute/path/dated-evidence.json --authority=/absolute/path/separate-authority.json
```

The pending template `evidence/canonical-mutation-G2-G4-template.json` is
deliberately rejected. Do not replace missing observation with boolean approvals
or fabricated hashes. Observation cannot be completed merely by waiting in this
implementation session. Other tenants are shared-consumer evidence scope, not
additional rollout permission.

## Removal ledger closure

Removed locally: legacy Dart group/membership/private-place writers, split
activities publish/autosave/discard callers and duplicate SQL activity writer
sources. One canonical DML owner serves each intent. Current legacy public names
are thin compatibility boundaries over these owners, not second implementations.

Still open: retiring nine issued SQL contracts, effective shared grants,
post-contraction source cleanup and verified production ACL state. These are the
exact reasons the final two completion criteria in the authoritative plan remain
unchecked. Local tests cannot substitute for their production evidence.

## Authorized continuation and deployment correction

The user authorized publication and CSM Ostrava deployment after reviewing the
proposal. GitHub main protection requires one approving PR review, so publication
uses that PR workflow. The real registry has 41/41 ready rows and eleven enabled
occasions; metadata migration 130000 would downgrade shared read capability. It
now rejects that active state before any registry write. Only domain correction
migrations 110000/120000 are candidates for the first approved production step.
The registry transition, mixed-client closure and final shared contraction remain
gated. Current authority and refreshed hashes are in the CSM rollout proposal.
