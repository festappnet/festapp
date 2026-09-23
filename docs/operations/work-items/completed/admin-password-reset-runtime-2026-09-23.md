# Work item: deploy the admin password-reset permission fix

Opened: 2026-09-23
Closed: 2026-09-23
Status: completed
Verification: standard

## Authoritative sources

- Migration: [`../../../../supabase/migrations/20260923120000_scope_admin_password_reset_to_membership.sql`](../../../../supabase/migrations/20260923120000_scope_admin_password_reset_to_membership.sql)
- Canonical function: [`../../../../database/functions/users/reset_user_password.sql`](../../../../database/functions/users/reset_user_password.sql)
- Regression test: [`../../../../database/tests/users/reset_user_password_permissions_test.sql`](../../../../database/tests/users/reset_user_password_permissions_test.sql)
- Protected SQL fallback: [`../../supabase-self-hosted/admin-dashboard-security.md`](../../supabase-self-hosted/admin-dashboard-security.md)

## Outcome

The live self-hosted `reset_user_password` RPC has the reviewed membership and
unit-editor permission rules. A cross-organization administrator can reset a
participating user's password; anonymous callers remain denied. The isolated
regression test covers unit editors, privileged targets and users outside the
unit. No production user password was permanently changed during verification.

## Production receipt

- `main` contains the fix at `3d9123037`; selected tenant
  `prod/festapptickets` contains it via `c1c17f803`.
- `vstupenky.online/backend-activation.json` returned
  `tenant=festapptickets`, `backend=canonical`, `generation=1`.
- The protected `Festapp Production` Studio session returned database
  `festapp_rehearsal_20260909220601`, role `postgres`, and organization `3`
  present. The R2 backup manifest `20260922T024347Z` listed four nonempty
  encrypted artifacts with 30-day retention.
- Before application, migration version `20260923120000` was absent and the
  unit-editor code path was absent. The checked-in migration SHA-256 was
  `8828b0216a1fecf6234a23eca4cb72874041b1af82244f72415d1f326c86572d`.
- The migration body and its `supabase_migrations.schema_migrations` row were
  committed together. Readback returned one ledger row, an exact function-body
  MD5 match to the checked-in migration, `SECURITY DEFINER`,
  `search_path=public, extensions`, and `authenticated` execute permission.
- A SQL canary selected an organization `3` administrator and a participating
  user whose home organization differs. It received success (`200`), verified
  the password hash changed inside the transaction, then received denial
  (`4030`) as an anonymous caller with no second hash change. The canary ran
  through the Access-protected SQL API, returned HTTP `200`, and ended with an
  explicit `ROLLBACK`; SQL SHA-256:
  `4b097b12d5a88ba1d702c7ebfc2db4dd7f5591db890aa7d4647af327dca24ebe`.

## Recovery

The pre-fix function definition is in repository history before `3d9123037`.
The encrypted production backup above remains available for broader recovery.
The canary's password change was rolled back in its transaction.

## Definition of complete

- [x] Live function definition matches the checked-in migration.
- [x] Authorized admin canary succeeds and anonymous caller remains denied.
- [x] This receipt is in `completed/` and the open index is updated.
