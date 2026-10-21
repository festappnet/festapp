# Local authorization captures and historical replay

Normal policy generation and PostgreSQL regressions use the independent committed
inputs in `database/fixtures/authorization/`; they never read a dated capture tree.

Run `bash automation/authorization/prepare-local.sh` for the dedicated, marker-
verified database. Its connection uses `supabase_admin`, not `postgres`: PostgreSQL
information-schema ACL visibility depends on the querying role. Keep its loopback
61022 port, dedicated marker, disabled cron and paused/fenced email checks intact.
Do not substitute production or the ordinary SQL-test database.

All capture/replay scripts use `FESTAPP_AUTHORIZATION_EVIDENCE_DIR`, defaulting to
`.codex-artifacts/authorization/run/`. Select a distinct ignored folder for each
run; an explicit absolute folder outside the checkout also works. Standalone
`benchmark.mjs` writes `benchmark.json` there unless given an explicit output.
The SQL catalog query remains `catalog.sql`; save deliberately paired before/after
captures into the selected run directory. A current capture is never a historical
baseline.

Historical `baseline.py` requires the original `catalog-before.json`; paired
`compare.mjs`, `concurrent.mjs` and `cold.mjs` require its `baseline.sql` before
connecting. See [immutable recovery and hashes](../../docs/archive/canonical-authorization-evidence-2026-10-20.md).

The one-time source-inventory, boundary-review, reconciliation, ledger/receipt and
performance-summary builders and their private transport-decisions registry were
retired after their migration completed. Recover the original source plus paired
evidence from Git only for deliberate historical reproduction; they are not part
of current checks. Their conclusions, limitations and unapplied production gates
remain in the historical records. The benchmark/fixture exports, connection fences,
raw catalog query, preparation script and SQL projection template remain active.
