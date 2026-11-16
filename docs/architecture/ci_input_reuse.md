# CI input reuse

All eight canonical check names remain required on the exact release main SHA.
A green job means complete coverage of its current unit inventory. Each unit executed or has independently verified direct execution evidence with identical inputs. Targeted local tests precede
publication. GitHub owns complete authoritative verification. The full local
mirror remains available explicitly for diagnosis and offline work.

## One dependency map

`checks.json` owns job inputs, independent documentation paths, scenario inventory
and the seven-day reuse limit. `run.py affected` and `selection.py fingerprint`
use the same `owners()` function. Unknown paths and unregistered tests select
all jobs. Shared contracts have all consumers. Known Flutter package paths include
locks and manifests; unknown packages remain conservative. Git tree entries bind
content, path, mode, additions, removals and renames. Unit inputs live alongside their scripts in the same contract. Units without explicit inputs retain the conservative lane inputs. Unknown paths/tests select every unit. `after` orders verification, while optional `requires` names preparation that must execute with a consumer; default preparation closure follows `after`. The selected DAG removes only already verified dependencies.

`image-policy` owns the image worker typecheck and unit suite once. Server policy
retains MCP/auth tests. All source startup/WebView scenarios remain in CI;
production builders verify their exact canonical CI source and assembled tenant
artifact instead of repeating that source suite.

## Direct execution evidence

The existing immutable receipt includes repository ID, workflow definition digest,
run/job ID and attempt, event, actual checkout SHA/tree, lane input digest,
runner image/architecture, declared tool versions and full scenario inventory.
Schema 2 records each unit's input digest, PASS and `executed`/`reused` state. Reused rows retain the original run/attempt/job, source and immutable artifact digest. Only directly executed rows from a complete, clean, unchanged aggregate can supply evidence. Lane-only/schema-1 artifacts never become unit evidence. Local and legacy receipts cannot attest
hosted execution.

The selector independently verifies GitHub repository/run/attempt/job/artifact
bindings, the job's final success and execution step, artifact expiry and GitHub's
SHA-256 digest of the downloaded archive. It reads bounded JSON without extracting
ZIP paths. Receipt claims alone never authorize reuse. Missing/deleted artifacts,
API errors, unknown origins, malformed evidence or a newer unresolved failed or
pending run cause execution. Reuse never turns a reused row into direct execution and never refreshes the original run's seven-day age. Mixed aggregates can supply their executed rows only. `All lane tests executed` marks a full execution; `Some lane tests executed` marks a mixed run; `Lane coverage verified` is emitted only after the canonical runner admits complete coverage. Reuse-only jobs have no execution marker and are ignored before ZIP downloads.

Internal PR evidence can be consumed on subsequent PR updates or main even when
merge, squash or rebase changes commit identities. The actual checkout digest
must match. For PRs the tested commit must be the synthetic merge of the API head
and a canonical main ancestor, with the computed merge tree matching its tree.
This does not infer checkout identity from `run.head_sha`. Forks and changes to
the producer/selector/workflow policy force execution. The protected definitions
must equal current canonical main. The first rollout therefore runs all lanes
and establishes a new baseline; old incomplete receipts are not grandfathered.

Drafts remain deferred. Ready-for-review, reruns, manual dispatch and `merge_group` force
execution. Merge queue support does not activate a queue or change protection.
The job summary links the original execution and input fingerprint. Exact-main
release admission still rejects missing, skipped, pending or failed current jobs.

## Tenant build and upload continuation

All hosting adapters enter `build_web_bundle.sh`, which requires exact-source CI
before compilation. CI owns the full source startup suite. Build-time runtime
manifest checks and final `verify_web_build.mjs` retain tenant/backend identity,
CSP, legal/support, immutable versions and module-entry checks. Flutter commands
use the workstation slot. Direct deployment also rechecks the source gate before
upload and runs its canonical live probe.

