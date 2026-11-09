# Test runtime speedup - implementation and verification

Implementation waves0-7 are published on canonical main. The verified deployed
application source is `0da72ea9f799e1762533c16afd1c7d541f7b368b`, including the
sibling occasion-user fix from `81e00bfdf8905b0144c5eb6caf58d25239a154b5`.
The selected tenant is live at **0.20.542+1053**, with all eight required hosted
checks, build validation and three consecutive coherent live probes passing.
Final numerical/result updates follow as a documentation-only main commit;
they do not change the deployed application source or require another deployment.
The original user checkout and its unrelated work were preserved.

Authoritative performance: corrected seat median102.51 ->45.72 s (2.24x);
Flutter median90.77 ->58.07 s (36%). The seat40s absolute target and the browser
75s combined target remain unmet; the seat >=2x fallback is met. Original,
superseded samples below are explicitly historical and retained for audit.

## Delivered contract

- `automation/local_db/runtime.py` owns pinned provider-compatible PG15/PG17
  initialization, real supported-history replay, content fingerprints, verified
  prefix checkpoints, fenced immutable templates, isolated run databases,
  persisted leases and conservative crash recovery/pruning. Ordinary SQL runs
  download only PostgreSQL. Provider artifacts come from a fresh real CLI
  provider, including real Auth/Storage helpers and password-free role grants.
  Cron is disabled and network workers use an inert empty database.
- The public bootstrap, SQL runner, broad wrapper, payment/seating transports,
  security/abuse proofs and historical email rehearsal use that owner. The email
  rehearsal explicitly requests provider prerequisites before its real populated
  historical upgrade; current behavior templates never replace that predecessor.
  The first-start probe waits for the final PostgreSQL PID 1, avoiding the image's
  temporary initialization server.
- The SQL pool continuously fills available workers, prepares shared assertion,
  scanner and blueprint functions once, and resets each session after every
  file. Notification and shared fixture mutations have declared resource claims.
  The two fixtures that truncate shared tables run exclusively. Actual concurrent
  writers and COMMIT tests remain. A first-attempt failure fails the command;
  diagnostic retry cannot change that verdict.
- Ticket-client uses the existing suite registry: 24 original inputs/two invocations
  become four compatible groups plus eight isolated inputs, with the new main
  email root retained as the thirteenth input in one invocation.
  All 295 current-main semantic cases and skip states are retained. The full 1893-font matrix
  remains; its explicitly expected absent-catalog diagnostics are summarized.
- Browser startup keeps isolated origins, trusted clicks and all negative
  observation windows. A split ESM fixture build preserves dynamic imports and
  chunk CSS loading. CLI round trips and redundant blank-page navigations are
  reduced. Current-main pinned CLI 0.41.2 uses native browser discovery. Its real
  pending iframe gate passed a full candidate run and 12 targeted trials without
  the removed 0.39-specific geometry helper. The first matched control startup
  subsequently failed the same iframe timeout; reliability is not established
  by the toolchain upgrade alone. A failed control is not a speedup baseline.
  Explicit executable-path launch stalled iframe actions on this machine;
  preserve native discovery and trusted actions without assertion/action retries.
- The eight public CI jobs consume one structured unit DAG in `checks.json`.
  Native local mirrors and hosted lanes execute the same scripts. Dependencies,
  worker/RAM/database/browser/Flutter claims and affected-source recommendations
  are explicit. Unknown inputs select all jobs. Failed dependencies are
  INCOMPLETE. The exact-SHA release gate is unchanged.
- Append-only traces and immutable run receipts record toolchains, source
  identity, inventory, attempts, setup/body/waits/cleanup, sampled process-tree
  RSS, separately sampled container memory and host contention. Missing container
  samples are unavailable, never zero-memory evidence.

## Registry prerequisite and parity

The obsolete participant-era waitlist slot registration retained a dangling
`regclass` after table retirement. Both original and minimal-runtime clean
replays reproduced it. The canonical forward source
`database/functions/eshop_waitlist/retired_registry.sql` and matching migration
`20261109180000_retired_waitlist_registry.sql` remove only the exact obsolete
registration. A populated regression checks repeated application and preserves
all unrelated/current registrations. Historical migrations and baseline ledger
were not rewritten.

