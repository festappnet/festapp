# Order controls polish - 2026-10-06

- Order symbol copy uses a bare 16px icon and a theme-aware green success check that resets after two seconds. Timer cancellation covers disposal and symbol replacement.
- Valid orders/tickets start enabled. Other grid consumers keep their existing default.
- The filter uses the application's ElevatedButton theme with checked/unchecked icons and toggled semantics, matching the adjacent scan button.
- Five targeted regression tests passed in `test/components/eshop/order_grid_filters_test.dart`, covering both themes, clipboard feedback/reset and grid filtering behavior.
- Actual application-theme screenshots inspected for light/dark copy/success states. Temporary screenshot harness removed; its painting-debug teardown assertion does not affect product tests or captured rendering.
- No backend or database change. Deployment scope: main and prod/festapptickets only.

## Deployment

- Main: `06087bc51a027f8088a1003877f55e8046748a40` (PR #325).
- Tenant: `05b283e9c590aea476b3e72940cf4a84f5bb4e31`, version `0.20.126+610`.
- Main-owned tenant drift check passed.
- Deploy workflow succeeded, including coherent public release verification: https://github.com/festappnet/festapp/actions/runs/37500332626
- Reusable release skill validated, installed and published independently in miakh/development-tools at `fec983b`; unrelated local changes were preserved.
