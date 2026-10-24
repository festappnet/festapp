/// Available to every authenticated user whose server-side organization and
/// permissions enable notification delivery.
class NotificationCenterRollout {
  static const bool visibleToEveryone = true;

  static bool isVisibleTo(String? email) => visibleToEveryone;
}
