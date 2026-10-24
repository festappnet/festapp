import 'package:test/test.dart';
import 'package:festapp_core/forms.dart';

void main() {
  group('customer_order_overview', () {
    test('view parser keeps write fragments separate', () {
      expect(
        CustomerOrderScope.fromFragment('waitlist?token=anything'),
        isNull,
      );
      final scope = CustomerOrderScope.fromFragment(
        'order?order_id=1&token=${'a' * 64}',
      )!;
      expect(CustomerOrderScope.fromFragment(scope.fragment)!.orderId, 1);
      expect(
        () => CustomerOrderScope.fromFragment('order?order_id=0&token=x'),
        throwsStateError,
      );
    });
  });
}
