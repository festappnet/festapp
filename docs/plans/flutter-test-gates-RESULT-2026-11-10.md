# Flutter test gate consolidation

Source baseline: main `f62ab0124492e96fc157ed857ef71d3bb7087293`, deployed as
0.20.543+1054 before this follow-up. The user authorized unification and release.

## Controlled opportunity probes

All samples retain dependency/browser/compiler/OS caches. Results are local
whole-command comparisons, not hosted or all-eight-job speedup estimates.
Each candidate preserves the original cases, skip states and assertions.

| Scope | Original samples | Candidate samples | Conservative reduction |
|---|---|---|---|
| Seven compatible navigation files, 76 cases | 16.84 / 13.41 s | 8.70 / 8.09 s | 35.1% |
| Two Flutter Chrome files, six cases, original JPEG setup | 33.79 / 33.42 s | 21.06 / 20.83 s | 37.0% |
| Same six cases, one Chrome invocation and exact prepared JPEG | 33.79 / 33.42 s | 16.73 / 17.29 s | 48.3% |

Conservative comparisons use the fastest original and slowest candidate. Both
actual registration orders passed. The JPEG experiment separately reduced the
case body from 4.93 to 0.28 s. All four JPEG probe samples had identical
164675-byte inputs with SHA-256
`b27f650439c804d5870a68434b4f442b0ab937c42d3f19b862128f778549b975`.
Normal/reverse browser runs retained all six original semantic cases.

## Canonical implementation

- `checks.json` assigns the two Flutter browser files to `image-client-browser`
  in `client-contract`, in a single original Flutter invocation. The former
  navigation Chrome command is removed. Hosted input filters follow ownership.
- Navigation uses the existing scoped registration helper for seven compatible
  default-environment files; backend/service roots, other locale environments,
  browser tests and the unsupported-app compile variant remain separate.
- The existing semantic inventory gains frozen original snapshots for 166
  navigation cases and six browser cases. Both mirrors and hosted CI enforce
  them using the existing inventory checker, alongside the ticket inventory.
- The preview fixture is generated reproducibly from the pinned encoder,
  verified by original byte length/SHA-256, and decoded in the browser.
  Routine VM regeneration introduces a separate toolchain invocation, so it
  remains an authoring check rather than mandatory per-run work.
  No production source, test dimensions, assertion or negative observation
  window changes. Ordinary VM upload JPEG cases only took 39-71 ms, so expanding
  fixture replacement there was rejected as low value.

All eight public release jobs and the exact-main-SHA gate remain mandatory.
Final canonical validation and release evidence are recorded in the PR and
protected local release receipt; deployment follows the repository's local
build/direct-upload path for the single selected tenant.

Raw probes are retained under `/Users/miakh/Library/Caches/` in
`festapp-image-preview-probe-20261110`,
`festapp-navigation-session-probe-20261110`, and
`festapp-flutter-browser-probe-20261110`. These precede final CI wiring and
fixture freshness verification; they are not final release receipts.

## Final local validation

Dart format checks and targeted analysis passed. All eight canonical local jobs
passed with unchanged inputs in receipt `20261110T013049-65a9a928ffcb` (189.04 s).
After replacing per-run VM regeneration with browser byte-length/SHA checks,
affected `image-contract` and `client-contract` lanes passed again with unchanged
inputs in receipt `20261110T013737-ac4aea9b6e46`. Final image widgets took 17.8 s
and the six-case browser unit 15.8 s in that functional run; these are observations,
not a controlled full-CI speedup claim. The canonical inventory confirmed 166
navigation cases, six browser cases and 296 ticket cases, including skip states.
The final navigation subset also passed all 76 original cases in reverse order.

No production application implementation or backend schema is changed. The
release is explicitly requested; exact merged-main GitHub gates, tenant drift,
one local build and coherent live probes remain required before completion.
