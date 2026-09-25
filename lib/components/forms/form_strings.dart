import 'package:easy_localization/easy_localization.dart';
import 'package:fstapp/components/_shared/common_strings.dart';

class FormStrings {
// Form Settings Feature
  static String get formSettingsTitle => 'FeatureFormSettings.title'.tr();
  static String get formNotFound => 'FeatureFormSettings.formNotFound'.tr();
  static String get labelFormTitle => 'FeatureFormSettings.labelFormTitle'.tr();
  static String get labelFormLink => 'FeatureFormSettings.labelFormLink'.tr();
  static String get validationLinkRequired =>
      'FeatureFormSettings.validationLinkRequired'.tr();
  static String get validationLinkInvalidChars =>
      'FeatureFormSettings.validationLinkInvalidChars'.tr();
  static String get validationLinkInUse =>
      'FeatureFormSettings.validationLinkInUse'.tr();
  static String get labelDeadlineDays =>
      'FeatureFormSettings.labelDeadlineDays'.tr();
  static String get helperDeadlineDays =>
      'FeatureFormSettings.helperDeadlineDays'.tr();
  static String get labelCardDesign =>
      'FeatureFormSettings.labelCardDesign'.tr();
  static String get subtitleCardDesign =>
      'FeatureFormSettings.subtitleCardDesign'.tr();
  static String get errorFixBeforeSave =>
      'FeatureFormSettings.errorFixBeforeSave'.tr();
  static String get labelUseExternalForm =>
      'FeatureFormSettings.labelUseExternalForm'.tr();
  static String get labelReservationLink =>
      'FeatureFormSettings.labelReservationLink'.tr();
  static String get helperReservationLink =>
      'FeatureFormSettings.helperReservationLink'.tr();
  static String get labelPrice => 'FeatureFormSettings.labelPrice'.tr();
  static String get helperPrice => 'FeatureFormSettings.helperPrice'.tr();
  static String get labelAdvancedSettings =>
      'FeatureFormSettings.labelAdvancedSettings'.tr();
  static String get labelReserveButtonTitle =>
      'FeatureFormSettings.labelReserveButtonTitle'.tr();
  static String get labelDeadlineDuration =>
      'FeatureFormSettings.labelDeadlineDuration'.tr();
  static String get helperDeadlineDuration =>
      'FeatureFormSettings.helperDeadlineDuration'.tr();
  static String get labelReminderEnabled =>
      'FeatureFormSettings.labelReminderEnabled'.tr();
  static String get helperReminderEnabled =>
      'FeatureFormSettings.helperReminderEnabled'.tr();
  static String get labelReminderInterval =>
      'FeatureFormSettings.labelReminderInterval'.tr();
  static String get helperReminderInterval =>
      'FeatureFormSettings.helperReminderInterval'.tr();
  static String get validationReminderInterval =>
      'FeatureFormSettings.validationReminderInterval'.tr();
  static String get labelEnableReminders =>
      'FeatureFormSettings.labelEnableReminders'.tr();
  static String get subtitleEnableReminders =>
      'FeatureFormSettings.subtitleEnableReminders'.tr();
  static String get subtitleRemindersDisabled =>
      'FeatureFormSettings.subtitleRemindersDisabled'.tr();
  static String get paymentDetailsTitle =>
      'FeatureFormSettings.paymentDetailsTitle'.tr();
  static String get labelVariableSymbol =>
      'FeatureFormSettings.labelVariableSymbol'.tr();
  static String get vsTypeRandom => 'FeatureFormSettings.vsTypeRandom'.tr();
  static String get vsTypeSequence => 'FeatureFormSettings.vsTypeSequence'.tr();
  static String get labelStartingNumber =>
      'FeatureFormSettings.labelStartingNumber'.tr();
  static String get helperStartingNumber =>
      'FeatureFormSettings.helperStartingNumber'.tr();
  static String get labelPaymentMessage =>
      'FeatureFormSettings.labelPaymentMessage'.tr();
  static String get msgTypeNameSurname =>
      'FeatureFormSettings.msgTypeNameSurname'.tr();
  static String get msgTypeNone => 'FeatureFormSettings.msgTypeNone'.tr();
  static String get msgTypeOccasionTitle =>
      'FeatureFormSettings.msgTypeOccasionTitle'.tr();

