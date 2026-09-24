import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/eshop/eshop_columns.dart';
import 'package:fstapp/components/eshop/models/order_model.dart';

void main() {
  test('cancelled ticket usage cannot be toggled', () {
    expect(canToggleTicketUsage(OrderModel.stornoState), isFalse);
    expect(
      canToggleTicketUsage('${OrderModel.stornoState};STORNO'),
      isFalse,
    );
  });

  test('active and used ticket usage can be toggled', () {
    expect(canToggleTicketUsage(OrderModel.sentState), isTrue);
    expect(canToggleTicketUsage(OrderModel.usedState), isTrue);
  });
}
