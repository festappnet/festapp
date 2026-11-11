# Order, ticket and history read performance - 2026-11-11

The reported event's orders tab originally took 838-903 ms in three read-only
production database measurements, before transport or rendering. Payment contexts
for its 113 orders took 612 ms in a separate probe. The transaction ledger lacked
a payment lookup index; one scoped lookup scanned 4284 unrelated rows.

The prepared migration `20261111123041_order_read_performance.sql` optimizes only
the shared order/ticket/history read path. Payment information, money buttons,
delivery status, history and current/historical seating remain available.
There is no stale-data cache, deferred payment loading or client change.

## Final local benchmark

The disposable PostgreSQL 15 workload asserts 113 orders, 113 linked tickets,
113 allocated seats, 115 messages and a saved hall plan with 1000 nodes. It also
contains 4284 unrelated ledger movements. Each reader is warmed once, then the
median of five samples is compared within one rolled-back transaction.

The original-source comparison restores the saved original scalar payment,
permission, email and seating readers before applying the complete candidate.
Read indexes are already present for both phases, so their gain is not inflated
by removing them only from the baseline.

| Database reader | Original source | Complete candidate | Reduction |
| --- | --- | --- | --- |
| Orders tab | 122.4 ms | 28.4 ms | 77% |
| Tickets | 123.3 ms | 24.2 ms | 80% |
| Order history | 124.7 ms | 23.9 ms | 81% |

All complete JSON responses matched, excluding the capacity snapshot's intended
`serverTime` clock reading. Synthetic message creation times are made distinct:
the existing history contract orders by time without specifying a tie-breaker.
An explicit benchmark gate requiring at least 50% reduction passed for all three
readers. These are database measurements on synthetic local data, not verified
production latency or browser rendering speed.

The latest email/layout work was also measured separately against the preceding
bulk-payment optimization on the same workload: orders 39.1 -> 29.3 ms (25%),
tickets 38.7 -> 23.9 ms (38%), history 38.0 -> 22.8 ms (40%). These percentages
are incremental; they must not be added to the complete-package percentages.
A slower intermediate layout strategy was replaced before validation.

From `web_client`, compare a marked disposable database with a saved baseline:

```sh
FESTAPP_ORDER_READ_MIN_SPEEDUP=0.5 \
DATABASE_URL=postgresql://postgres:postgres@127.0.0.1:61632/postgres \
  pnpm exec node ../automation/benchmarks/order_reads.mjs \
  --baseline-sql /path/to/saved-original-function-definitions.sql
```

Without a baseline file the benchmark compares the installed database against
the candidate. An already updated database compared to itself cannot reproduce
the original gain. The minimum-speedup gate is opt-in to avoid a timing-dependent
normal CI test. Test fixtures and candidate DDL are always rolled back.

## Implementation

- Payment movements and refund history are aggregated once for selected payments.
  Financial detail readers delegate to the same financial projection. Connector
  facts retain their existing handler and validation boundary.
- Typed payment policy predicates share a batch owner that evaluates distinct
  stored units, occasions and bank accounts once per read. Private capability
  handlers receive these freshly computed flags; a client cannot authorize a
  money command by submitting forged flags. Commands still re-authorize.
- Payment context, pending amounts and stored payment values use one statement
  snapshot. Bank warnings are computed once per distinct account.
- Email delivery events and repair provenance are read in bulk with explicit
  order and message-kind boundaries. Healthy orders skip repair-chain traversal.
  Per-order attention counts and message histories use grouped aggregation.
  The single-order issue API delegates to this same provenance owner.
- Ticket snapshot enrichment resolves selected assignment links in bulk. Shared
  blueprint nodes and table labels are read once per plan and indexed in memory.
  Current assignments still override saved presentation fields; released seats
  retain their historical snapshot. Standing-area, form-transition and occasion
  boundaries are preserved. Enrichment uses the order statement's snapshot.
  Existing narrow scalar seating queries remain available for detail/PDF calls.
- Indexes cover payment movement, order/payment and refund-history lookup.

## Validation and limits

49 distinct targeted SQL tests passed across payment providers, email delivery,
notification email recovery, seating and the generated canonical source contract.
Focused rechecks passed after the last scalar seating adjustment. Coverage includes
mixed currencies/scopes, reservations and refunds, immediate role revocation,
forged flags, unknown orders, repaired/stale deliveries, cyclic or cross-order
repair references, cancelled orders, current/released seats and standing areas.
The real list entrypoints also run with scalar payment, seating or email issue
adapters deliberately blocked inside disposable test transactions, preventing
accidental return to per-order calls.

Consistency checks passed for this migration, payment operations, server security,
immutable seating history and the canonical source generator. A separate older
sale-opening assembler's exact-history comparison is already stale across 11
source sections (10 beyond the email reader changed here); it was not rewritten
or used to regenerate applied history. The previously identified broader
`security/rpc_object_authorization_test.sql` failure in the people access path
also remains outside this optimization.

Production has not been changed. Publication and deployment still require
canonical main, normal affected CI lanes and the exact-base production gates.
