import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/occasion/news_badge_controller.dart';

void main() {
  test('tapping News clears its unread badge without reloading the old count',
      () async {
    var unreadCount = 1;
    var reloadCalls = 0;
    var acknowledgementCalls = 0;
    final reloadResult = Completer<int>();

    handleNewsBadgeTabTap(
      isNewsTab: true,
      isLoggedIn: true,
      loadUnreadCount: () {
        reloadCalls++;
        return reloadResult.future;
      },
      setUnreadCount: (count) => unreadCount = count,
      acknowledgeUnread: () => acknowledgementCalls++,
    );

    expect(unreadCount, 0);
    expect(reloadCalls, 0);
    expect(acknowledgementCalls, 1);
  });

  test('tapping another tab refreshes the unread badge', () async {
    var unreadCount = 1;
    var reloadCalls = 0;
    var acknowledgementCalls = 0;

    handleNewsBadgeTabTap(
      isNewsTab: false,
      isLoggedIn: true,
      loadUnreadCount: () async {
        reloadCalls++;
        return 3;
      },
      setUnreadCount: (count) => unreadCount = count,
      acknowledgeUnread: () => acknowledgementCalls++,
    );
    await Future<void>.delayed(Duration.zero);

    expect(reloadCalls, 1);
    expect(unreadCount, 3);
    expect(acknowledgementCalls, 0);
  });
}
