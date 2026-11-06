# Barion sandbox approval and successful payment - 2026-11-06

The shop `Festapp - integrační sandbox` is **Active (sandbox)**. The agent
completed the official sandbox approval flow in the user's main Chrome via
Panerelay. The official [sandbox shop tutorial](https://docs.barion.com/Creating_a_shop)
explicitly describes the sandbox checklist and automatic approval. This is not
live underwriting or proof of a real bank transfer, production invoicing,
marketplace eligibility or legal readiness.

A read-only authenticated API call changed from `401 ShopIsInDraftState` to
`400 NotExistingPaymentId` for a nonexistent ID. The first approved-shop 1 CZK
Start returned `400 NotExistingCurrency`; this wallet initially had only HUF.
A CZK currency account was then created with zero balance. No funds were loaded
or transferred.

## Actual successful test

- Case: `czk-enabled-card-smoke-20261106`.
- Command: `23399c05-88e6-4e11-91a7-f128093614d0`.
- Payment: `30a7fa31dcd9f1118c35001dd8b71cc5`, **1.00 CZK**, sandbox only.
- Start at 12:18:38 UTC returned `Prepared`. Guest checkout used the official
  public sandbox card in a separate isolated headless browser, with a synthetic
  buyer distinct from the merchant. The UI displayed successful payment.
- One callback arrived. It was acknowledged as a hint; authenticated PaymentState
  read at 12:21:27 UTC independently returned **Succeeded**, currency CZK,
  total 1, matching command/payment identity, and `FundingSource: BankCard`.
- Another authenticated read at 12:21:49 UTC retained Succeeded. State contains
  the original `CardPayment` for 1 CZK and a separate `CardProcessingFee` of
  0.01 CZK in Reserved status. That fee must not become another customer payment.
- No order, ticket, SQL ledger, email or application paid transition was written.

Machine-readable redacted evidence and current source hashes:
[barion-approved-payment-evidence.json](barion-approved-payment-evidence.json).
Private intent receipts are retained under
`~/.local/share/festapp/barion-sandbox/`; callback URLs and checkout links are
not published. Temporary tunnel/server and isolated buyer browser were stopped.
The merchant's main Chrome session was preserved.

## Recovery and credential boundary

The original `1f5b1e02-9a01-4eca-9bff-67377ddfe7bd` Start remains unresolved:
its particular status/body was not retained. Later read errors do not prove its
outcome. The approved-shop rejected command
`56026796-f5f9-4efd-83c9-bdae4db8f522` retains its own NotExistingCurrency
receipt. The successful case is explicitly independent of that command, not an
automatic replay or replacement of an uncertain customer order. Named case
reservations are immutable. Only local setup still marked prepared, without a
dispatch timestamp, can resume the same command. No automatic Start retries.

POSKey and verified payee identity remain in the encrypted local macOS login
Keychain. iCloud synchronization is unverified. No login password was captured
or newly saved because the user had already submitted the login form. Existing
credentials were preserved.

## Validation and remaining work

Final targeted checks: **8 Barion protocol tests, 38 Stripe tests and 3 durable
intent tests passed**; Deno check of the operator probe passed. Earlier full
common-engine, Stripe SQL and migration evidence remains in the original and
followup receipts; it was not replaced by this browser test.

This proves the real Barion sandbox protocol happy path, callback and known-ID
readback. The client is not registered as an application PaymentConnector.
Financial movement normalization/SQL integration, external refund and reversal
semantics, lost-response recovery, account capabilities and the complete wave 4/5
acceptance remain unfinished. Unknown idempotency retention and definitive
absence remain closed gates. No production activation or deployment occurred.

## Navazující realizace

Popis neimplementovaného adaptéru výše zachycuje stav při původním smoke testu.
Adaptér, vlastní SQL storage a registrace jsou nyní implementované a skutečné
provider reads prošly společným enginem a SQL ownerem. Aktuální stav a hranice:
[Barion integration result](BARION-INTEGRATION-RESULT-2026-11-06.md).
