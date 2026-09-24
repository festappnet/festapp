# Work item: complete store publishing data cutover

Opened: 2026-08-24
Updated: 2026-08-24
Status: blocked
Verification: standard

> Revalidation required (2026-09-10): the recorded candidate branch and
> command `1027` predate later production releases. Do not advance that branch
> or replay the command. Reconcile the remaining outcome against current
> tenant refs and the private release-manifest owner first.

## Authoritative sources

- Architecture: [`../../../architecture/ai_context.md`](../../../architecture/ai_context.md)
- Public implementation: `main` commit `478bb68aec187e6cdd65bf2f32d89533b919f537`
- Private owner: the designated private release-manifest repository; its
  locator and revision are intentionally omitted here

## Outcome

Festapp contains reusable, fail-closed release tooling only. CSM Apple/Google
identity, metadata, screenshots, artwork and operational decisions have exactly
one owner: the private configuration repository.

## Fixed point

- Private repository fixed point: retained in the private operational record.
- Public generic cleanup: `main` at
  `478bb68aec187e6cdd65bf2f32d89533b919f537`.
- CSM canonical candidate: `cutover/csm-after-1027` at
  `d90d42a3d5551cf3871734d6f36cc3967d9025ed`.
- Hvezda morska production: `prod/hvezdamorska` at
  `7febb2734110add23b84c2d3063924af743db907`; Netlify deploy
  `6a8c2e9f69d58a00089f6c5a` is published.

## Completed actions

- Canonical Apple and Google publishing assets are committed byte-identically
  in the private configuration repository after credential-pattern and filename
  scans.
- The private manifest owns both bundle IDs, Android package and release branch;
  `automation/project.conf` in the exact Festapp checkout exclusively owns the
  target version and numeric build.
- Public release consumers now fail closed without the exact generic
  `FESTAPP_RELEASE_MANIFEST` pointer; no public script contains a tenant path.
- Public generic consumers and overlay policy are integrated in `main`.
- CSM and Hvezda morska were regenerated deterministically from their recorded
  canonical `main` SHA; both drift checks, configuration checks and negative
  legacy-path proofs passed.
- Duplicate CSM metadata, screenshots, artwork and app-specific manifests are
  absent from both candidates.
- The superseded public cleanup branch was removed from `origin`; the duplicate
  helper checkout was moved to the macOS Trash after byte-for-byte comparison
  with the private configuration repository.
- Hvezda morska was advanced to its canonical production overlay, passed the
  repaired CI tenant gate and was published by Netlify. The live
  `0.19.84+387` form renders the product-type description below `Záloha`.

## Next action

Wait for production Windows command `1027` to finish, verify its signed AAB
receipt, then advance the CSM production branch to the already verified
`cutover/csm-after-1027` candidate.

## Remaining order

1. Accept only the exact matching `COMPLETE` result for Windows command `1027`
   and verify its artifact receipt.
2. Advance `prod/csmostrava2026` to `d90d42a3d` and run the production-branch
   drift/readback gate.

## Current blocker

The Windows workstation has not yet returned command `1027`; advancing the CSM
branch first would invalidate the requested artifact provenance.

## Authority gates

| Action | Required authority | State |
|---|---|---|
| Festapp commit | Explicit user confirmation after staging | granted 2026-08-24 |
| Advance CSM production branch | Completed Windows command `1027` plus deterministic overlay gate | pending |

## Rollback and recovery

- Public deletions remain recoverable from Git and the dated local preservation snapshot.
- Private canonical data remains preserved at the private operational fixed
  point and
  the recoverable Trash copy of the former helper checkout.

## Definition of complete

- [ ] All release consumers use the private manifest or public runtime config as appropriate.
- [ ] No app-specific store data remains reachable in Festapp HEAD.
- [ ] Cleanup is integrated through canonical main and tenant generation.
- [ ] Superseded worktrees/branches are removed.
- [ ] This item is moved to `../completed/` and the index is updated.

## Operational log

| Date | Action | Receipt/evidence | Result |
|---|---|---|---|
| 2026-08-24 | Source asset/config consolidation | source commits `0093ff0`, `fa666c0`, `dc93da5` | 95 files copied byte-identically into the designated private owner |
| 2026-08-24 | Private configuration consolidation | private operational receipt; 7 provisioning tests plus filename/content credential scan | committed; canonical private owner ready |
| 2026-08-24 | Public canonical integration | `main` `478bb68aec187e6cdd65bf2f32d89533b919f537` | generic fail-closed manifest contract and self-contained tenant web build integrated |
| 2026-08-24 | Deterministic tenant regeneration | CSM `d90d42a3d`; Hvezda morska production `7febb2734` | drift/config/absence gates passed; HM temporary candidate removed after production cutover |
| 2026-08-24 | Duplicate cleanup | removed remote `cleanup/store-assets-private-cutover`; former helper checkout moved to macOS Trash | obsolete public/helper paths no longer active |
| 2026-08-24 | Hvezda morska production web | Netlify `6a8c2e9f69d58a00089f6c5a`; commit `7febb2734110add23b84c2d3063924af743db907`; bundle `0.19.84+387` | published; live `kralovna2026` form visibly renders the deposit description |
