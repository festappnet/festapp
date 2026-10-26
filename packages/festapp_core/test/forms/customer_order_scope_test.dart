import 'package:test/test.dart';
import 'package:festapp_core/forms.dart';

void main() {
  group('customer_order_overview', () {
    test('view parser keeps write fragments separate', () {
      expect(
        CustomerOrderScope.fromUri(
          Uri.parse('/order?waitlist=1&token=anything'),
        ),
        isNull,
      );
      final scope = CustomerOrderScope.fromUri(
        Uri.parse('/order?order_id=1&token=${'a' * 64}'),
      )!;
      expect(CustomerOrderScope.fromUri(scope.uri)!.orderId, 1);
      expect(
        () =>
            CustomerOrderScope.fromUri(Uri.parse('/order?order_id=0&token=x')),
        throwsStateError,
      );
    });
  });
}