  static String get communicationToneTitle =>
      'FeatureFormSettings.communicationToneTitle'.tr(); // "Communication Tone"
  static String get helperCommunicationTone =>
      'FeatureFormSettings.helperCommunicationTone'
          .tr(); // "Select the tone for automated communications, like payment confirmation emails or reminders. This will affect the wording in the email templates."
  static String get labelCommunicationTone =>
      'FeatureFormSettings.labelCommunicationTone'.tr(); // "Tone"
  static String get toneFormal =>
      'FeatureFormSettings.toneFormal'.tr(); // "Formal"
  static String toneInherit(String tone) =>
      'FeatureFormSettings.toneInherit'.tr(namedArgs: {'tone': tone});
  static String get toneInformal =>
      'FeatureFormSettings.toneInformal'.tr(); // "Informal "
  static String get pickColor =>
      'FeatureFormSettings.pickColor'.tr(); // "Pick a color"
  static String get buttonGotIt =>
      'FeatureFormSettings.buttonGotIt'.tr(); // "Got it"
  static String get designPresets =>
      'FeatureFormSettings.designPresets'.tr(); // "Design Presets"
  static String get more => 'FeatureFormSettings.more'.tr(); // "More"
  static String get less => 'FeatureFormSettings.less'.tr(); // "Less"
  static String get customColors =>
      'FeatureFormSettings.customColors'.tr(); // "Custom Colors"
  static String get primaryColor =>
      'FeatureFormSettings.primaryColor'.tr(); // "Primary Color"
  static String get typography =>
      'FeatureFormSettings.typography'.tr(); // "Typography"
  static String get browseGoogleFonts =>
      'FeatureFormSettings.browseGoogleFonts'.tr(); // "Browse Google Fonts"
  static String get currentFont =>
      'FeatureFormSettings.currentFont'.tr(); // "Current Font: "
  static String get defaultFont =>
      'FeatureFormSettings.defaultFont'.tr(); // "Default"
  static String get resetToDefault =>
      'FeatureFormSettings.resetToDefault'.tr(); // "Reset to Default"
  static String get choosePopularFonts =>
      'FeatureFormSettings.choosePopularFonts'
          .tr(); // "Choose from Popular Fonts"
  static String get selectFromList =>
      'FeatureFormSettings.selectFromList'.tr(); // "Select from list..."
  static String get or => 'FeatureFormSettings.or'.tr(); // "OR"
  static String get customFontNameLabel =>
      'FeatureFormSettings.customFontNameLabel'
          .tr(); // "Custom Google Font Name"
  static String get customFontHelper => 'FeatureFormSettings.customFontHelper'
      .tr(); // "Paste the exact font title from Google Fonts (e.g. 'Roboto Condensed')."
  static String get fontNotFound => 'FeatureFormSettings.fontNotFound'
      .tr(); // "Font not found. Please paste the exact name from fonts.google.com"
  static String get hexCodeLabel =>
      'FeatureFormSettings.hexCodeLabel'.tr(); // "Hex Code"
  static String get days => 'FeatureFormSettings.days'.tr(); // "Days"
  static String get hours => 'FeatureFormSettings.hours'.tr(); // "Hours"
  static String get minutes => 'FeatureFormSettings.minutes'.tr(); // "Minutes"
  static String get seconds => 'FeatureFormSettings.seconds'.tr(); // "Seconds"
  static String get previewMode =>
      'FeatureFormSettings.previewMode'.tr(); // "PREVIEW MODE"
  static String get registrationStart =>
      'FeatureFormSettings.registrationStart'.tr(); // "Registration Start"
  static String get reservationUnavailable =>
      'FeatureFormSettings.reservationUnavailable'
          .tr(); // "Reservation Unavailable"
  static String get reservationUnavailableMessage =>
      'FeatureFormSettings.reservationUnavailableMessage'
          .tr(); // "Reservation for the selected event is currently unavailable."
  static String get availability =>
      'FeatureFormSettings.availability'.tr(); // "Availability"
  static String get formClosedMessage =>
      'FeatureFormSettings.formClosedMessage'.tr(); // "Form is CLOSED."
  static String scheduledWithTime(String time) =>
      'FeatureFormSettings.scheduledWithTime'
          .tr(namedArgs: {'time': time}); // "Scheduled (Starts: {time})"
  static String endedWithTime(String time) =>
      'FeatureFormSettings.endedWithTime'
          .tr(namedArgs: {'time': time}); // "Ended (Closed: {time})"
  static String get formOpenMessage => 'FeatureFormSettings.formOpenMessage'
      .tr(); // "Form is OPEN & accepting responses."
  static String get scheduleAndLimits =>
      'FeatureFormSettings.scheduleAndLimits'.tr(); // "Schedule & Limits"
  static String get autoOpenHelp =>
      'FeatureFormSettings.autoOpenHelp'.tr(); // "Auto-open/close times."
  static String get labelStartTime =>
      'FeatureFormSettings.labelStartTime'.tr(); // "Start Time"
  static String get labelEndTime =>
      'FeatureFormSettings.labelEndTime'.tr(); // "End Time"
  static String get errorEndTimeBeforeStartTime =>
      'FeatureFormSettings.errorEndTimeBeforeStartTime'
          .tr(); // "End time cannot be before start time."
  static String get labelCountdownTimer =>
      'FeatureFormSettings.labelCountdownTimer'.tr(); // "Countdown Timer"
  static String get requiresStartTime =>
      'FeatureFormSettings.requiresStartTime'.tr(); // "Requires Start Time."
  static String get countdownDescription =>
      'FeatureFormSettings.countdownDescription'
          .tr(); // "Displayed before scheduled start time."
  static String get labelCountdownMessage =>
      'FeatureFormSettings.labelCountdownMessage'.tr(); // "Countdown Message:"
  static String get labelClosedMessage =>
      'FeatureFormSettings.labelClosedMessage'.tr(); // "Closed Message"
  static String get labelMessageContent =>
      'FeatureFormSettings.labelMessageContent'.tr(); // "Message Content"
  static String get helperClosedMessage =>
      'FeatureFormSettings.helperClosedMessage'
          .tr(); // "Shown when form is closed / inactive."
  static String get notSet => 'FeatureFormSettings.notSet'.tr(); // "Not set"
  static String get publicView =>
      'FeatureFormSettings.publicView'.tr(); // "Public View"
  static String get editorPreview =>
      'FeatureFormSettings.editorPreview'.tr(); // "Editor Preview"
  static String get buttonContinue =>
      CommonStrings.continueAction; // "Continue" (Global key)

