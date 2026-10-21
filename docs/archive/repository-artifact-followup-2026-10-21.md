# Repository artifact follow-up - 2026-10-21

Local reduction continues the [initial cleanup](generated-evidence-blueprint-reduction-RESULT-2026-10-21.md)
in the same isolated checkout, based on canonical main `f4aa0b6edfa688b03937197d74b0506d2ae81db7`.
Original working copy, runtime behavior and production remain untouched. No commit,
push, deployment, package publication or history rewrite is part of this task.

## Google sign-in

Removed historical component PNGs, generated HTML and dated proofs; normal tests
read no removed file. The 2026-10-01 record reported 304 component screenshots,
no overflow and a 44px minimum web button height. Those were local component
renders, not live navigation. The later rollout historically installed Google
for web/flutter-web on live.festapp.net 0.20.41+525; native stayed disabled.
OIDC/callback reached the existing-account proof dialog, then was cancelled.
No production account mutation, full mutation E2E or physical-device verification
was claimed. [The complete rollout limits remain](../operations/auth/google-sign-in-live-rollout-2026-10-02.md).
This cleanup performs no new authentication/provider or production operation.
New visual/SDK outputs use `FESTAPP_GOOGLE_AUTH_EVIDENCE_DIR`, default
`.codex-artifacts/google-auth/run/`; visual artifacts go under `implementation/`.
The normal Flutter test creates no capture directory unless explicitly exporting.

## Blueprint

Removed dated MCP closure, geometry and typography output bundles, repeated
Flutter JSONL logs, screenshots and manifests. Historical findings and any
unperformed production gates remain in their existing plan/result documents;
links now identify this recovery record instead of a missing current artifact.
Local geometry/SQL/MCP checks and a source archive proof never imply a new
production migration or package publication. Current immutable Dart snapshots,
selected npm archive, SQL fixtures and all regression assertions are retained.

The sole active historical data reader was the text corpus generator. Its complete
4-row independent input projection is now
`test/fixtures/blueprint/text-corpus-input.json`; shaping measurements are not inputs.
Each fontId/text/language/direction value and its order was compared to the pinned
source dump. New engine/Edge/MCP/fresh-migration outputs use
`FESTAPP_BLUEPRINT_EVIDENCE_DIR`, default `.codex-artifacts/blueprint/run/`.
The Edge probe requires an explicit paired engine capture and fails clearly when
it is missing. Existing loopback, fixture-marker and database safeguards remain.

## Demo occasions

Removed dated PNG/PDF render evidence. The recorded six PDFs (ball, concert,
weekend and copies) had no renderer warnings. Active demo layouts, seed assets and
renderer remain. New renders use `FESTAPP_DEMO_EVIDENCE_DIR`, default
`.codex-artifacts/demo-occasions/run/`. This is local rendering evidence only.

## Retired authorization source

Eight one-time builders plus their private transport-decisions input had no
remaining external code/CI/test callers. The canonical SQL catalog, preparation,
benchmark/fixture API, baseline and paired performance runners remain intact.
The retired tools built the completed migration's source inventory, reviewed
transport/domain ledgers, historical receipts and performance summaries. Their
original conclusions and unperformed production gates remain recoverable.
Do not rebuild historical expectations from current runtime output.

| Retired source under `automation/authorization/` | Local bytes removed | Original source SHA-256 |
|---|---:|---|
| `inventory.py` | 8,227 | `d69814c566adc477ef87fcdf6b9d1121915c256eac5f77454f0b3bb25cd94409` |
| `boundary-reviews.py` | 9,821 | `d8e861c6cc33d7f47cf37f5467cfcb4ca5ac9e859f7f1c24f126aebb0ba6c33c` |
| `close-inventory.py` | 12,768 | `3060d06d559d9e4aec26f233933e13ec016c60bdc1baf4d3b3d679f5fbf9d8a5` |
| `contract-evidence.py` | 2,655 | `d7d41c1dff666f7ab34f389f3b77ab3c51568462626b74a13e4e5c07c8919096` |
| `reconcile.py` | 5,921 | `a44a1882cd295c92dc8534d94e6d9a8d461904fef065181d8c33eaf5a27182e9` |
| `resolve-transports.py` | 1,984 | `2055989c324696efe55bdc5a1464c7216fdebd754f64a52b021ed54ba392a552` |
| `summarize-performance.py` | 6,275 | `34681e34b229e2cd050c632702ccbb47c61587fc2c4b4f6471c96fbaa5bc8f49` |
| `receipts.py` | 12,576 | `d167c55ed88c0106a919991262f535b1aceb72c6fa1f20aac425398fa9901d9e` |
| `transport-decisions.json` | 16,170 | `3bebef378bfd0bf682a7c9cb1723f054481951b59578a1f3eadbcf8878c42df5` |

## Independent JSON formatting

Font catalog, client test inventory and email preview JSON
are compact UTF-8 with one trailing newline. Their generators use the same format.
Font/client decoded values, font IDs, family hashes, SQL seeds, historical
migrations and test case membership are unchanged. All 54 email scenario values
and the generated reference HTML are unchanged; only the preview JSON sourceDigest
was refreshed because its serializer source is itself part of that provenance hash.

