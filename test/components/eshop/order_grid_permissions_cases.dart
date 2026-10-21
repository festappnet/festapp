import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/eshop/views/orders_content.dart';

void main() {
  test('order writes or deletions enable saving the corresponding grid changes',
      () {
    expect(
        canSaveOrderGridChanges(canWriteOrders: true, canDeleteOrders: false),
        isTrue);
    expect(
        canSaveOrderGridChanges(canWriteOrders: false, canDeleteOrders: true),
        isTrue);
    expect(
        canSaveOrderGridChanges(canWriteOrders: false, canDeleteOrders: false),
        isFalse);
  });
}
