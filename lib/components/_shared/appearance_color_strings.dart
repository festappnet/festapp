import 'package:easy_localization/easy_localization.dart';

class AppearanceColorStrings {
  static String get style => 'AppearanceColors.style'.tr();
  static String get paletteHint => 'AppearanceColors.paletteHint'.tr();
  static String get custom => 'AppearanceColors.custom'.tr();
  static String get inherited => 'AppearanceColors.inherited'.tr();
  static String palette(String name) =>
      'AppearanceColors.palette'.tr(namedArgs: {'name': name});
  static String get gradient => 'AppearanceColors.gradient'.tr();
  static String get hint => 'AppearanceColors.hint'.tr();
  static String get theme => 'AppearanceColors.theme'.tr();
  static String get first => 'AppearanceColors.first'.tr();
  static String get second => 'AppearanceColors.second'.tr();
  static String get done => 'AppearanceColors.done'.tr();
}
