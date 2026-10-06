# Order controls polish - 2026-10-06

- Order symbol copy uses a bare 16px icon and a theme-aware green success check that resets after two seconds. Timer cancellation covers disposal and symbol replacement.
- Valid orders/tickets start enabled. Other grid consumers keep their existing default.
- The filter uses the application's ElevatedButton theme with checked/unchecked icons and toggled semantics, matching the adjacent scan button.
- Five targeted regression tests passed in `test/components/eshop/order_grid_filters_test.dart`, covering both themes, clipboard feedback/reset and grid filtering behavior.
- Actual application-theme screenshots inspected for light/dark copy/success states. Temporary screenshot harness removed; its painting-debug teardown assertion does not affect product tests or captured rendering.
- No backend or database change. Deployment scope: main and prod/festapptickets only.
