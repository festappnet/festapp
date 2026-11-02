# Order detail polish - 2026-11-02

Local review: http://127.0.0.1:58631/order-detail-ples/reservations/orders/current

Source base: f37babbf2d8155ee6dcb73723ba982d4a616f8b2 (main).
Branch: fix/order-detail-polish-20261102.
Implementation commit: b21ae3739.
Local Flutter web artifact SHA256 (main.dart.js, verified on disk and over HTTP):
`4b680f4bbfd385b2980858fc481e426273f2329ecab60f842d404f416b41a71f`.

Changes:
- Missing/cleared answers use Nevyplněno, with matching translations.
- Shared payment summary shows received / total and meaningful nonzero facts. Unknown and Stripe states remain explicit. Cancelled orders retain receipts/refunds/overpayment without requesting historical balances or deposit deadlines.
- Order changes retain the current tab and discard previous order-specific ticket/message targets.
- Only the detail-header copy button is removed; grid copies stay.
- Shared asynchronous PDF control displays generation, prevents queued double clicks, and releases after completion/failure in detail and ticket grid.
- Nonempty ordinary customer note appears immediately after contact, above hidden note. Existing lower duplicate removed. Disposable fixture note seeded without changing other local data.

Verification:
- Targeted widget suites passed: async_download_button (3), order_payment_summary (5), order_detail_presentation_revision (31), empty_orders (13), order_detail_answers (1), order_grid_activation_revision (4), order_detail_save_changes (2).
- Targeted Dart analysis exited successfully; pre-existing informational diagnostics in existing files remain. New payment summary has no diagnostics.
- Local release-mode full-app build passed using the existing disposable tenant defines and test/browser/full_app_e2e.dart.
- Browser QA is recorded separately in this directory. No real customer data or production mutations were used.
- Primary checkout received only owned source/tests/translation changes. Unrelated edits and additional translations were preserved.

This follow-up has not been deployed to production.
