import 'package:easy_localization/easy_localization.dart';

/// Localized strings for the Cleaning service (úklidová služba) feature.
/// Keys live under "Cleaning" / "FeatureCleaning" in the translations.
/// Only cs + en are provided (plan section 4.6).
class CleaningStrings {
  static String get featureTitle => 'FeatureCleaning.title'.tr();
  static String get featureDescription => 'FeatureCleaning.description'.tr();

  static String get pageTitle => 'Cleaning.pageTitle'.tr();

  /// Column header of the "mark this place as a toilet" checkbox in admin Places.
  static String get placeIsToilet => 'Cleaning.placeIsToilet'.tr();

  static String get noToilets => 'Cleaning.noToilets'.tr();

  /// Shown when the page is reached but the cleaning feature is disabled.
  static String get featureDisabled => 'Cleaning.featureDisabled'.tr();
  static String get tapToReport => 'Cleaning.tapToReport'.tr();
  static String get refresh => 'Cleaning.refresh'.tr();
  static String get showOnMap => 'Cleaning.showOnMap'.tr();
  static String get toiletsOnMap => 'Cleaning.toiletsOnMap'.tr();

  // Report dialog
  static String get reportProblem => 'Cleaning.reportProblem'.tr();
  static String reportDialogTitle(String toilet) =>
      'Cleaning.reportDialogTitle'.tr(namedArgs: {'toilet': toilet});
  static String get noteHint => 'Cleaning.noteHint'.tr();
  static String get send => 'Cleaning.send'.tr();
  static String get cancel => 'Cleaning.cancel'.tr();

  // Problem type labels
  static String get problemPaper => 'Cleaning.problemPaper'.tr();
  static String get problemHygiene => 'Cleaning.problemHygiene'.tr();
  static String get problemContamination => 'Cleaning.problemContamination'.tr();

  // Report result feedback
  static String get reportSuccess => 'Cleaning.reportSuccess'.tr();
  static String get reportDuplicate => 'Cleaning.reportDuplicate'.tr();
  static String get reportRateLimited => 'Cleaning.reportRateLimited'.tr();
  static String get reportError => 'Cleaning.reportError'.tr();

  // Status labels
  static String get statusOk => 'Cleaning.statusOk'.tr();
  static String get allClean => 'Cleaning.allClean'.tr();
  static String get needsAttention => 'Cleaning.needsAttention'.tr();

  // Short status labels for the compact tiles.
  static String get shortPaper => 'Cleaning.shortPaper'.tr();
  static String get shortHygiene => 'Cleaning.shortHygiene'.tr();
  static String get shortContamination => 'Cleaning.shortContamination'.tr();

  /// Short label for a status shown on a tile.
  static String statusLabelShort(String type) {
    switch (type) {
      case 'paper':
        return shortPaper;
      case 'hygiene':
        return shortHygiene;
      case 'contamination':
        return shortContamination;
      default:
        return statusOk;
    }
  }

  // Crew view
  static String get markCleaned => 'Cleaning.markCleaned'.tr();
  static String get cleanedConfirm => 'Cleaning.cleanedConfirm'.tr();
  static String get reportedBy => 'Cleaning.reportedBy'.tr();
  static String reportedAt(String time) =>
      'Cleaning.reportedAt'.tr(namedArgs: {'time': time});
  static String get anonymous => 'Cleaning.anonymous'.tr();

  /// Self-service notification opt-out toggle (crew).
  static String get notifyOnReports => 'Cleaning.notifyOnReports'.tr();

  // Crew tabs + history (feature A)
  static String get tabCurrent => 'Cleaning.tabCurrent'.tr();
  static String get tabHistory => 'Cleaning.tabHistory'.tr();
  static String get historyTitle => 'Cleaning.historyTitle'.tr();
  static String get historyEmpty => 'Cleaning.historyEmpty'.tr();
  static String get historyOpen => 'Cleaning.historyOpen'.tr();
  static String historyCleanedAt(String time) =>
      'Cleaning.historyCleanedAt'.tr(namedArgs: {'time': time});
  static String get download => 'Cleaning.download'.tr();

  // Blocking reporters (feature B)
  static String get blockReporter => 'Cleaning.blockReporter'.tr();
  static String blockReporterConfirm(String name) =>
      'Cleaning.blockReporterConfirm'.tr(namedArgs: {'name': name});
  static String get reporterBlocked => 'Cleaning.reporterBlocked'.tr();
  static String get blockedMessage => 'Cleaning.blockedMessage'.tr();

  /// Human label for a problem-type code (paper|hygiene|contamination).
  static String problemLabel(String type) {
    switch (type) {
      case 'paper':
        return problemPaper;
      case 'hygiene':
        return problemHygiene;
      case 'contamination':
        return problemContamination;
      default:
        return type;
    }
  }
}
