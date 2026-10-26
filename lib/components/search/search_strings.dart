import 'package:easy_localization/easy_localization.dart';

/// Localized strings for the GlobalSearch feature.
/// Keys live under the "GlobalSearch" namespace in assets/translations/*.json.
class SearchStrings {
  static String get featureTitle => 'GlobalSearch.featureTitle'.tr();
  static String get featureDescription =>
      'GlobalSearch.featureDescription'.tr();

  static String get hint => 'GlobalSearch.hint'.tr();
  static String get tooltip => 'GlobalSearch.tooltip'.tr();
  static String get emptyPrompt => 'GlobalSearch.emptyPrompt'.tr();
  static String get noResults => 'GlobalSearch.noResults'.tr();

  static String get profileMovedTitle => 'GlobalSearch.profileMovedTitle'.tr();
  static String get profileMovedBody => 'GlobalSearch.profileMovedBody'.tr();

  /// Group header label for a given entity type.
  static String groupTitle(String entityType) {
    switch (entityType) {
      case 'event':
        return 'GlobalSearch.groupEvent'.tr();
      case 'place':
        return 'GlobalSearch.groupPlace'.tr();
      case 'song':
        return 'GlobalSearch.groupSong'.tr();
      case 'game':
        return 'GlobalSearch.groupGame'.tr();
      case 'news':
        return 'GlobalSearch.groupNews'.tr();
      case 'speaker':
        return 'GlobalSearch.groupSpeaker'.tr();
      case 'info':
      default:
        return 'GlobalSearch.groupInfo'.tr();
    }
  }

  /// Stable ordering of result groups in the UI.
  static const List<String> groupOrder = [
    'event',
    'speaker',
    'place',
    'info',
    'song',
    'game',
    'news',
  ];
}
