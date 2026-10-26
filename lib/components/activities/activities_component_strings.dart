import 'package:easy_localization/easy_localization.dart';
import 'package:fstapp/components/_shared/common_strings.dart';

class ActivitiesComponentStrings {
  // General
  static String get buttonCancel =>
      'ActivitiesComponentStrings.buttonCancel'.tr();
  static String get buttonOK => 'ActivitiesComponentStrings.buttonOK'.tr();
  static String get buttonPublish =>
      'ActivitiesComponentStrings.buttonPublish'.tr();
  static String get labelTitle => 'ActivitiesComponentStrings.labelTitle'.tr();
  static String get tooltipRemovePlace =>
      'ActivitiesComponentStrings.tooltipRemovePlace'.tr();
  static String get tooltipRemoveEvent =>
      'ActivitiesComponentStrings.tooltipRemoveEvent'.tr();
  static String get tooltipExitFullscreen =>
      'ActivitiesComponentStrings.tooltipExitFullscreen'.tr();
  static String get tooltipEnterFullscreen =>
      'ActivitiesComponentStrings.tooltipEnterFullscreen'.tr();
  static String get tooltipAddNewActivity =>
      'ActivitiesComponentStrings.tooltipAddNewActivity'.tr();
  static String get tooltipUndo =>
      'ActivitiesComponentStrings.tooltipUndo'.tr();
  static String get tooltipRedo =>
      'ActivitiesComponentStrings.tooltipRedo'.tr();
  static String get buttonClose =>
      'ActivitiesComponentStrings.buttonClose'.tr();
  static String get buttonRestore =>
      'ActivitiesComponentStrings.buttonRestore'.tr();
  static String get tooltipZoomIn =>
      'ActivitiesComponentStrings.tooltipZoomIn'.tr();
  static String get tooltipZoomOut =>
      'ActivitiesComponentStrings.tooltipZoomOut'.tr();

  // Autosave status
  static String get textAutosaved =>
      'ActivitiesComponentStrings.textAutosaved'.tr();
  static String get publishedSuccessfully =>
      'ActivitiesComponentStrings.publishedSuccessfully'.tr();

  // Publish Button Tooltips
  static String get textPublishing =>
      'ActivitiesComponentStrings.textPublishing'.tr();
  static String get tooltipClickToPublish =>
      'ActivitiesComponentStrings.tooltipClickToPublish'.tr();
  static String get textEverythingIsPublished =>
      'ActivitiesComponentStrings.textEverythingIsPublished'.tr();

  // Search/Filter
  static String get hintSearchUsers =>
      'ActivitiesComponentStrings.hintSearchUsers'.tr();
  static String get hintSearchPlaces =>
      'ActivitiesComponentStrings.hintSearchPlaces'.tr();
  static String get hintSearchEvents =>
      'ActivitiesComponentStrings.hintSearchEvents'.tr();
  static String get hintGlobalFilter =>
      'ActivitiesComponentStrings.hintGlobalFilter'.tr();
  static String get textNoFilterMatch =>
      'ActivitiesComponentStrings.textNoFilterMatch'.tr();

  // Activities Timeline
  static String get titleActivitiesTimeline =>
      'ActivitiesComponentStrings.titleActivitiesTimeline'.tr();
  static String get textNoActivitiesAvailable =>
      'ActivitiesComponentStrings.textNoActivitiesAvailable'.tr();
  static String get textClickPlusToAddOne =>
      'ActivitiesComponentStrings.textClickPlusToAddOne'.tr();
  static String get textActivityHidden =>
      'ActivitiesComponentStrings.textActivityHidden'.tr();
  static String get textNewActivityAddedDragDrop =>
      'ActivitiesComponentStrings.textNewActivityAddedDragDrop'.tr();
  static String get textDragUsersFromTopDropHere =>
      'ActivitiesComponentStrings.textDragUsersFromTopDropHere'.tr();
  static String get textNoUsersAssignedYet =>
      'ActivitiesComponentStrings.textNoUsersAssignedYet'.tr();
  static String get textUntitledActivity =>
      'ActivitiesComponentStrings.textUntitledActivity'.tr();

  // Activity Options
  static String get menuRename => 'ActivitiesComponentStrings.menuRename'.tr();
  static String get menuDelete => 'ActivitiesComponentStrings.menuDelete'.tr();
  static String get menuDetails => CommonStrings.description;
  static String get dialogRenameActivity =>
      'ActivitiesComponentStrings.dialogRenameActivity'.tr();
  static String get tooltipActivityOptions =>
      'ActivitiesComponentStrings.tooltipActivityOptions'.tr();
  static String get tooltipMarkVisible =>
      'ActivitiesComponentStrings.tooltipMarkVisible'.tr();
  static String get tooltipMarkHidden =>
      'ActivitiesComponentStrings.tooltipMarkHidden'.tr();

  // Assignment Detail Overlay
  static String get labelPlaces =>
      'ActivitiesComponentStrings.labelPlaces'.tr();
  static String get labelEvents =>
      'ActivitiesComponentStrings.labelEvents'.tr();
  static String get textNoItemsAssigned =>
      'ActivitiesComponentStrings.textNoItemsAssigned'.tr();
  static String get tooltipDeleteAssignment =>
      'ActivitiesComponentStrings.tooltipDeleteAssignment'.tr();

