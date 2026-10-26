import 'package:easy_localization/easy_localization.dart';

/// Localized strings for the EventFeedback feature.
/// Keys live under "EventFeedback" / "FeatureEventFeedback" in translations.
class EventFeedbackStrings {
  static String get featureTitle => 'FeatureEventFeedback.title'.tr();
  static String get featureDescription =>
      'FeatureEventFeedback.description'.tr();

  static String get howWasThisEvent => 'EventFeedback.howWasThisEvent'.tr();
  static String get positive => 'EventFeedback.positive'.tr();
  static String get neutral => 'EventFeedback.neutral'.tr();
  static String get negative => 'EventFeedback.negative'.tr();
  static String get rating => 'EventFeedback.rating'.tr();
  static String get optionalComment => 'EventFeedback.optionalComment'.tr();
  static String get comment => 'EventFeedback.comment'.tr();
  static String get sendFeedback => 'EventFeedback.sendFeedback'.tr();
  static String get updateFeedback => 'EventFeedback.updateFeedback'.tr();
  static String get saveComment => 'EventFeedback.saveComment'.tr();
  static String get removeFeedback => 'EventFeedback.removeFeedback'.tr();
  static String get chooseRatingFirst => 'EventFeedback.chooseRatingFirst'.tr();
  static String get feedbackSavedThankYou =>
      'EventFeedback.feedbackSavedThankYou'.tr();
  static String get feedbackCouldNotBeSaved =>
      'EventFeedback.feedbackCouldNotBeSaved'.tr();
  static String get feedbackRemoved => 'EventFeedback.feedbackRemoved'.tr();
  static String get feedbackTextTooLong =>
      'EventFeedback.feedbackTextTooLong'.tr();
  static String get signInRequired => 'EventFeedback.signInRequired'.tr();
  static String get onlySignedInParticipants =>
      'EventFeedback.onlySignedInParticipants'.tr();
  static String get feedbackOpensWhenEventStarts =>
      'EventFeedback.feedbackOpensWhenEventStarts'.tr();
  static String get editorPreviewBeforeStart =>
      'EventFeedback.editorPreviewBeforeStart'.tr();
  static String get showSmileyFeedbackAfterStart =>
      'EventFeedback.showSmileyFeedbackAfterStart'.tr();
  static String get anonymous => 'EventFeedback.anonymous'.tr();
  static String get yes => 'EventFeedback.yes'.tr();
  static String get no => 'EventFeedback.no'.tr();

  // Admin / results
  static String get enableEventFeedback =>
      'EventFeedback.enableEventFeedback'.tr();
  static String get feedbackResults => 'EventFeedback.feedbackResults'.tr();
  static String get noFeedbackYet => 'EventFeedback.noFeedbackYet'.tr();
  static String get exportFeedbackCsv => 'EventFeedback.exportFeedbackCsv'.tr();
  static String get refresh => 'EventFeedback.refresh'.tr();
  static String get respondent => 'EventFeedback.respondent'.tr();
  static String get submittedAt => 'EventFeedback.submittedAt'.tr();
  static String get updatedAt => 'EventFeedback.updatedAt'.tr();
  static String get event => 'EventFeedback.event'.tr();
  static String get from => 'EventFeedback.from'.tr();
  static String get to => 'EventFeedback.to'.tr();

  /// Human label for a rating code (happy|neutral|sad).
  static String ratingLabel(String rating) {
    switch (rating) {
      case 'happy':
        return positive;
      case 'sad':
        return negative;
      case 'neutral':
      default:
        return neutral;
    }
  }
}
