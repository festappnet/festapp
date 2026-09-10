# Execute: Recepce, role recepčního a přihlášení přes QR

Work in `<repo-root>`.

Read `AGENTS.md` instructions supplied for this repository and
`docs/architecture/ai_context.md` first. Use `verification: standard` because
the work changes authentication and authorization.

Implement the entire authoritative plan:

`docs/archive/plans/2026-08-05_receptionist_qr_login_plan.md`

Read it in full before editing. The outcome is a default-disabled per-occasion
Reception feature: an explicitly assigned receptionist can create one new
unprivileged occasion user with required name, surname, email and explicit sex,
optionally select one existing standard group and accommodation service, and
issue an opaque revocable QR credential; the login camera exchanges only that
credential for a normal Supabase session. Exact-name matches are shown only as
a bounded masked warning. A receptionist can cancel only their own fresh
registration: domain membership/QR are removed before refresh sessions are
globally revoked.
Completion requires backend feature/permission enforcement, classic and
client-sync projection parity, one shared post-login pipeline, hashed-only QR
storage outside idempotency ledgers, rotation/revocation, safe partial-failure
handling for cancellation, and rejection of UUID/ticket QR at login.

Execute the waves in dependency order. Preserve the existing dirty-worktree
changes, especially the concurrent app-links work in users/auth/translations
and shared Edge files. Do not leave placeholders, parallel create/login
business paths, role escalation fields, compatibility aliases, raw QR logging,
roster-capable duplicate/group endpoints, inventory side effects, or fallback
login by UUID, e-mail, ticket symbol, or password embedded in QR.
If current evidence invalidates a factual premise, update the authoritative
plan with the evidence before adapting the affected wave; do not silently
change the requested outcome.

Use the plan's narrow field and catalog allowlists. Do not claim that Supabase
global sign-out instantly invalidates an already issued access JWT; immediate
occasion protection comes from membership removal. Run only the standard
targeted validation specified by the plan and repository rules. Do not start
an independent review or subagent audit unless explicitly requested.

Do not apply production migrations, deploy Edge Functions, enable the feature
on a live occasion, revoke live sessions, commit, or push without separate
authority. At handoff report the canonical SQL/Edge/Auth contracts, projection
parity, deleted bypasses/duplication, validation results, and exact pending
production steps.
