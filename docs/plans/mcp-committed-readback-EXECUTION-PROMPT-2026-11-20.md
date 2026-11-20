# Implement confirmed-write recovery in PR #984

Read the repository instructions and the authoritative
`docs/plans/mcp-committed-readback-plan-2026-11-20.md` in full. Use standard
verification. Start at the current head of PR #984 and implement the waves in
order. Confirm that SQL remains the receipt owner, hosted auth retains its
existing revocation behavior, and released v1 JSON remains compatible.
Update the plan if current code invalidates a premise. Finish with the
canonical MCP checks and verify the PR head after publication. A production
rollout or production write requires separate authorization.
