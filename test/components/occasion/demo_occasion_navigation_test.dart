import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/occasion/demo/demo_occasion_navigation.dart';

void main() {
  test('return restores the originating owned event list and its query', () {
    expect(
        DemoOccasionNavigation.returnPath(
            '/unit/7/edit/occasions?search=ples', [3, 7]),
        '/unit/7/edit/occasions?search=ples');
    expect(DemoOccasionNavigation.returnPath('/', []), '/');
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
