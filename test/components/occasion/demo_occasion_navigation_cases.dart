import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/unit/unit_model.dart';
import 'package:fstapp/components/occasion/demo/demo_occasion_navigation.dart';

void main() {
  test('return restores the originating owned event list and its query', () {
    expect(
        DemoOccasionNavigation.returnPath(
            '/unit/7/edit/occasions?search=ples', [3, 7]),
        '/unit/7/edit/occasions?search=ples');
    expect(DemoOccasionNavigation.returnPath('/', []), '/');
  });
  test('breadcrumb uses the originating owned organizer with a safe fallback',
      () {
    final units = [
      UnitModel(id: 3, title: 'First'),
      UnitModel(id: 7, title: 'Own')
    ];
    expect(
        DemoOccasionNavigation.originUnit('/unit/7/edit/occasions', units)?.id,
        7);
    expect(
        DemoOccasionNavigation.originUnit('/unit/99/edit/occasions', units)?.id,
        3);
    expect(DemoOccasionNavigation.originUnit(null, []), isNull);
  });
  test('direct entries return to an owned list, never the demo organizer', () {
    for (final origin in [
      null,
      '/demo-ball/admin',
      '/unit/99/edit/occasions',
      'https://example.test/unit/7/edit/occasions',
      '//example.test/unit/7/edit/occasions'
    ]) {
      expect(DemoOccasionNavigation.returnPath(origin, [7]),
          '/unit/7/edit/occasions');
    }
    expect(DemoOccasionNavigation.returnPath(null, []), '/');
  });
}
