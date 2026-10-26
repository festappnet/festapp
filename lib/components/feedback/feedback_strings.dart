import 'package:easy_localization/easy_localization.dart';

class FeedbackStrings {
  static String get helpTitle =>
      'Feedback.helpTitle'.tr(); // "How can we help?"

  // Options
  static String get requestFeature =>
      'Feedback.requestFeature'.tr(); // "Request Feature"
  static String get reportBug => 'Feedback.reportBug'.tr(); // "Report Bug"
  static String get support => 'Feedback.support'.tr(); // "Support / Help"
  static String get other => 'Feedback.other'.tr(); // "Other / Feedback"

  // Dialog / Action
  static String get openEmailApp =>
      'Feedback.openEmailApp'.tr(); // "Open Email App"
  static String get manualInstructions => 'Feedback.manualInstructions'
      .tr(); // "Please send an email in the following format:"
  static String get copyToClipboard =>
      'Feedback.copyToClipboard'.tr(); // "Copy to clipboard"
  static String get copied => 'Feedback.copied'.tr(); // "Copied!"
  static String get emailTo => 'Feedback.emailTo'.tr(); // "To:"
  static String get emailSubject => 'Feedback.emailSubject'.tr(); // "Subject:"
  static String get emailBody => 'Feedback.emailBody'.tr(); // "Message:"
  static String get close => 'Feedback.close'.tr(); // "Close"

  // Subjects
  static String subjectFeature(String appName) => 'Feedback.subjectFeature'
      .tr(namedArgs: {'appName': appName}); // "[{appName}] Feature Request"
  static String subjectBug(String appName) => 'Feedback.subjectBug'
      .tr(namedArgs: {'appName': appName}); // "[{appName}] Bug Report"
  static String subjectSupport(String appName) => 'Feedback.subjectSupport'
      .tr(namedArgs: {'appName': appName}); // "[{appName}] Support Request"
  static String subjectGeneral(String appName) => 'Feedback.subjectGeneral'
      .tr(namedArgs: {'appName': appName}); // "[{appName}] Feedback"

  // Body Hints
  static String get hintFeature => 'Feedback.hintFeature'
      .tr(); // "I would like to suggest a feature: [Describe your idea]"
  static String get hintBug => 'Feedback.hintBug'
      .tr(); // "I encountered an issue: [Describe what happened]"
  static String get hintSupport => 'Feedback.hintSupport'
      .tr(); // "I need help with: [Describe your problem]"
  static String get hintGeneral =>
      'Feedback.hintGeneral'.tr(); // "Message: [Your feedback]"

  // Footer
  static String sentFrom(String appName) => 'Feedback.sentFrom'
      .tr(namedArgs: {'appName': appName}); // "Sent from {appName}"
}
