# Execute: Společníci — capabilities a admin assignment

Work in `<repo-root>`.

Use the repository instructions in `CLAUDE.md` and
`docs/architecture/ai_context.md`. Verification is `standard` because the work
changes authorization, account lifecycle, schema and shared program behavior.

Implement the entire authoritative plan:

`docs/archive/plans/2026-08-05_companions_capabilities_admin_assignment_plan.md`

Read it in full before editing. The outcome is one occasion-level `companions`
feature with independent `allow_user_create` and `allow_admin_assign`
capabilities, occasion-scoped relationships, group-aware admin selection and a
strict separation between deleting a self-created technical account and merely
unassigning an existing participant.

Preserve the current offline-first contract: typed feature policy comes from
cached `occasion_config`; companion ownership/list/group/origin comes only from
the active identity-scoped `private_profile`; relationship changes are full
replacements observed through `projectionEpoch`; identity changes cannot leak a
previous private scope. Lifecycle and attendance writes remain online-only and
must not be queued or optimistically persisted. An admin assignment advances the
owner's private head but must never apply that owner's private payload into the
admin's local identity store.

Keep the UI surfaces separate. Self-create management belongs in Profile and is
gated by `allow_user_create`. Event/Program/My Program offer only attendance for
already-related companions, and their companion action is visible only when the
current owner's active private profile contains at least one companion. Admin
assignment exists only in Admin → Users with the named rights/capability gates.

Completion requires both working canonical behavior and removal (or the
plan's explicitly bounded safe-reject rollout retention) of every global,
occasion-less or generic account-delete path in the deletion ledger. Execute
the waves in dependency order. Do not leave placeholders, duplicate business
implementations, direct relation DML, speculative fallbacks, compatibility
aliases without the named rollout gate, or obsolete version labels.

Preserve all unrelated dirty-worktree changes, especially overlapping edits in
`user_page.dart` and schedule files. Never infer the live Supabase target from
`.env.local`; resolve it from `automation/project.conf` and verify
`FORCE_OCCASION_LINK`.

If current repository or runtime evidence invalidates a factual premise, update
the authoritative plan with the evidence and adapt the affected wave without
silently changing the requested outcome. Run only the targeted standard
validation required by the plan; do not start an independent review or
subagent audit.

Do not perform production migration, deploy, feature enablement, real-user
assignment, App Store operation, commit or push without separate authority. At
handoff report the final feature JSON contract, canonical SQL commands, migrated
data/callers, deleted legacy artifacts, group projection behavior, validation
results and every still-pending operational step.

After separately authorized production rollout, the requested acceptance pair
is owner `9+bujnmi@gmail.com` and existing participant
`9+b.ujnmi@gmail.com` in `csmostrava2026`. Resolve both identities again by exact
email plus occasion membership, show their current groups before confirmation,
and assign only through the canonical admin command—never by direct table DML.
