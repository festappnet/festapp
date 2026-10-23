import 'package:easy_localization/easy_localization.dart';

class FeaturesStrings {
  static String get receptionTitle => 'FeatureReception.title'.tr();
  static String get receptionDescription => 'FeatureReception.description'.tr();
  // Schedule Feature Form
  static String get labelScheduleType =>
      'FeatureSchedule.labelScheduleType'.tr();
  static String get optionBasic => 'FeatureSchedule.optionBasic'.tr();
  static String get optionAdvanced => 'FeatureSchedule.optionAdvanced'.tr();
  static String get optionLight => 'FeatureSchedule.optionLight'.tr();

  // New strings for Enable Children
  static String get labelEnableChildren =>
      'FeatureSchedule.labelEnableChildren'.tr();
  static String get subtitleEnableChildren =>
      'FeatureSchedule.subtitleEnableChildren'.tr();

  static String get labelBreakDefinition =>
      'FeatureSchedule.labelBreakDefinition'.tr();
  static String get optionTime => 'FeatureSchedule.optionTime'.tr();
  static String get optionPlace => 'FeatureSchedule.optionPlace'.tr();

  static String get titleTimeBasedBreaks =>
      'FeatureSchedule.titleTimeBasedBreaks'.tr();
  static String get labelAfternoonTime =>
      'FeatureSchedule.labelAfternoonTime'.tr();
  static String get labelEveningTime => 'FeatureSchedule.labelEveningTime'.tr();

  // Event Types Management for Schedule Feature
  static String get titleEventTypes => 'FeatureSchedule.titleEventTypes'.tr();
  static String get buttonAddEventType =>
      'FeatureSchedule.buttonAddEventType'.tr();
  static String get eventTypeDefaultTitle =>
      'FeatureSchedule.eventTypeDefaultTitle'.tr();
  static String get eventTypeCodeAlreadyUsed =>
      'FeatureSchedule.eventTypeCodeAlreadyUsed'.tr();
  static String get labelEventTypeCode =>
      'FeatureSchedule.labelEventTypeCode'.tr();
  static String get labelEventTypeTitle =>
      'FeatureSchedule.labelEventTypeTitle'.tr();
  static String get labelColorSource => 'FeatureSchedule.labelColorSource'.tr();
  static String get optionCustomColor =>
      'FeatureSchedule.optionCustomColor'.tr();
  static String get labelCustomColorHex =>
      'FeatureSchedule.labelCustomColorHex'.tr();
  static String get tooltipRemoveEventType =>
      'FeatureSchedule.tooltipRemoveEventType'.tr();
  static String get emptyEventTypes => 'FeatureSchedule.emptyEventTypes'.tr();
  static String get noType => 'FeatureSchedule.noType'.tr();

  // Import Feature
  static String get importFeatureDescription =>
      'FeatureImport.importFeatureDescription'.tr();
  static String get labelImportFromCsv =>
      'FeatureImport.labelImportFromCsv'.tr();
  static String get labelImportFromTickets =>
      'FeatureImport.labelImportFromTickets'.tr();
  static String get importFromTicketsSuccess =>
      'FeatureImport.importFromTicketsSuccess'.tr();
  static String get importFromTicketsConfirm =>
      'FeatureImport.importFromTicketsConfirm'.tr();
  static String get importFromTicketsError =>
      'FeatureImport.importFromTicketsError'.tr();
  static String get importFromTicketsTitle =>
      'FeatureImport.importFromTicketsTitle'.tr();
  static String get importFromTicketsCompleted =>
      'FeatureImport.importFromTicketsCompleted'.tr();
  static String get importResultsTitle =>
      'FeatureImport.importResultsTitle'.tr();
  static String get chooseSourcePrompt =>
      'FeatureImport.chooseSourcePrompt'.tr();
  static String get createdUsers => 'FeatureImport.createdUsers'.tr();
  static String get updatedUsers => 'FeatureImport.updatedUsers'.tr();
  static String get deletedUsers => 'FeatureImport.deletedUsers'.tr();
  static String get none => 'FeatureImport.none'.tr();