  // --- Form Fields (General) ---
  static String get noOptionsForCurrency =>
      'FormsFeature.noOptionsForCurrency'.tr();
  static String get clearSelection => 'FormsFeature.clearSelection'.tr();
  static String get unavailable => 'FormsFeature.unavailable'.tr();
  static String get inWhatCurrency => 'FormsFeature.inWhatCurrency'.tr();
  static String get depositOnSite => 'OrderGridColumns.depositOnSite'.tr();
  static String get depositInfo => 'OrderGridColumns.depositInfo'.tr();

// --- FormsTab (Main Grid View) ---
  static String get formsTitle => 'FormsFeature.formsTitle'.tr(); // "Forms"
  static String get createNewForm =>
      'FormsFeature.createNewForm'.tr(); // "Create/Copy Form"
  // --- There are no forms for this event. Click '{createNew}' to add one.
  static String noFormsForEventPrompt(String createNew) =>
      'FormsFeature.noFormsForEventPrompt'
          .tr(namedArgs: {'createNew': createNew});
  static String get createCopy =>
      'FormsFeature.createCopy'.tr(); // "Create Copy"
  static String get statusOpen =>
      'FormsFeature.statusOpen'.tr(); // "Form is Open"
  static String get statusClosed =>
      'FormsFeature.statusClosed'.tr(); // "Closed"
  static String get responses => 'FormsFeature.responses'.tr(); // "Responses"
  static String get duplicateSuccess =>
      'FormsFeature.duplicateSuccess'.tr(); // "Form duplicated successfully!"
  static String get deleteFormTitle => 'FormsFeature.deleteFormTitle'.tr();
  static String get deleteFormContent => 'FormsFeature.deleteFormContent'.tr();
  static String get cannotDeleteFormWithResponses =>
      'FormsFeature.cannotDeleteFormWithResponses'.tr();

// --- FormTab (The TabBar holder) ---
  static String get tabForm => 'FormsFeature.tabForm'.tr(); // "Form"
  static String get tabResponses =>
      'FormsFeature.tabResponses'.tr(); // "Responses" (can be reused)

// --- FormCreationHelper (Creation Dialog) ---
  static String get defaultFormTitle =>
      'FormsFeature.defaultFormTitle'.tr(); // "new-form"
  static String get formAvailableAt =>
      'FormsFeature.formAvailableAt'.tr(); // "This form will be available at"
  static String get formCreatedSuccess =>
      'FormsFeature.formCreatedSuccess'.tr(); // "Form created successfully!"

// --- FormEditorContent (Form Editor Tab) ---
  static String get formTurnedOff =>
      'FormsFeature.formTurnedOff'.tr(); // "This form is currently turned off"
  static String get editOffText =>
      'FormsFeature.editOffText'.tr(); // "Edit off text"
  static String get editContent =>
      'FormsFeature.editContent'.tr(); // "Edit content"
  static String get dragToReorder =>
      'FormsFeature.dragToReorder'.tr(); // "Drag to reorder fields"
  static String get addFieldTitle =>
      'FormsFeature.addFieldTitle'.tr(); // "Add Field"
  static String get personalInfo =>
      'FormsFeature.personalInfo'.tr(); // "Personal Info"
  static String get noFieldsAvailable =>
      'FormsFeature.noFieldsAvailable'.tr(); // "No fields available to add."

// --- Form Editor (Ticket Editor) ---
  static String get addProductTypeTitle =>
      'FormsFeature.addProductTypeTitle'.tr();
  static String get createNewProductTypeOption =>
      'FormsFeature.createNewProductTypeOption'.tr();
  static String get untitledProductType =>
      'FormsFeature.untitledProductType'.tr();
  static String get noProductTypesToAdd =>
      'FormsFeature.noProductTypesToAdd'.tr();
  static String get newProductTypeDefaultName =>
      'FormsFeature.newProductTypeDefaultName'.tr();