Expanded PG15 parity passed: schema/ACL/owners, role attributes and memberships,
extensions, migration ledger, sequence values and reference rows are equal;
both sides have zero dangling references and disabled cron. Normalized schema
SHA-256 is `8701b7e0e425afae2b63beab77bc6c99de378ffb960ef67ad544a475a4959947`.
See `main-provider-parity.json` in the evidence directory.

## Inventory and completed measurements

The current-main matched seat workload has 110 SQL executions (109 unique IDs)
over nine groups. This includes the previously omitted delivered-ticket regression
and new main communication-tone/user-creation authorization gates. Added
runner/runtime/registry regressions are separate from the matched workload.

Current-main Flutter control: cold 118.05 s; warm 93.06, 90.77, 86.73 s
(median 90.77 s). Candidate: cold 89.60 s; warm 52.69, 60.87, 58.07 s
(median 58.07 s), a 36.0% warm reduction. All eight runs passed exactly 295
semantic cases with equal skip state and immutable inputs. Reverse order also
passed all 295 cases in 43.08 s. SDK/pub caches stayed warm; cold explicitly
removed test/compiler assets. Global Flutter slot queue time was outside the
measurement and separately recorded. Host process-tree peak RSS and observed
CPU/swap contention are retained per run in `main-flutter/results.json`.
The third warm event profile records 37.79 s of loading windows across the two
control invocations versus 19.06 s in the candidate, and 45.69 versus 37.41 s
of semantic-body windows. These are unions within each invocation, not compiler
CPU measurements; category overlaps are not added to wall time. The slowest
candidate semantic case was real blueprint opening (3.12 s). Full per-invocation
profiles are in `main-flutter/event-profile.json`.

The SQL concurrency matrix below predates main integration and preserves its
original 108-execution scope. It is a tuning experiment, not current-main
whole-suite performance.

| SQL workers | Matched execution time | Sampled host process-tree peak RSS |
|---|---:|---:|
| 2 | 19.08 s | 85.7 MiB |
| 4 | 19.45 s | 172.1 MiB |
| 5 | 28.84 s | See raw result |

All three runs passed every first attempt with immutable inputs. Default is 2.
The first matrix discarded Docker ANSI cursor controls; those zero-sample
container records are unavailable evidence. The corrected sampler has a
regression using the observed stream encoding. A second complete matrix passed
with actual container samples (27-31 per run): 2/4/5 workers took
15.72/14.14/13.75 s, host RSS 95.2/104.0/104.6 MiB and PostgreSQL container
347.0/375.8/432.9 MiB. Default 2 trades two seconds for lower pressure when
independent units overlap. Historical failed diagnostic runs remain preserved.

Current-main browser correctness passed all 306 Node tests with zero skips or
failures and 31 browser reports, including the same 30 form-access reports.
Measurement preserves 194 scenarios. Current-main matched timings are below.

Cache identity includes all transitive literal seed includes, generators,
configuration and validation assertions. A same-name mutation regression checks
both base and prefix keys; dynamic/out-of-repository includes fail explicitly.
Fresh current-main PG15 parity and all nine real runtime contracts passed.

The Joomla/WordPress adapter gate now runs the actual packagers and PHP renderer
in a private copied tree. Its 24 renderer cases passed without modifying tracked
or untracked source inputs. This fixes a real final-mirror source mutation;
generated artifacts remain part of the immutable-source policy.

## Retired paths and preserved boundaries

| Replaced path | Canonical replacement / retained boundary |
|---|---|
| Unconditional CLI stop/start and full replay for behavior tests | Runtime prepare/template/lease; explicit `upgrade` still performs full replay |
| `automation/local_db/supabase/config.toml` and copied variants | Removed; pinned runtime/provider configuration |
| Per-fixture pg_dump/psql restore and owner/schema repair | Runtime-owned clean clone; actual populated predecessor/forward assertions retained |
| Fixed five-file SQL batches and retry-to-green | Work-conserving resource scheduler; first-attempt verdict |
| Repeated public helper DDL and sequence maintenance | Once per group, transaction-local helpers per session |
| Fixed 20 worker no-op loops | Bounded actual readiness over real workers and the exact existing view context |
| Duplicate Flutter CI roots/second invocation | Existing registry plus non-default-discovered CI entrypoints |
| Browser raw-module waterfall/redundant opens | Split fixture chunks and verified isolated startup |
| Hand-maintained workflow command lists | Shared eight-job contract/unit DAG |
| Single overwritten receipt | Unique immutable run directory plus atomic latest pointer |
| Guessed localhost DB / `.env.local` defaults in public test wrappers | Explicit owned lease or deliberately supplied marked local fixture |

