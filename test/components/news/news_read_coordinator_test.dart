import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/news/news_read_coordinator.dart';

void main() {
  test('acknowledges every newer batch while the News tab is visible',
      () async {
    final coordinator = NewsReadCoordinator();
    var isVisible = false;
    var latestUnreadId = 16;
    final persisted = <int>[];
    final markedLocally = <int>[];

    Future<void> acknowledge() => coordinator.acknowledgeLatest(
          isVisible: () => isVisible,
          isLoggedIn: () => true,
          latestUnreadId: () => latestUnreadId,
          persist: (id) async => persisted.add(id),
          markLocally: (id) {
            markedLocally.add(id);
            latestUnreadId = 0;
          },
        );

    await acknowledge();
    expect(persisted, isEmpty);

    isVisible = true;
    await acknowledge();
    expect(persisted, [16]);
    expect(markedLocally, [16]);

    latestUnreadId = 17;
    await acknowledge();
    expect(persisted, [16, 17]);
    expect(markedLocally, [16, 17]);
  });

  test('rechecks the latest unread message after an in-flight mutation',
      () async {
    final coordinator = NewsReadCoordinator();
    final firstMutation = Completer<void>();
    var latestUnreadId = 16;
    final persisted = <int>[];

    Future<void> acknowledge() => coordinator.acknowledgeLatest(
          isVisible: () => true,
          isLoggedIn: () => true,
          latestUnreadId: () => latestUnreadId,
          persist: (id) async {
            persisted.add(id);
            if (id == 16) await firstMutation.future;
          },
          markLocally: (id) {
            if (latestUnreadId == id) latestUnreadId = 0;
          },
        );

    final first = acknowledge();
    latestUnreadId = 17;
    final second = acknowledge();
    firstMutation.complete();
    await Future.wait([first, second]);

    expect(persisted, [16, 17]);
  });
}
