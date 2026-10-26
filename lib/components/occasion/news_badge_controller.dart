import 'dart:async';

/// Keeps the unread-news badge in sync when a bottom-navigation tab is tapped.
void handleNewsBadgeTabTap({
  required bool isNewsTab,
  required bool isLoggedIn,
  required Future<int> Function() loadUnreadCount,
  required void Function(int count) setUnreadCount,
  required void Function() acknowledgeUnread,
}) {
  if (!isLoggedIn) return;

  // Opening News is the user's acknowledgement of the unread messages. Clear
  // the badge synchronously so an in-flight count taken before News marks the
  // messages as read cannot put the stale value back.
  if (isNewsTab) {
    setUnreadCount(0);
    acknowledgeUnread();
    return;
  }

  unawaited(loadUnreadCount().then(setUnreadCount));
}
