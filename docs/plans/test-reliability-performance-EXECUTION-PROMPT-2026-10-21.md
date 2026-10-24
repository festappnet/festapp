# Execute the reconciled Festapp test plan

Read applicable repository instructions and the entire authoritative plan:
`docs/plans/test-reliability-performance-plan-2026-10-21.md`.

The October 21 audit measured the old dirty wizard worktree, not canonical main.
Start from current main in a task worktree without disturbing other sessions.
Preserve already merged image/form/price/auth/palette and wrapper fixes. In
particular retain sign-in-code exchange behavior and its tests; the initial
password-only repair proposal was withdrawn. Recheck main SHA before starting.

Use standard verification at the plan's sensitive seams. Run one complete
one-worker current-main baseline first; repair only actual remaining failures.
Finish runner concurrency/timing/timeout gaps without reimplementing merged
failure aggregation. Optimize demonstrated loading/body costs while preserving
semantic inventory, intentional retirements and required fixture isolation.
Combine full correctness checks with measurement; do not run full suites per edit.

Completion requires the passing client/discovery/runner gates and honest comparable
performance evidence. Do not claim stable speedup from one run or fewer roots.
Update the authoritative plan when current evidence changes a premise. Keep origin
mappings and reverse-order checks for any grouped suites; no weakened assertions,
new skips, duplicate registration, speculative fallback or blanket inventory reset.

No production operations, tenant changes, merge of the old dirty worktree, commit
or push without separate authority. No independent subagent audit is requested.
Report final source, passing checks, actual timing improvement or exact residual
blocker briefly with links to the evidence.