The web client owns generated compiler inputs in `pnpm run prepare:build`.
Both its standalone build and the canonical bundle builder run that preparation
before compilation; the bundle builder does so before capturing build inputs.
The cached Vite command is `pnpm run compile`, which only consumes prepared
inputs. Scanner decoder generation belongs to preparation, so a clean checkout
needs no operator bootstrap and does not change inputs during compilation.

After complete artifact verification, the existing `festapp-version.json` gains
a `buildReceipt`. It binds main/tenant SHA, tenant ID/config, target, actual source
and generated bytes, toolchain, flags and all output bytes. The version manifest
is hashed without its receipt field to avoid a circular digest. Inputs are
captured before compilation and compared again at sealing. Already sealed
artifacts cannot be relabelled. Before rebuilding, a sealed predecessor is moved
under a distinct receipt digest in `build/web-artifacts/`; it is never overwritten. `--skip-build` requires this receipt, final bundle
verification and all normal source/preflight/upload gates. Missing or differing
evidence rejects reuse and requires a fresh build; no new bypass flag exists.

Direct release attempts write build/upload/live-probe phases through existing
`telemetry.py` to the CI cache. Hosted receipts retain lane/preparation timings.
Real PR/main promotion and production timing remain separate authorized checks;
local fixtures establish correctness, not a measured production speedup.

## Bounded lookup and CMS preparation

Within a 20-second lookup, immutable trees, fingerprints and validated checkout
bindings are cached. Run/attempt status is fresh; main input mismatches are
rejected before archive downloads. PR evidence always validates the synthetic
merge checkout. Network subprocesses use the remaining budget and kill their
owned process group on timeout. A timeout selects execution, never success.
The consumer rechecks the selection partition and its provenance before running
the DAG. Immutable archives may be retained within the hosted job under their
GitHub SHA-256; the digest is verified again on every read.

Wix has quick contracts/build, PHP adapter smoke and an installed CMS unit.
Seat domains have separate lease-owned databases; cluster-wide mutations remain
exclusive. The local mirror finishes other Node-version consumers before Wix
reinstalls shared package dependencies. CMS uses one frozen WordPress tool
installation within the run, keeping all copied environment state private.
Only pinned browser binaries are cached on GitHub, keyed by OS/architecture,
package/lock/config. System libraries are still installed; no database or CMS
state is restored. Image references and the nine-scenario browser matrix remain
unchanged. Layer archive caching is not added without transfer cost evidence.

The first definition rollout requires full execution. Main/release concurrency
is unchanged. Batch related ready changes before publication and assign one
monitor; queued runs are not a reason to dispatch duplicates. Measurement and
remaining hosted verification are recorded in
[CI efficiency result](../plans/ci-efficiency-result-2026-11-16.md).

The subsequent measured pass starts the independent CMS backend, WordPress,
Joomla and browser installation through three bounded workers, and joins all
startup results before any scenario. Cleanup joins the three owned services
independently. The same nine cases and all three browser engines remain required.
Backend service tests use an ordinary isolated database lease while retaining
the source-generation lock; cluster-changing upgrade tests remain exclusive.
The service unit starts early and the PostgreSQL wildcard suite runs each of
its four previously repeated files once.

CMS fingerprints retain schemas, migrations, shared Function dependencies and
all form code. A separate order Edge handler or unrelated browser script is
owned by quick transport contracts rather than installed CMS preparation.
Pure backend units declare their inputs instead of inheriting every checkout
UI input. The canonical version file has an explicit release-contract owner;
generated pubspec, package and HTML files retain their existing owning checks.
Unknown inputs, changed CI definitions and unregistered tests still run the
conservative complete coverage path.

For a production artifact, use `automation/deploy_direct.sh` end to end. It
exports the selected project configuration before building. A manual
`cloudflare_build.sh` run without those exports can produce different component
fingerprints and correctly fail the later upload receipt check. Do not reseal
that artifact or bypass the mismatch; rebuild in the canonical environment.
