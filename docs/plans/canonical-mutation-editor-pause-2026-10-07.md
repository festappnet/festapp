# Shared editor write fence and reopening

State: verified local sources; production not applied. Verification: standard.
Base main: `7ac35f7823d5131a63776122ec66b2df0392dc23`.
The user approved the shared pause across all eleven enabled occasions and asked
to continue. Only the CSM client release is in scope; no other tenant release.

## Canonical boundary

The single self-hosted database shares these table/function ACLs. The release
helper is called directly by all nine typed group, activity draft/publish/discard
and place save/move/delete owners, before mutation receipts or persistence. The
existing domain owners still authorize actors and own atomic writes and replay.
No dispatcher, second kernel, persistent application trigger or tenant ACL is
introduced. Two existing map facades continue to delegate to the same map owner.

A new private operational table holds one paused/minimum-build/organization policy
row. Ordinary and service API roles cannot read or modify it or execute the
internal guard directly. Absent policy is the explicit additive G3 compatibility
phase; activation creates the row and must not remove it to reopen editing.
Malformed headers fail closed. Current CSM metadata means `X-Client-Info` with a
numeric build at least 620 and organization 12. Header metadata is a release
signal, not proof of a signed application binary and not domain authorization.
Spoofing metadata cannot reopen a revoked old writer or direct table DML.
Existing authorized SQL operators, cron and signed service lanes retain their
previous domain authority. Their closure remains separately required for G3.

## Ordered operation

1. Merge reviewed sources to authoritative main. Prepare the CSM overlay with
   the next build 620; the prior prepared 619 lacks measurement metadata. Run
   the main-owned tenant/legal/release checks before any publication.
2. Validate live canonical activation/org/occasion/runtime DB. Capture private
   exact pre-operation table/column/function ACLs, role inheritance, registry,
   gate state and function definitions. Reject overload or source/hash drift.
3. Apply only migration `20261007160000`, its ledger and the approved pause SQL
   atomically. The migration adds the owner guard without changing accepted DTOs.
   The pause creates build-620/org-12 policy, drains in-flight writes under table
   locks and denies ordinary EXECUTE on nine legacy plus nine typed commands,
   including PUBLIC/inherited paths. All eight scoped tables lose ordinary
   INSERT/UPDATE/DELETE/TRUNCATE and column INSERT/UPDATE. A bounded timeout
   rolls back the whole transaction. No function is dropped or registry changed.
4. Verify all 61 owner bodies, exact effective privileges, unchanged SELECT,
   read RPCs, existing explicit service grants, enabled occasions and registry.
   Publish only the verified CSM overlay through existing release gates and
   verify its exact live build, legal pages and activation. Budget the maintenance
   interval around the actual build/deploy run; on failure report paused state
   and resolve forward, without restoring legacy grants.
5. Declare the G3 window prospectively from the actual retained coverage and
   supported release/offline policy; cover the hourly scheduled job and token
   lifetime. Never infer closed service writers, complete platform coverage or
   zero legacy use from missing logs. Current measurement exports stay G3=false.
6. Reopen only after required G3/G4 gates, verified CSM build and external-writer
   closure. The prepared reopening SQL rejects any surviving ordinary legacy or
   direct-DML bypass, requires the exact paused build/org policy and grants only
   the nine typed commands to authenticated. Readiness stays untouched. Other
   occasions remain denied by organization policy until separately approved.
   The scoped registry transition and final function drop require their own
   reviewed exact G4 operation; do not replay migration 20261007130000 on the
   already-ready live registry or restore old split publication.

## Verification

Disposable project `festapp-canonical-mutation-pg15`, loopback port 55452 and
identity marker were checked before destructive runners. Eight SQL suites and
26 Node tests passed without skips, including five two-connection concurrency
cases. The final pause/reopen test additionally proves direct DML and old RPC
negative behavior, inherited-role bypass removal, preservation of readers,
service privileges and function definitions, and rejection of premature/unsafe
reopening. The release test proves old/missing/malformed headers, every one of
the nine owner entry points, current authorized persistence and receipt replay,
revoked actor denial and protected policy writes. Source parity covers 61 owners.
No production fixtures or synthetic business writes were used.

Exact SQL digests and validation log digests are in
`evidence/canonical-mutation-editor-pause-manifest.json`. G3 is not yet satisfied
and this proposal is not final production contraction.
