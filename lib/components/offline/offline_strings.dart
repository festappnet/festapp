import 'package:easy_localization/easy_localization.dart';

/// Localized strings for offline degradation (global banner, data-age note,
/// unified write messages). Keys live under "Offline" in the translations
/// (cs + en only). The game keeps its own InformationStrings.offlineWarning —
/// feature imports are not crossed.
class OfflineStrings {
  static String get youAreOffline => 'Offline.youAreOffline'.tr();

  /// Minimal label for the global banner — just "Offline", no reason/time.
  static String get offline => 'Offline.offline'.tr();

  /// Compact "last updated {time}" tail for the banner (muted secondary text).
  static String updatedAt(String time) =>
      'Offline.updatedAt'.tr(namedArgs: {'time': time});

  static String lastUpdated(String time) =>
      'Offline.lastUpdated'.tr(namedArgs: {'time': time});

  static String get writeRequiresConnection =>
      'Offline.writeRequiresConnection'.tr();

  static String get counselingNeedsConnection =>
      'Offline.counselingNeedsConnection'.tr();

  static String get feedbackStateUnknown =>
      'Offline.feedbackStateUnknown'.tr();
}
