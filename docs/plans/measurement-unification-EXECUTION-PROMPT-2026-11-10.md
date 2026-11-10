# Execute measurement unification

Read `docs/plans/measurement-unification-plan-2026-11-10.md` in full; it is the
authoritative plan. Follow AGENTS.md, CLAUDE.md and architecture context with
standard verification and mandatory canonical release gates.

Integrate #778/#779/#780, establish one private SQL runtime-support owner, bind
runtime deployment verification to actual organization/Unit/backend and an
eligible public-form handshake, and require selected-organization receivers
before web release. Preserve the existing consent lifecycle and fail-closed
behavior. Remove duplicated current predicates and documentary-only ordering.
Do not add placeholders, parallel policy implementations or speculative aliases.

The user authorized implementation, publication, normal PR merges and deployment
to prod/festapptickets only. Routine deployment must be delegated using the
standing deployment instructions. Use local builds and deploy_direct.sh; do not
dispatch GitHub Deploy. No other tenant release, customer enablement, production
fixtures or credential rotation is authorized. Preserve branch protection,
exact-main CI, backend identity, queue drain/restart and tenant drift safeguards.

Update the plan when evidence invalidates a premise. Completion includes the
actual authorized deployment and coherent live probes; report precise blockers
instead of claiming a queued operation is deployed.
