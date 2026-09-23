# Work item: deploy the admin password-reset permission fix

Opened: 2026-09-23
Updated: 2026-09-23
Status: blocked
Verification: standard

## Authoritative sources

- Migration: [`../../../../supabase/migrations/20260923120000_scope_admin_password_reset_to_membership.sql`](../../../../supabase/migrations/20260923120000_scope_admin_password_reset_to_membership.sql)
- Canonical function: [`../../../../database/functions/users/reset_user_password.sql`](../../../../database/functions/users/reset_user_password.sql)
- Regression test: [`../../../../database/tests/users/reset_user_password_permissions_test.sql`](../../../../database/tests/users/reset_user_password_permissions_test.sql)

## Outcome

The live self-hosted `reset_user_password` RPC allows an organization admin to
reset a user participating in that organization even when the user's home
organization differs, and allows a unit editor to reset an ordinary user in
their unit. Privileged targets, users outside the unit and anonymous callers
remain denied for the unit-editor path.

## Fixed point

- Repository fix on `main`: `3d9123037`.
- Selected tenant `prod/festapptickets`: merge `c1c17f803` contains the fix.
- Production SQL deployment: unverified and not represented as complete.

## Completed actions

- Reproduced the cross-organization admin denial against the old function in
  isolated PostgreSQL 17.10 (`4030`).
- Applied the new migration in that isolated database; admin, unit-editor,
  privilege-boundary, outside-unit and anonymous cases passed.
- Published the migration, canonical function and regression test directly to
  `main`, then synchronized only the selected tenant branch.
- A read-only SSH probe to the recorded host `46.224.187.4:22` timed out on
  2026-09-23. No production SQL was run.

## Next action

Restore the approved production-host database access path, apply the checked-in
migration to the live self-hosted database, then read back its definition and
run a controlled admin password-reset canary on an authorized test identity.

## Current blocker

The recorded SSH route is unreachable from this workstation. No alternative
approved SQL execution channel has been verified.

## Authority gates

| Action | Required authority | State |
| --- | --- | --- |
| Apply the migration to production | Authorized production database access and a current backup | access unavailable |
| Exercise a password-change canary | Designated test identity and authorized admin session | pending |

## Rollback and recovery

- The migration replaces one function definition; the prior definition remains
  in repository history before `3d9123037` for a targeted rollback.
- Check the current encrypted backup before applying production SQL. No user
  password or production identity was modified during this investigation.

## Definition of complete

- [ ] Live function definition matches the checked-in migration.
- [ ] Authorized admin canary succeeds and a denied-role canary still fails.
- [ ] The item is moved to `../completed/` and the index is updated.

## Operational log

| Date | Action | Result |
| --- | --- | --- |
| 2026-09-23 | Reproduce and publish repository fix | Isolated PostgreSQL tests pass; production SQL access remains unavailable. |