Historical security proof fixtures now target the live fail-closed guard and
current typed inventory errors; invalid cross-tenant/resource/context/slot and
capacity rejection assertions remain. Optional null context is checked as a
valid hint, and an invalid explicit context remains rejected. The historical
Auth budget test applies the immutable migration's actual Auth upgrade section,
including legacy counter adoption, rather than adding a legacy fallback back to
the reusable current handler. Production authorization/business SQL is unchanged.

## Evidence and publication boundary

Raw logs, traces, benchmark commands and failure-preserving experiment directories:
`/private/tmp/festapp-runtime-evidence-20261109/`.
The following passing service proofs were completed before main integration;
current-main parity/runtime and final mirror are reported separately.
PG17 security (11 Node server/concurrency cases,
one guarded deployment-driver case, 28 scan/attendance assertions and six SQL
files); historical email populated cutover/readiness; native Auth v2.189.0
password replay, committed shared budget and denial. The abuse wrapper also
retains all 43 SQL and three multi-connection/adoption cases. Historical Auth
adoption is executed from the immutable migration section. Private network
ownership and loopback publication remain; Auth needs a normal owned bridge
for host HTTP access on Docker Desktop/Colima. Role credentials are restored and
only nonce-owned service/network resources are removed, including on failure.

## Corrected comparison and release verification

The authoritative corrected seat comparison is `release1053-seat-summary.json`.
Both variants used their own validated disposable databases. The old control
explicitly received its documented image lifecycle URL; the candidate consumed
only the shared `DATABASE_URL`, verified its project/database lease identity and
ignored a deliberately invalid obsolete alias. All eight first attempts passed,
including both real image Worker cases and the same110SQL executions109unique.
Source input digests stayed unchanged throughout each run.

Control first106.59 s; warm103.78/101.95/102.51 s (median102.51 s).
Candidate first67.43 s; warm45.72/44.90/46.95 s (median45.72 s).
The corrected speedup is2.24x; the40 s target is missed by5.72 s,
while the >=2x fallback is met. Scope remains nine behavior units; canonical
upgrade/runtime and additive safety gates remain separately mandatory.
Host RSS control1716-1728 MiB, candidate1729-1774 MiB; PostgreSQL peaks
205-257 versus286-327 MiB with24-50 actual samples per run. Fresh-project first
runs retain image, pnpm and OS caches; start/clone/release/stop and Node resolution
are included.

Corrected source `0da72ea9f799e1762533c16afd1c7d541f7b368b` passed all eight
required hosted GitHub checks. Their workflows now preserve immutable receipts,
unit logs and timings for seven days, including failed runs. The superseded
comparison below is retained for audit and must not be used as the final result.

## Historical comparison superseded by the corrected release1053 comparison

Correction discovered during release verification: the historical seat runs
below did not prove the image Worker used its allocated database. Its separate
legacy URL fell back to a foreign local port55432, which concealed the missing
runtime binding. The 110 SQL-file executions and Flutter/browser observations
remain recorded, but the nine-unit seat speedup is superseded and replaced by the corrected
comparison above. The Worker now consumes the common `DATABASE_URL`, validates the
active lease identity and has no guessed connection fallback. A real targeted
run passed with the obsolete alias deliberately set to an invalid port.
Corrected release measurements are retained in the release1053 evidence.

| Scope | Control first / warm median | Candidate first / warm median |
|---|---:|---:|
| Flutter, same 295 semantic cases | 118.05 / 90.77 s | 89.60 / 58.07 s |
| Seat, same nine behavior units and 110 SQL executions | 116.03 / 108.07 s | 73.93 / 52.12 s |
| Browser measurement, same 194 scenarios | 33.80 / 33.18 s | 31.97 / 31.65 s |

All eight seat samples passed the same SQL multiset (109 unique IDs); warm
control was 108.07/108.09/105.52 s and candidate 52.12/51.09/52.80 s.
The candidate is 2.07x faster, meeting the fallback target. It misses the
absolute 40 s target by 12.12 s. The final warm profile still chains seat-contract
18.05 s, seat-notifications 16.40 s and seat-browser 7.54 s; earlier stages and
runtime transitions make up the remaining elapsed time. Sampled process-tree
RSS was 1.63-1.71 GiB candidate and 1.65-1.85 GiB control; PostgreSQL peaks were
282-314 MiB versus 203-255 MiB, with 26-54 actual samples per run.