  static String get typeHere => 'FormsFeature.typeHere'.tr();
  static String get typeHere_informal => 'FormsFeature.typeHere_informal'.tr();
  static String get phoneFormatHint => 'FormsFeature.phoneFormatHint'.tr();
  static String get phoneFormatValidation =>
      'FormsFeature.phoneFormatValidation'.tr();

  // --- Strings from TicketEditorWidgets ---
  static String get noProductTypes =>
      'FormsFeature.noProductTypes'.tr(); // "No Product Types"
  static String get productTypes =>
      'FormsFeature.productTypes'.tr(); // "ProductTypes"
  static String get seatSelection =>
      'FormsFeature.seatSelection'.tr(); // "Seat selection"
  static String get note => 'FormsFeature.note'.tr(); // "Note"
  // --- Strings for TicketEditorWidgets (Max Tickets) ---
  static String get labelMaxTicketsPerOrder =>
      'FormsFeature.labelMaxTicketsPerOrder'.tr(); // "Max tickets per order:"
  static String get helperMaxTicketsPerOrder =>
      'FormsFeature.helperMaxTicketsPerOrder'
          .tr(); // "How many tickets a user can buy in a single order (default: 1)."
  static String get validationMaxTicketsInvalid =>
      'FormsFeature.validationMaxTicketsInvalid'
          .tr(); // "Please enter a valid number (1 or more)."
  static String get showDepositDescription =>
      'FormsFeature.showDepositDescription'.tr();
  static String get defaultSelectionHintSingle =>
      'FormsFeature.defaultSelectionHintSingle'.tr();
  static String get defaultSelectionHintMulti =>
      'FormsFeature.defaultSelectionHintMulti'.tr();
  static String get clearDefaultSelection =>
      'FormsFeature.clearDefaultSelection'.tr();

// --- Create/Copy Dialog (_CreateOrCopyFormDialog) ---
  static String get createFormTitle =>
      'FormsFeature.createFormTitle'.tr(); // "Create a Form"
  static String get createNewBlankForm =>
      'FormsFeature.createNewBlankForm'.tr(); // "Create a new blank form"
  static String get orCreateFromCopy => 'FormsFeature.orCreateFromCopy'
      .tr(); // "Or create a copy from an existing form:"
  static String get searchFormsToCopy =>
      'FormsFeature.searchFormsToCopy'.tr(); // "Search forms to copy..."
  static String get groupHappeningNow =>
      'FormsFeature.groupHappeningNow'.tr(); // "Happening Now"
  static String get groupUpcoming =>
      'FormsFeature.groupUpcoming'.tr(); // "Upcoming"
  static String get groupOther => 'FormsFeature.groupOther'.tr(); // "Other"
  static String numberOfResponsesTooltip(int count) =>
      'FormsFeature.numberOfResponsesTooltip'.tr(namedArgs: {
        'count': count.toString()
      }); // "Number of responses: {count}"

// --- Field & Product Editors (widgets_editor) ---
  static String get addProduct =>
      'FormsFeature.addProduct'.tr(); // "Add Product"
  static String get addDescription =>
      'FormsFeature.addDescription'.tr(); // "Add description"
  static String get additionalSettings =>
      'FormsFeature.additionalSettings'.tr(); // "Additional Settings"
  static String get answerText =>
      'FormsFeature.answerText'.tr(); // "Answer text"
  static String get constraints =>
      'FormsFeature.constraints'.tr(); // "Constraints"
  static String get enterZeroForUnlimited =>
      'FormsFeature.enterZeroForUnlimited'.tr(); // "Enter 0 for unlimited"
  static String get enterOptionValue =>
      'FormsFeature.enterOptionValue'.tr(); // "Enter option value"
  static String get expiryDateLabel =>
      'FormsFeature.expiryDateLabel'.tr(); // "Expiry Date Label"
  static String get idCardPassportNumber =>
      'FormsFeature.idCardPassportNumber'.tr(); // "ID Card / Passport Number"
  static String get minAge => 'FormsFeature.minAge'.tr(); // "Min Age"
  static String get maxAge => 'FormsFeature.maxAge'.tr(); // "Max Age"
  static String get maxAgeLowerThanMinAge =>
      'FormsFeature.maxAgeLowerThanMinAge'
          .tr(); // "Max age cannot be lower than min age."
  static String get multipleChoice =>
      'FormsFeature.multipleChoice'.tr(); // "Multiple Choice"
  static String get singleChoice =>
      'FormsFeature.singleChoice'.tr(); // "Single Choice"
  static String get newProduct =>
      'FormsFeature.newProduct'.tr(); // "New Product"
  static String get noProducts =>
      'FormsFeature.noProducts'.tr(); // "No Products"
  static String get noOptions => 'FormsFeature.noOptions'.tr(); // "No options"
  static String get options => 'FormsFeature.options'.tr(); // "Options"
  static String get productQuantity =>
      'FormsFeature.productQuantity'.tr(); // "Product Quantity"
  static String get productType =>
      'FormsFeature.productType'.tr(); // "Product Type"
  static String get productTypeTitle =>
      'FormsFeature.productTypeTitle'.tr(); // "Product Type Title"
  static String get requiredLabel =>
      'FormsFeature.requiredLabel'.tr(); // "Required"
  static String get show => 'FormsFeature.show'.tr(); // "Show"
  static String get showExpiryDate =>
      'FormsFeature.showExpiryDate'.tr(); // "Show Expiry Date"
  static String get strict => 'FormsFeature.strict'.tr(); // "Strict"
  static String get strictValidation =>
      'FormsFeature.strictValidation'.tr(); // "Strict Validation"
  static String get validationMode =>
      'FormsFeature.validationMode'.tr(); // "Validation Mode"
  static String get textFieldType =>
      'FormsFeature.textFieldType'.tr(); // "Text"
  static String get viewMore => 'FormsFeature.viewMore'.tr(); // "View more"
  static String get tabDesign => 'FormsFeature.tabDesign'.tr(); // "Design"
}
