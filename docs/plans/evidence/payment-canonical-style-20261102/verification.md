# Payment presentation aligned with Transactions - 2026-11-02

Compared the historical Transactions dialog at c288a6fb1 and current canonical transaction renderer. Financial text used 14px body typography, compact 3:5 label/value rows and 5px row gaps. Its Add Payment control used 16px horizontal/12px vertical internal padding and 8px surrounding separation.

Customer payment details now follow that density and column split, replacing the previous large label-over-value treatment at widths below 480px. Clipboard actions remain adjacent to their original values. A deliberate fallback stacks only genuinely narrow panes with enlarged text (available width below 340px and scaled 14px text above 20px). Values, reference types, exact/future deadlines and payment/capability logic are unchanged.

Add Payment retains internal padding/action/permission checks. Its toolbar now uses an explicit right alignment plus 8px above and 16px below, so it is separated from the reference/summary content.

Native Flutter captures with local Futura/Material fonts and synthetic metadata: 400px/1.4x light+dark, 760px/1x, 320px/1.6x long IBAN/RF/creditor. Primary and Astra Medium reviewed the final renders. Narrow values wrap without clipping; ordinary panes retain compact columns.

26 targeted tests passed; all 7 affected customer-payment tests passed again after the narrow-layout refinement. Existing real OrderPaymentsContent test with mocked standard RPC verifies at least 12px visible separation below Add Payment. Targeted analysis has no errors/warnings (five existing informational diagnostics in Transactions; final details widget has no diagnostics).

Logs: /tmp/payment-style-tests.log, /tmp/payment-style-final-tests.log, /tmp/payment-style-toolbar-test.log, /tmp/payment-style-analyze.log, /tmp/payment-style-final-analyze.log.
No backend or payment data changes. Local review services remain stopped.
