# Barion protocol research - 2026-11-06

Protocol research; subsequent sandbox validation is recorded separately. Sandbox API base is https://api.test.barion.com. Shop credentials and payee must be from sandbox.

- `POST /v2/Payment/Start`: documented basic immediate body has `POSKey`, `PaymentType: "Immediate"`, unique `PaymentRequestId`, `GuestCheckOut: true`, `FundingSources: ["All"]`, `Currency`, `RedirectUrl`, `CallbackUrl`, `Locale`, and `Transactions` with at least one `{POSTransactionId, Payee, Total, Items}`. Payee is valid wallet email. Item example uses `Name`, `Description`, `Quantity`, `Unit`, `UnitPrice`, `ItemTotal`, `SKU`. Amounts are decimal major units; transaction precision documented as CZK/EUR/USD 2 digits, HUF 0. RON/PLN precision not established by that page. Item amounts are not validated against transaction total, so caller must ensure consistency. Sources: https://docs.barion.com/Payment-Start-v2 https://docs.barion.com/PaymentTransaction https://docs.barion.com/Responsive_web_payment https://docs.barion.com/Accepting_your_first_online_payment
- Start response includes `PaymentId`, `PaymentRequestId`, `Status`, `Transactions` and `GatewayUrl`. Save Barion PaymentId and each generated TransactionId. Preferred state endpoint `GET /v4/payment/<PaymentId>/paymentstate`, shop `x-pos-key` header; state returns `PaymentId`, `PaymentRequestId`, `Status`, `PaymentType`, `FundingSource`, `Transactions`, decimal `Total`, `Currency` and more. Request-ID-only lookup not established. https://docs.barion.com/Payment-PaymentState-v4
- Start reference marks both redirect and callback required, though response says shop defaults can apply if omitted. Treat as required. Callback is POST to URL with `paymentId` query parameter, not a financial assertion. Acknowledge 200 within 15 seconds then retrieve state. Localhost cannot receive Barion callbacks; polling after redirect and about 15 minutes after expiry is documented fallback. Per-PaymentId polling more than once in five seconds can trigger 429. https://docs.barion.com/Callback_mechanism
- Payment status enum: Prepared, Started, InProgress, Waiting, Reserved, Authorized, Canceled, Succeeded, Failed, PartiallySucceeded, Expired. Canceled and Expired are final, immediate Succeeded means all transactions went through; Failed documented for bank transfer scenarios. Do not assume a declined card creates a final Failed payment. https://docs.barion.com/PaymentStatus
- State transaction has `TransactionId`, `POSTransactionId`, `Total`, `Currency`, `Status`, `TransactionType`, `RelatedId` and other fields. `Total` on original transaction remains original; payment total can change on refund. Refund adds a transaction; payment can remain Succeeded. Types include Refund, RefundToBankCard, StornoUnSuccessfulRefundToBankCard, UnderReview and ReleaseReview. No complete dispute/chargeback identity contract established; unknown types must not be silently treated as settled. https://docs.barion.com/DetailedPaymentTransaction https://docs.barion.com/TransactionType https://docs.barion.com/Callback_mechanism
- Refund POST `/v2/Payment/Refund` uses PaymentId and TransactionsToRefund entries containing TransactionId, POSTransactionId, AmountToRefund; responses list RefundedTransactions. https://docs.barion.com/Payment-Refund-v2 https://docs.barion.com/TransactionToRefund
- Optional `Idempotency-Key` GUID header is documented for all data-changing API endpoints. Simultaneous same-key request can return still-processing error; reuse with changed payload errors. No lifetime, scope, or replay-result guarantee for Payment/Start was established in the consulted general reference. Do not infer retry safety past documented conditions or from PaymentRequestId alone. https://docs.barion.com/Calling_the_API

## Historical account evidence before approval

The user authenticated their business sandbox account through main Chrome and
Panerelay. A new shop named `Festapp - integrační sandbox` was saved as a Draft.
It explicitly describes its phone contacts as synthetic test data and was not
submitted for approval. No pricing agreement or readiness/legal declarations
were accepted by the agent.

Sandbox POSKey and verified wallet identity are retained and verified in the
encrypted macOS login Keychain, using services `festapp-barion-sandbox-poskey`
and `festapp-barion-sandbox-payee`, account `festapp-sandbox`. Secret values do
not appear in this evidence. This is local Keychain storage, not verified iCloud
synchronization.

A single Start for 1 CZK was dispatched with command
`1f5b1e02-9a01-4eca-9bff-67377ddfe7bd` at 2026-11-06 11:36:25 UTC. It returned
non-2xx without a retained status/body or known PaymentId. It remains explicitly
unresolved. No checkout was opened, card entered or money outcome asserted.
A durable guard blocks another Start; subsequent development did not replay it.

A later **read-only** request using the actual stored key, through the new
provider boundary, returned **HTTP 401 / ShopIsInDraftState**. This proves the
current API account gate, not the exact outcome of the earlier Start. A browser
shop configuration flag saying bank cards are enabled is not API approval.

The original authenticated tab subsequently stopped appearing in the authorized
Panerelay tab list. Whether it was closed or its authorization disappeared could
not be established. A new background sandbox tab was opened; selecting the
remembered account did not fill a password. The user was asked to sign in and
complete sandbox-only approval, or signal that form assistance is needed.

Previously observed approval prerequisites include category, logo, selected
customer-service contact, discovery source, pricing choice, and readiness items
covering domain ownership, card logos, Pixel/privacy/terms, purchase conditions,
merchant details, purchasable products, integration and transfer. No unverified
claim was marked true. These are account prerequisites, not missing code tests.

Implemented here: a sandbox-only protocol client, bounded transport, validated
redirect/command/account identity, redacted transport diagnostics, and an
operator probe with durable dispatch intent, callback hint plus authenticated
state read, restricted receipts and no automatic create retry. Seven protocol
regression tests pass. This module is **not installed in the production
registries**, has no automatic paid transition and is not a completed real
sandbox acceptance or Barion application connector. Full refund/reversal/
chargeback semantics and merchant/marketplace eligibility remain separate gates.

The previous Stripe implementation and SQL were unchanged. A targeted rerun
passed **44 Stripe tests plus 7 new Barion tests**. Existing 12 Stripe SQL suites,
PostgreSQL concurrency proof and the 155-test common-hardening receipt remain
separate prior evidence. All temporary test server/tunnel processes stopped.

## Subsequent approval and live sandbox probe

The Draft/login gate described above is historical and has been cleared. See
[approval and payment evidence](BARION-APPROVAL-2026-11-06.md) for the current
account state, independent test cases and verification boundary. Historical
uncertain attempts remain retained and are not relabeled as absent.
