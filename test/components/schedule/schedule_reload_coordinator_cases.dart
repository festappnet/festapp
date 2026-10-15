import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/_shared/async_reload_coordinator.dart';

void main() {
  test('coalesces a concurrent request into one trailing reload', () async {
    final coordinator = AsyncReloadCoordinator();
    final firstLoad = Completer<void>();
    var calls = 0;

    Future<void> reload() async {
      calls++;
      if (calls == 1) await firstLoad.future;
    }

    final first = coordinator.run(reload);
    final concurrent = coordinator.run(reload);
    expect(calls, 1);

    firstLoad.complete();
    await Future.wait([first, concurrent]);

    expect(calls, 2);
    expect(coordinator.isLoading, isFalse);
  });

  test('an error unlocks future reloads', () async {
    final coordinator = AsyncReloadCoordinator();

    await expectLater(
      coordinator.run(() => Future.error(StateError('failed'))),
      throwsStateError,
    );
    await coordinator.run(() async {});

    expect(coordinator.isLoading, isFalse);
  });

  test('dispose prevents queued reloads from starting', () async {
    final coordinator = AsyncReloadCoordinator();
    final firstLoad = Completer<void>();
    var calls = 0;

    final running = coordinator.run(() async {
      calls++;
      await firstLoad.future;
    });
    coordinator.run(() async => calls++);
    coordinator.dispose();
    firstLoad.complete();
    await running;

    expect(calls, 1);
  });
}
