# Local integration rehearsal

The recorded source base is `eab22c17db361362fc7fd1c5aa84a09dd4c427eb`. Use the prepared integration worktree and its frozen migration hashes in `fresh-replay.json`.

`rehearse-executed.sh` is the exact executed task script. It resets ONLY the two task-owned Supabase projects named in the accompanying TOML files, on loopback ports 61232 and 61242. It never resets the shared 55432 harness. Do not run it over another task's instance.

Restore its inputs before reproduction:

```sh
mkdir -p /tmp/festapp-stripe-readiness-db/supabase /tmp/festapp-stripe-upgrade-db/supabase /tmp/festapp-stripe-main-eab22c17
cp docs/plans/stripe-client-owned/integration-evidence/fresh-supabase.toml /tmp/festapp-stripe-readiness-db/supabase/config.toml
cp docs/plans/stripe-client-owned/integration-evidence/upgrade-supabase.toml /tmp/festapp-stripe-upgrade-db/supabase/config.toml
cp docs/plans/stripe-client-owned/integration-evidence/bank-upgrade-fixture.sql /tmp/stripe-upgrade-bank-fixture.sql
git archive eab22c17db361362fc7fd1c5aa84a09dd4c427eb | tar -x -C /tmp/festapp-stripe-main-eab22c17
bash docs/plans/stripe-client-owned/integration-evidence/rehearse-executed.sh fresh
bash docs/plans/stripe-client-owned/integration-evidence/rehearse-executed.sh upgrade
```

The script uses the original repository's Git object store only to materialize pinned historical migration SQL. Bootstrap provider extensions and the baseline as `postgres`; execute the real forward migration runner as the extension-owning `supabase_admin`. New private Stripe owners are explicitly `postgres`; existing shared function owners remain intact. `cron.launch_active_jobs=off` is set before application SQL. Load `automation/local_db/reference_tenants.sql` before guarded forward migrations. Seed only with an explicit local service-role claim.

Read both catalogs with `readback.sql`; their JSON results must match. The upgrade fixture must exist before any Stripe table, and its original order/payment JSON must remain byte-for-byte equal after excluding only the two newly added payment columns. Default new sales and private-table client access remain off.

Run SQL through `web_client/scripts/run_db_tests.js` with an explicit loopback `DATABASE_URL`, using local user `postgres` and `options=-c%20request.jwt.claim.role%3Dservice_role`. `upgradeSql-summary.txt` names the 12-file upgrade selection (Stripe directory and canonical source parity). The fresh selection additionally includes all scanner tests; bank/free/deposit/manual/report regressions; BankSync atomicity, ingestion and ticket delivery.

The held-lock suite accepts `FESTAPP_STRIPE_TEST_CONTAINER=supabase_db_festapp-stripe-upgrade-20261022` and the 61242 `/postgres` URL. It verifies the named local Docker container owns that port, then clones its own disposable database. One Node test executes six real held-lock races. It never targets a remote server or restarts its source.

Use pnpm 11.24.0, the frozen Deno lock, and `fvm flutter test --concurrency=1`. Flutter preview widget fixtures opt in via `showCardPayments: true`; the ordinary build and hidden-route test keep `FESTAPP_STRIPE_PREVIEW=false`. The complete recorded checks and their limits are in `../INTEGRATION-READINESS.md`.
