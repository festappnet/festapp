import 'package:fstapp/app_config.dart';

/// Temporary UI rollout. Server permissions and delivery stay unchanged.
class NotificationCenterRollout {
  // Flip this to true when the preview has been tested.
  static const bool visibleToEveryone = false;

  static bool isVisibleTo(String? email) =>
      visibleToEveryone ||
      AppConfig.removeUserPrefix(email?.trim().toLowerCase() ?? '') ==
          'bujnmi@gmail.com';
}
