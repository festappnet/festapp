# CI critical path: plan and implementation

Scope: canonical Festapp CI. Baseline product source is main
`9a8e156ab9c825c9514b27230e2517603a875a5b`. No production release is part of
this change. Keep all eight required jobs, proof provenance/age checks, complete
scenario ownership, 3500 MiB/three-worker admission, two DB slots, exclusive
cluster operations and the single local Flutter task with concurrency one.

## Baseline and success criteria

The exact-source hosted baseline executed all eight complete lanes successfully.
Its first-workflow-created to last-required-job-completed window was **363 s**
(16:30:54-16:36:57 UTC). Wix took 359 s, seat checkout 284 s, ticket delivery
279 s, navigation 206 s. The earlier unchanged-input documentation sample took
37 s; that does not demonstrate faster affected/full execution.

Target materially shorter affected runs without removing scenarios. A tenfold
improvement is a target for narrow changes, not a claim about the full cold suite.
Count preparation, cache transfer/export, cleanup and failed experiments. Compare
actual work, source, runtimes and complete semantic inventories.

## Ordered implementation plan

1. **Correct consumed inputs and runtime dependencies.** Remove broad MCP inputs
   from seven SQL units and the public checkout browser unit that do not import
   MCP application code. Retain the explicit disposable-database guard consumer.
   Separate ticket Deno/core inputs from the Flutter application; retain their
   actual external email/brand/layout/font fixtures. Unknown input paths/tests
   remain conservative. Keep `after` for full-run check order; use existing
   `requires` for real preparation. Always add requirements as scheduler edges
   when independently verified ordering checks are omitted from a partial plan.
2. **Provision selected tools only.** Derive Flutter, SQL and browser preparation
   flags from executed commands/resource claims. Deno-only ticket execution does
   not install Flutter; MCP-only execution does not download browsers. Missing
   local preparation flags default to full setup; invalid flags fail closed.
   Runtime.acquire() prepares and clones its own marked canonical database.
   Reused upgrade/runtime checks still need valid exact-input direct proof.
3. **Reduce compatible Flutter engine starts.** Use existing grouped registration,
   explicit semantic-origin mappings and isolated SDK/font/locale environments.
   Six compatible ticket roots share an engine (22 -> 17 roots), four navigation
   roots share one (13 -> 10, plus the separate define=false engine). Reverse only
   the new outer groups with `FESTAPP_CI_GROUP_ORDER=reverse`; retain legacy nested
   fixture profiles. Preserve all 657 ticket and 228 navigation registrations,
   including their original skip states and multiplicities.
4. **Remove redundant work.** Five MCP PostgreSQL files were run both in the full
   contracts group and in measurement. Remove only the duplicate invocation and
   dependency install; all files remain dynamically discovered in the complete
   grouped suite. Keep the new information assembler with its actual contract
   owner. A CI contract now prevents duplicate per-file SQL MCP execution.
5. **Shorten unavoidable execution.** Evaluate all 2,048 authorization combinations
   in one real authenticated PostgreSQL loop; retain the independent JavaScript
   predicate/capability/historical-envelope assertions and verify the actor role
   on every row. Remove the obsolete next-OTP-window sleep from the production-
   pinned GoTrue fixture. Explicitly reject replay of the verified browser
   challenge and verify a distinct challenge using a current valid OTP. Preserve
   AAL2, separate sessions, browser refresh credentials, provider-verified actor,
   refresh and freshness assertions. No provider policy or MFA clock is changed.
6. **Reduce CMS preparation.** Start four independent preparation workers. Use
   supported wp-env cleanup to remove owned state while retaining runtime images.
   Evaluate preparation caches using transfer-inclusive hosted measurements.
   Reject caches without demonstrated recurring benefit; never cache private CMS
   state, accounts or credentials. Advance browser time through the real 20 s
   iframe renewal interval and still require its actual message. Preserve all
   nine real CMS/backend cases and negative revocation waits.
7. **Validate, publish and measure.** Run targeted canonical mirrors, inventory,
   reverse-order isolation and a real fresh-runtime checkout. Fetch and integrate
   latest main before publication. Require eight exact-source GitHub jobs to pass;
   separately measure cold and warm CMS execution, including cache transfer.
   Record first-cache construction cost. Do not substitute a short reuse run for
   full-suite improvement or dispatch a production build.

