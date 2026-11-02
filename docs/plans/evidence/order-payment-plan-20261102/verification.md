# Customer payment details and whole-order plan navigation - 2026-11-02

User-requested additions to PR #702:

- A native payment-destination block above the existing transaction UI, with receiving account, IBAN when distinct, actual VS/RF reference, server-owned amount due and deadline. Bank/reference fields use the existing clipboard control. Existing transaction actions/calculations remain owned by OrderPaymentsContent; its duplicate standalone reference is suppressed only when the new block displays it.
- The authorized admin order reader exposes limited bankPaymentDetails for the payment-linked receiving account even after payment. It retains the existing order/occasion authorization guard, excludes cards and mismatched currency, and never creates instructions. Forward migration 20261102153000_order_admin_bank_payment_details.sql matches the canonical function exactly. Customer/public payment projection remains unchanged.
- Payment deadlines retain their exact local date and add future-only natural-language text, e.g. '(za 3 dny)'. Shared formatter supports cs/en/sk/de/pl/uk, with CLDR pluralization and existing timeago thresholds; expired dates omit past-relative text. Existing TimeHelper.timeAgo is unchanged.
- Customer-overview glyph is 16px, centered with the identifier, retaining a 44px hit target.
- Map header opens the main Blueprint section with every active order place on the displayed plan highlighted/focused. Per-place actions still target one place. Single-node URLs remain supported; multi-node targets are bound to the loaded plan/document. Visual focus does not alter operational selection or geometry.

Validation:

- 137 combined Flutter tests passed across payment instructions, relative dates, root routing, real Blueprint camera/highlights, map selection, email history/repair and presentation. Additional full-route whole-order navigation and final typed-projection integration probes passed.
- Real disposable PostgreSQL tests passed for the existing order reader plus the new paid-bank/RF/card/authorization/read-side-effect contract. Target identity festapp-db-tests-pg15 was asserted; source functions and fixtures were loaded inside BEGIN/ROLLBACK. No production data tests or changes were performed.
- Targeted Dart analysis has no errors or warnings. Six action-label catalogs parse successfully. Migration/canonical-function exact parity verified.
- Actual native Flutter captures at 400px/1.4x text scale, plus a 400px/1.6x order header. Primary and Astra Medium reviewed both themes and header alignment without clipping. Synthetic metadata and local Futura/Material fonts only.

Logs: /tmp/order-admin-combined-final-tests.log, /tmp/order-plan-whole-route-test.log, /tmp/order-admin-final-getter-test.log, /tmp/order-payment-details-db-test.log, /tmp/order-admin-final-analyze.log, /tmp/order-payment-plan-analyze.log.

Production release requires the exact forward read-function migration/ledger before publishing the web client; no email/provider or capacity mutations are needed. Local review services remain stopped. A failed optional test-database clone was removed; the existing disposable service was not restarted.
