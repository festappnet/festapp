# Compact product and report controls

PR #333 reduces product editing height with one row on wide screens, lean amount fields and responsive stacking. Product grouping and disabled default selectors remain. Report validity toggle is now a compact header action beside refresh, replacing the full-width filter strip.

Validation: 7 product layout/behavior tests and 23 report tests passed. Product row height constrained below 100px at the tested wide viewport; actual five-product editor screenshot inspected at /tmp/compact-products.png. Temporary screenshot test passed and was removed.

Released 0.20.132+616, tenant commit 54f6ebe8cb8fe799f34ab7df1ac5c1b7e8cd7324. Canonical tenant drift and Deploy workflow passed, including coherent public-version verification: https://github.com/festappnet/festapp/actions/runs/37516493013
