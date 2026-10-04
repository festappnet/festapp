import 'package:easy_localization/easy_localization.dart';

class CommonStrings {
  // --- Common Actions ---
  static String get save => 'Common.save'.tr(); // "Save"
  static String get unexpectedError =>
      'Common.unexpectedError'.tr(); // "An unexpected error occurred."
  static String get storno => 'Common.storno'.tr(); // "Storno"
  static String get delete => 'Common.delete'.tr(); // "Delete"
  static String get edit => 'Common.edit'.tr(); // "Edit"
  static String get ok => 'Common.ok'.tr(); // "Ok"
  static String get close => 'Common.close'.tr(); // "Close"
  static String get confirm => 'Common.confirm'.tr(); // "Confirm"
  static String get rename => 'Common.rename'.tr(); // "Rename"
  static String get addNew => 'Common.addNew'.tr(); // "Add new"
  static String get addExisting =>
      'Common.addExisting'.tr(); // "Add existing"
  static String get create => 'Common.create'.tr(); // "Create"
  static String get cancel => 'Common.cancel'.tr(); // "Cancel"
  static String get reset => 'Common.reset'.tr(); // "Reset"
  static String get search => 'Common.search'.tr(); // "Search"
  static String get back => 'Common.back'.tr(); // "Back"
  static String get or => 'Common.or'.tr(); // "Or"
  static String get send => 'Common.send'.tr(); // "Send"
  static String get update => 'Common.update'.tr(); // "Update"
  static String get retry => 'Common.retry'.tr();
  static String get continueAction => 'Common.continueAction'.tr(); // "Continue"
  static String get proceed => 'Common.proceed'.tr(); // "Proceed"
  static String get saveChanges => 'Common.saveChanges'.tr(); // "Save changes"
  static String get editContent => 'Common.editContent'.tr(); // "Edit content"
  static String get moreOptions => 'Common.moreOptions'.tr(); // "More Options"

  // --- Common Nouns & Labels ---
  static String get title => 'Common.title'.tr(); // "Title"
  static String get price => 'Common.price'.tr(); // "Price"
  static String get amount => 'Common.amount'.tr(); // "Amount"
  static String get currency => 'Common.currency'.tr(); // "Currency"
  static String get date => 'Common.date'.tr(); // "Date"
  static String get note => 'Common.note'.tr(); // "Note"
  static String get color => 'Common.color'.tr(); // "Color"
  static String get hex => 'Common.hex'.tr(); // "Hex"
  static String get hexFormat =>
      'Common.hexFormat'.tr(); // "RRGGBB" (color hex placeholder)
  static String get password => 'FeatureUser.password'
      .tr(); // "Password" (Moved to FeatureUser, but widely used? UserStrings has it too?)
  static String get icon => 'Common.icon'.tr(); // "Icon"
  static String get id => 'Common.id'.tr(); // "Id"
  static String get map => 'Common.map'.tr(); // "Map"
  static String get max => 'Common.max'.tr(); // "Max"
  static String get order => 'Common.order'.tr(); // "Order"
  static String get spot => 'Common.spot'.tr(); // "Spot"
  static String get ticket => 'Common.ticket'.tr(); // "Ticket"
  static String get blueprint => 'Common.blueprint'.tr(); // "Blueprint"
  static String get companions => 'Common.companions'.tr(); // "Companions"
  static String get participants =>
      'Common.participants'.tr(); // "Participants"
  static String get volunteers => 'Common.volunteers'.tr(); // "Volunteers"
  static String get groups => 'Common.groups'.tr(); // "Groups"
  static String get places => 'Common.places'.tr(); // "Places"
  static String get products => 'Common.products'.tr(); // "Products"
  static String get food => 'Common.food'.tr(); // "Food"
  static String get game => 'Common.game'.tr(); // "Game"
  static String get songbook => 'Common.songbook'.tr(); // "Songbook"
  static String get schedule => 'Common.schedule'.tr(); // "Schedule"
  static String get mySchedule => 'Common.mySchedule'.tr(); // "My schedule"
  static String get event => 'Common.event'.tr(); // "Event"
  static String get user => 'Common.user'.tr(); // "User"
  static String get defaultLabel => 'Common.defaultLabel'.tr(); // "default"

  // --- Events & Scheduling ---
  static String get eventManagement =>
      'Common.eventManagement'.tr(); // "Event management"
  static String get happeningNow =>
      'Common.happeningNow'.tr(); // "Happening Now"
  static String get upcomingEvents =>
      'Common.upcomingEvents'.tr(); // "Upcoming Events"
  static String get pastEvents => 'Common.pastEvents'.tr(); // "Past Events"
  static String get noEventsFound =>
      'Common.noEventsFound'.tr(); // "No events found"
  static String get reserveASpot =>
      'Common.reserveASpot'.tr(); // "Reserve a spot"
  static String get searchAttendees =>
      'Common.searchAttendees'.tr(); // "Search Attendees"
  static String get searchParticipants =>
      'Common.searchParticipants'.tr(); // "Search participants"
  static String get startDate => 'Common.startDate'.tr(); // "Start date"
  static String get endDate => 'Common.endDate'.tr(); // "End date"

