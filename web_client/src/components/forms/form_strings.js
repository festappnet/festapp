import { LocalizationService } from '../../services/localization_service.js';

export class FormStrings {
    // Currency Selector
    static get currencySelectLabel() { return LocalizationService.tr('FormsFeature.inWhatCurrency'); }

    // Form Settings Feature
    static get formSettingsTitle() { return LocalizationService.tr('FeatureFormSettings.title'); }
    static get formNotFound() { return LocalizationService.tr('FeatureFormSettings.formNotFound'); }
    static get loadFailed() { return LocalizationService.tr('FeatureFormSettings.loadFailed', {}, 'The form could not be loaded. Check your connection and try again.'); }
    static get labelFormTitle() { return LocalizationService.tr('FeatureFormSettings.labelFormTitle'); }
    static get labelFormLink() { return LocalizationService.tr('FeatureFormSettings.labelFormLink'); }
    static get validationLinkRequired() { return LocalizationService.tr('FeatureFormSettings.validationLinkRequired'); }
    static get validationLinkInvalidChars() { return LocalizationService.tr('FeatureFormSettings.validationLinkInvalidChars'); }
    static get validationLinkInUse() { return LocalizationService.tr('FeatureFormSettings.validationLinkInUse'); }
    static get labelDeadlineDays() { return LocalizationService.tr('FeatureFormSettings.labelDeadlineDays'); }
    static get helperDeadlineDays() { return LocalizationService.tr('FeatureFormSettings.helperDeadlineDays'); }
    static get labelCardDesign() { return LocalizationService.tr('FeatureFormSettings.labelCardDesign'); }
    static get subtitleCardDesign() { return LocalizationService.tr('FeatureFormSettings.subtitleCardDesign'); }
    static get errorFixBeforeSave() { return LocalizationService.tr('FeatureFormSettings.errorFixBeforeSave'); }
    static get labelUseExternalForm() { return LocalizationService.tr('FeatureFormSettings.labelUseExternalForm'); }
    static get labelReservationLink() { return LocalizationService.tr('FeatureFormSettings.labelReservationLink'); }
    static get helperReservationLink() { return LocalizationService.tr('FeatureFormSettings.helperReservationLink'); }
    static get labelPrice() { return LocalizationService.tr('FeatureFormSettings.labelPrice'); }
    static get helperPrice() { return LocalizationService.tr('FeatureFormSettings.helperPrice'); }
    static get labelAdvancedSettings() { return LocalizationService.tr('FeatureFormSettings.labelAdvancedSettings'); }
    static get labelReserveButtonTitle() { return LocalizationService.tr('FeatureFormSettings.labelReserveButtonTitle'); }
    static get labelDeadlineDuration() { return LocalizationService.tr('FeatureFormSettings.labelDeadlineDuration'); }
    static get helperDeadlineDuration() { return LocalizationService.tr('FeatureFormSettings.helperDeadlineDuration'); }
    static get labelReminderEnabled() { return LocalizationService.tr('FeatureFormSettings.labelReminderEnabled'); }
    static get helperReminderEnabled() { return LocalizationService.tr('FeatureFormSettings.helperReminderEnabled'); }
    static get labelReminderInterval() { return LocalizationService.tr('FeatureFormSettings.labelReminderInterval'); }
    static get helperReminderInterval() { return LocalizationService.tr('FeatureFormSettings.helperReminderInterval'); }
    static get validationReminderInterval() { return LocalizationService.tr('FeatureFormSettings.validationReminderInterval'); }
    static get labelEnableReminders() { return LocalizationService.tr('FeatureFormSettings.labelEnableReminders'); }
    static get subtitleEnableReminders() { return LocalizationService.tr('FeatureFormSettings.subtitleEnableReminders'); }
    static get subtitleRemindersDisabled() { return LocalizationService.tr('FeatureFormSettings.subtitleRemindersDisabled'); }
    static get paymentDetailsTitle() { return LocalizationService.tr('FeatureFormSettings.paymentDetailsTitle'); }
    static get labelVariableSymbol() { return LocalizationService.tr('FeatureFormSettings.labelVariableSymbol'); }
    static get vsTypeRandom() { return LocalizationService.tr('FeatureFormSettings.vsTypeRandom'); }
    static get vsTypeSequence() { return LocalizationService.tr('FeatureFormSettings.vsTypeSequence'); }
    static get labelStartingNumber() { return LocalizationService.tr('FeatureFormSettings.labelStartingNumber'); }
    static get helperStartingNumber() { return LocalizationService.tr('FeatureFormSettings.helperStartingNumber'); }
    static get labelPaymentMessage() { return LocalizationService.tr('FeatureFormSettings.labelPaymentMessage'); }
    static get msgTypeNameSurname() { return LocalizationService.tr('FeatureFormSettings.msgTypeNameSurname'); }
    static get msgTypeNone() { return LocalizationService.tr('FeatureFormSettings.msgTypeNone'); }
    static get msgTypeOccasionTitle() { return LocalizationService.tr('FeatureFormSettings.msgTypeOccasionTitle'); }

