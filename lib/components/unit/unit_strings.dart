import 'package:easy_localization/easy_localization.dart';

/// Localized strings for the unit component.
/// Keys live under the "Unit" namespace in assets/translations/*.json.
class UnitStrings {
  static String get unit => 'Unit.unit'.tr(); // "Unit"
  static String get quotes => 'Unit.quotes'.tr(); // "Quotes"
  static String get emailTemplates =>
      'Unit.emailTemplates'.tr(); // "Email Templates"
  static String get loadUnitFailed =>
      'Unit.loadUnitFailed'.tr(); // "Failed to load unit data."

  // Occasions screen
  static String get addNewEvent => 'Unit.addNewEvent'.tr(); // "Add New Event"
  static String get noEventsFound =>
      'Unit.noEventsFound'.tr(); // "No events found."
  static String get loadEventFailed =>
      'Unit.loadEventFailed'.tr(); // "Could not load event. Please try again."
  static String get createCopy => 'Unit.createCopy'.tr(); // "Create Copy"
  static String get createCopyConfirm => 'Unit.createCopyConfirm'
      .tr(); // "Do you want to create copy of this event?"
  static String get createCopySuccess =>
      'Unit.createCopySuccess'.tr(); // "Event copy created successfully."
  static String get createCopyFailed =>
      'Unit.createCopyFailed'.tr(); // "Failed to create event copy."
  static String get createCopyMediaFailed => 'Unit.createCopyMediaFailed'.tr();
}
