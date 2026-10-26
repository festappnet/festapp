import 'package:easy_localization/easy_localization.dart';

/// Strings for the occasion icon library + place types
/// (OccasionSettings.icons* / OccasionSettings.placeType* keys).
class IconsStrings {
  static String get icons => 'OccasionSettings.icons'.tr();
  static String get uploadIcon => 'OccasionSettings.iconsUpload'.tr();
  static String get empty => 'OccasionSettings.iconsEmpty'.tr();
  static String get deleteConfirm => 'OccasionSettings.iconsDeleteConfirm'.tr();
  static String get author => 'OccasionSettings.iconsAuthor'.tr();
  static String get googleHint => 'OccasionSettings.iconsGoogleHint'.tr();
  static String get googleLink => 'OccasionSettings.iconsGoogleLink'.tr();
  static String get inUseTitle => 'OccasionSettings.iconsInUseTitle'.tr();
  static String inUseDetail(int places, int paths, int types) =>
      'OccasionSettings.iconsInUseDetail'.tr(namedArgs: {
        'places': '$places',
        'paths': '$paths',
        'types': '$types',
      });
  static String get invalidSvg => 'OccasionSettings.iconsInvalidSvg'.tr();
  static String get legacyReadOnly =>
      'OccasionSettings.iconsLegacyReadOnly'.tr();
  static String get linkHelper => 'OccasionSettings.iconsLinkHelper'.tr();
  static String get linkLabel => 'OccasionSettings.iconsLinkLabel'.tr();
  static String get noUnit => 'OccasionSettings.iconsNoUnit'.tr();
  static String get searchHint => 'OccasionSettings.iconsSearchHint'.tr();
  static String get tabFile => 'OccasionSettings.iconsTabFile'.tr();
  static String get tabGoogle => 'OccasionSettings.iconsTabGoogle'.tr();
  static String get tooLarge => 'OccasionSettings.iconsTooLarge'.tr();
  static String get uploadHint => 'OccasionSettings.iconsUploadHint'.tr();

  // Place types
  static String get placeTypes => 'OccasionSettings.placeTypes'.tr();
  static String get placeTypeCode => 'OccasionSettings.placeTypeCode'.tr();
  static String get placeTypeTitle => 'OccasionSettings.placeTypeTitle'.tr();
  static String get placeTypeDefault =>
      'OccasionSettings.placeTypeDefault'.tr();
  static String get placeTypesOther => 'OccasionSettings.placeTypesOther'.tr();
}
