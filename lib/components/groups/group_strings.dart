import 'package:easy_localization/easy_localization.dart';

class GroupsStrings {
  // --- UserGroupStringsTab ---
  static String get newGroup => 'GroupStrings.newGroup'.tr(); // "New Group"
  static String get columnId => 'GroupStrings.columnId'.tr(); // "Id"
  static String get columnName => 'GroupStrings.columnName'.tr(); // "Name"
  static String get columnParticipants =>
      'GroupStrings.columnParticipants'.tr(); // "Participants"
  static String get columnContent =>
      'GroupStrings.columnContent'.tr(); // "Content"
  static String get columnPlace => 'GroupStrings.columnPlace'.tr(); // "Place"
  static String get manageParticipantsTooltip =>
      'GroupStrings.manageParticipantsTooltip'.tr(); // "Manage Participants"
  static String get buttonEdit => 'GroupStrings.buttonEdit'.tr(); // "Edit"
  static String get choosePlace => 'GroupStrings.choosePlace'.tr();
  static String get placeDialogTitle => 'GroupStrings.placeDialogTitle'.tr();
  static String currentPlace(String place) =>
      'GroupStrings.currentPlace'.tr(namedArgs: {'place': place});
  static String get chooseExistingPlace =>
      'GroupStrings.chooseExistingPlace'.tr();
  static String get chooseExistingPlaceHint =>
      'GroupStrings.chooseExistingPlaceHint'.tr();
  static String get customGroupLocation =>
      'GroupStrings.customGroupLocation'.tr();
  static String get customGroupLocationHint =>
      'GroupStrings.customGroupLocationHint'.tr();
  static String get removePlace => 'GroupStrings.removePlace'.tr();

  // --- ParticipantsManagementDialog ---
  static String dialogTitle(String groupTitle, int count) =>
      'GroupStrings.dialogTitle'.tr(namedArgs: {
        'groupTitle': groupTitle,
        'count': count.toString()
      }); // "Manage Participants: {groupTitle} ({count})"
  static String get sectionLeader =>
      'GroupStrings.sectionLeader'.tr(); // "Leader"
  static String get noLeaderSelected =>
      'GroupStrings.noLeaderSelected'.tr(); // "No leader selected."
  static String get sectionMembers =>
      'GroupStrings.sectionMembers'.tr(); // "Members"
  static String get searchHint =>
      'GroupStrings.searchHint'.tr(); // "Search by name or other info..."
  static String get buttonAdd => 'GroupStrings.buttonAdd'.tr(); // "Add"
  static String get buttonClose => 'GroupStrings.buttonClose'.tr(); // "Close"
  static String get demoteLeaderTooltip =>
      'GroupStrings.demoteLeaderTooltip'.tr(); // "Demote leader"
  static String get assignLeaderTooltip =>
      'GroupStrings.assignLeaderTooltip'.tr(); // "Assign as leader"
  static String get removeParticipantTooltip =>
      'GroupStrings.removeParticipantTooltip'.tr(); // "Remove participant"

  // --- GameTab / game contents ---
  static String get checkPoints =>
      'GroupStrings.checkPoints'.tr(); // "Check points"
  static String get correctAnswer =>
      'GroupStrings.correctAnswer'.tr(); // "Correct answer"
  static String get startBeforeEnd => 'GroupStrings.startBeforeEnd'
      .tr(); // "Start time must be earlier than end time."
  static String get noOneAssigned =>
      'GroupStrings.noOneAssigned'.tr(); // "No one assigned"
}