Seat first-run scope is a fresh project/template with existing image, pnpm and
OS caches. It includes Node resolution, preparation, acquisition/release and
cluster stop. The matched benchmark excludes additive registry/runner tests and
separate real upgrade/runtime gates. It is not the full current canonical lane.

Browser candidate startup first was 113.47 s; warm 103.33/107.15/108.23 s
(median107.15 s). Every candidate run retained all 31 reports. Original control
failed its first attempt after 60.17 s at the 1440px iframe validation gate;
that verdict is preserved and supplies no passing startup speedup baseline.
Measurement control warm 32.50/33.18/34.74 s and candidate31.65/32.80/29.69 s
all passed. Combined candidate medians are138.80 s, missing75 s by63.80 s.
Fresh browser sessions and fixture builds occur each run; dependencies, browser
binary, Vite and OS caches remain. These first samples are not cold-cache runs.
Process/CLI startup remains the principal observed browser cost; the historical
profile recorded38 opens44.65 s and413 CLI calls23.11 s. Those profile numbers
predate main integration and are diagnostic context, not a new-main speedup.

Warm owned clone acquisition was1.05/0.69/0.65 s, including release1.20/0.82/0.77 s.
The three explicitly scoped notification SQL files ran end-to-end in
2.18/2.67/2.23 s, including automatic acquisition and cleanup. Both targeted
thresholds are met; these figures are separate from full-suite performance.

## Historical local mirror and exact source boundary

The final all-eight local mirror passed36/36 units and8/8 jobs with
`complete=true`, `inputsUnchanged=true` and zero per-file manifest changes.
Outer elapsed340.12 s; receipt338.92 s includes5.18 s preparation,
333.57 s execution and0.17 s cleanup. Sampled host process-tree peak RSS was
2.52 GiB (2,705,080,320 bytes). Receipt:
`/Users/miakh/Library/Caches/festapp-ci/runs/20261109T193539-edc7a4a13f01/receipt.json`.
Tested HEAD is `e3de2261a0717893b41b8cbfc955f9b47ed46da4`, dirty source input SHA
`c0ff5e89e75f2243b283bbb327614fd48fefe6ef7dbd13a850d7167c06053a94`.

The eleven canonical seat step events, including real upgrade/runtime gates and
resource scheduling waits within the shared all-eight run, span187.02 s. This
span is not comparable with the isolated nine-unit benchmark. No controlled
before/after full-eight total or hosted cold runtime was measured. That earlier receipt covered then-uncommitted local sources; it is historical.
The approved release is published and deployed as recorded below. All task-owned
benchmark runtimes are stopped.

Only this result pair and the authoritative plan receive final numerical
updates after the passing receipt. A separate post-documentation manifest check
must show no functional input changes. The receipt, logs, source patch and
changed source archive are also retained under
`/Users/miakh/Library/Caches/festapp-test-runtime-20261109/`.


The historical local receipt did not attest the later published source.
Release1053 separately passed all eight canonical GitHub checks on its exact
`baseMainSha`; local mirror success was not substituted for that release gate.

## Approved release1053 completed

Published shared source: `0da72ea9f799e1762533c16afd1c7d541f7b368b`, including
sibling occasion-user fix `81e00bfdf8905b0144c5eb6caf58d25239a154b5`.
Tenant `festapptickets` overlay: `9fac6c3e90c9ee99f2a84bd4a4ba9f3f505b54f8`.
Live https://vstupenky.online is **0.20.542+1053**, verified by three consecutive
coherent deployment probes after one local build and the supported direct upload.
All eight required hosted jobs passed the exact source. The build retained306
Node cases and31 real browser reports, all passing. Tenant ancestry, source-owned
drift replay, release manifest and generated build checks passed.

The exact canonical registry migration1800 and its ledger entry committed
atomically after target/backup verification; selector0 and ledger1800/1900 were
verified after deployment. No production fixtures or unrelated backend operations
were run. The one-row protected backup is retained outside the repository.

Sanitized deployment receipt, source readiness and corrected benchmark evidence:
`/Users/miakh/Library/Caches/festapp-test-runtime-20261109/release-1053/`.
The final numerical/result notes were published on main after release as a
documentation-only change. They do not change the immutable deployed source
or require another release.
