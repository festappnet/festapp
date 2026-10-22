# Test reliability and performance - execution result

Date: 2026-10-21. Local implementation and bounded performance investigation complete.

Final client source is exactly canonical main `35e421e27a26f1d4e4dc45016767669e760e4f48`.
The separately authorized release session integrated the qualified frozen patches;
this task created no commit, push, tenant change or production operation.
The original dirty wizard checkout was not modified.

The final complete offline client gate passes with one worker: **1890 semantic
cases, zero failures, one established optional adapter skip**. Architecture and
inventory pass: 1219 retained baseline cases + 671 additions, with 41 explicit
contract revisions. No new skips, retries, weakened assertions or blanket
inventory reset were introduced.

| Lane | Cases | Time | Result |
| --- | ---: | ---: | --- |
| Core | 182 | 6.66 s | PASS |
| Dart adapters | 87 | 13.57 s | PASS, 1 established skip |
| Flutter | 1621 | 191.17 s | PASS, 71 roots |
| Complete client + architecture/inventory | 1890 | 204.85 s | PASS |

Peak sampled owned-process RSS was 1.26 GiB. RSS sums can count shared pages
more than once. Source/lock/SDK fingerprint, host load, lane/loading/body times
and every earlier failed observation are preserved in [the receipt](results.json).
Dependencies were resolved before measurement; no backend credentials were used.

The final source fingerprint is `2b656793fd1ee0828daa917b2a310662d408d275b1cbf6de60cbaa17a0b664e0`.
After discarding the experiment, it matches the passing canonical baseline
byte-for-byte. Its passing receipt is reused for those unchanged inputs rather
than represented as another execution.

The retained repairs include request-bound command-response fixtures; a real
disposable Information command journal; explicit per-scenario capability
projections; corrected UI/font fixtures and exactly-once registration; preserved
sign-in-code exchange; and a required ProductGridGuard supplied by ProductsTab.
The latter keeps the real ExceptionHandler.guardVoid, live permission refresh
and rethrow. Denied save/delete caller tests prove one mutation, one projection
refresh and retained product state. The targeted production analyzer reports
no issues. Creation/revocation passes with the optional setup flag both disabled
and enabled through a separate targeted invocation.

Runner contracts pass: **19 Python + 5 Node tests**, covering one-worker policy,
failed/incomplete lanes, continued execution, cwd ownership, structured monotonic
timings, literal argv, secret-free wrapper output, and timeout/interrupt cleanup
of owned descendants. The selected web timeout remains 60 seconds. Required
scripts use their interpreter; no selected missing prerequisite silently passes.

The six affected existing shared groups were checked in reverse order. The
only cache-order finding was fixed using dedicated real font fixture faces and
exact byte hashes. Its Czech group passes 282 cases in normal and reverse order
(21.02 / 21.46 s); the other five groups pass their unchanged reversed checks.
No vendor snapshot or private SDK cache was patched/reset. Rendered camera
inspection remains a localized test coupling, not a new public SDK API.

**No stable speedup is claimed; the 15-20% performance target is unmet.**
Earlier repaired-source and final canonical observations span 175.63-204.85 s;
they include source/cache differences and shared-host variability. The failed
initial and intermediate runs are not passing optimization baselines.

A two-root consolidation experiment targeted 12 cases. Their measured loading
was only 2055 ms, about 1% of the complete run. Sharing introduced timezone
lifecycle coupling and exposed one initialization error in the experimental
normal run. After correcting the public initialization guard, the affected
Czech group passes normal/reverse (289 cases, 26.89 / 25.27 s), but this small
potential gain does not justify retaining the coupling. **Both root moves were
reverted**. The main remaining costs are already grouped rendering/application
suites and deliberately isolated identity/binding environments. No broad
refactor or additional benchmark loop was forced to reach a target.

Raw JSONL, logs, immutable intake patches, hashes and the declined experiment
are in [.codex-artifacts](../../../.codex-artifacts/test-reliability-20261021/).
The archived [plan](test-reliability-performance-plan-2026-10-21.md) records
source drift, origin/retirement evidence and the completed gates; the
[execution prompt](test-reliability-performance-EXECUTION-PROMPT-2026-10-21.md)
is historical. This is offline client/runner evidence, not certification of
live font admission, authentication deployment, SQL speed or worker speed.