  // User Row Options
  static String get menuRemoveUserFromActivity =>
      'ActivitiesComponentStrings.menuRemoveUserFromActivity'.tr();
  static String get tooltipUserAssignmentOptions =>
      'ActivitiesComponentStrings.tooltipUserAssignmentOptions'.tr();

  // Default/Unnamed Items
  static String get textUnnamedPlace =>
      'ActivitiesComponentStrings.textUnnamedPlace'.tr();
  static String get textUnnamedEvent =>
      'ActivitiesComponentStrings.textUnnamedEvent'.tr();

  static String get activity => 'ActivitiesComponentStrings.activity'.tr();
  static String publishWithCount(int count) =>
      'ActivitiesComponentStrings.publishWithCount'
          .tr(namedArgs: {"count": count.toString()});

  // Conflict Dialog
  static String get dialogTitleUpdateConflict =>
      'ActivitiesComponentStrings.dialogTitleUpdateConflict'.tr();
  static String get buttonLoadNewestVersion =>
      'ActivitiesComponentStrings.buttonLoadNewestVersion'.tr();
  static String get buttonContinueWithDraft =>
      'ActivitiesComponentStrings.buttonContinueWithDraft'.tr();

  // Version History Dialog
  static String get dialogTitleVersionHistory =>
      'ActivitiesComponentStrings.dialogTitleVersionHistory'.tr();
  static String get tooltipVersionHistory =>
      'ActivitiesComponentStrings.tooltipVersionHistory'.tr();
  static String get textAutosavedDraft =>
      'ActivitiesComponentStrings.textAutosavedDraft'.tr();
  static String get textPublishedVersion =>
      'ActivitiesComponentStrings.textPublishedVersion'.tr();
  static String historyLabel(String type, String user) =>
      'ActivitiesComponentStrings.historyLabel'
          .tr(namedArgs: {'type': type, 'user': user});

  // Conflict Dialog Messages
  static String get conflictMessageDefault =>
      'ActivitiesComponentStrings.conflictMessageDefault'.tr();
  static String conflictMessageWithTime(String time, String date) =>
      'ActivitiesComponentStrings.conflictMessageWithTime'
          .tr(namedArgs: {'time': time, 'date': date});
  static String get staleAutosaveConflictMessage =>
      'ActivitiesComponentStrings.staleAutosaveConflictMessage'.tr();

  // User Assignments Dialog
  static String get dialogTitleSelectTargetUser =>
      'ActivitiesComponentStrings.dialogTitleSelectTargetUser'.tr();
  static String dialogTitleAssignmentsFor(String user) =>
      'ActivitiesComponentStrings.dialogTitleAssignmentsFor'
          .tr(namedArgs: {'user': user});
  static String get labelTotalTime =>
      'ActivitiesComponentStrings.labelTotalTime'.tr();
  static String get textNoAssignmentsForUser =>
      'ActivitiesComponentStrings.textNoAssignmentsForUser'.tr();
  static String get buttonCopyToUser =>
      'ActivitiesComponentStrings.buttonCopyToUser'.tr();
  static String toastAssignmentsCopied(int count, String user) =>
      'ActivitiesComponentStrings.toastAssignmentsCopied'
          .tr(namedArgs: {'count': count.toString(), 'user': user});
  static String get textSelectAll =>
      'ActivitiesComponentStrings.textSelectAll'.tr();
  static String get tooltipCloseDialog =>
      'ActivitiesComponentStrings.tooltipCloseDialog'.tr();
  static String toastAssignmentsDeletedInDialog(int count) =>
      'ActivitiesComponentStrings.toastAssignmentsDeletedInDialog'
          .tr(namedArgs: {'count': count.toString()});
  static String toastAssignmentsCopiedInDialog(int count, String user) =>
      'ActivitiesComponentStrings.toastAssignmentsCopiedInDialog'
          .tr(namedArgs: {'count': count.toString(), 'user': user});

  // NEW: Date format string
  static String get dateFormatDayMonth => 'EEEE, d. MMMM';

  // Toast Messages
  static String get toastFailedToLoad =>
      'ActivitiesComponentStrings.toastFailedToLoad'.tr();

  /// Returns a list of localized weekday abbreviations for the given locale.
  static List<String> getWeekdayAbbreviations(String locale) {
    final List<String> abbreviations = [];
    final now = DateTime.now();
    // Ensure we start from Monday
    DateTime monday = now.subtract(Duration(days: now.weekday - 1));

    for (int i = 0; i < 7; i++) {
      final date = monday.add(Duration(days: i));
      abbreviations.add(DateFormat('E', locale).format(date));
    }
    return abbreviations;
  }

  /// Returns a list of localized month abbreviations for the given locale.
  static List<String> getMonthAbbreviations(String locale) {
    final List<String> abbreviations = [];
    for (int i = 1; i <= 12; i++) {
      // Use a fixed year to avoid leap year issues
      final date = DateTime(2000, i, 1);
      abbreviations.add(DateFormat('MMM', locale).format(date));
    }
    return abbreviations;
  }
}
