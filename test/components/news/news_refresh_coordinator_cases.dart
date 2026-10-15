import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/_shared/async_reload_coordinator.dart';

void main() {
  test('replays a refresh requested while the current load is in flight',
      () async {
    final coordinator = AsyncReloadCoordinator();
    final firstLoadStarted = Completer<void>();
    final releaseFirstLoad = Completer<void>();
    final projectedViews = <int>[];
    var availableViews = 0;

    Future<void> load() async {
      final viewsAtStart = availableViews;
      if (projectedViews.isEmpty) {
        firstLoadStarted.complete();
        await releaseFirstLoad.future;
      }
      projectedViews.add(viewsAtStart);
    }

    final initialLoad = coordinator.run(load);
    await firstLoadStarted.future;

    availableViews = 1637;
    final liveProjectionLoad = coordinator.run(load);
    releaseFirstLoad.complete();

    await Future.wait([initialLoad, liveProjectionLoad]);
    expect(projectedViews, [0, 1637]);
  });
}
