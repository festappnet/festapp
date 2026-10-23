# Ticket batch release verification

Verification: release. Scope: canonical main and prod/festapptickets only.
Released 2026-10-23: **0.20.371+868** at https://vstupenky.online.
The earlier failed baseline report is superseded by the results below.

- Application main: `25ca9c3dbe85fac4ee82a1cef08d19134b7a7dd1`.
- Tenant: `eef39e71db71faacde495f9cded8cf05242d5aa5`; previous production
  `be6fec583ea41d4e7102505f0f6182db6b32a370` remains an ancestor.
- Immutable Pages deployment: https://55dc3db9.vstupenkyonline.pages.dev.
- Three consecutive live version/asset/legal probes: PASS.
- Canonical drift, local build and both unchanged PWA cache limits: PASS.
  Core 24,174,445 / 26,214,400 bytes; known 62,877,220 / 62,914,560 bytes.
- Both exact SQL migrations are committed with their original-byte ledger records;
  all 77 effective API role matrices match. Private R2 capability, Functions health
  and the bounded three-service document CPU policy are verified live.
- Backend function/Worker source remains the unchanged ancestor `c47e6edf0`;
  the runtime policy patch is from application main above. Later main changes
  only compact served translation formatting and complete that runtime policy.


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

The release used the local direct Pages deployment path and published only
`prod/festapptickets`; no GitHub production build was dispatched. The live
Worker revision is `136aa32c-f3ef-4221-8495-0471251d6860`. Existing production
data was never used for fixtures or synthetic sales.

Final private receipts, mode 0600:
`/private/tmp/festapp-ticket-batches-release-evidence-20261023/final-release-receipt.json`,
`backend-release-receipt.json`, and `validation.json` alongside it.
The deployed artifact tree SHA-256 is
`a5befaacd8b4732bb4d0441261d4db1b851a5aae23217114697923b0041b0508`.
