# Canonical mutation contraction - reviewed final operation

Verification: standard. Base: a3a0fff7224d59ddfb2833400e934284071da950.

CSM Ostrava 0.20.136+620 is deployed. The approved shared editor fence is active
across all 11 enabled occasions. Canonical editors remain paused. This change
prepares final contraction; it does not deploy SQL or reopen writes.

## Exact operation

`database/operations/canonical_mutation_contraction.sql` removes nine exact
legacy writer signatures without CASCADE. The `update_activities(bigint)` read
overload remains. It closes effective ordinary table and column DML, including
PUBLIC, inherited roles and TRUNCATE, across the eight scoped tables.

The operation requires an already-ready version-1 registry before any DROP.
It updates seven scoped entries, clears their legacy writer metadata and adds
`private_profile/public.places`. Live inventory has 41 ready rows and six of
these seven entries: the expected result is 42 ready rows. Existing readiness,
all unrelated registry rows and occasion capability flags are preserved.
No global registry activation or historical migration rewrite is included.

Current authoring removes the nine legacy facades, preserving internal owners.
The remaining 53 inventoried SQL owners are covered by generated source parity.
The historical image URL rewrite refuses writes on a canonical mutation target;
read-only inspection remains available. Privileged data repair needs its own
approved operation.

## Verification

- Registry checker: 40 source tables, 9 gated components.
- Generated source contract: 53 current SQL owners.
- Node batch: 28 passed, 0 skipped, including five two-connection concurrency cases.
- Disposable PostgreSQL batch: 8 passed, 0 failed, including contracted schema,
  group/activity commands, adjacent owners, source parity and release fencing.
- Contracted tests cover inherited/PUBLIC column privileges, old RPC absence,
  negative ordinary writes, positive canonical commands and registry preservation.

No production fixtures or synthetic domain writes were run. Wizard work is outside
this worktree. No additional tenant build or rollout is included.

## Pending production gates

G3 requires the complete shared consumer matrix and retained request/SQL audit
coverage. The prospectively declared 13:53-14:53 UTC interval is a lower bound,
not proof: the supported offline/idle policy is still unspecified. Known deployed
Edge sources have no old RPC or scoped direct DML calls; privileged service_role
currently retains old RPC EXECUTE and must not be described as ACL-denied.
Scheduled writers and dynamic call sites require their explicit coverage proof.

G4 requires separate approval of this exact SQL digest and the registry transition.
After G3 and G4, apply the reviewed operation atomically, verify effective ACL,
legacy signature absence, 42 ready registry rows and 53 surviving owners, then
run the existing reviewed editor reopen operation. Reopening permits the nine
typed editor commands only for organization 12 with declared client build >=620.
Other tenants remain outside the approved client rollout.

Rollback is a forward canonical repair or temporary editor pause. Do not restore
old functions or ordinary direct-write grants.
