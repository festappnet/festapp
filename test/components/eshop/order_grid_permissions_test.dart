import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/eshop/views/orders_content.dart';

void main() {
  test('unit manager can save an order row deletion', () {
    expect(
      canSaveOrderGridChanges(
        isOrderEditor: false,
        isUnitManager: true,
        isUnitEditor: false,
      ),
      isTrue,
    );
  });

  test('unit editor can save an order row deletion', () {
    expect(
        canSaveOrderGridChanges(
          isOrderEditor: false,
          isUnitManager: false,
          isUnitEditor: true,
        ),
        isTrue);
  });

  test('read-only order viewer cannot save grid changes', () {
    expect(
      canSaveOrderGridChanges(
        isOrderEditor: false,
        isUnitManager: false,
        isUnitEditor: false,
      ),
      isFalse,
    );
  });
}
