import 'package:easy_localization/easy_localization.dart';

class OccasionSetupStrings {
  static String story(String key) => 'OccasionSetup.story.$key'.tr();
  static String readiness(int percent) =>
      'OccasionSetup.story.readiness'.tr(namedArgs: {'percent': '$percent'});
  static String questionNumber(int current, int total) =>
      'OccasionSetup.story.questionNumber'.tr(namedArgs: {
        'current': '$current',
        'total': '$total',
      });
  static String get createStepByStep => 'OccasionSetup.createStepByStep'.tr();
  static String get createEvent => 'OccasionSetup.createEvent'.tr();
  static String get finalizeFailed => 'OccasionSetup.finalizeFailed'.tr();
  static String get drafts => 'OccasionSetup.drafts'.tr();
  static String get untitled => 'OccasionSetup.untitled'.tr();
  static String get resume => 'OccasionSetup.resume'.tr();
  static String get basics => 'OccasionSetup.basics'.tr();
  static String get review => 'OccasionSetup.review'.tr();
  static String get saving => 'OccasionSetup.saving'.tr();
  static String get saved => 'OccasionSetup.saved'.tr();
  static String get saveFailed => 'OccasionSetup.saveFailed'.tr();
  static String get conflict => 'OccasionSetup.conflict'.tr();
  static String get retry => 'OccasionSetup.retry'.tr();
  static String get reload => 'OccasionSetup.reload'.tr();
  static String get reloadConfirm => 'OccasionSetup.reloadConfirm'.tr();
  static String get leave => 'OccasionSetup.leave'.tr();
  static String get incomplete => 'OccasionSetup.incomplete'.tr();
  static String get deleteConfirm => 'OccasionSetup.deleteConfirm'.tr();
}