The operation inventory and its generator remain byte-identical to the implementation
base. Its existing `--check` is stale against current main (1,162 recorded vs 1,178
scanned source files; 371 vs 373 RPC names and 1,073 vs 1,077 SQL definitions).
It was excluded from formatting to preserve its recorded data rather than fold
an unrelated inventory refresh into this reduction. Inventory unit tests still pass.

## Recovery

All original tracked files are recoverable from full revision `f4aa0b6edfa688b03937197d74b0506d2ae81db7`.
The following tree IDs identify complete immutable original directory contents.
Counts include two small untracked explanatory READMEs from the first cleanup;
their recovery notes are folded into this record, and they are not original blobs.

| Removed directory | Local files removed | Local bytes removed | Original Git tree |
|---|---:|---:|---|
| `docs/plans/google-sign-in-reference-2026-10-01` | 318 | 8,257,116 | `2154018bc454dec9e66622c186cb88301a8da6df` |
| `docs/plans/evidence/blueprint-mcp-closure-20261020` | 40 | 5,417,737 | `1223e5f8a203781e39012261c7742dc23f0a4819` |
| `docs/plans/evidence/blueprint-b-20261019` | 56 | 2,383,110 | `264c9304eebd4af06b4611d7ccb35264849f0de8` |
| `docs/plans/evidence/blueprint-typography-20261020` | 50 | 1,994,304 | `3b3e3935d0ebe7b0f1efea1992ee18cb5286b2ce` |
| `docs/plans/demo-occasions-evidence-2026-10-14` | 29 | 2,250,081 | `ff158aedf07d722f1e17ef3732a65e3d42f90529` |

To inspect one original: `git show f4aa0b6edfa688b03937197d74b0506d2ae81db7:<original-path>`.
To recover a whole paired bundle without writing into the repository:

```sh
recovery_dir="$(mktemp -d /tmp/festapp-history.XXXXXX)"
git archive f4aa0b6edfa688b03937197d74b0506d2ae81db7 docs/plans/evidence/blueprint-typography-20261020 | tar -x -C "$recovery_dir"
```

Use the same full revision for a historical script and its captured inputs.
Historical scripts may still name their original dated directories; recover into
an isolated historical checkout when reproducing them. New captures go to ignored
run folders. Full original local `/tmp` logs were never committed; recovered
receipts are dated evidence, not newly executed tests.

## Verification and measured delta

- Node artifact/distribution, operation-inventory and font-catalog contracts:
  **15 passed, 0 failed, 0 skipped**.
- Client-runner/inventory Python contracts: **12 passed**.
- Actual grouped Google Flutter panel root, concurrency 1, `--name google_login_panel`:
  **2 passed**. Normal tests created no capture directory. No shared registration or
  fixture lifecycle changed, so reverse group-order checks were unnecessary.
- Font-catalog `--check` passed; all selected font identities, SQL seeds and family
  hashes remain unchanged. Email generator `--check` passed for **54 scenarios**;
  full scenario values/reference HTML matched the original, with only the intentional
  serializer-source digest update described above.
- Actual web visual preview built under an explicit ignored run folder; no browser
  or server was opened. Actual shared demo renderer produced **4 PDFs**, zero text
  warnings, in its explicit ignored run folder. Historical captures contained six
  PDFs; their historical source is Git, not a claim that this renderer regenerated
  every past artifact.
- The full constructed Blueprint producer document matched the pinned original
  for every row using both producer paths and the same selected font families.
  Historical measurement fields were not substituted with current output.
- TypeScript syntax (five changed producers), Python and JS syntax passed.
  Expanded prevention tests cover all retired trees/ignored run roots and missing
  paired probe input before any Docker/provider operation.
- Active SQL tests, ACL/policy fixtures, database safety gates, immutable dependency
  manifest/receipt and lockfiles are byte-identical to the preceding validated phase.
  Its SQL, parity and build evidence is reused for unchanged inputs. No database,
  live Google, real-provider, browser or production check was performed in this phase.

The pre-existing operation-inventory stale check is the retained limitation above.
An initial demo invocation used too narrow an env allowlist for its existing npm
renderer dependency; the documented local command now permits environment reads
and completed. No environment values were printed. Initial email check required
refreshing the serializer's self-digest; rendered content did not change.

Local logs: `/tmp/festapp-followup-{node,client,flutter,preview,demo,email,generators}.log`.
All owned verification processes exited; no server was started or left running.

Follow-up delta against the already-reduced checkout: **502 files removed,
33 modified, 2 added**. Removed files totaled **20,378,745 bytes**;
three compact JSONs save another **520,170 bytes** before small fixture/documentation
additions. Complete changed-file storage: **24,261,813 -> 3,378,524 bytes**, net
**20,883,289 bytes saved**. Text LF separators: **153,597 -> 5,458**
(**148,139 fewer**); binary screenshot/PDF/archive bytes are not code lines.

Eight one-time Python builders removed **702 LF-delimited lines**; their private
JSON registry removed another **209**. The ninth retired file is that registry,
not another application component. Both counts use the pre-follow-up local snapshot.
These are current-tree bytes, not compressed Git history or clone-size savings.

The later [tooling cleanup](repository-tooling-cleanup-2026-10-21.md) retired
the remaining one-time Blueprint diagnostics. Checks and measurements above
describe this earlier phase; active corpus generation remains independent.
