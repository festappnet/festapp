// activity_timeline_controller.dart
import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/activities/activity_model.dart';

class ActivityTimelineController {
  final List<ActivityUserInfoModel> allUsers;
  final List<ActivityPlaceModel> allPlaces;
  final List<ActivityEventModel> allEvents;
  final List<ActivityModel> allActivities;
  final Map<ActivityModel, List<ActivityAssignmentModel>> activityAssignments;
  final Map<String, Duration> userAssignedHours;
  final String userFilter;
  final String placeFilter;
  final String eventFilter;
  final ValueChanged<String> onUserFilterChanged;
  final ValueChanged<String> onPlaceFilterChanged;
  final ValueChanged<String> onEventFilterChanged;
  final void Function(ActivityUserInfoModel) onUserDragStarted;
  final VoidCallback onUserDragEnd;
  final VoidCallback hideAssignmentDetailOverlay;
  final void Function(ActivityUserInfoModel targetUser,
      List<ActivityAssignmentModel> assignmentsToCopy) onCopyAssignments;
  final void Function(List<ActivityAssignmentModel>) onDeleteAssignments;
  final void Function(ActivityAssignmentModel, dynamic)
      onRemoveLinkFromAssignment;

  final bool isDark;

  ActivityTimelineController({
    required this.allUsers,
    required this.allPlaces,
    required this.allEvents,
    required this.allActivities,
    required this.activityAssignments,
    required this.userAssignedHours,
    required this.userFilter,
    required this.placeFilter,
    required this.eventFilter,
    required this.onUserFilterChanged,
    required this.onPlaceFilterChanged,
    required this.onEventFilterChanged,
    required this.onUserDragStarted,
    required this.onUserDragEnd,
    required this.onCopyAssignments,
    required this.onDeleteAssignments,
    required this.onRemoveLinkFromAssignment,
    required this.hideAssignmentDetailOverlay,
    required this.isDark,
  });

  Color get hintColor => isDark ? Colors.white54 : Colors.black54;
  Color get textColor => isDark ? Colors.white : Colors.black87;
}
