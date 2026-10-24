# BankSync integration and bank email intake

BankSync owns bank credentials, polling, recovery windows, authenticated bank
email intake and signed deliveries. Festapp owns account permissions, physical
account mappings, its ledger, payment matching, orders and ticket email intents.
The former Festapp SNS parser and direct bank polling paths are retired.
Their [historical setup](../archive/setup/bank_import-pre-banksync.md) is not an
operating procedure.

## Current boundaries

- `fetch-transactions` is the occasion-editor API adapter requesting a BankSync
  pull; it does not contact a bank directly.
- `bank-sync-manage` handles account control with durable, fenced operation
  intents. `bank-sync-reconcile` recovers incomplete control operations using
  versioned protected keys. Account creation, connection and token setup are
  separate operations; dormant or expired accounts are not implicitly activated.
- `bank-sync-webhook` verifies a bounded raw-body HMAC v2 before
  `public.ingest_bank_sync_transaction` atomically commits inbox identity,
  ledger, existing matcher and receipt. Original bank references and signed
  amounts remain facts; do not synthesize order IDs or deduplicate by amount/VS.
- Matching and manual pairing remain Festapp SQL responsibilities. The paid
  transition atomically enqueues ticket intents and wakes `process-email-queue`
  after commit. The global email gate can defer sending; a webhook receipt is
  not proof of delivered tickets.

Canonical SQL lives in `database/functions/eshop_bank_sync/`. The scoped
migration is assembled by `automation/assemble-bank-sync-migration.py`.
Apply repository migrations and the reviewed Function bundle only through the
canonical backend release procedure described in
[tenant setup](howto.md#database-and-edge-functions) and
[Edge deployment](../backend/edge_functions.md#deployment).

## Account control and migration evidence

New account control uses `bank-sync-manage` and its reconciliation path above.
Activation adopts historical identities under the account lock, verifies the
credential digest and enables only the intended account. Suspension does not
restore a retired writer. These are current invariants, not a requirement to
repeat the original all-account migration.

The [2026-10-04 migration sequence](../operations/banksync/FULL-CUTOVER-2026-10-04.md)
retains the original ordered rollout and retirement gates. The checked-in
production snapshot proves only its named pilot scope and records a blocked
payment check; it does not establish that every account passed the full rollout.
[Account management](../../lib/components/bank_accounts/README.md) explains
permissions and token status. Historical migration state does not authorize
activating a new account or replaying an old delivery.

The [implementation record](../operations/banksync/IMPLEMENTATION-2026-10-04.md)
and [production snapshot](../operations/banksync/PRODUCTION-2026-10-04.md)
describe different dated phases. Read subsequent evidence before interpreting
a recorded timeout or blocked payment as current state. This documentation
refresh performed no new production or bank readback.

## Bank email evidence gate

Receiving bank emails belongs to BankSync, not a Festapp SES/SNS parser.
New intake requires authenticated sender evidence, exact server-owned receiving
addresses and the encrypted spool/storage gates in the implementation record.
Fio/Air Bank email identifiers without proven movement identity remain retained,
quarantined observations. A fixture does not prove automatic payment completion.
Require a real authorized bank email journey and identity evidence before
claiming automatic email payment confirmation. EUR payment activation additionally
requires the [real-bank pilot](../operations/work-items/open/eur-payment-reference-rollout-2026-08-24.md).

## Local verification

Use `supabase/functions/test-coverage.json` for current receiver/control tests and
`database/tests/` for identity, ledger, permission and payment regressions.
[CONTRIBUTING](../../CONTRIBUTING.md) describes isolated test execution.
Live canaries and email sends require their own explicit scope; do not replay
archived parser tests or commands.