  // New Auto Import strings
  static String get labelAutoImport =>
      'FeatureImport.labelAutoImport'.tr(); // "Auto-Import Users"
  static String get helperAutoImport => 'FeatureImport.helperAutoImport'
      .tr(); // "UUsers will automatically have an account created upon signing up through the form. Default password is '1'."

  // CSV import format description (shown in the drop-file dialog)
  static String get csvFormatTitle =>
      'FeatureImport.csvFormatTitle'.tr(); // "Expected file format"
  static String get csvFormatIntro => 'FeatureImport.csvFormatIntro'
      .tr(); // Explanation of how the header row is matched.
  static String get csvFormatRequired =>
      'FeatureImport.csvFormatRequired'.tr(); // "required"
  static String get csvColEmail => 'FeatureImport.csvColEmail'.tr();
  static String get csvColName => 'FeatureImport.csvColName'.tr();
  static String get csvColSurname => 'FeatureImport.csvColSurname'.tr();
  static String get csvColSex => 'FeatureImport.csvColSex'.tr();
  static String get csvColPhone => 'FeatureImport.csvColPhone'.tr();
  static String get csvColText1 => 'FeatureImport.csvColText1'.tr();
  static String get csvColText2 => 'FeatureImport.csvColText2'.tr();
  static String get csvColBirthDate => 'FeatureImport.csvColBirthDate'.tr();
  static String get csvColNote => 'FeatureImport.csvColNote'.tr();
  static String get csvColDiet => 'FeatureImport.csvColDiet'.tr();
  static String get csvColFood => 'FeatureImport.csvColFood'.tr();
  static String get csvColAccommodation =>
      'FeatureImport.csvColAccommodation'.tr();
  static String get csvColGroup => 'FeatureImport.csvColGroup'.tr();
  static String get csvCopyHeader =>
      'FeatureImport.csvCopyHeader'.tr(); // "Copy header for pasting"
  static String get csvCopyTooltip =>
      'FeatureImport.csvCopyTooltip'.tr(); // "Copy"
  static String get csvCopiedToast =>
      'FeatureImport.csvCopiedToast'.tr(); // "Copied to clipboard."

  // Feature Contract
  static String get contractTitle => 'FeatureContract.title'.tr();
  static String get contractDescription => 'FeatureContract.description'.tr();
  static String get contractTransport => 'FeatureContract.transport'.tr();
  static String get contractDeparturePoint =>
      'FeatureContract.departurePoint'.tr();
  static String get contractPlaceOfStay => 'FeatureContract.placeOfStay'.tr();
  static String get contractTourName => 'FeatureContract.tourName'.tr();
  static String get contractTourDate => 'FeatureContract.tourDate'.tr();
  static String get contractNotes => 'FeatureContract.notes'.tr();
  static String get contractNumberOfDays => 'FeatureContract.numberOfDays'.tr();
  static String get contractPaymentInfo => 'FeatureContract.paymentInfo'.tr();
  static String get contractLoadFromDescription =>
      'FeatureContract.loadFromDescription'.tr();
  static String get downloadContract => 'FeatureContract.downloadContract'.tr();
  static String get generatingContract =>
      'FeatureContract.generatingContract'.tr();
  static String generatingContractFor(String customer) =>
      'FeatureContract.generatingContractFor'
          .tr(namedArgs: {'customer': customer});

  // Feature Deposit
  static String get depositTitle => 'FeatureDeposit.title'.tr();
  static String get depositDescription => 'FeatureDeposit.description'.tr();

  static String get enablePregeneratedTickets =>
      'FeatureTicket.enablePregeneratedTickets'.tr();
  static String get pregeneratedTicketsDescription =>
      'FeatureTicket.pregeneratedTicketsDescription'.tr();

