# Order detail focus and presentation - 2026-11-02

Implementation commit: `616a1423a` on `fix/order-detail-focus-20261102`, based on canonical main `e5609bd7838403e884118c379841dfecf2e690d1`.
Local preview: http://127.0.0.1:58631/order-detail-ples/reservations/orders/current
Main JS SHA256 (disk and HTTP): `a1be5019c6b39f4ff2e0c24024d072dbbea3dcfecb8c3c396cdc858de4b68823`.

- Header status uses the canonical grid state opacity composited on the canonical grid background, tested in both themes. Fresh local preferences default to 720px detail width, making the table narrower; stored widths remain authoritative.
- Place selection no longer invokes delayed card expansion/ancestor scrolling. The separate crosshair opens the existing main Blueprint section with explicit plan/node query parameters. Only a node in the requested saved plan can receive visual focus. Main Blueprint focus is a camera/highlight operation; saved geometry, business selection, rights and mutations are unchanged.
- Blueprint route focus is scoped to the active occasion/route; repeat entry focuses again and unrelated rebuilds retain the camera. Stale reads are invalidated.
- Payments reuses the original Transactions content without extra reference/account/summary blocks. Its canonical variable-symbol label remains the single source of bank-payment naming; card status and unknown-state diagnostics remain.
- E-mail uses a static external label/frame and static validation text, avoiding InputDecorator floating/underline/error animations. Global Save/Discard stays below the scroll viewport and does not shift the form on first edit.

Verification: 83 targeted tests across Blueprint focus/camera and host panning, place overview, detail presentation, pane resize/persistence, order routing/payments, email recovery/design, scroll storage and draft saving. Initial expected-position/fixture-route assumptions were corrected and affected suites passed (58); the final synthetic payment fixture also passed its targeted test. Targeted analyzer completed without errors or warnings (informational style diagnostics remain). Release-mode local full-app web build passed. Actual browser checks are in browser-receipt.md, with observed limits stated separately.

Only synthetic local data was used. Existing local services and unrelated primary-checkout edits were preserved. This follow-up is not deployed to production.