    static get communicationToneTitle() { return LocalizationService.tr('FeatureFormSettings.communicationToneTitle'); }
    static get helperCommunicationTone() { return LocalizationService.tr('FeatureFormSettings.helperCommunicationTone'); }
    static get labelCommunicationTone() { return LocalizationService.tr('FeatureFormSettings.labelCommunicationTone'); }
    static get toneFormal() { return LocalizationService.tr('FeatureFormSettings.toneFormal'); }
    static get toneInformal() { return LocalizationService.tr('FeatureFormSettings.toneInformal'); }
    static get pickColor() { return LocalizationService.tr('FeatureFormSettings.pickColor'); }
    static get buttonGotIt() { return LocalizationService.tr('FeatureFormSettings.buttonGotIt'); }
    static get designPresets() { return LocalizationService.tr('FeatureFormSettings.designPresets'); }
    static get more() { return LocalizationService.tr('FeatureFormSettings.more'); }
    static get less() { return LocalizationService.tr('FeatureFormSettings.less'); }
    static get customColors() { return LocalizationService.tr('FeatureFormSettings.customColors'); }
    static get primaryColor() { return LocalizationService.tr('FeatureFormSettings.primaryColor'); }
    static get typography() { return LocalizationService.tr('FeatureFormSettings.typography'); }
    static get browseGoogleFonts() { return LocalizationService.tr('FeatureFormSettings.browseGoogleFonts'); }
    static get currentFont() { return LocalizationService.tr('FeatureFormSettings.currentFont'); }
    static get defaultFont() { return LocalizationService.tr('FeatureFormSettings.defaultFont'); }
    static get resetToDefault() { return LocalizationService.tr('FeatureFormSettings.resetToDefault'); }
    static get choosePopularFonts() { return LocalizationService.tr('FeatureFormSettings.choosePopularFonts'); }
    static get selectFromList() { return LocalizationService.tr('FeatureFormSettings.selectFromList'); }
    static get or() { return LocalizationService.tr('FeatureFormSettings.or'); }
    static get customFontNameLabel() { return LocalizationService.tr('FeatureFormSettings.customFontNameLabel'); }
    static get customFontHelper() { return LocalizationService.tr('FeatureFormSettings.customFontHelper'); }
    static get fontNotFound() { return LocalizationService.tr('FeatureFormSettings.fontNotFound'); }
    static get hexCodeLabel() { return LocalizationService.tr('FeatureFormSettings.hexCodeLabel'); }
    static get days() { return LocalizationService.tr('FeatureFormSettings.days'); }
    static get hours() { return LocalizationService.tr('FeatureFormSettings.hours'); }
    static get minutes() { return LocalizationService.tr('FeatureFormSettings.minutes'); }
    static get seconds() { return LocalizationService.tr('FeatureFormSettings.seconds'); }
    static get previewMode() { return LocalizationService.tr('FeatureFormSettings.previewMode'); }
    static get registrationStart() { return LocalizationService.tr('FeatureFormSettings.registrationStart'); }
    static get reservationUnavailable() { return LocalizationService.tr('FeatureFormSettings.reservationUnavailable'); }
    static get reservationUnavailableMessage() { return LocalizationService.tr('FeatureFormSettings.reservationUnavailableMessage'); }
    static get availability() { return LocalizationService.tr('FeatureFormSettings.availability'); }
    static get formClosedMessage() { return LocalizationService.tr('FeatureFormSettings.formClosedMessage'); }
    static scheduledWithTime(time) { return LocalizationService.tr('FeatureFormSettings.scheduledWithTime', { time }); }
    static endedWithTime(time) { return LocalizationService.tr('FeatureFormSettings.endedWithTime', { time }); }
    static get formOpenMessage() { return LocalizationService.tr('FeatureFormSettings.formOpenMessage'); }
    static get scheduleAndLimits() { return LocalizationService.tr('FeatureFormSettings.scheduleAndLimits'); }
    static get autoOpenHelp() { return LocalizationService.tr('FeatureFormSettings.autoOpenHelp'); }
    static get labelStartTime() { return LocalizationService.tr('FeatureFormSettings.labelStartTime'); }
    static get labelEndTime() { return LocalizationService.tr('FeatureFormSettings.labelEndTime'); }
    static get errorEndTimeBeforeStartTime() { return LocalizationService.tr('FeatureFormSettings.errorEndTimeBeforeStartTime'); }
    static get labelCountdownTimer() { return LocalizationService.tr('FeatureFormSettings.labelCountdownTimer'); }
    static get requiresStartTime() { return LocalizationService.tr('FeatureFormSettings.requiresStartTime'); }
    static get countdownDescription() { return LocalizationService.tr('FeatureFormSettings.countdownDescription'); }
    static get labelCountdownMessage() { return LocalizationService.tr('FeatureFormSettings.labelCountdownMessage'); }
    static get labelClosedMessage() { return LocalizationService.tr('FeatureFormSettings.labelClosedMessage'); }
    static get labelMessageContent() { return LocalizationService.tr('FeatureFormSettings.labelMessageContent'); }
    static get helperClosedMessage() { return LocalizationService.tr('FeatureFormSettings.helperClosedMessage'); }
    static get notSet() { return LocalizationService.tr('FeatureFormSettings.notSet'); }
    static get publicView() { return LocalizationService.tr('FeatureFormSettings.publicView'); }
    static get editorPreview() { return LocalizationService.tr('FeatureFormSettings.editorPreview'); }
    static get addTicket() { return LocalizationService.tr('FormsFeature.addTicket') || "Add ticket"; }
    static get ticket() { return LocalizationService.tr('Common.ticket') || "Ticket"; }
    static get buttonContinue() { return LocalizationService.tr('Common.continueAction'); }