  // Feature Ticket
  static String get enableManualTicketScan =>
      'FeatureTicket.enableManualTicketScan'.tr();
  static String get enableManualTicketScanDescription =>
      'FeatureTicket.enableManualTicketScanDescription'.tr();
  static String get labelShowHiddenNote =>
      'FeatureTicket.labelShowHiddenNote'.tr();
  static String get descriptionShowHiddenNote =>
      'FeatureTicket.descriptionShowHiddenNote'.tr();
  static String get selectTicket => 'FeatureTicket.selectTicket'.tr();
  static String get unknown => 'FeatureTicket.unknown'.tr();
  static String get noData => 'FeatureTicket.noData'.tr();
  static String get ticketDescription => 'FeatureTicket.description'
      .tr(); // "After payment, a ticket is sent to the user. The ticket can have a custom background and text color."
  static String get ticketType =>
      'FeatureTicket.ticketType'.tr(); // "Ticket Type"
  static String get backgroundColor =>
      'FeatureTicket.backgroundColor'.tr(); // "Background color"
  static String get fontColor => 'FeatureTicket.fontColor'.tr(); // "Font color"
  static String get backgroundImageHint =>
      'FeatureTicket.backgroundImageHint'.tr(); // "(1600x900 px)"
  static String get uploadImageSuccess =>
      'FeatureTicket.uploadImageSuccess'.tr(); // "File uploaded successfully."
  static String get uploadImageError =>
      'FeatureTicket.uploadImageError'.tr(); // "Failed to upload image."
  static String get deleteImageConfirm => 'FeatureTicket.deleteImageConfirm'
      .tr(); // "Are you sure you want to delete this image?"
  static String get removeImageSuccess =>
      'FeatureTicket.removeImageSuccess'.tr(); // "Image removed successfully."
  static String get removeImageError =>
      'FeatureTicket.removeImageError'.tr(); // "Failed to remove image."

  // Feature Form
  static String get formTitle => 'FeatureForm.title'.tr(); // "Form"
  static String get formDescription => 'FeatureForm.description'
      .tr(); // "Allows creating a form to reserve one or more seats at an event."

  // Feature Companions
  static String get companionsDescription => 'FeatureCompanions.description'
      .tr(); // "Allows adding companions (partner, child, or friend without a phone) and signing them up for workshops."
  static String get enterNumberGreaterThanZero =>
      'FeatureCompanions.enterNumberGreaterThanZero'
          .tr(); // "Enter a number greater than 0"
  static String get companionsAllowUserCreate =>
      'FeatureCompanions.allowUserCreate'.tr();
  static String get companionsAllowAdminAssign =>
      'FeatureCompanions.allowAdminAssign'.tr();

  // Feature Songbook
  static String get songbookDescription => 'FeatureSongbook.description'
      .tr(); // "Displays a songbook and allows adding custom songs."

  // Feature Game
  static String get gameDescription => 'FeatureGame.description'
      .tr(); // "Allows defining teams, stations, and playing a game where team members enter a code to complete a station."

  // Feature Groups
  static String get groupsDescription => 'FeatureGroups.description'
      .tr(); // "Allows creating groups and scheduling meetings for them."

  // Feature My Schedule
  static String get myScheduleDescription => 'FeatureMySchedule.description'
      .tr(); // "Enables adding program items to favorites."

  // Program notifications
  static String get programNotificationsTitle =>
      'FeatureProgramNotifications.title'.tr();
  static String get programNotificationsDescription =>
      'FeatureProgramNotifications.description'.tr();

  // Feature Entry Code
  static String get entryCodeTitle =>
      'FeatureEntryCode.title'.tr(); // "Entry Code"
  static String get entryCodeDescription => 'FeatureEntryCode.description'
      .tr(); // "It is possible to verify users via QR code on workshops or other limited events."

