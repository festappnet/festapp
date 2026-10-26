import 'package:test/test.dart';
import '../../test/support/fixtures/resource_scope.dart';

void main() {
  test('partial setup releases acquired resources after a later setup failure',
      () async {
    final scope = FixtureScope();
    final resources = <String>{};
    try {
      resources.add('database');
      scope.onDispose(() => resources.remove('database'));
      throw StateError('second acquisition failed');
    } catch (_) {
      await scope.dispose();
    }
    expect(resources, isEmpty);
  });
  test('cleanup attempts all resources in reverse order and reports failures',
      () async {
    final scope = FixtureScope();
    final order = <int>[];
    scope.onDispose(() => order.add(1));
    scope.onDispose(() {
      order.add(2);
      throw StateError('failed close');
    });
    scope.onDispose(() => order.add(3));
    await expectLater(scope.dispose(), throwsA(isA<FixtureCleanupException>()));
    expect(order, [3, 2, 1]);
    await scope.dispose();
    expect(order, [3, 2, 1]);
  });
}
