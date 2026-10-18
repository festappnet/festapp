# Festapp-owned payment references

Revised: 2026-10-18, following the user's explicit architecture correction.
Status: local implementation; no production tenant or deployment authorized.
Verification: standard (payments, database concurrency, public contracts).

## Decision and boundary

Festapp owns allocation, reservation and matching of its payment references.
BankSync remains a bank-fact ingestion/delivery service. The user subsequently
requested withdrawal of its preexisting reservation API as well. Remove that
allocator/runtime/export capability, return HTTP 410 even behind cached responses,
and prepare a forward migration which locks retained historical data and removes
the registry account-edit trigger. Keep bank polling/health identity normalization
and original bank references independent of issuance. Deployments, external
consumer compatibility review, credentials and historical deletion remain separate
operations. The runtime must accept schemas 13 and 14 before applying 0014. The earlier distributed
BankSync allocator/preparation design is superseded, including its remote
reference accounts, accepted-command registry, reference leases, workers and
rematching saga. The abandoned implementation was removed from both worktrees.

Uniqueness covers participating Festapp writers in one database and canonical
receiving account namespace. It does not cover another application, another
Festapp database, independently issued invoices, or deleted historical records
for which no archive is available. Sharing a bank account with such writers
requires an explicit range agreement or a future separately scoped service.

## Implementation

1. Preserve entry working changes. Add a private durable registry, physical-account
   alias bindings, sequence cursors and form high-water marks in Festapp SQL.
   Use canonical IBANs (including normalized Czech local account notation), never
   BankSync connection IDs, as receiving-account identity. Enrollment starts locked.
2. Reserve inside the existing order transaction, after creating the payment row.
   Serialize writes by the receiving-account namespace. Exact, next-free sequence
   and bounded cryptographic random allocation share one permanent namespace.
   Source/policy/hash replay returns the same reservation; changed intent conflicts.
   SQL rollback leaves neither an order nor a standalone reservation. Committed
   reservations survive cancellation, payment/order deletion and alias recreation.
3. Keep existing form sequence settings; preserve a form high-water mark across
   account changes and deletion. Random defaults to 4-10 digits, with 16 candidates
   per length. Sequence never wraps or changes policy on exhaustion.
4. Normal checkout, waitlist acceptance and atomic blueprint replacement already
   converge on the finalizer. Route them through the same allocator. Free and CASH
   flows never reserve. Replace direct manual symbol writes with an authorized,
   receipted exact allocation restricted to unpublished drafts. Supply the local VS
   to Fakturoid for CZK and EUR, assert readback and remove email substitutions.
5. Keep immutable command receipts and require client command identity at the Edge
   boundary. Preserve identities on transport/retryable failures. Project current
   canonical order/reference state on replay so old snapshots cannot renumber or
   resurrect cancelled orders. No new waitlist capability/payload persistence.
6. Ship additive, dormant SQL and a selected-organization activation gate. Legacy
   generation remains only for explicitly unactivated organizations; it is never
   an active-scope fallback. Import reviewed historical references, seed watermarks,
   check shared aliases/writers and activate separately under operator authority.
   Freeze enrolled account identity and revoke allocator/table bypass grants.

## Unchanged owners and scope

There is no remote reference attach window, so the existing matcher sees the
reference at the same commit as the order. No new rematch worker or matcher lock
order is needed. Existing Fakturoid preparation, email queue, waitlist compensation,
pricing, inventory and replacement transaction owners remain. This change does
not claim to solve the independent external-invoice exactly-once problem or
redesign invoice-dependent replacement staging; those require their own scoped
work. Gateway tests reject ambiguous invoice lookup rather than choosing its
first result. No new invoice API, provider sending or real transaction is run.

## Verification and operational gates

Use isolated PostgreSQL fixtures and genuine multi-connection tests for alias
collisions, sequence gaps/upper bound, same-source replay, changed intent, random
bounds, rollback and tombstone retention. Check authorization and frozen identity.
Run checkout/EUR/payment pairing and affected Fakturoid/client regressions, plus
focused Dart analysis if Dart changes remain. Generated migrations come from the
owning assembler; do not rewrite released migrations.

Prepare a parameterized runbook that requires an explicit organization, reviewed
manifest and conflict disposition. Record known-history limitations, nonparticipating
writers, activation/grant inventory and verification results. Commit, push,
deployment, historical production writes and real provider effects remain unauthorized.