## Completed native validation

- Latest main was integrated before validation; its information migration and new
  tests are preserved. Canonical inventory passed.
- The five-lane mirror passed all 31 units, all 283 MCP tests (24 authorization,
  259 contracts, zero skips/failures), all 657/228 Flutter registrations and all
  nine CMS cases: `20261116T175301-b43213742746`.
- Compatible Flutter grouping passed both ordinary and reversed new-outer-group
  order with identical semantic inventories.
- A completely fresh, uniquely marked canonical Runtime ran public seat checkout
  and offline recovery in 14.99 s without the independent upgrade-test units.
  The task-owned database/container/volume/cache were verified and removed.
- Final clean source `889e47575b5714b54e9086f8c1e4999254f94865` passed all 21 image
  and seat units in 109.86 s, complete=true, inputsUnchanged=true, dirty=false:
  `20261116T185230-6b4a8dc3ffd8`. All 283 MCP cases passed with zero skips.
  The real pinned GoTrue case took 964.63 ms, versus earlier 7-29 s samples.
  This is a local measurement, not a hosted total-time claim.
- The authorization-loop paired sample was 16.884 -> 13.391 s (-20.7%) on the
  same disposable database and Node 22.23.4, retaining all 2,048 combinations.

The pinned GoTrue implementation verifies new challenges against current valid
OTPs and rejects verified-challenge reuse:
[GoTrue v2.197.0](https://github.com/supabase/auth/blob/v2.197.0/internal/api/mfa.go#L540).
The fixture now tests that rejection explicitly rather than sleeping until a
new OTP period. Private token output remains only in its parent pipe.

## Rejected experiments and limits

A transitive Dart graph was rejected: real router imports and dynamic source-
inspection tests made a mostly-fallback parser an unsafe or ineffective shortcut.
Broader Flutter aggregation failed SDK/cache/font/fallback isolation checks;
those failures narrowed the final groups, never weakened assertions.

A third DB slot was rejected. A 126.72 -> 96.36 s pair initially looked promising,
but another valid run took 125.33 s. The GoTrue case alone varied 25.72 -> 7.45 ->
29.27 s because of its explicit OTP-window sleep. That is not stable evidence of
an admission improvement. One additional exploratory run changed inputs and is
also excluded. The final configuration retains the original two-slot capacity
and all whole-cluster exclusion claims. The actual sleep was removed instead.

## Hosted outcome

The first candidate passed all eight full GitHub lanes on exact source
`c0a26b422dbefe56c3e67751f4c50894e691216b`, but its overall hosted window was
413 s versus the 363 s baseline. Wix was 410 s cold and 429 s on a controlled
same-source warm rerun; installed CMS was 327.0 / 325.6 s. All nine CMS scenarios
passed. The 2.25 GB Docker image cache had a confirmed hit, 29 s restore and
10.79 s initial save, without a recurring total-time benefit. It was removed.
WordPress startup remained 150.5 s warm. An isolated fresh two-version PHPUnit
source preparation probe took 6.974 s locally; this does not isolate the hosted
bottleneck or justify another source-cache implementation. No source cache was
added. Further full-suite gains require profiling the generated WordPress image
build and installed-browser system dependencies on GitHub, not removing cases.

The pinned GoTrue test improved from 31.016 to 6.863 s on GitHub. Image contracts
were 116 -> 85 s; navigation 206 -> 182 s; web startup 177 -> 132 s. Other lanes
regressed or stayed flat, including the hosted authorization batch (35.166 ->
36.570 s), so the local authorization improvement is not a hosted speedup claim.
These are individual samples on shared GitHub runners, not controlled averages.

Partial-run input ownership and tool provisioning now avoid unrelated work; a
new affected-change hosted sample is still needed to quantify that benefit.
After removing the rejected cache, clean source `f92ffc5f6` passed the affected
canonical image + Wix mirror (eight units), complete=true and
inputsUnchanged=true: `20261116T193514-7945f9afa6f2`. All nine installed CMS cases
passed; CMS was 123.2 s and the combined local mirror 155.1 s. Hosted validation
for the final published source remains a separate gate.
