# CI input reuse

Every job in the canonical CI registry is required on the exact release main SHA.
A green job means complete coverage of its current unit inventory. Each unit executed or has independently verified direct execution evidence with identical inputs. Targeted local tests precede
publication. GitHub owns complete authoritative verification. The full local
mirror remains available explicitly for diagnosis and offline work.

## One dependency map

`checks.json` owns job inputs, independent documentation paths, scenario inventory
and the 90-day evidence retention policy. `run.py affected` and `selection.py fingerprint`
use the same `owners()` function. Unknown paths and unregistered tests select
all jobs. Shared contracts have all consumers. Known Flutter package paths include
locks and manifests; unknown packages remain conservative. Git tree entries bind
content, path, mode, additions, removals and renames. Unit inputs live alongside their scripts in the same contract. Units without explicit inputs retain the conservative lane or input-group inputs. Combined jobs retain the original groups. Unit fingerprints include the groups that cover the unit and its setup dependencies. Unknown paths/tests select every unit. `after` orders verification, while optional `requires` names preparation that must execute with a consumer; default preparation closure follows `after`. The selected DAG removes only already verified ordering checks and always keeps
runtime requirements as actual scheduler edges. SQL workspaces call canonical
prepare before cloning, so a behavior test need not rerun independent full-replay
checks whose exact-input execution evidence remains valid. Selected commands and
resource claims control Flutter, SQL and browser provisioning; missing preparation
flags default conservatively and invalid flags fail before execution.

The registry JSON is hashed as a canonical projection of the lane/unit command,
input map, resources, preparation dependencies and relevant registered test paths,
instead of its entire raw blob. Shared policy fields, including SQL group policy,
remain conservative inputs. Adding a registered Flutter test in another lane or
changing an independent sibling's test command no longer invalidates installed
CMS evidence. A changed command, environment dependency, input map, relevant
test inventory or unknown policy field still invalidates the affected proof.
The receipt's complete aggregate and inventory are verified against the policy
at its original source commit, then its directly executed unit fingerprint must
match today's inputs. Executable CI code and every workflow remain protected
by the global trusted definition digest.

The combined server-policy job covers image storage, MCP/auth and web startup.
`image-policy` owns the image worker typecheck and unit suite once. Chromium,
Deno and PyYAML are provisioned only when their consumers execute. All source
startup/WebView scenarios remain in CI;
production builders verify their exact canonical CI source and assembled tenant
artifact instead of repeating that source suite.

## Direct execution evidence

Hosted checkout, database regression and MCP database checks run on independent
runners. Each builds its own disposable database when needed. Cold history and
runtime lifecycle proofs run in the database regression job. The local mirror
shares one owned database runtime and orders the cluster-wide operations before
other SQL units. The Flutter native and browser client checks have independent
hosted runners and retain the single Flutter slot in the local mirror.

MCP PostgreSQL tests use three independent leased databases: the canonical
authorization matrix and two partitions of the remaining contracts. Files
within each group stay serial because fixtures may commit, analyze tables or
replace functions.
The slower contract partition runs alongside the database service regressions
on their existing hosted runner. Both runners prepare the same immutable API
contracts, and `seat-mcp-prepare` verifies the dynamic partition covers every
`*-postgres.test.mjs` file.
The ordinary `test:postgres` command still runs the complete suite. All CI
groups retain the marked-database and paused-delivery guard. Each group claims one
of two database slots. Whole-cluster units reserve both slots.
Payment checks use one slot. Upgrade and Stripe concurrency fixtures acquire
their own marked clones, and the remaining payment checks use the unit's lease.
API generation finishes before all MCP groups. The local mirror also waits for
the server-policy API writer. Backend changes
invalidate MCP proofs; standalone checkout UI changes do not.

The existing immutable receipt includes repository ID, workflow definition digest,
run/job ID and attempt, event, actual checkout SHA/tree, lane input digest,
runner image/architecture, declared tool versions and full scenario inventory.

Host `ImageVersion` remains in the audit receipt, while compatibility compares
the OS family (`ImageOS`), operating system, CPU architecture and every declared
runtime version exactly. Different opaque builds of the same compatible host
image do not invalidate identical source inputs. Missing/malformed image metadata,
a different OS/CPU or different Node/Python/pnpm still requires execution. SDK,
browser and database image pins remain covered by the source and lockfile digests.

Functional CMS and backend units project only known, canonical application
version stamps: the web package's version field, the generated version export
and the HTML build-version assignment where declared. Every other byte, package
dependency/script/exports order, file mode and path stays an input. Unknown
formats fall back to raw bytes. Startup and browser checkout keep raw version
inputs and verify the new generation. The image-health preflight has explicit
image/deploy-contract owners rather than the unknown-path fallback to every lane.
Schema 2 records each unit's input digest, PASS and `executed`/`reused` state. Reused rows retain the original run/attempt/job, source and immutable artifact digest. Only directly executed rows from a complete, clean, unchanged aggregate can supply evidence. Lane-only/schema-1 artifacts never become unit evidence. Local and legacy receipts cannot attest
hosted execution.

