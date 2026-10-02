import 'package:easy_localization/easy_localization.dart';

/// Contains all the strings for the Admin-facing panels and components.
class AdministrationStrings {
  // Existing Strings
  static String get findUnitHint =>
      'Administration.findUnitHint'.tr(); // "Find unit..."
  static String get newUnitButton =>
      'Administration.newUnitButton'.tr(); // "New unit"
  static String get findOccasionHint =>
      'Administration.findOccasionHint'.tr(); // "Find occasion..."
  static String get newOccasionButton =>
      'Administration.newOccasionButton'.tr(); // "New occasion"
  static String get viewApp => 'Administration.viewApp'.tr(); // "View App"
  static String get reservations =>
      'Administration.reservations'.tr(); // "Reservations"
  static String get oneSignalSecretManagedServerSide =>
      'Administration.oneSignalSecretManagedServerSide'.tr();

  static String get googleLoginEnabled =>
      'Administration.googleLoginEnabled'.tr();
  static String get googleLoginDescription =>
      'Administration.googleLoginDescription'.tr();

  // New Strings for Occasion Creation
  static String get myFestival =>
      'Administration.myFestival'.tr(); // "myfestival"
  static String get addNewEventTitle =>
      'Administration.addNewEventTitle'.tr(); // "Add New Event"
  static String get titleLabel => 'Administration.titleLabel'.tr(); // "Title"
  static String get linkLabel => 'Administration.linkLabel'.tr(); // "Link"
  static String get eventAvailableAt => 'Administration.eventAvailableAt'
      .tr(); // "This event will be available at"
  static String get cancelButton =>
      'Administration.cancelButton'.tr(); // "Cancel"
  static String get createButton =>
      'Administration.createButton'.tr(); // "Create"
  static String get linkIsRequiredError =>
      'Administration.linkIsRequiredError'.tr(); // "Link is required"
  static String get invalidCharactersError =>
      'Administration.invalidCharactersError'.tr(); // "Invalid characters"
  static String get linkInUseError =>
      'Administration.linkInUseError'.tr(); // "Link already in use"
}
