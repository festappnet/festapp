import 'package:easy_localization/easy_localization.dart';
import 'package:fstapp/components/_shared/common_strings.dart';

class OccasionSettingsStrings {
  static String get placeName => 'OccasionSettings.placeName'.tr();
  static String get placeNameHelp => 'OccasionSettings.placeNameHelp'.tr();

  // Form Fields
  static String get title => 'OccasionSettings.title'.tr(); // "Title"
  static String get titleIsRequired =>
      'OccasionSettings.titleIsRequired'.tr(); // "Title is required"
  static String get introImage =>
      'OccasionSettings.introImage'.tr(); // "Intro Image"
  static String imageRatioHint(String width, String height) =>
      'OccasionSettings.imageRatioHint'.tr(
        namedArgs: {
          "width": width,
          "height": height,
        },
      ); // "Image with ratio {width} : {height}"
  static String get description =>
      'OccasionSettings.description'.tr(); // "Description"
  static String get editContent =>
      'OccasionSettings.editContent'.tr(); // "Edit content"
  static String get defaultValue => CommonStrings.defaultLabel; // "default"

  // Toggles & Help
  static String get public => 'OccasionSettings.public'.tr(); // "Public"
  static String get publicHelp => 'OccasionSettings.publicHelp'
      .tr(); // "Determines whether event details (schedule, info, etc.) are available to the public."
  static String get hide => 'OccasionSettings.hide'.tr(); // "Hide"
  static String get hideHelp => 'OccasionSettings.hideHelp'
      .tr(); // "This determines whether this event is hidden from list views."

  static String get promoted => 'OccasionSettings.promoted'.tr(); // "Promoted"
  static String get promotedHelp => 'OccasionSettings.promotedHelp'
      .tr(); // "Promote this event to make it stand out in lists or on the homepage."

  // Advanced Settings
  static String get advancedSettings =>
      'OccasionSettings.advancedSettings'.tr(); // "Advanced Settings"
  static String get link => 'OccasionSettings.link'.tr(); // "Link"
  static String get linkIsRequired =>
      'OccasionSettings.linkIsRequired'.tr(); // "Link is required"
  static String get timezone => 'OccasionSettings.timezone'.tr(); // "Timezone"
  static String get timezoneIsRequired =>
      'OccasionSettings.timezoneIsRequired'.tr(); // "Timezone is required"
  static String get invalidTimezone => 'OccasionSettings.invalidTimezone'
      .tr(); // "Please select or type a valid timezone"
  static String get timezonesLoading => 'OccasionSettings.timezonesLoading'
      .tr(); // "Timezones loading or unavailable..."
  static String get invalidNumber =>
      'OccasionSettings.invalidNumber'.tr(); // "Please enter a valid number"

  // Deposit Deadline Settings
  static String get depositDeadline =>
      'OccasionSettings.depositDeadline'.tr(); // "Deposit Deadline"
  static String get depositDeadlineDaysBefore =>
      'OccasionSettings.depositDeadlineDaysBefore'
          .tr(); // "X days before occasion"
  static String get depositDeadlineOnSite =>
      'OccasionSettings.depositDeadlineOnSite'.tr(); // "On site (no deadline)"
  static String get numberOfDays =>
      'OccasionSettings.numberOfDays'.tr(); // "Number of days"

  // Meta Surcharge (visual-only info, not part of payment)
  static String get metaSurchargeDescription =>
      'OccasionSettings.metaSurchargeDescription'
          .tr(); // "Surcharge description (visual)"
  static String get metaSurchargeDescriptionHelp =>
      'OccasionSettings.metaSurchargeDescriptionHelp'
          .tr(); // "Free-form text shown under product price in form, preview, e-mail, PDF. Not a real charge."
  static String get depositModeTitle =>
      'OccasionSettings.depositModeTitle'.tr(); // "Deposit mode"
  static String get depositModeReal => 'OccasionSettings.depositModeReal'
      .tr(); // "Real deposit (payment-linked)"
  static String get depositModeVirtual => 'OccasionSettings.depositModeVirtual'
      .tr(); // "Virtual surcharge (visual only)"
  static String get depositModeRealHelp => 'OccasionSettings.depositModeRealHelp'
      .tr(); // "Customer pays the deposit upfront; the remainder is settled later or on-site."
  static String get depositModeVirtualHelp =>
      'OccasionSettings.depositModeVirtualHelp'
          .tr(); // "Shown next to products as informational; does not affect order total. Negative amounts allowed (discounts)."

  // Email Settings
  static String get labelReplyToEmail =>
      'OccasionSettings.labelReplyToEmail'.tr(); // "Reply-To Email"
  static String get helperReplyToEmail => 'OccasionSettings.helperReplyToEmail'
      .tr(); // "Replies from customers to automated emails (confirmations, reminders) will be sent to this address."
  static String get validationEmailInvalid =>
      'OccasionSettings.validationEmailInvalid'
          .tr(); // "Please enter a valid email address."

  // Features Section
  static String get features => 'OccasionSettings.features'.tr(); // "Features"
  static String get searchFeatures =>
      'OccasionSettings.searchFeatures'.tr(); // "Search features"
  static String get enabledFeatures =>
      'OccasionSettings.enabledFeatures'.tr(); // "Enabled Features"
  static String get otherFeatures =>
      'OccasionSettings.otherFeatures'.tr(); // "Other Features"
  static String get noFeaturesFound => 'OccasionSettings.noFeaturesFound'
      .tr(); // "No features match your search."

  // Dialogs & Toasts
  static String get deleteEvent =>
      'OccasionSettings.deleteEvent'.tr(); // "Delete Event"
  static String get deleteEventConfirmation =>
      'OccasionSettings.deleteEventConfirmation'
          .tr(); // "Are you sure you want to delete this event? All the event data will be lost."

  static String get cannotDeleteWithOrders =>
      'OccasionSettings.cannotDeleteWithOrders'
          .tr(); // "Cannot delete event because it contains orders (including storno)."

  static String get confirmRemoval =>
      'OccasionSettings.confirmRemoval'.tr(); // "Confirm removal"
  static String get deleteImageConfirmation =>
      'OccasionSettings.deleteImageConfirmation'
          .tr(); // "Are you sure you want to delete this image?"
  static String get imageRemovedSuccess =>
      'OccasionSettings.imageRemovedSuccess'
          .tr(); // "Image removed successfully."
  static String get imageRemovedFail =>
      'OccasionSettings.imageRemovedFail'.tr(); // "Failed to remove image."
  static String get fileUploadedSuccess =>
      'OccasionSettings.fileUploadedSuccess'
          .tr(); // "File uploaded successfully."
  static String get failedToUploadImage =>
      'OccasionSettings.failedToUploadImage'.tr(); // "Failed to upload image."
}
