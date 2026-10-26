import 'package:easy_localization/easy_localization.dart';

/// Localized strings for the user import helpers (CSV import flow).
/// Keys live under the "FeatureImport" namespace in assets/translations/*.json
/// (shared with FeaturesStrings, which owns the feature-level keys).
class ImportStrings {
  // --- Progress dialog titles ---
  static String get creatingUsers =>
      'FeatureImport.creatingUsers'.tr(); // "Creating users"
  static String get updatingUsers =>
      'FeatureImport.updatingUsers'.tr(); // "Updating users"
  static String get removingUsers =>
      'FeatureImport.removingUsers'.tr(); // "Removing users"

  // --- Confirmation prompts ---
  static String get createUsersConfirm => 'FeatureImport.createUsersConfirm'
      .tr(); // "New users found. Do you want to create them?"
  static String get updateUsersConfirm => 'FeatureImport.updateUsersConfirm'
      .tr(); // "These users have some changes. Do you want to update them?"
  static String get removeUsersConfirm => 'FeatureImport.removeUsersConfirm'
      .tr(); // "These users have been removed, but they still exist in the application. Do you want to remove them?"

  // --- Per-item toasts ---
  static String createdItem({required String item}) =>
      'FeatureImport.createdItem'
          .tr(namedArgs: {'item': item}); // "Created: {item}."
  static String removedItem({required String item}) =>
      'FeatureImport.removedItem'
          .tr(namedArgs: {'item': item}); // "Removed: {item}."
}