  // Feature Blueprint
  static String get blueprintDescription => 'FeatureBlueprint.description'
      .tr(); // "This feature lets you create a seating blueprint with a limited number of seats for the reservation form. For example, you can design a seating chart for a bus or a layout of a hall with assigned seats."

  // Feature Timetable
  static String get timetableTitle =>
      'FeatureTimetable.title'.tr(); // "Timetable"
  static String get timetableDescription => 'FeatureTimetable.description'
      .tr(); // "Allows displaying the program in a table."

  // Feature Volunteers
  static String get volunteersDescription => 'FeatureVolunteers.description'
      .tr(); // "Allows management of activities for volunteers."

  // Feature Schedule (feature list metadata)
  static String get scheduleDescription => 'FeatureSchedule.description'
      .tr(); // "Allows customizing event schedule display settings."

  // Feature Workshops
  static String get workshopsTitle =>
      'FeatureWorkshops.title'.tr(); // "Workshops"
  static String get workshopsDescription => 'FeatureWorkshops.description'
      .tr(); // "Indicates the start time from when people can sign in for workshops."
  static String get registrationStartTime =>
      'FeatureWorkshops.registrationStartTime'
          .tr(); // "Workshop Registration Start Time"
  static String get selectStartTime =>
      'FeatureWorkshops.selectStartTime'.tr(); // "Select start time"
  static String get earlyRegistrationMessage =>
      'FeatureWorkshops.earlyRegistrationMessage'
          .tr(); // "Early Registration Attempt Message"
  static String get earlyRegistrationMessageHint =>
      'FeatureWorkshops.earlyRegistrationMessageHint'
          .tr(); // "Enter message for users trying to register too early"

  // Feature Map
  static String get mapDescription => 'FeatureMap.description'
      .tr(); // "Various settings for map inside the app."
  static String get mapZoom => 'FeatureMap.mapZoom'.tr(); // "Map Zoom"
  static String get latitude => 'FeatureMap.latitude'.tr(); // "Latitude"
  static String get longitude => 'FeatureMap.longitude'.tr(); // "Longitude"
  static String get mapLayerSettings =>
      'FeatureMap.mapLayerSettings'.tr(); // "Map Layer Settings"
  static String get mapLayerLogo =>
      'FeatureMap.mapLayerLogo'.tr(); // "Map Layer Logo"
  static String get mapLayerText =>
      'FeatureMap.mapLayerText'.tr(); // "Map Layer Text"
  static String get mapLayerLogoLink =>
      'FeatureMap.mapLayerLogoLink'.tr(); // "Map Layer Logo Link"
  static String get mapLayerTextLink =>
      'FeatureMap.mapLayerTextLink'.tr(); // "Map Layer Text Link"
  static String get mapLayerUrl =>
      'FeatureMap.mapLayerUrl'.tr(); // "Map Layer URL"
  static String get offlineMapLayerSettings =>
      'FeatureMap.offlineMapLayerSettings'.tr(); // "Offline Map Layer Settings"
  static String get forceOfflineMap =>
      'FeatureMap.forceOfflineMap'.tr(); // "Force offline map"
  static String get mapBaseMode => 'FeatureMap.mapBaseMode'.tr();
  static String get mapBaseModeDescription =>
      'FeatureMap.mapBaseModeDescription'.tr();
  static String get mapBaseModeOnline => 'FeatureMap.mapBaseModeOnline'.tr();
  static String get mapBaseModeMapLibre =>
      'FeatureMap.mapBaseModeMapLibre'.tr();
  static String get offlineMapBundleManifestUrl =>
      'FeatureMap.offlineMapBundleManifestUrl'.tr();
  static String get mapLibreBundleManifestRequired =>
      'FeatureMap.mapLibreBundleManifestRequired'.tr();
  static String get offlineMapHttpsUrlRequired =>
      'FeatureMap.offlineMapHttpsUrlRequired'.tr();
}