    // --- Form Fields (General) ---
    static get noOptionsForCurrency() { return LocalizationService.tr('FormsFeature.noOptionsForCurrency'); }
    static get clearSelection() { return LocalizationService.tr('FormsFeature.clearSelection'); }
    static get unavailable() { return LocalizationService.tr('FormsFeature.unavailable'); }
    static get inWhatCurrency() { return LocalizationService.tr('FormsFeature.inWhatCurrency'); }
    static get surchargeOnSite() { return LocalizationService.tr('OrderGridColumns.surchargeOnSite'); }
    static get depositInfo() { return LocalizationService.tr('OrderGridColumns.depositInfo'); }


    // Auto-Titles
    static get fieldName() { return LocalizationService.tr('Common.name'); }
    static get fieldSurname() { return LocalizationService.tr('PersonFields.surname'); }
    static get fieldEmail() { return LocalizationService.tr('PersonFields.email'); }
    static get fieldPhone() { return LocalizationService.tr('PersonFields.phone'); }
    static get fieldCity() { return LocalizationService.tr('PersonFields.city'); }
    static get fieldBirthYear() { return LocalizationService.tr('PersonFields.birthYear'); }
    static get fieldNote() { return LocalizationService.tr('Common.note'); }
    static get fieldAddress() { return LocalizationService.tr('PersonFields.address'); }
    static get fieldNationality() { return LocalizationService.tr('PersonFields.nationality'); }
    static get fieldIdDocument() { return LocalizationService.tr('PersonFields.identificationDocument'); }
    static get fieldBirthDate() { return LocalizationService.tr('PersonFields.birthDate'); }
    static birthDateError(minAge, maxAge) { return LocalizationService.tr('PersonFields.ageRestriction', { minAge, maxAge }); }
    static birthDateWarning(minAge, maxAge) { return LocalizationService.tr('PersonFields.ageOutsideRecommendedRange', { minAge, maxAge }); }
    static get birthDateFormatHint() { return LocalizationService.currentLocale === 'cs' ? 'D. M. RRRR' : 'MM/DD/YYYY'; }
    static get expiryDate() { return LocalizationService.tr('PersonFields.expiryDate'); }
    static get expiryDatePastError() { return LocalizationService.tr('PersonFields.expiryDateInPast'); }

    static get sexLabel() { return LocalizationService.tr('PersonFields.sexLabel'); }
    static get maleLabel() { return LocalizationService.tr('PersonFields.male'); }
    static get femaleLabel() { return LocalizationService.tr('PersonFields.female'); }
    static get notSpecifiedLabel() { return LocalizationService.tr('PersonFields.notSpecified'); }


    // --- FormsTab (Main Grid View) ---
    static get formsTitle() { return LocalizationService.tr('FormsFeature.formsTitle'); }
    static get createNewForm() { return LocalizationService.tr('FormsFeature.createNewForm'); }
    static noFormsForEventPrompt(createNew) { return LocalizationService.tr('FormsFeature.noFormsForEventPrompt', { createNew }); }
    static get createCopy() { return LocalizationService.tr('FormsFeature.createCopy'); }
    static get statusOpen() { return LocalizationService.tr('FormsFeature.statusOpen'); }
    static get statusClosed() { return LocalizationService.tr('FormsFeature.statusClosed'); }
    static get responses() { return LocalizationService.tr('FormsFeature.responses'); }
    static get duplicateSuccess() { return LocalizationService.tr('FormsFeature.duplicateSuccess'); }
    static get deleteFormTitle() { return LocalizationService.tr('FormsFeature.deleteFormTitle'); }
    static get deleteFormContent() { return LocalizationService.tr('FormsFeature.deleteFormContent'); }

