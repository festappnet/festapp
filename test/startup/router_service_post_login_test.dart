import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/unit/unit_model.dart';
import 'package:fstapp/router_service.dart';

void main() {
  test('post-login admin navigation prefers the managed unit', () {
    final managedUnit = UnitModel(id: 5);

    final destination = RouterService.postLoginAdminUnit([managedUnit]);

    expect(destination?.id, 5);
  });

  test('post-login admin navigation keeps fallback without a managed unit', () {
    expect(RouterService.postLoginAdminUnit([]), isNull);
  });
}