The selector independently verifies GitHub repository/run/attempt/job/artifact
bindings, the job's final success and execution step, artifact expiry and GitHub's
SHA-256 digest of the downloaded archive. It reads bounded JSON without extracting
ZIP paths. Receipt claims alone never authorize reuse. Missing/deleted artifacts,
API errors, unknown origins and malformed evidence cause unresolved units to
execute. A completed workflow with a failed sibling can still supply direct
evidence from a successful job. Verification checks that job's current attempt
and receipt in both selection and consumption. A failed or pending matching main
job blocks older evidence only for matching units. An unresolved PR can have an
unknown merge checkout and blocks older evidence for all unresolved units. A completed skipped workflow
whose lane job is confirmed skipped with no steps does not block older evidence.
Units already verified against newer runs retain that evidence. Reuse never turns a reused row into direct execution and never changes the direct job's completion time. Mixed aggregates can supply their executed rows only. `All lane tests executed` marks a full execution; `Some lane tests executed` marks a mixed run; `Lane coverage verified` is emitted only after the canonical runner admits complete coverage. Reuse-only jobs have no execution marker and are ignored before ZIP downloads.

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

When the 20-second lookup budget expires, selection retains only unit proofs
whose complete provenance verification already finished. All unresolved units
and their preparation dependencies execute. A timeout during a unit's own
verification never admits that unit. Selection still walks newest runs first;
the retained proofs are rechecked with fresh GitHub status at consumption.
Timeout before any proof is verified still runs the full lane. This avoids
discarding valid coverage while searching older history for newly changed units.
Run discovery pages newest workflow history while the lookup budget permits.
Freshness is measured from the direct job's completion, including successful
reruns of older workflows. Upload retention uses the same configured limit.
An expired or missing artifact cannot supply evidence. The selector can still
look for older independent evidence if the newer job itself passed.
Changing the trusted selector and upload policy requires a new execution baseline.
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

Wix has quick contracts/build, PHP adapter smoke and an installed Joomla,
Wix and generated HTML unit. The installed WordPress suite has its own required
job. Each installed suite starts only its CMS platforms and browser engines,
using a separate disposable Supabase PostgreSQL instance and the pinned
PostgREST image. PostgreSQL starts through the canonical local runtime's pinned
image and readiness probe. Each fixture removes its container, volume and
bridge after its browser and PostgREST services stop. The fixture's HTTPS transport serves the browser's public
`/rest/v1` requests, and readiness requires the actual anonymous form policy
RPC. Wix's hosted units can run together
within the 5000 MiB admission budget.
The local mirror retains 3500 MiB. The ticket rendering root has its own
required hosted runner and semantic inventory. Delivery and the other ticket
client roots use independent verification with the original fixture boundaries.
Seat domains have separate lease-owned databases; cluster-wide mutations remain
exclusive. The local mirror finishes other Node-version consumers before Wix
reinstalls shared package dependencies. Installed CMS uses digest-pinned official
WordPress and WP-CLI images directly, avoiding wp-env's unused Composer/PHPUnit
image builds. Both configured core/PHP pairs are verified at runtime, with
separate volumes and databases. The two core containers start concurrently.
Their installations run concurrently once MariaDB creates both databases.
The older core release is staged from its SHA-256-pinned archive. WP-CLI
reads that archive offline. All browser binaries come from the Playwright
dependency in the workspace lockfile. Chromium and shared Playwright tools
have one cache by browser version, OS and architecture. WordPress adds a
disjoint cache for Firefox and WebKit. No apt archives travel between runners.
The launch probes check the actual required engines before host package setup.
A repair uses the library names reported by the same Playwright dependency.
If the configured mirror or its package index fails, hosted Ubuntu retries
against the signed official archives for its current release. Package
resolution and installation use the same archive source. On failure the job
reports bounded apt diagnostics. A successful install must pass the launch probes.
Owner labels fence creation and cleanup. Private state is never cached.
Developer wp-env tooling and its dependency tests remain.
Deno reuses dependency downloads keyed by its pin and lockfile, and pnpm caches
include the lockfiles installed by each job. Closing a pull request evicts its
merge-ref caches so unused copies do not displace shared main-branch entries.
Private CMS/database state stays disposable. A measured upstream Docker
image archive cache was removed: even a verified warm hit did not improve the
hosted CMS duration, and transferred a 2.25 GB archive. All nine browser scenarios
remain; the iframe renewal case advances browser time through its real 20-second
interval and requires the actual message. Transfer/restore overhead is included
in hosted measurements.

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
