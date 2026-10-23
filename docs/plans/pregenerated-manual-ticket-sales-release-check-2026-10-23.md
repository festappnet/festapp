# Ticket batch release verification

Verification: release. Scope: canonical main and prod/festapptickets only.
Production deployment is pending; the earlier failed baseline report is superseded by the results below.

| Gate | Result |
| --- | --- |
| Fresh baseline plus every forward migration | PASS, including 20261024020000 and 20261024021000 |
| Complete portable SQL suite | 315 PASS, 0 FAIL |
| Complete Edge Function suite | 590 PASS, 0 FAIL |
| Complete client suite and architecture/inventory | 198 core, 87 adapters, 1859 Flutter cases, 0 FAIL; two existing runner skips |
| Complete web suite | 660 PASS, 0 FAIL, 0 SKIP, including the dedicated scanner concurrency database |
| Automation release suite | PASS; affected canonical/ACL/source contracts rechecked after final SQL edits |
| Image Worker | typecheck PASS; 118 unit tests PASS |
| Real local Worker/private R2 | PASS: unauthorized denied, immutable create, conflict on overwrite, byte-exact read, no delete |
| Real renderer plus R2, full batch | 200 singles; one 100-page A4 PDF, two tickets per sheet; ZIP 200 originals with every digest verified |

The 27 existing remote image integrations intentionally skip localhost databases;
they are not claimed as passing production mutation tests. The live ACL preflight verified the same effective API role matrix for all 77
functions receiving explicit ACLs. Eleven preexisting
owned-environment blueprint acceptance scripts are preserved under
`database/acceptance/` with an explicit manifest, outside portable SQL discovery.
They require owned full-backend fixtures and are not counted as passing here.
The portable suite exercises canonical layout, checkout, financial, permission,
receipt, batch lifecycle and race contracts with rollback fixtures.

Evidence: `/tmp/festapp-batches-fresh-bootstrap2.log`,
`/tmp/festapp-batches-fresh-sql2.log`,
`/private/tmp/festapp-batches-final-client2/summary.json`,
`/tmp/festapp-batches-final-backend.log`,
`/private/tmp/festapp-batches-final-automation/summary.json`,
`/tmp/festapp-batches-final-web3.log`,
`/tmp/festapp-batches-final-contracts.log`,
`/tmp/festapp-batches-worker-final.log`,
`/tmp/festapp-batches-r2-pdf-result.log`.

Before deployment: fetch main/prod again, preserve canonical ancestry and tenant
policy, provision the dedicated private R2 capability, install the verified
44-function bundle, apply exact migration bytes with the ledger atomically,
verify runtime/ACL/readiness, then build locally and deploy directly with the
normal build, drift, PWA, legal and coherent live-version gates.
