import 'package:easy_localization/easy_localization.dart';

/// Localized strings for the news feature.
/// Keys live under the "FeatureNews" namespace in assets/translations/*.json.
class NewsStrings {
  static String get news => 'FeatureNews.news'.tr(); // "News"
  static String get test => 'FeatureNews.test'.tr(); // "Test"
  static String get noMessagesYet =>
      'FeatureNews.noMessagesYet'.tr(); // "No news messages yet"

  // Form
  static String get createNews =>
      'FeatureNews.createNews'.tr(); // "Create news"
  static String get heading => 'FeatureNews.heading'.tr(); // "Heading"
  static String get sendWithNotification =>
      'FeatureNews.sendWithNotification'.tr(); // "Send with notification"
  static String get publishAndSend => 'FeatureNews.publishAndSend'.tr();
  static String get publishWithoutNotification =>
      'FeatureNews.publishWithoutNotification'.tr();
  static String get newsWithoutNotification =>
      'FeatureNews.newsWithoutNotification'.tr();
  static String get newsWithoutNotificationDetail =>
      'FeatureNews.newsWithoutNotificationDetail'.tr();
  static String get recipientChoiceTitle =>
      'FeatureNews.recipientChoiceTitle'.tr();
  static String get recipientChoiceRequired =>
      'FeatureNews.recipientChoiceRequired'.tr();
  static String notificationAudienceSelfDetail(String identity) =>
      'FeatureNews.notificationAudienceSelfDetail'
          .tr(namedArgs: {'identity': identity});
  static String get publishAndSendSelf => 'FeatureNews.publishAndSendSelf'.tr();
  static String get publishAndSendEveryone =>
      'FeatureNews.publishAndSendEveryone'.tr();
  static String get selectRecipients => 'FeatureNews.selectRecipients'.tr();
  static String get contentRequired => 'FeatureNews.contentRequired'.tr();

  // Notification confirmation
  static String get notificationAudienceTitle =>
      'FeatureNews.notificationAudienceTitle'.tr();
  static String notificationAudienceEveryone(String appName) =>
      'FeatureNews.notificationAudienceEveryone'
          .tr(namedArgs: {'appName': appName});
  static String get notificationAudienceEveryoneDetail =>
      'FeatureNews.notificationAudienceEveryoneDetail'.tr();
  static String get notificationAudienceSelf =>
      'FeatureNews.notificationAudienceSelf'.tr();
  static String get notificationPreviewTitle =>
      'FeatureNews.notificationPreviewTitle'.tr();
  static String get confirmSendTitle => 'FeatureNews.confirmSendTitle'.tr();
  static String get confirmTestSendTitle =>
      'FeatureNews.confirmTestSendTitle'.tr();
  static String get sendExplanation => 'FeatureNews.sendExplanation'.tr();
  static String get testSendExplanation =>
      'FeatureNews.testSendExplanation'.tr();
  static String get notificationCannotBeRecalled =>
      'FeatureNews.notificationCannotBeRecalled'.tr();
  static String get confirmSend => 'FeatureNews.confirmSend'.tr();
  static String get confirmTestSend => 'FeatureNews.confirmTestSend'.tr();
  static String get cancel => 'FeatureNews.cancel'.tr();

  // Feedback
  static String get messageSent =>
      'FeatureNews.messageSent'.tr(); // "Message has been sent."
  static String get messageSentToSelf => 'FeatureNews.messageSentToSelf'.tr();
  static String get messageSentToEveryone =>
      'FeatureNews.messageSentToEveryone'.tr();
  static String get testSentToSelf => 'FeatureNews.testSentToSelf'.tr();
  static String get messageCreatedWithoutNotification =>
      'FeatureNews.messageCreatedWithoutNotification'.tr();
  static String get messageCreated =>
      'FeatureNews.messageCreated'.tr(); // "Message has been created."
  static String get messageChanged =>
      'FeatureNews.messageChanged'.tr(); // "Message has been changed."
  static String get messageRemoved =>
      'FeatureNews.messageRemoved'.tr(); // "Message has been removed."
}
