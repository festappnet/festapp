import 'package:easy_localization/easy_localization.dart';

/// Localized strings for the occasion home page and its navigation tabs.
/// Keys live under the "OccasionHome" namespace in assets/translations/*.json.
class OccasionHomeStrings {
  static String get home => 'OccasionHome.home'.tr(); // "Home"
  static String get news => 'OccasionHome.news'.tr(); // "News"
  static String get more => 'OccasionHome.more'.tr(); // "More"
  static String get addToSchedule =>
      'OccasionHome.addToSchedule'.tr(); // "Add To Schedule"
}
