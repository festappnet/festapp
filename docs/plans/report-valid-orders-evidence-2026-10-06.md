# Valid-only occasion report

- Source main: 7437904ed710be4d0a1ae75bb1eeaefbf4446cc5 (PR #328).
- Default valid-only view with an include-cancelled switch; counts, states, order history and client text/export select the same snapshot. Payment ledger remains complete.
- Additive RPC projection preserves existing response fields and authorization. Tickets require a non-cancelled state and a non-cancelled parent; null/future states remain visible.
- Flutter: 23 report tests passed. Existing single-currency fixture updated to keep its valid timeline consistent.
- SQL: report metrics and tenant isolation tests passed on disposable local database report_valid_20261006. Covered partially cancelled tickets, cancelled parent orders, deduplication and history totals. Local baseline required historical symbol backfill before contract migration; no test fixtures executed in production. Disposable database removed.
- Migration 20261006201500 deployed atomically with migration ledger and schema notification. SHA256 2e70fd73316525f5cd31e1596cf7c2beebe6f530b1b81fb1ede4ddd683d95760. Previous live function body matched canonical base; backup retained at /var/lib/festapp-rehearsal-evidence/report-valid-20261006.
- Read-only live report check for the user's organization 3 occasion: 3 valid / 4 all orders and 3 valid / 4 all tickets.
- Tenant release efcf432705f9d933b2261b870210685c44b43a31, version 0.20.128+612; canonical drift check passed.
- Deployment succeeded: https://github.com/festappnet/festapp/actions/runs/37509355272 . Public coherent-version verification passed for 0.20.128+612.
