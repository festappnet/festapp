import 'package:easy_localization/easy_localization.dart';

class EmailTemplatesStrings {
  static String get recommended => 'EmailTemplates.authoring.recommended'.tr();
  static String get usedBlocks => 'EmailTemplates.authoring.usedBlocks'.tr();
  static String scenarioName(String value) =>
      'EmailTemplates.authoring.$value'.tr();
  static String toneName(String value) =>
      'EmailTemplates.authoring.$value'.tr();
  static String get authoringHint =>
      'EmailTemplates.authoring.authoringHint'.tr();
  static String get insertVariable =>
      'EmailTemplates.authoring.insertVariable'.tr();
  static String get noVariable => 'EmailTemplates.authoring.noVariable'.tr();
  static String get alreadyUsed => 'EmailTemplates.authoring.alreadyUsed'.tr();
  static String get sampleData => 'EmailTemplates.authoring.sampleData'.tr();
  static String get variable => 'EmailTemplates.authoring.variable'.tr();
  static String get previewUnavailable =>
      'EmailTemplates.authoring.previewUnavailable'.tr();
  static String get preview => 'EmailTemplates.authoring.preview'.tr();
  static String get previewScope =>
      'EmailTemplates.authoring.previewScope'.tr();
  static String get scenario => 'EmailTemplates.authoring.scenario'.tr();
  static String get replaceVariable =>
      'EmailTemplates.authoring.replaceVariable'.tr();
  static String get keepText => 'EmailTemplates.authoring.keepText'.tr();
  static String get unknownVariable =>
      'EmailTemplates.authoring.unknownVariable'.tr();
  static String suggestTitle(String title) =>
      'EmailTemplates.authoring.suggestTitle'.tr(args: [title]);

  static String get subParticipantCount =>
      'EmailTemplates.subs.participantCount'.tr();
  static String get subManageWaitlistUrl =>
      'EmailTemplates.subs.manageWaitlistUrl'.tr();
  static String get subManageWaitlistButton =>
      'EmailTemplates.subs.manageWaitlistButton'.tr();
  static String get subOfferedCount => 'EmailTemplates.subs.offeredCount'.tr();
  static String get subOfferExpiresAt =>
      'EmailTemplates.subs.offerExpiresAt'.tr();
  static String get subOfferUrl => 'EmailTemplates.subs.offerUrl'.tr();
  static String get subOfferButton => 'EmailTemplates.subs.offerButton'.tr();
  static String get usageWaitlistConfirmationTitle =>
      'EmailTemplates.usage.waitlistConfirmation_title'.tr();
  static String get usageWaitlistConfirmationDescription =>
      'EmailTemplates.usage.waitlistConfirmation_description'.tr();
  static String get usageWaitlistOfferTitle =>
      'EmailTemplates.usage.waitlistOffer_title'.tr();
  static String get usageWaitlistOfferDescription =>
      'EmailTemplates.usage.waitlistOffer_description'.tr();
  // --- Substitution Descriptions ---
  static String get subPlatformLinks =>
      'EmailTemplates.subs.platformLinks'.tr();
  static String get subAppName => 'EmailTemplates.subs.appName'.tr();
  static String get subEmail => 'EmailTemplates.subs.email'.tr();
  static String get subName => 'EmailTemplates.subs.name'.tr();
  static String get subSurname => 'EmailTemplates.subs.surname'.tr();
  static String get subResetLink => 'EmailTemplates.subs.resetLink'.tr();
  static String get subSignInCode => 'EmailTemplates.subs.signInCode'.tr();
  static String get subOccasionTitle =>
      'EmailTemplates.subs.occasionTitle'.tr();
  static String get subAmount => 'EmailTemplates.subs.amount'.tr();
  static String get subAccountNumber =>
      'EmailTemplates.subs.accountNumber'.tr();
  static String get subIban => 'EmailTemplates.subs.iban'.tr();
  static String get subVariableSymbol =>
      'EmailTemplates.subs.variableSymbol'.tr();
  static String get subDeadline => 'EmailTemplates.subs.deadline'.tr();
  static String get subFullOrder => 'EmailTemplates.subs.fullOrder'.tr();
  static String get subChangeOverview =>
      'EmailTemplates.subs.changeOverview'.tr();
  static String get subBalanceReasoning =>
      'EmailTemplates.subs.balanceReasoning'.tr();
  static String get subPaymentDetails =>
      'EmailTemplates.subs.paymentDetails'.tr();
  static String get subRemainingTime =>
      'EmailTemplates.subs.remainingTime'.tr();
  static String get subConfirmationUrl =>
      'EmailTemplates.subs.confirmationUrl'.tr();
  static String get subExpiresAt => 'EmailTemplates.subs.expiresAt'.tr();

  // --- Template Usage Details ---

  // RESET_PASSWORD
  static String get usageResetPasswordTitle =>
      'EmailTemplates.usage.resetPassword_title'.tr();
  static String get usageResetPasswordDescription =>
      'EmailTemplates.usage.resetPassword_description'.tr();