  // --- Common Statuses & Feedback ---
  static String get saved => 'Common.saved'.tr(); // "Saved"
  static String get deleted => 'Common.deleted'.tr(); // "Deleted"
  static String get success => 'Common.success'.tr(); // "Success"
  static String get loading => 'Common.loading'.tr(); // "Loading..."
  static String get settings => 'Common.settings'.tr(); // "Settings"
  static String get advancedSettings =>
      'Common.advancedSettings'.tr(); // "Advanced Settings"
  static String get contentChanged =>
      'Common.contentChanged'.tr(); // "Content has been changed."
  static String get copiedToClipboard =>
      'Common.copiedToClipboard'.tr(); // "Copied to clipboard"
  static String get confirmRemoval =>
      'Common.confirmRemoval'.tr(); // "Confirm removal"
  static String updatedItem({required String item}) =>
      'Common.updatedItem'.tr(namedArgs: {'item': item}); // "Updated {item}."
  static String get processing => 'Common.processing'.tr(); // "Processing..."
  static String get progress => 'Common.progress'.tr(); // "Progress"
  static String get processingCancelled => 'Common.processingCancelled'
      .tr(); // "The processing has been cancelled."
  static String get processingCompleted => 'Common.processingCompleted'
      .tr(); // "The processing has completed successfully."
  static String get processingFailed => 'Common.processingFailed'
      .tr(); // "The processing has finished with error."
  static String get unknownDatabaseError => 'Common.unknownDatabaseError'
      .tr(); // "An unknown database error occurred."
  static String get detailsLabel => 'Common.detailsLabel'.tr(); // "Details:"
  static String get newVersionAvailable =>
      'Common.newVersionAvailable'.tr(); // "New Version Available"
  static String get updateAppPrompt => 'Common.updateAppPrompt'
      .tr(); // "Update the app to the latest version to access all features."
  static String get notificationsAllowed => 'Common.notificationsAllowed'
      .tr(); // "Notifications have been allowed."
  static String get notificationsDisabled => 'Common.notificationsDisabled'
      .tr(); // "Notifications have been disabled."
  static String get notifications =>
      'Common.notifications'.tr(); // "Notifications"
  static String get notificationsInfo => 'Common.notificationsInfo'
      .tr(); // "Notifications will inform you about schedule changes and other selected news."
  static String get enable => 'Common.enable'.tr(); // "Enable"
  static String get disable => 'Common.disable'.tr(); // "Disable"
  static String errorWithCode({required String code}) => 'Common.errorWithCode'
      .tr(namedArgs: {'code': code}); // "Error (Code: {code})"
  static String credentialsEmailSent({required String email}) =>
      'Common.credentialsEmailSent'.tr(namedArgs: {
        'email': email
      }); // "E-mail with credentials was sent to: {email}."

  // --- Appearance & Language ---
  static String get appearance => 'Common.appearance'.tr(); // "Appearance"
  static String get auto => 'Common.auto'.tr(); // "Auto"
  static String get dark => 'Common.dark'.tr(); // "Dark"
  static String get light => 'Common.light'.tr(); // "Light"
  static String get languageSettings =>
      'Common.languageSettings'.tr(); // "Language Settings"
  static String currentLanguage({required String language}) =>
      'Common.currentLanguage'.tr(namedArgs: {
        'language': language
      }); // "Current Language: {language}"
  static String get chooseLanguage =>
      'Common.chooseLanguage'.tr(); // "Choose language"
  static String languageSetTo({required String language}) =>
      'Common.languageSetTo'.tr(namedArgs: {
        'language': language
      }); // "Language was set to {language}."

  // --- Forms & Validation ---
  static String get fieldCannotBeEmpty =>
      'Common.fieldCannotBeEmpty'.tr(); // "Field cannot be empty"
  static String get invalidFormat =>
      'Common.invalidFormat'.tr(); // "Invalid format"
  static String get name => 'Common.name'.tr(); // "Name"
  static String get description => 'Common.description'.tr(); // "Description"
  static String get content => 'Common.content'.tr(); // "Content"
  static String get add => 'Common.add'.tr(); // "Add"
  static String get addToGroup => 'Common.addToGroup'.tr(); // "Add to group"
  static String get type => 'Common.type'.tr(); // "Type"
  static String get hide => 'Common.hide'.tr(); // "Hide"
  static String get place => 'Common.place'.tr(); // "Place"
  static String get users => 'Common.users'.tr(); // "Users"
  static String get events => 'Common.events'.tr(); // "Events"
  static String get start => 'Common.start'.tr(); // "Start"
  static String get end => 'Common.end'.tr(); // "End"
  static String get cancelled => 'Common.cancelled'.tr(); // "Cancelled"
  static String get import => 'Common.import'.tr(); // "Import"
  static String get dropFileHere =>
      'Common.dropFileHere'.tr(); // "Drop file here"
  static String get dropFileHereOrClick => 'Common.dropFileHereOrClick'
      .tr(); // "Drop file here or click to upload"
}