    // --- FormTab (The TabBar holder) ---
    static get tabForm() { return LocalizationService.tr('FormsFeature.tabForm'); }
    static get tabResponses() { return LocalizationService.tr('FormsFeature.tabResponses'); }

    // --- FormCreationHelper (Creation Dialog) ---
    static get defaultFormTitle() { return LocalizationService.tr('FormsFeature.defaultFormTitle'); }
    static get formAvailableAt() { return LocalizationService.tr('FormsFeature.formAvailableAt'); }
    static get formCreatedSuccess() { return LocalizationService.tr('FormsFeature.formCreatedSuccess'); }

    // --- FormEditorContent (Form Editor Tab) ---
    static get formTurnedOff() { return LocalizationService.tr('FormsFeature.formTurnedOff'); }
    static get editOffText() { return LocalizationService.tr('FormsFeature.editOffText'); }
    static get editContent() { return LocalizationService.tr('FormsFeature.editContent'); }
    static get dragToReorder() { return LocalizationService.tr('FormsFeature.dragToReorder'); }
    static get addFieldTitle() { return LocalizationService.tr('FormsFeature.addFieldTitle'); }
    static get personalInfo() { return LocalizationService.tr('FormsFeature.personalInfo'); }
    static get noFieldsAvailable() { return LocalizationService.tr('FormsFeature.noFieldsAvailable'); }

    // --- Form Editor (Ticket Editor) ---
    static get addProductTypeTitle() { return LocalizationService.tr('FormsFeature.addProductTypeTitle'); }
    static get createNewProductTypeOption() { return LocalizationService.tr('FormsFeature.createNewProductTypeOption'); }
    static get untitledProductType() { return LocalizationService.tr('FormsFeature.untitledProductType'); }
    static get noProductTypesToAdd() { return LocalizationService.tr('FormsFeature.noProductTypesToAdd'); }
    static get newProductTypeDefaultName() { return LocalizationService.tr('FormsFeature.newProductTypeDefaultName'); }

    static get typeHere() { return LocalizationService.tr('FormsFeature.typeHere'); }
    static get typeHere_informal() { return LocalizationService.tr('FormsFeature.typeHere_informal'); }
    static get phoneFormatHint() { return LocalizationService.tr('FormsFeature.phoneFormatHint'); }
    static get phoneFormatValidation() { return LocalizationService.tr('FormsFeature.phoneFormatValidation'); }

    // --- Strings from TicketEditorWidgets ---
    static get noProductTypes() { return LocalizationService.tr('FormsFeature.noProductTypes'); }
    static get productTypes() { return LocalizationService.tr('FormsFeature.productTypes'); }
    static get seatSelection() { return LocalizationService.tr('FormsFeature.seatSelection'); }
    static get note() { return LocalizationService.tr('FormsFeature.note'); }

    // --- Strings for TicketEditorWidgets (Max Tickets) ---
    static get labelMaxTicketsPerOrder() { return LocalizationService.tr('FormsFeature.labelMaxTicketsPerOrder'); }
    static get helperMaxTicketsPerOrder() { return LocalizationService.tr('FormsFeature.helperMaxTicketsPerOrder'); }
    static get validationMaxTicketsInvalid() { return LocalizationService.tr('FormsFeature.validationMaxTicketsInvalid'); }

    // --- Create/Copy Dialog (_CreateOrCopyFormDialog) ---
    static get createFormTitle() { return LocalizationService.tr('FormsFeature.createFormTitle'); }
    static get createNewBlankForm() { return LocalizationService.tr('FormsFeature.createNewBlankForm'); }
    static get orCreateFromCopy() { return LocalizationService.tr('FormsFeature.orCreateFromCopy'); }
    static get searchFormsToCopy() { return LocalizationService.tr('FormsFeature.searchFormsToCopy'); }
    static get groupHappeningNow() { return LocalizationService.tr('FormsFeature.groupHappeningNow'); }
    static get groupUpcoming() { return LocalizationService.tr('FormsFeature.groupUpcoming'); }
    static get groupOther() { return LocalizationService.tr('FormsFeature.groupOther'); }
    static numberOfResponsesTooltip(count) { return LocalizationService.tr('FormsFeature.numberOfResponsesTooltip', [count]); }
    
    // Validations (General)
    static get fieldCannotBeEmpty() { return LocalizationService.tr('Common.fieldCannotBeEmpty') || "Field cannot be empty"; }
    static get invalidFormat() { return LocalizationService.tr('Common.invalidFormat') || "Invalid format"; }
}