  // SIGN_IN_CODE
  static String get usageSignInCodeTitle =>
      'EmailTemplates.usage.signInCode_title'.tr();
  static String get usageSignInCodeDescription =>
      'EmailTemplates.usage.signInCode_description'.tr();
  static String get usageAppLinksTitle =>
      'EmailTemplates.usage.appLinks_title'.tr();
  static String get usageAppLinksDescription =>
      'EmailTemplates.usage.appLinks_description'.tr();
  static String get usageAccountDeletionConfirmTitle =>
      'EmailTemplates.usage.accountDeletionConfirm_title'.tr();
  static String get usageAccountDeletionConfirmDescription =>
      'EmailTemplates.usage.accountDeletionConfirm_description'.tr();
  static String get usageAccountDeletionCompleteTitle =>
      'EmailTemplates.usage.accountDeletionComplete_title'.tr();
  static String get usageAccountDeletionCompleteDescription =>
      'EmailTemplates.usage.accountDeletionComplete_description'.tr();

  // TICKET_ORDER_CONFIRMATION
  static String get usageTicketOrderConfirmationTitle =>
      'EmailTemplates.usage.ticketOrderConfirmation_title'.tr();
  static String get usageTicketOrderConfirmationDescription =>
      'EmailTemplates.usage.ticketOrderConfirmation_description'.tr();

  // TICKET_ORDER_UPDATE
  static String get usageTicketOrderUpdateTitle =>
      'EmailTemplates.usage.ticketOrderUpdate_title'.tr();
  static String get usageTicketOrderUpdateDescription =>
      'EmailTemplates.usage.ticketOrderUpdate_description'.tr();

  // TICKET_ORDER_PAYMENT_DONE
  static String get usageTicketOrderPaymentDoneTitle =>
      'EmailTemplates.usage.ticketOrderPaymentDone_title'.tr();
  static String get usageTicketOrderPaymentDoneDescription =>
      'EmailTemplates.usage.ticketOrderPaymentDone_description'.tr();

  // TICKET_ORDER_PAYMENT_REMINDER
  static String get usageTicketOrderPaymentReminderTitle =>
      'EmailTemplates.usage.ticketOrderPaymentReminder_title'.tr();
  static String get usageTicketOrderPaymentReminderDescription =>
      'EmailTemplates.usage.ticketOrderPaymentReminder_description'.tr();

  // TICKET_ORDER_STORNO
  static String get usageTicketOrderStornoTitle =>
      'EmailTemplates.usage.ticketOrderStorno_title'.tr();
  static String get usageTicketOrderStornoDescription =>
      'EmailTemplates.usage.ticketOrderStorno_description'.tr();

  // Settings
  static String get title => 'EmailTemplates.title'.tr();
  static String get settingsTitle => 'EmailTemplates.settings.title'.tr();
  static String get settingsBanner => 'EmailTemplates.settings.banner'.tr();
  static String get settingsBannerDescriptionOccasion =>
      'EmailTemplates.settings.bannerDescriptionOccasion'.tr();
  static String get settingsBannerDescriptionOrganization =>
      'EmailTemplates.settings.bannerDescriptionOrganization'.tr();
  static String get settingsBannerHint =>
      'EmailTemplates.settings.bannerHint'.tr();
  static String get settingsImageUploaded =>
      'EmailTemplates.settings.imageUploaded'.tr();
  static String get settingsUploadFailed =>
      'EmailTemplates.settings.uploadFailed'.tr();
  static String get resetToDefault =>
      'EmailTemplates.settings.resetToDefault'.tr();
  static String get defaultTemplateInUse =>
      'EmailTemplates.settings.defaultTemplateInUse'.tr();
  static String get defaultTemplateInfo =>
      'EmailTemplates.settings.defaultTemplateInfo'.tr();
  static String get resetConfirmTitle =>
      'EmailTemplates.settings.resetConfirmTitle'.tr();
  static String get resetConfirmContent =>
      'EmailTemplates.settings.resetConfirmContent'.tr();
  static String get statusLabel => 'EmailTemplates.settings.statusLabel'.tr();
  static String get statusOccasionOverride =>
      'EmailTemplates.settings.statusOccasionOverride'.tr();
  static String get statusUnit => 'EmailTemplates.settings.statusUnit'.tr();
  static String get statusUnitInherited =>
      'EmailTemplates.settings.statusUnitInherited'.tr();
  static String get statusNoBanner =>
      'EmailTemplates.settings.statusNoBanner'.tr();

  // --- Template editor dialog ---
  static String get availableSubstitutions =>
      'EmailTemplates.availableSubstitutions'
          .tr(); // "Available Substitutions:"
  static String get subject => 'EmailTemplates.subject'.tr(); // "Subject"
  static String get subjectRequired =>
      'EmailTemplates.subjectRequired'.tr(); // "Subject is required"
  static String get emailTemplateContent =>
      'EmailTemplates.emailTemplateContent'.tr(); // "Email Template Content"

  // --- Template card ---
  static String get template => 'EmailTemplates.template'.tr(); // "Template"
}
