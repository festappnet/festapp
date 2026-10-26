import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/map/map_viewport_controller.dart';

final class _FakeViewportController implements MapViewportController {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('readiness belongs to the currently attached map surface', () {
    final viewport = MapViewportCoordinator();
    final first = _FakeViewportController();
    final second = _FakeViewportController();

    viewport.attach(first);
    expect(viewport.isAttached, isTrue);
    expect(viewport.isReady, isFalse);

    viewport.markReady();
    expect(viewport.isReady, isTrue);

    viewport.attach(second);
    expect(viewport.isReady, isFalse);
    viewport.markReady();
    viewport.detach(first);
    expect(viewport.isReady, isTrue);

    viewport.detach(second);
    expect(viewport.isAttached, isFalse);
    expect(viewport.isReady, isFalse);
  });
}
