# Execute: Production hardening klientského sync enginu

Work in `<repo-root>`.

Use all applicable repository instructions, beginning with
`docs/architecture/ai_context.md`, and use `verification: standard` as recorded
in the plan.

Implement the entire authoritative plan:

`docs/archive/plans/client-sync-production-hardening-plan-2026-08-05.md`

Read it in full before editing. The target outcome is to keep
`client_sync_v1` as the one canonical protocol while adding real five-second
edge caching, five-second publication wake-up, complete event live projections,
fast failed-claim recovery, bounded local generations/blob storage, a single
safe occasion enable/disable lifecycle, bounded artifact/receipt retention,
read-only drift gates, and accurate operational documentation.

Completion requires both the target behavior and every deletion/retention proof
in the plan: no per-poll R2 read on cache hits, no unmanaged `loop.ts` runtime,
no event projection drift, no ordinary writer that can change the activation
flag, no stale public head after successful disable, no reusable expired command
ID, no unbounded local generations/blobs or server artefact/response history,
and no stale deployment-status instructions. Do not introduce protocol V2,
deltas, Realtime, persistent application triggers, client-selected publisher
scope, blanket R2 lifecycle deletion, automatic drift repair, prune-claim state,
pointer regression, or a parallel publisher implementation.

Execute the waves in dependency order. Do not leave placeholders, speculative
fallbacks, compatibility aliases, duplicate business paths, or obsolete status
labels. Never edit an applied migration; create a forward migration newer than
the current baseline cutoff. If current repository/runtime evidence invalidates
a factual premise, update the authoritative plan with the evidence and adapt
the affected wave without silently changing the requested outcome.

Run the targeted Worker, automation and isolated-database checks specified by
each wave, then one full repository validation batch at handoff. Do not start an
independent review or subagent audit unless explicitly requested.

Do not perform production DNS/custom-domain changes, secret/Vault writes,
Worker deploys, database migration/backfill, scheduler activation, 5k load
tests, first R2 deletion, receipt compaction, commit, or push without separate
authority. Retention must remain dry-run/default-off until its stated 7-day or
30-day window and explicit approval are both satisfied.

Keep the module shape narrow: `ClientSyncPublisher.runOnce()` is the sole
publication interface with HTTP/scheduled/manual adapters; `ClientSyncStore`
owns local replacement and eviction internally; the existing cutover tool is
the sole activation lifecycle interface; `ClientSyncRetention.runOnce({apply})`
is internal daily maintenance, not a second publisher. The 5-second cron must
call HTTP only when an indexed dirty-key `EXISTS` succeeds. Drift health is
read-only; known drift is repaired once by the forward migration and future
repairs require an explicit guarded operation. Enforce raw budgets in the
publisher and measure actual compressed/network bytes at the delivery gate.

At handoff, report the canonical cache/publisher/store/lifecycle contracts,
changed writers and projection repair, claim/retry behavior,
retention/tombstone policy, removed legacy artifacts, validation results, and
every exact unapplied production or destructive step.
