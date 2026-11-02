# Payment presentation aligned with Transactions - 2026-11-02

Compared the historical Transactions dialog at c288a6fb1 and current canonical transaction renderer. Financial text used 14px body typography, compact 3:5 label/value rows and 5px row gaps. Its Add Payment control used 16px horizontal/12px vertical internal padding and 8px surrounding separation.

Customer payment details now follow that density and column split, replacing the previous large label-over-value treatment at widths below 480px. Clipboard actions remain adjacent to their original values. A deliberate fallback stacks only genuinely narrow panes with enlarged text (available width below 340px and scaled 14px text above 20px). Values, reference types, exact/future deadlines and payment/capability logic are unchanged.

Add Payment retains internal padding/action/permission checks. Its toolbar now uses an explicit right alignment plus 8px above and 16px below, so it is separated from the reference/summary content.

Native Flutter captures with local Futura/Material fonts and synthetic metadata: 400px/1.4x light+dark, 760px/1x, 320px/1.6x long IBAN/RF/creditor. Primary and Astra Medium reviewed the final renders. Narrow values wrap without clipping; ordinary panes retain compact columns.

26 targeted tests passed; all 7 affected customer-payment tests passed again after the narrow-layout refinement. Existing real OrderPaymentsContent test with mocked standard RPC verifies at least 12px visible separation below Add Payment. Targeted analysis has no errors/warnings (five existing informational diagnostics in Transactions; final details widget has no diagnostics).

Logs: /tmp/payment-style-tests.log, /tmp/payment-style-final-tests.log, /tmp/payment-style-toolbar-test.log, /tmp/payment-style-analyze.log, /tmp/payment-style-final-analyze.log.
The styling change does not alter backend or payment data. Local review services remain stopped.

## Order preview occupancy and Orders-only copy refinement

The existing order preview RPC returned geometry without seat lifecycle facts, so the viewer rendered default green seats. It now returns only `nodeId`, `title`, `state`, `blocked`, and `hasProduct` for the current plan. The existing canonical lifecycle helper provides occupancy; the preview shares the main Blueprint adapter's state precedence and palette. Missing occupancy fails closed rather than claiming all seats are free. A missing plan title no longer renders literal `null`.

No editor, customer/order collection, full product catalog, new endpoint, polling, or request per seat was introduced. The existing controller cache is retained, and repeated selection during an in-flight request now reuses that load. Widget coverage asserts exactly one detail RPC plus one map RPC, including rapid selection before the first map resolves and subsequent seat selection.

Read-only measurement against the reported production plan: 228 seats, 116 ordered and 112 available. New minimal JSON facts were 29,068 bytes before HTTP compression; existing geometry was 131,167 bytes and referenced rendering resources 348,183 bytes. The additional facts projection took 4.505 ms in a single warm-buffer EXPLAIN ANALYZE sample; this is not an end-to-end RPC or cold-cache benchmark. The existing resource reader already restricts assets/text resources to document references, including reusable presets. All production diagnostics used explicit read-only transactions; no production function or data was changed.

Disposable SQL regression passes with own-order occupancy, another order's used seat, active and expired holds, blocked binding, all four plan seats, five-field-only facts, privacy, permissions, placement conflicts and mutation-free reads. Source and forward migration function bodies are identical. The production release needs the new one-function migration `20261102165000_order_blueprint_preview_occupancy.sql` before the matching web client.

The Orders grid explicitly disables the order-symbol copy control; Tickets and other callers retain their default copy action. An actual OrdersContent test verifies copy is absent and open navigation remains; the existing default copy feedback test still passes in light and dark mode.

Validation: initial targeted order/detail/grid checks passed (28 tests); Orders, default-copy and main Blueprint host regressions passed (56 tests); final changed preview/in-flight and Blueprint host checks passed (32 tests). Disposable SQL test completed with rollback. Analyzer has no errors/warnings; informational diagnostics in existing larger files are retained. Logs: `/tmp/order-preview-tests.log`, `/tmp/order-preview-regression-tests.log`, `/tmp/order-preview-final-tests.log`, `/tmp/order-preview-occupancy-db-test.log`, `/tmp/order-preview-analyze.log`, `/tmp/order-preview-final-analyze.log`.
