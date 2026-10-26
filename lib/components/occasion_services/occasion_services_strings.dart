import 'package:easy_localization/easy_localization.dart';

/// Localized strings for occasion services (food & accommodation) management.
/// Keys live under the "OccasionServices" namespace in assets/translations/*.json.
class OccasionServicesStrings {
  static String get accommodation =>
      'OccasionServices.accommodation'.tr(); // "Accommodation"
  static String get accommodationSettings =>
      'OccasionServices.accommodationSettings'
          .tr(); // "Accommodation settings"
  static String get foodSettings =>
      'OccasionServices.foodSettings'.tr(); // "Food settings"
  static String get accommodationCreateHint =>
      'OccasionServices.accommodationCreateHint'
          .tr(); // "To create accommodation, fill in the title, unique code, and the reference of the place."
  static String get foodCreateHint => 'OccasionServices.foodCreateHint'
      .tr(); // "To create food, fill in the title, unique code, and the reference of the event."

  static String get code => 'OccasionServices.code'.tr(); // "Code"
  static String get noPlaceSelected =>
      'OccasionServices.noPlaceSelected'.tr(); // "No place selected"
  static String get fillAllFields =>
      'OccasionServices.fillAllFields'.tr(); // "Please fill in all fields."
  static String get createItemFailed =>
      'OccasionServices.createItemFailed'.tr(); // "Failed to create the item."
  static String get codeMustBeUnique =>
      'OccasionServices.codeMustBeUnique'
          .tr(); // "This code is already used. Choose a unique one."
  static String get noManagerRight => 'OccasionServices.noManagerRight'
      .tr(); // "Only an occasion manager can manage this."
  static String get deleteServiceConfirmTitle =>
      'OccasionServices.deleteServiceConfirmTitle'
          .tr(); // "Really delete service?"
  static String get deleteServiceConfirmText =>
      'OccasionServices.deleteServiceConfirmText'
          .tr(); // "At least one user has this service. You can find them in the grid. Are you sure you want to delete it? Deletion cannot be undone."
}
