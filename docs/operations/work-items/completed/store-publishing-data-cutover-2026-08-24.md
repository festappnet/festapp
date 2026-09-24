# Work item: complete store publishing data cutover

Opened: 2026-08-24
Updated: 2026-09-23
Closed: 2026-09-23
Status: completed
Verification: standard

> The August candidate branch and command `1027` were superseded. Neither was
> replayed, and this closure did not publish a new app or alter a store listing.

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

None for the public store-data ownership cutover. Future store releases use
their own current manifest and artifact fixed point.

## Remaining order

No remaining operation in this work item.

## Current blocker

None for the repository ownership boundary. Current private manifest contents
and live store listings were not reread; they are inputs to a future release,
not evidence that public store data remains in Festapp.

## Authority gates

| Action | Required authority | State |
|---|---|---|
| Festapp commit | Explicit user confirmation after staging | granted 2026-08-24 |
| Advance CSM production branch | Fresh current-source fixed point plus deterministic overlay gate | pending |

## Rollback and recovery

- Public deletions remain recoverable from Git and the dated local preservation snapshot.
- Private canonical data remains preserved at the private operational fixed
  point and
  the recoverable Trash copy of the former helper checkout.

## Definition of complete

- [x] Public release entry points require the private manifest or public runtime config.
- [x] No app-specific store asset/metadata directories remain in `main` or any of the 11 active production branch trees.
- [x] Generic cleanup is in canonical `main` and all 11 active tenant branches contain it.
- [x] Superseded remote branches and local worktrees are absent.
- [x] This item is moved to `../completed/` and the index is updated.

## Operational log

| Date | Action | Receipt/evidence | Result |
|---|---|---|---|
| 2026-08-24 | Source asset/config consolidation | source commits `0093ff0`, `fa666c0`, `dc93da5` | 95 files copied byte-identically into the designated private owner |
| 2026-08-24 | Private configuration consolidation | private operational receipt; 7 provisioning tests plus filename/content credential scan | committed; canonical private owner ready |
| 2026-08-24 | Public canonical integration | `main` `478bb68aec187e6cdd65bf2f32d89533b919f537` | generic fail-closed manifest contract and self-contained tenant web build integrated |
| 2026-08-24 | Deterministic tenant regeneration | CSM `d90d42a3d`; Hvezda morska production `7febb2734` | drift/config/absence gates passed; HM temporary candidate removed after production cutover |
| 2026-08-24 | Duplicate cleanup | removed remote `cleanup/store-assets-private-cutover`; former helper checkout moved to macOS Trash | obsolete public/helper paths no longer active |
| 2026-08-24 | Hvezda morska production web | Netlify `6a8c2e9f69d58a00089f6c5a`; commit `7febb2734110add23b84c2d3063924af743db907`; bundle `0.19.84+387` | published; live `kralovna2026` form visibly renders the deposit description |
| 2026-09-23 | Repository-only revalidation | `origin/prod/csmostrava2026` config declares `0.20.14+498` | old CSM candidate and command are superseded; no branch or store mutation |
| 2026-09-23 | Closure check | current `main` release scripts require `FESTAPP_RELEASE_MANIFEST`; 11/11 active branch trees have zero paths under former store-data directories; superseded remote branches and local worktrees absent | Public store-data ownership cutover complete; no new app or store mutation |
