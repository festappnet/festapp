import 'package:easy_localization/easy_localization.dart';

/// Localized strings for app installation and settings pages.
/// Keys live under the "Administration" namespace in assets/translations/*.json.
class AppManagementStrings {
  // --- InstallPage ---
  static String get installApp =>
      'Administration.installApp'.tr(); // "Install App"
  static String get downloadApp =>
      'Administration.downloadApp'.tr(); // "Download App"
  static String get installNow =>
      'Administration.installNow'.tr(); // "Install Now"
  static String get installForApple =>
      'Administration.installForApple'.tr(); // "Install for Apple"
  static String get installForAndroid =>
      'Administration.installForAndroid'.tr(); // "Install for Android"
  static String get installForPcMac =>
      'Administration.installForPcMac'.tr(); // "Install for PC/Mac"
  static String installBenefits({required String title}) =>
      'Administration.installBenefits'.tr(namedArgs: {
        'title': title
      }); // "Install {title} to get notifications, offline functionality, and a quick launch icon."
  static String get androidInstallHint => 'Administration.androidInstallHint'
      .tr(); // "Open this website on your Android phone in a browser like Chrome or Edge and hit the Install Now button."
  static String get installOptionsLoadFailed =>
      'Administration.installOptionsLoadFailed'
          .tr(); // "Failed to load installation options."
  static String get appAlreadyInstalled => 'Administration.appAlreadyInstalled'
      .tr(); // "The app is already installed."
  static String get installFailedHint => 'Administration.installFailedHint'
      .tr(); // "Installation failed. Please open this link in your device's default system browser (e.g., Mi Browser or Chrome). Note: Some devices may not support installing web applications."
  static String get copyLink => 'Administration.copyLink'.tr(); // "Copy Link"

  // --- SettingsPage ---
  static String get notificationSettings =>
      'Administration.notificationSettings'.tr(); // "Notification Settings"
  static String get enableNotifications =>
      'Administration.enableNotifications'.tr(); // "Enable Notifications"
  static String get enableNotificationsFailed =>
      'Administration.enableNotificationsFailed'
          .tr(); // "Failed to enable notifications."
  static String get pwaPromptNotSupported => 'Administration.pwaPromptNotSupported'
      .tr(); // "This platform or browser does not support the PWA install prompt or the app is already installed."
  static String get storageTitle => 'Administration.storageTitle'.tr();
  static String get inspectStorage => 'Administration.inspectStorage'.tr();
  static String get pruneShells => 'Administration.pruneShells'.tr();
  static String get pruneShellsConfirm =>
      'Administration.pruneShellsConfirm'.tr();
  static String storageUsage({required String usage, required String quota}) =>
      'Administration.storageUsage'
          .tr(namedArgs: {'usage': usage, 'quota': quota});
  static String get storageBlocked => 'Administration.storageBlocked'.tr();
  static String storageReady(
          {required String retained, required String deletable}) =>
      'Administration.storageReady'.tr(
        namedArgs: {'retained': retained, 'deletable': deletable},
      );
}
