import 'dart:async';

import 'package:collection/collection.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fstapp/components/activities/activity_model.dart';
import 'package:fstapp/components/activities/db_activities.dart';
import 'package:fstapp/widgets/detail_dialog.dart';
import 'package:fstapp/components/html/rich_html_editor_dialog.dart';
import 'package:fstapp/components/html/rich_html_editor_controller.dart';
import 'package:fstapp/services/time_helper.dart';
import 'package:fstapp/services/app_logger.dart';
import 'package:fstapp/services/utilities_all.dart';
import 'package:multi_split_view/multi_split_view.dart';

import 'activities_component_strings.dart';
import 'activity_data_helper.dart';
import 'activity_history_helper.dart';
import 'activity_timeline_controller.dart';
import 'constants.dart';
import 'events_panel.dart';
import 'places_panel.dart';
import 'time_clamping_service.dart';
import 'timeline_painter.dart';
import 'timeline_row.dart';
import 'users_panel.dart';
import 'vertical_grid_lines_painter.dart';

class ActivitiesContent extends StatefulWidget {
  final int occasionId;

  const ActivitiesContent({super.key, required this.occasionId});

  @override
  _ActivitiesContentState createState() => _ActivitiesContentState();
}

class _ActivitiesContentState extends State<ActivitiesContent>
    with SingleTickerProviderStateMixin {
  final _htmlSave = HtmlSaveCoordinator();
  @override
  Widget build(BuildContext context) => HtmlEditingScope(
      coordinator: _htmlSave,
      child: AbsorbPointer(
          absorbing: _isPublishing, child: _buildHtmlParent(context)));

  EditDataBundle? _bundle;
  DateTime? _timelineStart, _timelineEnd;
  late final ActivityHistoryHelper _historyHelper;
  Timer? _autosaveDebounce;
  int _editorGeneration = 0;
  bool _autosaveQueued = false;
  bool _isPublishing = false;
  double _scale = ActivityConstants.kInitialScale;
  double _panOffset = ActivityConstants.kInitialPanOffset;
  final ValueNotifier<double> _currentPanOffsetNotifier =
      ValueNotifier<double>(ActivityConstants.kInitialPanOffset);
  double _gesturePanOffsetStart = 0.0;
  double _gestureDragStartX = 0.0;
  double _scrollbarGestureDragStartX = 0.0;
  double _scrollbarGesturePanOffsetStartValue = 0.0;
  final double _basePps = ActivityConstants.kBasePixelsPerSecond;
  late List<ActivityUserInfoModel> _allUsers;
  late List<ActivityPlaceModel> _allPlaces;
  late List<ActivityEventModel> _allEvents;
  String _userFilter = '';
  String _placeFilter = '';
  String _eventFilter = '';
  final Map<ActivityModel, List<ActivityAssignmentModel>> _activityAssignments =
      {};
  final Map<String, Duration> _userAssignedHours = {};
  final Set<ActivityModel> _selectedActivities = {};
  late MultiSplitViewController _mainController;
  late MultiSplitViewController _topController;
  ActivityUserInfoModel? _currentlyDraggedUser;
  ActivityModel? _hoveredActivityForPreview;
  DateTime? _previewStartTime;
  ActivityAssignmentModel? _copyDragSource;
  ActivityAssignmentModel? _copyDragPreview;
  OverlayEntry? _detailOverlayEntry;
  ActivityAssignmentModel? _selectedAssignmentForDetail;
  String _globalTimelineFilter = '';
  final TextEditingController _globalFilterController = TextEditingController();
  List<ActivityModel> _filteredActivities = [];
  bool _isTimelineFullscreen = false;
  double _currentViewportWidth = 0;
  static const int kTimelinePaddingDaysBefore = 1;
  static const int kTimelinePaddingDaysAfter = 1;
  bool _isModifierKeyPressedForScroll = false;
  late AnimationController _animationController;
  late Animation<double> _animationX;
  bool _justAutosaved = false;
  bool _isAutosaveLoaded = false;

  @override
  void initState() {
    super.initState();
    _historyHelper = ActivityHistoryHelper();
    _mainController = MultiSplitViewController(areas: [
      Area(data: 'top', size: 160, min: 100),
      Area(data: 'bottom', flex: 1)
    ]);
    _topController = MultiSplitViewController(areas: [
      Area(data: 'users', flex: 1),
      Area(data: 'places', flex: 1),
      Area(data: 'events', flex: 1)
    ]);
    _allUsers = [];
    _allPlaces = [];
    _allEvents = [];
    _loadData();
    _globalFilterController.addListener(() {
      if (_globalFilterController.text != _globalTimelineFilter) {
        setState(() {
          _globalTimelineFilter = _globalFilterController.text;
          _updateFilteredActivities();
        });
      }
    });
    _isModifierKeyPressedForScroll =
        HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isMetaPressed;
    HardwareKeyboard.instance.addHandler(_handleGlobalModifierKey);
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _animationController.addListener(() {
      _currentPanOffsetNotifier.value = _animationX.value;
    });
  }

  @override
  void dispose() {
    _editorGeneration++;
    _htmlSave.dispose();
    _hideAssignmentDetailOverlay();
    _autosaveDebounce?.cancel();
    _mainController.dispose();
    _topController.dispose();
    _globalFilterController.dispose();
    _currentPanOffsetNotifier.dispose();
    _animationController.dispose();
    HardwareKeyboard.instance.removeHandler(_handleGlobalModifierKey);
    super.dispose();
  }

  bool _handleGlobalModifierKey(KeyEvent event) {
    final bool newModifierState = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;

    if (_isModifierKeyPressedForScroll != newModifierState) {
      if (mounted) {
        setState(() {
          _isModifierKeyPressedForScroll = newModifierState;
        });
      }
    }
    return false;
  }

  void _triggerAutosaveDebounce() {
    // This block handles hiding the "Autosaved" text on a new edit.
    if (_justAutosaved) {
      setState(() {
        _justAutosaved = false;
      });
    }

    _autosaveDebounce?.cancel();
    _autosaveDebounce = Timer(ActivityConstants.autosaveInterval, _autosave);
  }

  void _recordStateChange() {
    if (_bundle == null || _isPublishing) return;
    _editorGeneration++;

    _bundle!.activities?.forEach((activity) {
      activity.assignments = _activityAssignments[activity]
              ?.where((a) => a.data?['isDragPreview'] != true)
              .toList() ??
          [];
    });
    _historyHelper.record(_bundle!);
    _triggerAutosaveDebounce();
    setState(() {});
  }

  void _undo() {
    if (_historyHelper.canUndo) {
      final stateToRestore = _historyHelper.undo();
      if (stateToRestore != null) {
        stateToRestore.retainSessionFrom(_bundle!);
        _processBundle(stateToRestore, preservePanAndScale: true);
        _triggerAutosaveDebounce();
      }
    }
  }

  void _redo() {
    if (_historyHelper.canRedo) {
      final stateToRestore = _historyHelper.redo();
      if (stateToRestore != null) {
        stateToRestore.retainSessionFrom(_bundle!);
        _processBundle(stateToRestore, preservePanAndScale: true);
        _triggerAutosaveDebounce(); // Trigger autosave, but don't record history
      }
    }
  }

  bool _isShowingConflictDialog = false;

  Future<EditDataBundle> _prepareActivityHtml() async {
    final bundle = _bundle!;
    final snapshot = EditDataBundle(
        id: bundle.id,
        parentHistoryId: bundle.parentHistoryId,
        aggregateVersion: bundle.aggregateVersion,
        events: bundle.events,
        places: bundle.places,
        users: bundle.users,
        assignmentPlaceLinks: bundle.assignmentPlaceLinks,
        assignmentEventLinks: bundle.assignmentEventLinks,
        activityAssignments: bundle.activityAssignments,
        activities: bundle.activities
            ?.map((activity) => ActivityModel.fromJson(activity.toJson()))
            .toList());
    for (final activity in snapshot.activities ?? <ActivityModel>[]) {
      activity.description = await _htmlSave.prepare(activity.description ?? '',
          HtmlMediaOwner.occasion(widget.occasionId));
    }
    return snapshot;
  }

  Future<void>? _autosaving;
  Future<void> _autosave() {
    if (_autosaving != null) {
      _autosaveQueued = true;
      return _autosaving!;
    }
    if (_isPublishing || _htmlSave.media.hasUnknownUploads) {
      return Future.value();
    }
    final operation = _performAutosave();
    _autosaving = operation;
    return operation.whenComplete(() {
      _autosaving = null;
      if (_autosaveQueued && mounted && !_isPublishing) {
        _autosaveQueued = false;
        _triggerAutosaveDebounce();
      }
    });
  }

  Future<void> _performAutosave() async {
    if (!mounted || _bundle == null || _isShowingConflictDialog) return;
    final generation = _editorGeneration;
    final actor = RightsService.currentUser()?.id;

    setState(() {
      _justAutosaved = false;
    });

    bool didSaveSuccessfully = false;
    try {
      final snapshot = await _prepareActivityHtml();
      if (!mounted ||
          generation != _editorGeneration ||
          actor != RightsService.currentUser()?.id) {
        _autosaveQueued = true;
        return;
      }
      final response =
          await DbActivities.autosaveActivities(widget.occasionId, snapshot);
      if (!mounted ||
          generation != _editorGeneration ||
          actor != RightsService.currentUser()?.id) {
        return;
      }

      if (response != null && response['code'] == 409) {
        final conflictData = response['data'] as Map<String, dynamic>?;
        final publishedAtStr = conflictData?['published_at'] as String?;

        String conflictMessage =
            ActivitiesComponentStrings.conflictMessageDefault;
        if (publishedAtStr != null) {
          final publishedAt = DateTime.parse(publishedAtStr).toLocal();
          final formattedTime =
              DateFormat.jm(context.locale.toString()).format(publishedAt);
          final formattedDate =
              DateFormat.yMMMd(context.locale.toString()).format(publishedAt);
          conflictMessage = ActivitiesComponentStrings.conflictMessageWithTime(
              formattedTime, formattedDate);
        }

        final choice = await _showConflictDialog(conflictMessage);

        if (mounted) {
          if (choice == 'reload') {
            await _loadData(forcePublished: true);
            return;
          } else if (choice == 'continue') {
            final currentSession =
                await DbActivities.getEditorSession(widget.occasionId);
            if (!mounted ||
                generation != _editorGeneration ||
                actor != RightsService.currentUser()?.id) {
              return;
            }
            setState(() {
              _bundle!.retainSessionFrom(currentSession.bundle);
            });
            _autosaveQueued = true;
            return;
          }
        }
      } else if (response != null && response['code'] == 200) {
        _bundle!.id = (response['data']['draft_id'] as num?)?.toInt();
        didSaveSuccessfully = true;
      } else {}
    } catch (e) {
      // Autosave failed
    }

    if (!mounted) return;

    setState(() {
      _justAutosaved = didSaveSuccessfully;
    });
  }

  void _copyAssignmentsToNewUser(ActivityUserInfoModel targetUser,
      List<ActivityAssignmentModel> assignmentsToCopy) {
    if (assignmentsToCopy.isEmpty) return;

    setState(() {
      for (final originalAssignment in assignmentsToCopy) {
        // Find the original activity for this assignment
        final activity = _bundle!.activities!
            .firstWhereOrNull((act) => act.id == originalAssignment.activityId);

        if (activity != null) {
          // Create a new assignment with the same details but for the target user
          final newAssignment = ActivityAssignmentModel(
            activityId: originalAssignment.activityId,
            userInfo: targetUser.id,
            user: targetUser,
            startTime: originalAssignment.startTime,
            endTime: originalAssignment.endTime,
            places: List.from(originalAssignment.places), // Deep copy lists
            events: List.from(originalAssignment.events),
            data: null, // Ensure data is clean for the new assignment
          );

          _activityAssignments
              .putIfAbsent(activity, () => [])
              .add(newAssignment);
        }
      }
      _recalculateUserAssignedHours();
      _recordStateChange();
    });
  }

  void _deleteAssignments(List<ActivityAssignmentModel> assignmentsToDelete) {
    if (assignmentsToDelete.isEmpty) return;
    setState(() {
      for (final assignment in assignmentsToDelete) {
        // Find the activity this assignment belongs to
        final activity = _bundle?.activities
            ?.firstWhereOrNull((act) => act.id == assignment.activityId);
        if (activity != null) {
          _activityAssignments[activity]
              ?.removeWhere((a) => a.id == assignment.id);
        }
      }
      _recalculateUserAssignedHours();
      _recordStateChange();
    });
  }

  void _removeLinkFromAssignment(
      ActivityAssignmentModel assignment, dynamic itemToRemove) {
    setState(() {
      if (itemToRemove is ActivityPlaceModel) {
        assignment.places.removeWhere((p) => p.id == itemToRemove.id);
      } else if (itemToRemove is ActivityEventModel) {
        assignment.events.removeWhere((e) => e.id == itemToRemove.id);
      }
      _recordStateChange();
    });
  }

  Future<String?> _showConflictDialog(String message) async {
    if (_isShowingConflictDialog) return null;
    setState(() => _isShowingConflictDialog = true);

    final String? choice = await showDialog<String>(
      context: context,
      barrierDismissible: true, // Allow dismissing by tapping the background
      builder: (ctx) => AlertDialog(
        title: Text(ActivitiesComponentStrings.dialogTitleUpdateConflict),
        content: Text(message),
        actions: <Widget>[
          // Both buttons are now TextButton for a neutral choice
          TextButton(
            child: Text(ActivitiesComponentStrings.buttonContinueWithDraft),
            onPressed: () {
              Navigator.of(ctx).pop('continue');
            },
          ),
          TextButton(
            child: Text(ActivitiesComponentStrings.buttonLoadNewestVersion),
            onPressed: () {
              Navigator.of(ctx).pop('reload');
            },
          ),
        ],
      ),
    );

    if (mounted) {
      setState(() => _isShowingConflictDialog = false);
    }

    return choice;
  }

  void _processBundle(EditDataBundle bundle,
      {bool preservePanAndScale = false}) {
    if (!mounted) return;
    _editorGeneration++;
    // Create a new, complete bundle for the new state.
    // If the incoming bundle from history is missing static data (users, places, events),
    // this merge operation populates it from the current state's master lists (_bundle).
    // If the incoming bundle is from the initial _loadData, it will be complete already.
    final newCompleteBundle = EditDataBundle(
      users: bundle.users ?? _bundle?.users,
      places: bundle.places ?? _bundle?.places,
      events: bundle.events ?? _bundle?.events,

      // Copy the dynamic, historical data from the incoming bundle
      activities: bundle.activities,
      activityAssignments: bundle.activityAssignments,
      assignmentPlaceLinks: bundle.assignmentPlaceLinks,
      assignmentEventLinks: bundle.assignmentEventLinks,

      // Copy the metadata
      id: bundle.id,
      parentHistoryId: bundle.parentHistoryId,
      aggregateVersion: bundle.aggregateVersion,
    );

    // The new bundle is now logically complete, but object references might be
    // broken if they came from a deserialized object. Re-link everything.
    ActivityDataHelper.linkAssignmentsToActivities(newCompleteBundle);

    // Sort activities by their specified order.
    newCompleteBundle.activities
        ?.sort((a, b) => (a.order ?? 0).compareTo(b.order ?? 0));

    setState(() {
      // Set the main state bundle to our newly constructed complete bundle.
      _bundle = newCompleteBundle;

      // Ensure the top-level master lists are also updated.
      _allUsers = _bundle!.users ?? [];
      _allPlaces = _bundle!.places ?? [];
      _allEvents = _bundle!.events ?? [];

      // Re-calculate all derived data and update UI.
      _computeTimelineBounds();
      _activityAssignments.clear();
      if (_bundle!.activities != null) {
        for (final activity in _bundle!.activities!) {
          _activityAssignments[activity] =
              List.from(activity.assignments ?? []);
        }
      }
      _recalculateUserAssignedHours();
      if (!preservePanAndScale) {
        _panOffset = ActivityConstants.kInitialPanOffset;
        _scale = ActivityConstants.kInitialScale;
      }
      _currentPanOffsetNotifier.value = _panOffset;
      _updateFilteredActivities();
    });
  }

  Future<void> _loadData(
      {bool forcePublished = false,
      double? initialPanOffset,
      double? initialScale}) async {
    // Prevent multiple load operations from running concurrently
    if (_isShowingConflictDialog) return;

    // Step 1: Always fetch the complete data bundle first. This provides the master lists
    // of all users, places, and events for the entire session.
    final generation = ++_editorGeneration;
    final actor = RightsService.currentUser()?.id;
    final session = await DbActivities.getEditorSession(widget.occasionId);
    if (!mounted ||
        generation != _editorGeneration ||
        actor != RightsService.currentUser()?.id) {
      return;
    }
    final baseBundle = session.bundle;
    // Step 2: Now, check for autosaves and the latest published version ID.
    final autosaveInfo = session.autosave;
    final latestPublishId = autosaveInfo.latestPublishId;
    // If forcePublished is true, we ignore the returned autosave bundle.
    final autosavedBundle =
        forcePublished ? null : autosaveInfo.autosavedBundle;

    EditDataBundle? dataToLoad;
    bool loadedFromAutosave = false;

    if (autosavedBundle != null) {
      // An autosave exists. It only contains activity-specific data.
      final isStale = latestPublishId != null &&
          autosavedBundle.parentHistoryId != latestPublishId;
      if (isStale) {
        // The user's autosave is based on an older published version.
        final choice = await _showConflictDialog(
            ActivitiesComponentStrings.staleAutosaveConflictMessage);

        if (!mounted ||
            generation != _editorGeneration ||
            actor != RightsService.currentUser()?.id) {
          return;
        }
        if (choice == 'reload') {
          await DbActivities.deleteAutosave(widget.occasionId,
              expectedDraftId: autosavedBundle.id);
          baseBundle.id = null;
          // Use the fresh baseBundle we already fetched.
          dataToLoad = baseBundle;
        } else if (choice == 'continue') {
          // User wants to keep their draft. MERGE it with the base data.
          baseBundle.activities = autosavedBundle.activities;
          baseBundle.activityAssignments = autosavedBundle.activityAssignments;
          baseBundle.assignmentEventLinks =
              autosavedBundle.assignmentEventLinks;
          baseBundle.assignmentPlaceLinks =
              autosavedBundle.assignmentPlaceLinks;
          // Re-base the merged bundle on the new published version.
          baseBundle.parentHistoryId = latestPublishId;
          dataToLoad = baseBundle;
          loadedFromAutosave = true;
        } else {
          // User dismissed the dialog. Default to loading the fresh data without the autosave.
          dataToLoad = baseBundle;
        }
      } else {
        // Autosave is not stale. MERGE its data into the base bundle.
        baseBundle.activities = autosavedBundle.activities;
        baseBundle.activityAssignments = autosavedBundle.activityAssignments;
        baseBundle.assignmentEventLinks = autosavedBundle.assignmentEventLinks;
        baseBundle.assignmentPlaceLinks = autosavedBundle.assignmentPlaceLinks;
        baseBundle.parentHistoryId = autosavedBundle.parentHistoryId;
        dataToLoad = baseBundle;
        loadedFromAutosave = true;
      }
    }

    // If dataToLoad is still null, it means no autosave existed. Use the base bundle.
    if (dataToLoad == null) {
      dataToLoad = baseBundle;
      dataToLoad.parentHistoryId =
          latestPublishId; // Base this session on the latest publish
      loadedFromAutosave = false;
    }

    if (!mounted ||
        generation != _editorGeneration ||
        actor != RightsService.currentUser()?.id) {
      return;
    }
    setState(() {
      _isAutosaveLoaded = loadedFromAutosave;
      _justAutosaved = loadedFromAutosave;
    });

    // _processBundle will now always receive a complete bundle for initial processing.
    _processBundle(dataToLoad, preservePanAndScale: initialPanOffset != null);
    _historyHelper.clear(dataToLoad);

    if (initialPanOffset != null && initialScale != null) {
      setState(() {
        _panOffset = initialPanOffset;
        _scale = initialScale;
        _currentPanOffsetNotifier.value = _panOffset;
      });
    }

    final loadedGeneration = _editorGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          loadedGeneration == _editorGeneration &&
          actor == RightsService.currentUser()?.id) {
        if (initialPanOffset == null) {
          _performInitialTimelineScroll();
        }
      }
    });
  }

  void _performInitialTimelineScroll() {
    if (_currentViewportWidth <= 0 && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _performInitialTimelineScroll();
      });
      return;
    }
    DateTime? earliestTimeToShow;
    List<DateTime> allPossibleStartTimes = [];
    if (_bundle?.events?.isNotEmpty ?? false) {
      allPossibleStartTimes.addAll(_bundle!.events!.map((e) => e.startTime));
    }
    _activityAssignments.values.expand((list) => list).forEach((assignment) {
      if (assignment.startTime != null &&
          assignment.data?['isDragPreview'] != true) {
        allPossibleStartTimes.add(assignment.startTime!);
      }
    });
    if (allPossibleStartTimes.isNotEmpty) {
      allPossibleStartTimes.sort((a, b) => a.compareTo(b));
      earliestTimeToShow = allPossibleStartTimes.first;
    }
    if (earliestTimeToShow != null &&
        _timelineStart != null &&
        _timelineEnd != null) {
      _shiftTimelineToDateTime(earliestTimeToShow);
    }
  }

  void _computeTimelineBounds() {
    final allStarts = <DateTime>[], allEnds = <DateTime>[];
    if (_bundle!.events != null) {
      for (var e in _bundle!.events!) {
        allStarts.add(e.startTime);
        allEnds.add(e.endTime);
      }
    }
    if (_bundle!.activities != null) {
      for (var activity in _bundle!.activities!) {
        for (var au in activity.assignments ?? []) {
          if (au.startTime != null && au.endTime != null) {
            allStarts.add(au.startTime!);
            allEnds.add(au.endTime!);
          }
        }
      }
    }
    if (allStarts.isNotEmpty && allEnds.isNotEmpty) {
      allStarts.sort();
      allEnds.sort();
      DateTime earliestActivityDate = allStarts.first;
      DateTime latestActivityDate = allEnds.last;
      _timelineStart = DateTime(earliestActivityDate.year,
              earliestActivityDate.month, earliestActivityDate.day)
          .toOccasionTime()
          .subtract(const Duration(days: kTimelinePaddingDaysBefore));
      _timelineEnd = DateTime(latestActivityDate.year, latestActivityDate.month,
              latestActivityDate.day, 23, 59, 59, 999)
          .toOccasionTime()
          .add(const Duration(days: kTimelinePaddingDaysAfter));
    } else {
      final now = TimeHelper.now();
      _timelineStart = now.subtract(const Duration(hours: 1));
      _timelineEnd = now.add(const Duration(hours: 1));
    }
  }

  void _shiftTimelineToDateTime(DateTime targetTime) {
    if (_timelineStart == null ||
        _timelineEnd == null ||
        _currentViewportWidth <= 0 ||
        !mounted) {
      return;
    }
    final pps = _basePps * _scale;
    final timelineWidth =
        _timelineEnd!.difference(_timelineStart!).inSeconds.toDouble() * pps;
    final visibleTimelineAreaWidth =
        _currentViewportWidth - ActivityConstants.kTimelineLabelWidth;
    DateTime effectiveTargetTime = targetTime;
    if (effectiveTargetTime.isBefore(_timelineStart!)) {
      effectiveTargetTime = _timelineStart!;
    }
    final Duration durationFromStart =
        effectiveTargetTime.difference(_timelineStart!);
    final double pixelOffsetFromTimelineStart =
        durationFromStart.inSeconds * pps;
    double newPanOffset = -pixelOffsetFromTimelineStart;
    newPanOffset = newPanOffset.clamp(
        (visibleTimelineAreaWidth - timelineWidth)
            .clamp(double.negativeInfinity, 0.0),
        0.0);
    if ((_panOffset - newPanOffset).abs() > 0.01 ||
        (_currentPanOffsetNotifier.value - newPanOffset).abs() > 0.01) {
      setState(() {
        _panOffset = newPanOffset;
        _currentPanOffsetNotifier.value = _panOffset;
      });
    }
  }

  void _onAddNewActivity() {
    _hideAssignmentDetailOverlay();
    final newOrder = _bundle?.activities?.length ?? 0;

    // The ActivityModel constructor now automatically generates a client-side UUID.
    final newAct = ActivityModel(
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      title:
          '${ActivitiesComponentStrings.textUntitledActivity} ${newOrder + 1}',
      description: '',
      type: null,
      occasion: widget.occasionId,
      unit: null,
      isHidden: false,
      order: newOrder,
      data: {},
      assignments: [],
    );

    setState(() {
      _bundle?.activities?.add(newAct);
      _activityAssignments[newAct] = [];
      _updateFilteredActivities();
      _recordStateChange();
    });
  }

  void _zoomIn(double vpWidth, double totalSec) {
    _hideAssignmentDetailOverlay();
    if (_timelineStart == null) return;
    final double oldScale = _scale;
    final double newScale = (_scale * ActivityConstants.kScaleFactor)
        .clamp(ActivityConstants.kMinScale, ActivityConstants.kMaxScale);

    if (newScale == oldScale) return;

    final double oldPps = _basePps * oldScale;
    final double newPps = _basePps * newScale;
    final double visibleTimelineAreaWidth =
        vpWidth - ActivityConstants.kTimelineLabelWidth;

    // Center the zoom on the middle of the viewport
    final double timelinePointAtViewportCenterPx =
        -_panOffset + (visibleTimelineAreaWidth / 2);
    final Duration durationOffsetFromStart =
        Duration(seconds: (timelinePointAtViewportCenterPx / oldPps).round());
    final double newTimelinePointAtViewportCenterPx =
        durationOffsetFromStart.inSeconds * newPps;

    double newPanOffset =
        (visibleTimelineAreaWidth / 2) - newTimelinePointAtViewportCenterPx;
    final double newTimelineWidth = totalSec * newPps;

    // Clamp the new pan offset to the valid range
    newPanOffset = newPanOffset.clamp(
        (vpWidth - (ActivityConstants.kTimelineLabelWidth + newTimelineWidth))
            .clamp(double.negativeInfinity, 0.0),
        0.0);

    setState(() {
      _scale = newScale;
      _panOffset = newPanOffset;
      _currentPanOffsetNotifier.value = _panOffset;
    });
  }

  void _zoomOut(double vpWidth, double totalSec) {
    _hideAssignmentDetailOverlay();
    if (_timelineStart == null) return;
    final double oldScale = _scale;
    final double newScale = (_scale / ActivityConstants.kScaleFactor)
        .clamp(ActivityConstants.kMinScale, ActivityConstants.kMaxScale);

    if (newScale == oldScale) return;

    final double oldPps = _basePps * oldScale;
    final double newPps = _basePps * newScale;
    final double visibleTimelineAreaWidth =
        vpWidth - ActivityConstants.kTimelineLabelWidth;

    // Center the zoom on the middle of the viewport
    final double timelinePointAtViewportCenterPx =
        -_panOffset + (visibleTimelineAreaWidth / 2);
    final Duration durationOffsetFromStart =
        Duration(seconds: (timelinePointAtViewportCenterPx / oldPps).round());
    final double newTimelinePointAtViewportCenterPx =
        durationOffsetFromStart.inSeconds * newPps;

    double newPanOffset =
        (visibleTimelineAreaWidth / 2) - newTimelinePointAtViewportCenterPx;
    final double newTimelineWidth = totalSec * newPps;

    // Clamp the new pan offset to the valid range
    newPanOffset = newPanOffset.clamp(
        (vpWidth - (ActivityConstants.kTimelineLabelWidth + newTimelineWidth))
            .clamp(double.negativeInfinity, 0.0),
        0.0);

    setState(() {
      _scale = newScale;
      _panOffset = newPanOffset;
      _currentPanOffsetNotifier.value = _panOffset;
    });
  }

  void _deleteSelectedActivities() {
    _hideAssignmentDetailOverlay();
    if (_selectedActivities.isEmpty) return;

    _bundle!.activities!
        .removeWhere((act) => _selectedActivities.contains(act));
    _selectedActivities.forEach(_activityAssignments.remove);
    _selectedActivities.clear();
    _updateFilteredActivities();
    _recalculateUserAssignedHours();
    _recordStateChange(); // This will handle the rebuild
  }

  Future<void> _showRenameDialog(ActivityModel a) async {
    _hideAssignmentDetailOverlay();
    final controller = TextEditingController(text: a.title);
    final isDark = ActivityConstants.isDarkMode(context);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? Colors.grey[800] : Colors.white,
        titleTextStyle: TextStyle(color: isDark ? Colors.white : Colors.black),
        contentTextStyle:
            TextStyle(color: isDark ? Colors.white70 : Colors.black87),
        title: Text(ActivitiesComponentStrings.dialogRenameActivity),
        content: TextField(
            controller: controller,
            autofocus: true,
            style: TextStyle(color: isDark ? Colors.white : Colors.black),
            decoration: InputDecoration(
                labelText: ActivitiesComponentStrings.labelTitle,
                labelStyle: TextStyle(
                    color: isDark ? Colors.white70 : Colors.black54))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(ActivitiesComponentStrings.buttonCancel,
                  style:
                      TextStyle(color: Theme.of(ctx).colorScheme.secondary))),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: Text(ActivitiesComponentStrings.buttonOK)),
        ],
      ),
    );
    if (result != null &&
        result.trim().isNotEmpty &&
        result.trim() != a.title) {
      setState(() {
        a.title = result.trim();
        _updateFilteredActivities();
        _recordStateChange();
      });
    }
  }

  Duration _getSnappedDragDuration() {
    const double baseDurationHours = 4.0;
    const double minDurationHours = 0.25;
    final double constant = baseDurationHours * ActivityConstants.kInitialScale;
    double calculatedHours = constant / _scale;
    calculatedHours =
        calculatedHours.clamp(minDurationHours, baseDurationHours);
    Duration calculatedDuration =
        Duration(minutes: (calculatedHours * 60).round());
    final Duration snapInterval = _scale < 0.5
        ? ActivityConstants.kSnapStepCoarse
        : ActivityConstants.kSnapStepFine;
    if (snapInterval.inSeconds > 0) {
      final int numSnapIntervals =
          (calculatedDuration.inSeconds / snapInterval.inSeconds).round();
      calculatedDuration =
          Duration(seconds: numSnapIntervals * snapInterval.inSeconds);
    }
    if (calculatedDuration < ActivityConstants.kMinTimeLength) {
      return ActivityConstants.kMinTimeLength;
    }
    return calculatedDuration;
  }

  DateTime _calculateSnappedTimeFromOffset(
      Offset globalOffset, double timelineRenderWidth) {
    if (_timelineStart == null || _timelineEnd == null || !mounted) {
      return _timelineStart ?? TimeHelper.now();
    }
    final RenderBox? timelineAreaRenderBox =
        context.findRenderObject() as RenderBox?;
    if (timelineAreaRenderBox == null || !timelineAreaRenderBox.hasSize) {
      return _timelineStart!;
    }
    final Offset localOffset =
        timelineAreaRenderBox.globalToLocal(globalOffset);
    final double dxOnTimelineCanvas = (localOffset.dx -
            ActivityConstants.kTimelineLabelWidth -
            _currentPanOffsetNotifier.value)
        .clamp(0.0, timelineRenderWidth);
    final double pct = timelineRenderWidth > 0
        ? dxOnTimelineCanvas / timelineRenderWidth
        : 0.0;
    final int totalTimelineSeconds =
        _timelineEnd!.difference(_timelineStart!).inSeconds;
    DateTime calculatedTime = _timelineStart!
        .add(Duration(seconds: (totalTimelineSeconds * pct).round()));
    final Duration snapStep = _scale < 0.5
        ? ActivityConstants.kSnapStepCoarse
        : ActivityConstants.kSnapStepFine;
    if (snapStep.inSeconds > 0) {
      final int numSnapSteps =
          (calculatedTime.difference(_timelineStart!).inSeconds /
                  snapStep.inSeconds)
              .round();
      calculatedTime = _timelineStart!
          .add(Duration(seconds: numSnapSteps * snapStep.inSeconds));
    }
    return calculatedTime;
  }

  void _handlePlaceOrEventDropOnAssignment(
      ActivityAssignmentModel assignment, dynamic droppedItemData) {
    bool changed = false;
    if (droppedItemData is ActivityPlaceModel) {
      if (!assignment.places.any((p) => p.id == droppedItemData.id)) {
        assignment.places.add(droppedItemData);
        changed = true;
      }
    } else if (droppedItemData is ActivityEventModel) {
      if (!assignment.events.any((e) => e.id == droppedItemData.id)) {
        assignment.events.add(droppedItemData);
        changed = true;
      }
    }
    if (changed) {
      if (_detailOverlayEntry != null &&
          _selectedAssignmentForDetail == assignment) {
        _detailOverlayEntry!.markNeedsBuild();
      }
      _recordStateChange();
    }
  }

  void _removePlaceFromAssignment(
      ActivityAssignmentModel assignment, ActivityPlaceModel place) {
    assignment.places.removeWhere((p) => p.id == place.id);
    if (_detailOverlayEntry != null &&
        _selectedAssignmentForDetail == assignment) {
      _detailOverlayEntry!.markNeedsBuild();
    }
    _recordStateChange();
  }

  void _removeEventFromAssignment(
      ActivityAssignmentModel assignment, ActivityEventModel event) {
    assignment.events.removeWhere((e) => e.id == event.id);
    if (_detailOverlayEntry != null &&
        _selectedAssignmentForDetail == assignment) {
      _detailOverlayEntry!.markNeedsBuild();
    }
    _recordStateChange();
  }

  void _hideAssignmentDetailOverlay() {
    if (_detailOverlayEntry != null) {
      _detailOverlayEntry!.remove();
      _detailOverlayEntry = null;
      _selectedAssignmentForDetail = null;
    }
  }

  void _deleteAssignment(ActivityAssignmentModel assignmentToDelete) {
    ActivityModel? targetActivity;
    for (var entry in _activityAssignments.entries) {
      if (entry.value.any((a) => a.id == assignmentToDelete.id)) {
        targetActivity = entry.key;
        break;
      }
    }
    if (targetActivity != null) {
      // Mutate state directly, without wrapping in setState
      _activityAssignments[targetActivity]
          ?.removeWhere((a) => a.id == assignmentToDelete.id);
      _recalculateUserAssignedHours();
      // Now call the method that triggers the rebuild
      _recordStateChange();
    }
    _hideAssignmentDetailOverlay();
  }

  void _recalculateUserAssignedHours() {
    _userAssignedHours.clear();
    _activityAssignments.values.expand((list) => list).forEach((assignment) {
      if (assignment.userInfo != null &&
          assignment.startTime != null &&
          assignment.endTime != null &&
          assignment.data?['isDragPreview'] != true) {
        final duration = assignment.endTime!.difference(assignment.startTime!);
        _userAssignedHours.update(
            assignment.userInfo!, (value) => value + duration,
            ifAbsent: () => duration);
      }
    });
  }

  Future<void> _showHistoryDialog() async {
    final historyItems =
        await DbActivities.listActivityHistory(widget.occasionId);
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) {
        final isDark = ActivityConstants.isDarkMode(ctx);
        return AlertDialog(
          title: Text(ActivitiesComponentStrings.dialogTitleVersionHistory),
          backgroundColor: isDark ? Colors.grey[800] : Colors.white,
          titleTextStyle:
              TextStyle(color: isDark ? Colors.white : Colors.black),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              itemCount: historyItems.length,
              itemBuilder: (context, index) {
                final item = historyItems[index];
                final isAutosave = item.historyType == 'AUTOSAVE';
                final formattedDate =
                    DateFormat.yMMMd(context.locale.toString())
                        .add_jms()
                        .format(item.createdAt.toLocal());

                final typeString = isAutosave
                    ? ActivitiesComponentStrings.textAutosavedDraft
                    : ActivitiesComponentStrings.textPublishedVersion;

                // Define a unique icon and color based on the history type for clear visual differentiation.
                final IconData versionIcon;
                final Color versionColor;
                if (isAutosave) {
                  versionIcon =
                      Icons.history_toggle_off; // Icon for an in-progress draft
                  versionColor =
                      isDark ? Colors.orange.shade300 : Colors.orange.shade700;
                } else {
                  // Published
                  versionIcon = Icons
                      .publish_outlined; // Icon for a finalized, published version
                  versionColor =
                      isDark ? Colors.green.shade300 : Colors.green.shade600;
                }

                return ListTile(
                  // Add the leading icon to the list tile.
                  leading: Icon(versionIcon, color: versionColor),
                  title: Text(
                    ActivitiesComponentStrings.historyLabel(
                        typeString, item.userFullName),
                    style: TextStyle(
                        fontSize: 14,
                        color: isDark ? Colors.white : Colors.black),
                  ),
                  subtitle: Text(
                    formattedDate,
                    style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white70 : Colors.black54),
                  ),
                  trailing: TextButton(
                    child: Text(ActivitiesComponentStrings.buttonRestore),
                    onPressed: () async {
                      Navigator.of(ctx).pop(); // Close dialog
                      final generation = _editorGeneration;
                      final actor = RightsService.currentUser()?.id;
                      final bundleToRestore =
                          await DbActivities.getActivityHistoryVersion(
                              widget.occasionId, item.id);

                      if (!mounted ||
                          generation != _editorGeneration ||
                          actor != RightsService.currentUser()?.id) {
                        return;
                      }
                      final currentSession =
                          await DbActivities.getEditorSession(
                              widget.occasionId);
                      if (!mounted ||
                          generation != _editorGeneration ||
                          actor != RightsService.currentUser()?.id) {
                        return;
                      }
                      if (bundleToRestore != null) {
                        // Re-base the restored version on the CURRENT latest publish ID.
                        bundleToRestore
                            .retainSessionFrom(currentSession.bundle);

                        _processBundle(bundleToRestore,
                            preservePanAndScale: true);
                        _recordStateChange();
                      }
                    },
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(ActivitiesComponentStrings.buttonClose),
            ),
          ],
        );
      },
    );
  }

  Widget _buildAssignmentDetailContent() {
    if (_selectedAssignmentForDetail == null) return const SizedBox.shrink();
    final assignment = _selectedAssignmentForDetail!;
    final isDark = ActivityConstants.isDarkMode(context);
    String formatTime(DateTime time) {
      return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    }

    final textColor = isDark ? Colors.white : Colors.black87;
    final chipTextColor = isDark ? Colors.white : Colors.black87;
    final chipBackgroundColor =
        isDark ? Colors.grey[700] : Colors.blueGrey[200];
    final chipDeleteIconColor = isDark ? Colors.white70 : Colors.black54;
    return StatefulBuilder(
      builder: (BuildContext context, StateSetter setStateInPopup) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 4.0, right: 8.0),
                    child: Text(
                      assignment.user!.toFullNameString(),
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: textColor),
                    ),
                  ),
                ),
                SizedBox(
                  height: 24,
                  child: TextButton(
                    onPressed: () => _deleteAssignment(assignment),
                    style: TextButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                        padding: EdgeInsets.zero,
                        minimumSize: Size(30, 20),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.delete_outline, size: 14),
                        SizedBox(width: 2),
                        Text(ActivitiesComponentStrings.menuDelete,
                            style: TextStyle(fontSize: 10)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (assignment.startTime != null && assignment.endTime != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Text(
                  '${formatTime(assignment.startTime!)} – ${formatTime(assignment.endTime!)}',
                  style: TextStyle(
                      fontSize: 12, color: textColor.withOpacity(0.8)),
                ),
              ),
            if (assignment.places.isNotEmpty) ...[
              Padding(
                padding: EdgeInsets.symmetric(vertical: 4.0),
                child: Text(ActivitiesComponentStrings.labelPlaces,
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: textColor)),
              ),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: assignment.places
                    .map((place) => Chip(
                          avatar: Icon(Icons.location_pin,
                              size: 14, color: chipTextColor),
                          label: Text(
                              place.title ??
                                  ActivitiesComponentStrings.textUnnamedPlace,
                              style: TextStyle(
                                  color: chipTextColor, fontSize: 11)),
                          padding:
                              EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          backgroundColor: chipBackgroundColor,
                          onDeleted: () {
                            _removePlaceFromAssignment(assignment, place);
                            setStateInPopup(() {});
                          },
                          deleteIconColor: chipDeleteIconColor,
                          deleteButtonTooltipMessage:
                              ActivitiesComponentStrings.tooltipRemovePlace,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ))
                    .toList(),
              ),
            ],
            if (assignment.places.isNotEmpty && assignment.events.isNotEmpty)
              const SizedBox(height: 8),
            if (assignment.events.isNotEmpty) ...[
              Padding(
                padding: EdgeInsets.symmetric(vertical: 4.0),
                child: Text(ActivitiesComponentStrings.labelEvents,
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: textColor)),
              ),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: assignment.events
                    .map((event) => Chip(
                          avatar:
                              Icon(Icons.event, size: 14, color: chipTextColor),
                          label: Text(
                              event.title ??
                                  ActivitiesComponentStrings.textUnnamedEvent,
                              style: TextStyle(
                                  color: chipTextColor, fontSize: 11)),
                          padding:
                              EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          backgroundColor:
                              isDark ? Colors.grey[600] : Colors.orange[200],
                          onDeleted: () {
                            _removeEventFromAssignment(assignment, event);
                            setStateInPopup(() {});
                          },
                          deleteIconColor: chipDeleteIconColor,
                          deleteButtonTooltipMessage:
                              ActivitiesComponentStrings.tooltipRemoveEvent,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ))
                    .toList(),
              ),
            ],
            if ((assignment.places.isEmpty) && (assignment.events.isEmpty))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Text(ActivitiesComponentStrings.textNoItemsAssigned,
                    style: TextStyle(
                        fontStyle: FontStyle.italic,
                        color: textColor.withOpacity(0.6),
                        fontSize: 11)),
              ),
          ],
        );
      },
    );
  }

// In _ActivitiesContentState class

  void _showAssignmentDetailOverlay(
      ActivityAssignmentModel assignment, Offset globalTapPosition) {
    _hideAssignmentDetailOverlay();
    _selectedAssignmentForDetail = assignment;
    final isDark = ActivityConstants.isDarkMode(context);

    // Use the root overlay
    final overlay = Overlay.of(context);
    final screenSize = MediaQuery.of(context).size;

    // Correct coordinate mapping for nested scrollviews or tabviews
    final RenderBox overlayRenderBox =
        overlay.context.findRenderObject() as RenderBox;
    final Offset localTapPosition =
        overlayRenderBox.globalToLocal(globalTapPosition);
    var realHeightAddition = ActivityConstants.realHeightAddition;

    _detailOverlayEntry = OverlayEntry(
      builder: (context) {
        double left = localTapPosition.dx + 15;
        double top = localTapPosition.dy + 15;
        const double popupWidth = 280.0;
        const double popupMaxHeight = 350.0;

        // Prevent the popup from rendering off the right side of the screen
        if (left + popupWidth > screenSize.width) {
          left = screenSize.width - popupWidth - 10;
        }

        // Prevent the popup from rendering off the bottom of the screen
        if (top + popupMaxHeight > screenSize.height + realHeightAddition) {
          top = (screenSize.height + realHeightAddition) - popupMaxHeight - 10;
        }

        // Prevent rendering off the left or top edges
        if (left < 10) left = 10;
        if (top < 10) top = 10;

        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: _hideAssignmentDetailOverlay,
                behavior: HitTestBehavior.opaque,
                child: Container(color: Colors.transparent),
              ),
            ),
            Positioned(
              left: left,
              top: top,
              child: Container(
                width: popupWidth,
                constraints: const BoxConstraints(maxHeight: popupMaxHeight),
                child: Material(
                  elevation: 4.0,
                  color: isDark ? Colors.grey[850] : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(12.0),
                    child: _buildAssignmentDetailContent(),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );

    overlay.insert(_detailOverlayEntry!);
  }

  void _updateFilteredActivities() {
    if (_bundle == null || _bundle!.activities == null) {
      _filteredActivities = [];
      return;
    }
    if (_globalTimelineFilter.isEmpty) {
      _filteredActivities = List.from(_bundle!.activities!);
    } else {
      final normalizedFilter =
          Utilities.removeDiacritics(_globalTimelineFilter.toLowerCase());
      if (normalizedFilter.isEmpty) {
        _filteredActivities = List.from(_bundle!.activities!);
      } else {
        _filteredActivities = _bundle!.activities!.where((activity) {
          if (Utilities.removeDiacritics(activity.title?.toLowerCase() ?? "")
              .contains(normalizedFilter)) {
            return true;
          }
          final assignmentsForActivity = _activityAssignments[activity] ?? [];
          for (var assignment in assignmentsForActivity) {
            if (assignment.data?['isDragPreview'] == true) continue;
            if (Utilities.removeDiacritics(
                    assignment.user?.toFullNameString().toLowerCase() ?? "")
                .contains(normalizedFilter)) {
              return true;
            }
            for (var place in assignment.places) {
              if (Utilities.removeDiacritics(place.title?.toLowerCase() ?? "")
                  .contains(normalizedFilter)) {
                return true;
              }
            }
            for (var event in assignment.events) {
              if (Utilities.removeDiacritics(event.title?.toLowerCase() ?? "")
                  .contains(normalizedFilter)) {
                return true;
              }
            }
          }
          return false;
        }).toList();
      }
    }
  }

  KeyEventResult _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      final isControl = HardwareKeyboard.instance.isControlPressed;
      final isMeta = HardwareKeyboard.instance.isMetaPressed;
      final isShift = HardwareKeyboard.instance.isShiftPressed;
      if ((isControl || isMeta) &&
          event.logicalKey == LogicalKeyboardKey.keyZ) {
        if (isShift) {
          _redo();
        } else {
          _undo();
        }
        return KeyEventResult.handled;
      }
      if ((isControl && event.logicalKey == LogicalKeyboardKey.keyY) ||
          (isMeta && isShift && event.logicalKey == LogicalKeyboardKey.keyZ)) {
        _redo();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.delete &&
          _selectedActivities.isNotEmpty) {
        _deleteSelectedActivities();
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.escape) {
        if (_detailOverlayEntry != null) {
          _hideAssignmentDetailOverlay();
          return KeyEventResult.handled;
        } else if (_isTimelineFullscreen) {
          setState(() {
            _isTimelineFullscreen = false;
          });
          return KeyEventResult.handled;
        }
      }
    }
    return KeyEventResult.ignored;
  }

  void _handleUserDragStarted(ActivityUserInfoModel user) {
    _hideAssignmentDetailOverlay();
    setState(() => _currentlyDraggedUser = user);
  }

  void _handleUserDragEnd() {
    setState(() {
      _currentlyDraggedUser = null;
      _hoveredActivityForPreview = null;
      _previewStartTime = null;
    });
  }

  void _showActivityDescriptionEditor(ActivityModel activity) {
    RichHtmlEditorDialog.show(context,
            initialHtml: activity.description,
            loadHtml: () async => activity.description,
            owner: HtmlMediaOwner.occasion(widget.occasionId),
            coordinator: _htmlSave)
        .then((value) {
      if (value != null && value != activity.description) {
        setState(() {
          activity.description = value;
        });
        _recordStateChange();
      }
    });
  }

  Widget _buildHtmlParent(BuildContext context) {
    if (_bundle == null || _timelineStart == null || _timelineEnd == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final isDarkTheme = ActivityConstants.isDarkMode(context);
    final timelineController = ActivityTimelineController(
      allUsers: _allUsers,
      allPlaces: _allPlaces,
      allEvents: _allEvents,
      activityAssignments: _activityAssignments,
      allActivities: _bundle?.activities ?? [],
      userAssignedHours: _userAssignedHours,
      userFilter: _userFilter,
      placeFilter: _placeFilter,
      eventFilter: _eventFilter,
      onUserFilterChanged: (v) => setState(() => _userFilter = v),
      onPlaceFilterChanged: (v) => setState(() => _placeFilter = v),
      onEventFilterChanged: (v) => setState(() => _eventFilter = v),
      onUserDragStarted: _handleUserDragStarted,
      onUserDragEnd: _handleUserDragEnd,
      onCopyAssignments: _copyAssignmentsToNewUser,
      onDeleteAssignments: _deleteAssignments,
      onRemoveLinkFromAssignment: _removeLinkFromAssignment,
      hideAssignmentDetailOverlay: _hideAssignmentDetailOverlay,
      isDark: isDarkTheme,
    );
    Widget mainContent;
    if (_isTimelineFullscreen) {
      mainContent = Column(
        children: [
          Expanded(child: _buildTimelineArea()),
        ],
      );
    } else {
      mainContent = MultiSplitView(
        controller: _mainController,
        axis: Axis.vertical,
        pushDividers: true,
        builder: (context, area) {
          if (area.data == 'top') {
            return MultiSplitView(
                controller: _topController,
                axis: Axis.horizontal,
                pushDividers: true,
                builder: (context, subArea) {
                  switch (subArea.data) {
                    case 'users':
                      return UsersPanel(controller: timelineController);
                    case 'places':
                      return PlacesPanel(controller: timelineController);
                    case 'events':
                      return EventsPanel(controller: timelineController);
                    default:
                      return const SizedBox();
                  }
                });
          } else {
            return _buildTimelineArea();
          }
        },
      );
    }
    return SafeArea(
      child: Focus(
        autofocus: true,
        onKeyEvent: (_, KeyEvent event) => _handleKeyEvent(event),
        child: MultiSplitViewTheme(
          data: MultiSplitViewThemeData(
              dividerThickness: _isTimelineFullscreen ? 0 : 8,
              dividerPainter: _isTimelineFullscreen
                  ? null
                  : DividerPainters.background(
                      color: isDarkTheme ? Colors.black54 : Colors.black12,
                      highlightedColor:
                          isDarkTheme ? Colors.black87 : Colors.black38)),
          child: mainContent,
        ),
      ),
    );
  }

  Widget _buildTimelineArea() {
    final isDark = ActivityConstants.isDarkMode(context);
    return LayoutBuilder(builder: (ctx, constraints) {
      if (_currentViewportWidth != constraints.maxWidth &&
          constraints.maxWidth > 0) {
        Future.microtask(() {
          if (mounted) {
            final oldWidth = _currentViewportWidth;
            _currentViewportWidth = constraints.maxWidth;
            if (oldWidth == 0 &&
                _panOffset == ActivityConstants.kInitialPanOffset) {
              _performInitialTimelineScroll();
            }
          }
        });
      }
      final vpWidth = _currentViewportWidth;
      if (vpWidth <= 0) return const SizedBox.shrink();
      final totalSec = _timelineStart != null && _timelineEnd != null
          ? _timelineEnd!.difference(_timelineStart!).inSeconds.toDouble()
          : 0.0;
      final pps = _basePps * _scale;
      final timelineWidth = totalSec * pps;
      final bool isScrollable =
          timelineWidth > (vpWidth - ActivityConstants.kTimelineLabelWidth);

      // Logic to determine button state and tooltip message
      final bool canPublish =
          (_historyHelper.changesCount > 0 || _isAutosaveLoaded) &&
              !_isPublishing;
      String publishTooltip;
      if (_isPublishing) {
        publishTooltip = ActivitiesComponentStrings.textPublishing;
      } else if (canPublish) {
        publishTooltip = ActivitiesComponentStrings.tooltipClickToPublish;
      } else {
        publishTooltip = ActivitiesComponentStrings.textEverythingIsPublished;
      }

      return GestureDetector(
        onTap: _hideAssignmentDetailOverlay,
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (d) {
          _gestureDragStartX = d.globalPosition.dx;
          _gesturePanOffsetStart = _currentPanOffsetNotifier.value;
          _hideAssignmentDetailOverlay();
          _animationController.stop();
        },
        onHorizontalDragUpdate: (d) {
          final dx = d.globalPosition.dx - _gestureDragStartX;
          double newPanOffsetValue = (_gesturePanOffsetStart + dx).clamp(
              (vpWidth -
                      (ActivityConstants.kTimelineLabelWidth + timelineWidth))
                  .clamp(double.negativeInfinity, 0.0),
              0.0);
          _currentPanOffsetNotifier.value = newPanOffsetValue;
        },
        onHorizontalDragEnd: (d) {
          if (d.primaryVelocity != null && d.primaryVelocity!.abs() > 100) {
            final double start = _currentPanOffsetNotifier.value;
            final double end = (start + d.primaryVelocity! * 0.1).clamp(
                (vpWidth -
                        (ActivityConstants.kTimelineLabelWidth + timelineWidth))
                    .clamp(double.negativeInfinity, 0.0),
                0.0);
            _animationX = Tween<double>(begin: start, end: end).animate(
                CurvedAnimation(
                    parent: _animationController, curve: Curves.easeOutQuad));
            _animationController.reset();
            _animationController.forward();
          }
          _panOffset = _currentPanOffsetNotifier.value;
        },
        child: Listener(
          onPointerSignal: (pointerSignal) {
            if (pointerSignal is PointerScrollEvent) {
              final bool canZoom = HardwareKeyboard.instance.isControlPressed ||
                  HardwareKeyboard.instance.isMetaPressed;
              if (canZoom) {
                _hideAssignmentDetailOverlay();
                if (pointerSignal.scrollDelta.dy < 0) {
                  _zoomIn(vpWidth, totalSec);
                } else if (pointerSignal.scrollDelta.dy > 0) {
                  _zoomOut(vpWidth, totalSec);
                }
              } else {
                _animationController.stop();
                double newPanOffsetValue = (_currentPanOffsetNotifier.value -
                        pointerSignal.scrollDelta.dx)
                    .clamp(
                        (vpWidth -
                                (ActivityConstants.kTimelineLabelWidth +
                                    timelineWidth))
                            .clamp(double.negativeInfinity, 0.0),
                        0.0);
                _currentPanOffsetNotifier.value = newPanOffsetValue;
                _panOffset = newPanOffsetValue;
              }
            }
          },
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.only(
                  left: 16.0, right: 16.0, top: 8.0, bottom: 4.0),
              child: Row(
                children: [
                  if (!_isTimelineFullscreen)
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      color: isDark ? Colors.white70 : Colors.black54,
                      iconSize: 20,
                      padding: EdgeInsets.zero,
                      constraints: BoxConstraints(minWidth: 36, minHeight: 36),
                      tooltip: ActivitiesComponentStrings.tooltipAddNewActivity,
                      onPressed: _onAddNewActivity,
                    ),
                  if (!_isTimelineFullscreen) const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                        ActivitiesComponentStrings.titleActivitiesTimeline,
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: isDark ? Colors.white : Colors.black87)),
                  ),
                  AnimatedOpacity(
                    opacity: _justAutosaved ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 500),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      child: Row(
                        children: [
                          Icon(Icons.check_circle_outline,
                              size: 12, color: Colors.green),
                          SizedBox(width: 6),
                          Text(ActivitiesComponentStrings.textAutosaved,
                              style: TextStyle(
                                  fontSize: 11,
                                  fontStyle: FontStyle.italic,
                                  color:
                                      isDark ? Colors.white54 : Colors.black54))
                        ],
                      ),
                    ),
                  ),
                  if (!_isTimelineFullscreen)
                    Tooltip(
                      message: publishTooltip,
                      child: ElevatedButton.icon(
                        icon: _isPublishing
                            ? SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color:
                                        isDark ? Colors.black : Colors.white))
                            : Icon(Icons.publish_outlined, size: 14),
                        label: Text(ActivitiesComponentStrings.buttonPublish,
                            style: TextStyle(fontSize: 11)),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Theme.of(context).primaryColor,
                            foregroundColor:
                                ActivityConstants.isDarkMode(context)
                                    ? Colors.black
                                    : Colors.white,
                            padding: EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            minimumSize: Size(60, 30)),
                        onPressed: canPublish
                            ? () async {
                                if (_isPublishing) return;
                                setState(() => _isPublishing = true);
                                // Cancel any pending autosave operation to prevent race conditions.
                                _autosaveDebounce?.cancel();

                                if (!await confirmHtmlUploadRetry(
                                        context, _htmlSave.media,
                                        html: _bundle?.activities
                                                ?.map((activity) =>
                                                    activity.description ?? '')
                                                .join() ??
                                            '') ||
                                    !mounted) {
                                  if (mounted)
                                    setState(() => _isPublishing = false);
                                  return;
                                }
                                setState(() => _isPublishing = true);
                                await _autosaving;
                                if (!mounted) {
                                  return;
                                }
                                _bundle!.activities ??= [];
                                for (var activityInBundle
                                    in _bundle!.activities!) {
                                  List<ActivityAssignmentModel>?
                                      assignmentsForThisActivity =
                                      _activityAssignments[activityInBundle];
                                  if (assignmentsForThisActivity != null) {
                                    activityInBundle.assignments =
                                        assignmentsForThisActivity
                                            .where((assign) =>
                                                assign.data?['isDragPreview'] !=
                                                true)
                                            .toList();
                                  } else {
                                    activityInBundle.assignments = [];
                                  }
                                }
                                try {
                                  final generation = _editorGeneration;
                                  final actor = RightsService.currentUser()?.id;
                                  final snapshot = await _prepareActivityHtml();
                                  if (!mounted ||
                                      generation != _editorGeneration ||
                                      actor !=
                                          RightsService.currentUser()?.id) {
                                    return;
                                  }
                                  final result =
                                      await DbActivities.saveActivitiesForEdit(
                                          context, widget.occasionId, snapshot);
                                  if (!mounted ||
                                      generation != _editorGeneration ||
                                      actor !=
                                          RightsService.currentUser()?.id) {
                                    return;
                                  }
                                  _bundle!.aggregateVersion = result.version;
                                  _bundle!.parentHistoryId = result.historyId;
                                  _bundle!.id = null;
                                  _htmlSave.markSaved();
                                  _isAutosaveLoaded = false;
                                  await _loadData(
                                      initialPanOffset: _panOffset,
                                      initialScale: _scale);
                                } catch (e) {
                                  AppLogger.error(
                                      "Error publishing activities from UI: $e");
                                } finally {
                                  if (mounted) {
                                    setState(() => _isPublishing = false);
                                  }
                                }
                              }
                            : null,
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: _globalFilterController,
                    style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white : Colors.black),
                    decoration: InputDecoration(
                      hintText: ActivitiesComponentStrings.hintGlobalFilter,
                      hintStyle: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white54 : Colors.black54),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          vertical: 6.0, horizontal: 8.0),
                      prefixIcon: Icon(Icons.search,
                          size: 14,
                          color: isDark ? Colors.white54 : Colors.black54),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                            color: isDark
                                ? Colors.grey.shade700
                                : Colors.grey.shade400,
                            width: 0.5),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                            color: isDark
                                ? Colors.grey.shade700
                                : Colors.grey.shade400,
                            width: 0.5),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                            color: Theme.of(context).primaryColor, width: 1),
                      ),
                      suffixIcon: _globalTimelineFilter.isNotEmpty
                          ? IconButton(
                              icon: Icon(Icons.clear,
                                  size: 14,
                                  color:
                                      isDark ? Colors.white54 : Colors.black54),
                              padding: EdgeInsets.zero,
                              constraints: BoxConstraints(),
                              onPressed: () {
                                _globalFilterController.clear();
                              },
                            )
                          : null,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton(
                  icon: Icon(_isTimelineFullscreen
                      ? Icons.fullscreen_exit
                      : Icons.fullscreen),
                  iconSize: 20,
                  splashRadius: 20,
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints(minWidth: 36, minHeight: 36),
                  tooltip: _isTimelineFullscreen
                      ? ActivitiesComponentStrings.tooltipExitFullscreen
                      : ActivitiesComponentStrings.tooltipEnterFullscreen,
                  color: isDark ? Colors.white70 : Colors.black54,
                  onPressed: () {
                    setState(() {
                      _isTimelineFullscreen = !_isTimelineFullscreen;
                      if (!_isTimelineFullscreen &&
                          _mainController.areas.first.size != 160) {
                        _mainController.areas.first.size = 160;
                      }
                    });
                  },
                ),
                IconButton(
                    icon: const Icon(Icons.history),
                    tooltip: ActivitiesComponentStrings.tooltipVersionHistory,
                    splashRadius: 20,
                    iconSize: 20,
                    padding: EdgeInsets.zero,
                    constraints: BoxConstraints(minWidth: 36, minHeight: 36),
                    onPressed: _showHistoryDialog,
                    color: isDark ? Colors.white70 : Colors.black54),
                IconButton(
                    icon: const Icon(Icons.undo),
                    tooltip: ActivitiesComponentStrings.tooltipUndo,
                    splashRadius: 20,
                    iconSize: 20,
                    padding: EdgeInsets.zero,
                    constraints: BoxConstraints(minWidth: 36, minHeight: 36),
                    onPressed: _historyHelper.canUndo ? _undo : null,
                    color: isDark ? Colors.white70 : Colors.black54),
                IconButton(
                    icon: const Icon(Icons.redo),
                    tooltip: ActivitiesComponentStrings.tooltipRedo,
                    splashRadius: 20,
                    iconSize: 20,
                    padding: EdgeInsets.zero,
                    constraints: BoxConstraints(minWidth: 36, minHeight: 36),
                    onPressed: _historyHelper.canRedo ? _redo : null,
                    color: isDark ? Colors.white70 : Colors.black54),
                IconButton(
                    icon: const Icon(Icons.zoom_in),
                    tooltip: ActivitiesComponentStrings.tooltipZoomIn,
                    splashRadius: 20,
                    iconSize: 20,
                    padding: EdgeInsets.zero,
                    constraints: BoxConstraints(minWidth: 36, minHeight: 36),
                    onPressed: () => _zoomIn(vpWidth, totalSec),
                    color: isDark ? Colors.white70 : Colors.black54),
                IconButton(
                    icon: const Icon(Icons.zoom_out),
                    tooltip: ActivitiesComponentStrings.tooltipZoomOut,
                    splashRadius: 20,
                    iconSize: 20,
                    padding: EdgeInsets.zero,
                    constraints: BoxConstraints(minWidth: 36, minHeight: 36),
                    onPressed: () => _zoomOut(vpWidth, totalSec),
                    color: isDark ? Colors.white70 : Colors.black54),
              ]),
            ),
            ValueListenableBuilder<double>(
                valueListenable: _currentPanOffsetNotifier,
                builder: (context, currentPanOffsetValue, child) {
                  return SizedBox(
                    height: ActivityConstants.kTotalTimelineRulerHeightConstant,
                    child: Row(children: [
                      SizedBox(width: ActivityConstants.kTimelineLabelWidth),
                      Expanded(
                        child: ClipRect(
                          child: Transform.translate(
                            offset: Offset(currentPanOffsetValue, 0),
                            child: RepaintBoundary(
                              child: CustomPaint(
                                size: Size(
                                    timelineWidth,
                                    ActivityConstants
                                        .kTotalTimelineRulerHeightConstant),
                                painter: TimelinePainter(
                                  start: _timelineStart!,
                                  end: _timelineEnd!,
                                  pps: pps,
                                  isDarkMode: isDark,
                                  weekdays: ActivitiesComponentStrings
                                      .getWeekdayAbbreviations(
                                          context.locale.languageCode),
                                  monthAbbreviations: ActivitiesComponentStrings
                                      .getMonthAbbreviations(
                                          context.locale.languageCode),
                                  dateHeaderHeight: ActivityConstants
                                      .kDateHeaderHeightConstant,
                                  timeTickAreaHeight: ActivityConstants
                                      .kTimeTickAreaHeightConstant,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ]),
                  );
                }),
            Expanded(
              child: Container(
                color: isDark ? Colors.grey[900] : Colors.white,
                child: _filteredActivities.isEmpty &&
                        _globalTimelineFilter.isNotEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Text(
                            ActivitiesComponentStrings.textNoFilterMatch,
                            style: TextStyle(
                                color: isDark
                                    ? Colors.grey[400]
                                    : Colors.grey[600],
                                fontSize: 14),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : (_bundle!.activities?.isEmpty ?? true)
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Text(
                                ActivitiesComponentStrings
                                        .textNoActivitiesAvailable +
                                    (!_isTimelineFullscreen
                                        ? " ${ActivitiesComponentStrings.textClickPlusToAddOne}"
                                        : ""),
                                style: TextStyle(
                                    color: isDark
                                        ? Colors.grey[400]
                                        : Colors.grey[600],
                                    fontSize: 14),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          )
                        : ReorderableListView.builder(
                            physics: _isModifierKeyPressedForScroll
                                ? NeverScrollableScrollPhysics()
                                : null,
                            buildDefaultDragHandles: false,
                            itemCount: _filteredActivities.length,
                            onReorderStart: (_) =>
                                _hideAssignmentDetailOverlay(),
                            onReorder: (oldI, newI) {
                              _hideAssignmentDetailOverlay();
                              setState(() {
                                final itemToMove = _filteredActivities[oldI];
                                final originalList = _bundle!.activities!;
                                int originalIndexOld =
                                    originalList.indexOf(itemToMove);
                                if (originalIndexOld == -1) return;
                                int targetOriginalIndexInAllActivities;
                                if (newI >= _filteredActivities.length) {
                                  if (_filteredActivities.isNotEmpty) {
                                    final lastFilteredItem =
                                        _filteredActivities.last;
                                    targetOriginalIndexInAllActivities =
                                        originalList.indexOf(lastFilteredItem) +
                                            1;
                                  } else {
                                    targetOriginalIndexInAllActivities =
                                        originalList.length;
                                  }
                                } else {
                                  if (newI > oldI) newI--;
                                  final itemAtNewFilteredPosition =
                                      _filteredActivities[newI];
                                  targetOriginalIndexInAllActivities =
                                      originalList
                                          .indexOf(itemAtNewFilteredPosition);
                                }
                                final item =
                                    originalList.removeAt(originalIndexOld);
                                if (targetOriginalIndexInAllActivities >
                                    originalList.length) {
                                  targetOriginalIndexInAllActivities =
                                      originalList.length;
                                }
                                originalList.insert(
                                    targetOriginalIndexInAllActivities, item);
                                for (var i = 0; i < originalList.length; i++) {
                                  originalList[i].order = i;
                                }
                                _updateFilteredActivities();
                                _recordStateChange();
                              });
                            },
                            itemBuilder: (context, index) =>
                                _buildActivityWithAssignments(
                                    _filteredActivities[index],
                                    timelineWidth,
                                    vpWidth,
                                    index),
                          ),
              ),
            ),
            if (isScrollable)
              Container(
                height: 10,
                margin: EdgeInsets.only(
                    left: ActivityConstants.kTimelineLabelWidth + 2,
                    right: 2,
                    top: 4,
                    bottom: 2),
                child: LayoutBuilder(
                  builder: (context, scrollbarConstraints) {
                    final double trackWidth = scrollbarConstraints.maxWidth;
                    final double visibleContentWidth =
                        vpWidth - ActivityConstants.kTimelineLabelWidth;
                    final double contentRatio = timelineWidth > 0
                        ? visibleContentWidth / timelineWidth
                        : 1.0;
                    final double thumbWidth =
                        (trackWidth * contentRatio).clamp(20.0, trackWidth);
                    final double maxScrollableTrackWidth =
                        trackWidth - thumbWidth;
                    final double maxTimelineScrollOffset =
                        timelineWidth - visibleContentWidth;
                    return ValueListenableBuilder<double>(
                      valueListenable: _currentPanOffsetNotifier,
                      builder: (context, currentPanOffsetValue,
                          gestureDetectorChild) {
                        final double currentTimelineScrollOffset =
                            -currentPanOffsetValue;
                        final double thumbPosition =
                            maxScrollableTrackWidth > 0 &&
                                    maxTimelineScrollOffset > 0
                                ? (currentTimelineScrollOffset /
                                        maxTimelineScrollOffset) *
                                    maxScrollableTrackWidth
                                : 0.0;
                        return Container(
                          width: trackWidth,
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.grey.shade700.withOpacity(0.7)
                                : Colors.grey.shade300.withOpacity(0.7),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Stack(
                            children: [
                              Positioned(
                                left: (thumbPosition.isNaN ||
                                            thumbPosition.isInfinite
                                        ? 0
                                        : thumbPosition)
                                    .clamp(0.0, maxScrollableTrackWidth)
                                    .toDouble(),
                                top: 0,
                                bottom: 0,
                                width:
                                    (thumbWidth.isNaN || thumbWidth.isInfinite
                                            ? trackWidth
                                            : thumbWidth)
                                        .clamp(0.0, trackWidth),
                                child: gestureDetectorChild!,
                              ),
                            ],
                          ),
                        );
                      },
                      child: GestureDetector(
                        onHorizontalDragStart: (details) {
                          _scrollbarGestureDragStartX =
                              details.globalPosition.dx;
                          _scrollbarGesturePanOffsetStartValue =
                              _currentPanOffsetNotifier.value;
                        },
                        onHorizontalDragUpdate: (details) {
                          if (maxScrollableTrackWidth <= 0 ||
                              maxTimelineScrollOffset <= 0) {
                            return;
                          }
                          double dragDeltaX = details.globalPosition.dx -
                              _scrollbarGestureDragStartX;
                          double contentPanDelta =
                              (dragDeltaX / maxScrollableTrackWidth) *
                                  maxTimelineScrollOffset;
                          double newPanOffsetValue =
                              (_scrollbarGesturePanOffsetStartValue -
                                      contentPanDelta)
                                  .clamp(
                                      (vpWidth -
                                              (ActivityConstants
                                                      .kTimelineLabelWidth +
                                                  timelineWidth))
                                          .clamp(double.negativeInfinity, 0.0),
                                      0.0);
                          _currentPanOffsetNotifier.value = newPanOffsetValue;
                        },
                        onHorizontalDragEnd: (details) {
                          if (_panOffset != _currentPanOffsetNotifier.value) {
                            setState(() {
                              _panOffset = _currentPanOffsetNotifier.value;
                            });
                          }
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.grey.shade500
                                : Colors.grey.shade500,
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ]),
        ),
      );
    });
  }

  Widget _buildActivityWithAssignments(ActivityModel a, double timelineWidth,
      double viewportWidth, int itemIndexInFilteredList) {
    final allAssignmentsForActivity = _activityAssignments[a] ?? [];
    final validAssignments = allAssignmentsForActivity
        .where((assign) =>
            assign.userInfo != null &&
            assign.user != null &&
            assign.data?['isDragPreview'] != true)
        .toList();
    final isDark = ActivityConstants.isDarkMode(context);
    final String normalizedFilter =
        Utilities.removeDiacritics(_globalTimelineFilter.toLowerCase());
    bool activityTitleMatchesFilter = _globalTimelineFilter.isEmpty ||
        Utilities.removeDiacritics(a.title?.toLowerCase() ?? "")
            .contains(normalizedFilter);
    Map<String?, List<ActivityAssignmentModel>> assignmentsByUser =
        groupBy<ActivityAssignmentModel, String?>(
            validAssignments, (assignment) => assignment.userInfo);
    List<String?> sortedUserInfos = assignmentsByUser.keys.toList();
    sortedUserInfos.sort((userInfoA, userInfoB) {
      if (userInfoA == null || userInfoB == null) return 0;
      final assignmentsA = assignmentsByUser[userInfoA] ?? [];
      final assignmentsB = assignmentsByUser[userInfoB] ?? [];
      bool hasPlaceA = assignmentsA.any((assign) => (assign.places).isNotEmpty);
      bool hasPlaceB = assignmentsB.any((assign) => (assign.places).isNotEmpty);
      if (hasPlaceA && !hasPlaceB) return -1;
      if (!hasPlaceA && hasPlaceB) return 1;
      bool hasEventA = assignmentsA.any((assign) => (assign.events).isNotEmpty);
      bool hasEventB = assignmentsB.any((assign) => (assign.events).isNotEmpty);
      if (hasEventA && !hasEventB) return -1;
      if (!hasEventA && hasEventB) return 1;
      final userA =
          assignmentsA.firstOrNull?.user?.toFullNameString().toLowerCase() ??
              userInfoA.toLowerCase();
      final userB =
          assignmentsB.firstOrNull?.user?.toFullNameString().toLowerCase() ??
              userInfoB.toLowerCase();
      return userA.compareTo(userB);
    });
    List<Widget> userRowsAndPreviews = [];
    Set<String?> usersWithRenderedRows = {};
    for (var userInfoId in sortedUserInfos) {
      if (userInfoId == null) continue;
      final userAssignmentsList = assignmentsByUser[userInfoId]!;
      List<ActivityAssignmentModel>? assignmentsToConsiderForRendering;
      if (_globalTimelineFilter.isEmpty) {
        assignmentsToConsiderForRendering = List.from(userAssignmentsList);
      } else {
        if (activityTitleMatchesFilter) {
          assignmentsToConsiderForRendering = List.from(userAssignmentsList);
        } else {
          List<ActivityAssignmentModel> filteredUserAssignmentsByName =
              userAssignmentsList.where((assign) {
            if (Utilities.removeDiacritics(
                    assign.user!.toFullNameString().toLowerCase())
                .contains(normalizedFilter)) {
              return true;
            }
            for (var place in assign.places) {
              if (Utilities.removeDiacritics(place.title?.toLowerCase() ?? "")
                  .contains(normalizedFilter)) {
                return true;
              }
            }
            for (var event in assign.events) {
              if (Utilities.removeDiacritics(event.title?.toLowerCase() ?? "")
                  .contains(normalizedFilter)) {
                return true;
              }
            }
            return false;
          }).toList();
          if (filteredUserAssignmentsByName.isNotEmpty) {
            assignmentsToConsiderForRendering = filteredUserAssignmentsByName;
          }
        }
      }
      if (assignmentsToConsiderForRendering != null &&
          assignmentsToConsiderForRendering.isNotEmpty) {
        List<ActivityAssignmentModel> assignmentsToRender =
            List.from(assignmentsToConsiderForRendering);
        final userForThisRow = assignmentsToRender[0].user;
        if (userForThisRow == null) continue;
        if (_hoveredActivityForPreview == a &&
            _currentlyDraggedUser?.id == userInfoId &&
            _previewStartTime != null) {
          final draggedDuration = _getSnappedDragDuration();
          final DateTimeRange pr = TimeClampingService.clampDateTimeRange(
              initialStartTime: _previewStartTime!,
              itemDuration: draggedDuration,
              timelineStart: _timelineStart!,
              timelineEnd: _timelineEnd!,
              minAllowedDuration: ActivityConstants.kMinTimeLength);
          assignmentsToRender.add(ActivityAssignmentModel(
              activityId: a.id,
              user: _currentlyDraggedUser,
              userInfo: _currentlyDraggedUser!.id,
              startTime: pr.start,
              endTime: pr.end,
              data: {'isDragPreview': true},
              places: [],
              events: []));
          assignmentsToRender
              .sort((a1, b1) => a1.startTime!.compareTo(b1.startTime!));
        }
        userRowsAndPreviews.add(_buildUserRow(
            a, userForThisRow, assignmentsToRender, timelineWidth));
        usersWithRenderedRows.add(userInfoId);
      }
    }
    if (_hoveredActivityForPreview == a &&
        _currentlyDraggedUser != null &&
        _previewStartTime != null &&
        !usersWithRenderedRows.contains(_currentlyDraggedUser!.id)) {
      bool showDraggedUserPreviewForThisActivity = false;
      if (_globalTimelineFilter.isEmpty) {
        showDraggedUserPreviewForThisActivity = true;
      } else {
        if (activityTitleMatchesFilter) {
          showDraggedUserPreviewForThisActivity = true;
        } else {
          if (Utilities.removeDiacritics(
                  _currentlyDraggedUser!.toFullNameString().toLowerCase())
              .contains(normalizedFilter)) {
            showDraggedUserPreviewForThisActivity = true;
          }
        }
      }
      if (showDraggedUserPreviewForThisActivity) {
        final draggedDuration = _getSnappedDragDuration();
        final DateTimeRange pr = TimeClampingService.clampDateTimeRange(
            initialStartTime: _previewStartTime!,
            itemDuration: draggedDuration,
            timelineStart: _timelineStart!,
            timelineEnd: _timelineEnd!,
            minAllowedDuration: ActivityConstants.kMinTimeLength);
        userRowsAndPreviews.add(_buildUserRow(
            a,
            _currentlyDraggedUser!,
            [
              ActivityAssignmentModel(
                  activityId: a.id,
                  user: _currentlyDraggedUser,
                  userInfo: _currentlyDraggedUser!.id!,
                  startTime: pr.start,
                  endTime: pr.end,
                  data: {'isDragPreview': true},
                  places: [],
                  events: [])
            ],
            timelineWidth));
      }
    }
    if (_globalTimelineFilter.isNotEmpty &&
        !activityTitleMatchesFilter &&
        userRowsAndPreviews.isEmpty) {
      return SizedBox.shrink(key: ObjectKey(a));
    }
    final int displayIndex = _filteredActivities.indexOf(a);
    return Padding(
      key: ObjectKey(a),
      padding: const EdgeInsets.symmetric(vertical: 0),
      child: DragTarget<ActivityUserInfoModel>(
        onWillAcceptWithDetails: (details) {
          _hideAssignmentDetailOverlay();
          if (a.isHidden!) return false;
          if (_timelineStart != null && _timelineEnd != null) {
            bool needsStateUpdate = false;
            DateTime snappedStartTime =
                _calculateSnappedTimeFromOffset(details.offset, timelineWidth);
            final Duration dynamicDuration = _getSnappedDragDuration();
            final DateTimeRange clampedRange =
                TimeClampingService.clampDateTimeRange(
                    initialStartTime: snappedStartTime,
                    itemDuration: dynamicDuration,
                    timelineStart: _timelineStart!,
                    timelineEnd: _timelineEnd!,
                    minAllowedDuration: ActivityConstants.kMinTimeLength);
            if (_hoveredActivityForPreview != a) {
              _hoveredActivityForPreview = a;
              needsStateUpdate = true;
            }
            if (_previewStartTime != clampedRange.start) {
              _previewStartTime = clampedRange.start;
              needsStateUpdate = true;
            }
            if (needsStateUpdate) setState(() {});
            return true;
          }
          if (_hoveredActivityForPreview == a) {
            setState(() {
              _hoveredActivityForPreview = null;
              _previewStartTime = null;
            });
          }
          return false;
        },
        onMove: (details) {
          if (a.isHidden!) return;
          if (_hoveredActivityForPreview == a &&
              _timelineStart != null &&
              _timelineEnd != null) {
            DateTime snappedStartTime =
                _calculateSnappedTimeFromOffset(details.offset, timelineWidth);
            final Duration dynamicDuration = _getSnappedDragDuration();
            final DateTimeRange clampedRange =
                TimeClampingService.clampDateTimeRange(
                    initialStartTime: snappedStartTime,
                    itemDuration: dynamicDuration,
                    timelineStart: _timelineStart!,
                    timelineEnd: _timelineEnd!,
                    minAllowedDuration: ActivityConstants.kMinTimeLength);
            if (_previewStartTime != clampedRange.start) {
              setState(() => _previewStartTime = clampedRange.start);
            }
          }
        },
        onLeave: (data) {
          if (_hoveredActivityForPreview == a) {
            setState(() {
              _hoveredActivityForPreview = null;
              _previewStartTime = null;
            });
          }
        },
        onAcceptWithDetails: (details) {
          if (_timelineStart == null || _timelineEnd == null || a.isHidden!) {
            return;
          }
          final draggedDataOnDrop = details.data;
          DateTime finalSnappedStartTime =
              _calculateSnappedTimeFromOffset(details.offset, timelineWidth);
          final Duration dynamicDuration = _getSnappedDragDuration();
          final DateTimeRange finalClampedRange =
              TimeClampingService.clampDateTimeRange(
                  initialStartTime: finalSnappedStartTime,
                  itemDuration: dynamicDuration,
                  timelineStart: _timelineStart!,
                  timelineEnd: _timelineEnd!,
                  minAllowedDuration: ActivityConstants.kMinTimeLength);
          final newAssignment = ActivityAssignmentModel(
              activityId: a.id,
              userInfo: draggedDataOnDrop.id!,
              user: draggedDataOnDrop,
              startTime: finalClampedRange.start,
              endTime: finalClampedRange.end,
              data: null,
              places: [],
              events: []);
          setState(() {
            _activityAssignments.putIfAbsent(a, () => []).add(newAssignment);
            _hoveredActivityForPreview = null;
            _previewStartTime = null;
            _recalculateUserAssignedHours();
            _recordStateChange();
          });
        },
        builder: (ctx, candidateData, rejectedData) {
          bool isHighlighted = candidateData.isNotEmpty &&
              _hoveredActivityForPreview == a &&
              !a.isHidden!;
          Color activityHeaderBgColor;
          Color activityHeaderTextColor;
          Color activityContentBgColor;
          if (isDark) {
            activityHeaderBgColor = a.isHidden!
                ? Colors.grey.shade700.withOpacity(0.7)
                : Colors.blueGrey.shade800.withOpacity(0.7);
            activityHeaderTextColor =
                a.isHidden! ? Colors.white60 : Colors.white;
            activityContentBgColor = isHighlighted
                ? Theme.of(context).primaryColor.withAlpha(30)
                : Colors.transparent;
          } else {
            activityHeaderBgColor = a.isHidden!
                ? Colors.grey.shade400.withOpacity(0.7)
                : Colors.blueGrey.shade50.withOpacity(0.7);
            activityHeaderTextColor =
                a.isHidden! ? Colors.white70 : Colors.black87;
            activityContentBgColor = isHighlighted
                ? Colors.lightBlue.shade50.withOpacity(0.6)
                : Colors.transparent;
          }
          List<Widget> activityContentChildren = [];
          if (!a.isHidden!) {
            if (userRowsAndPreviews.isNotEmpty) {
              activityContentChildren.addAll(userRowsAndPreviews);
            } else if ((_activityAssignments[a] == null ||
                    _activityAssignments[a]!.isEmpty) &&
                _globalTimelineFilter.isEmpty) {
              activityContentChildren.add(Padding(
                padding: EdgeInsets.only(
                    left: ActivityConstants.kTimelineLabelWidth + 8.0,
                    top: 8.0,
                    bottom: 8.0,
                    right: 8.0),
                child: Text(
                  ActivitiesComponentStrings.textDragUsersFromTopDropHere,
                  style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                      fontStyle: FontStyle.italic),
                ),
              ));
            } else if (userRowsAndPreviews.isEmpty &&
                _globalTimelineFilter.isNotEmpty &&
                activityTitleMatchesFilter) {
              activityContentChildren.add(Padding(
                padding: const EdgeInsets.only(
                    left: ActivityConstants.kTimelineLabelWidth + 8.0,
                    top: 4,
                    bottom: 4),
                child: Text(ActivitiesComponentStrings.textNoUsersAssignedYet,
                    style: TextStyle(
                        fontSize: 10,
                        color: (isDark ? Colors.grey[500] : Colors.grey[600]),
                        fontStyle: FontStyle.italic)),
              ));
            }
          } else {
            activityContentChildren.add(Padding(
              padding: const EdgeInsets.only(
                  left: ActivityConstants.kTimelineLabelWidth + 8.0,
                  top: 6,
                  bottom: 6),
              child: Text(ActivitiesComponentStrings.textActivityHidden,
                  style: TextStyle(
                      fontSize: 10,
                      color: (isDark ? Colors.grey[400] : Colors.grey[700]),
                      fontStyle: FontStyle.italic)),
            ));
          }
          return Container(
            decoration: BoxDecoration(
              color: activityContentBgColor,
              border: Border(
                  bottom: BorderSide(
                      color:
                          isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                      width: 0.8)),
            ),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                color: activityHeaderBgColor,
                child: Row(children: [
                  ReorderableDragStartListener(
                      index: displayIndex,
                      child: SizedBox(
                          width: ActivityConstants.kTimelineLabelWidth,
                          height: 24,
                          child: Row(children: [
                            IconButton(
                              icon: Icon(
                                  a.isHidden!
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  size: 13,
                                  color:
                                      activityHeaderTextColor.withOpacity(0.8)),
                              padding: EdgeInsets.zero,
                              constraints:
                                  BoxConstraints(minWidth: 22, minHeight: 22),
                              splashRadius: 12,
                              tooltip: a.isHidden!
                                  ? ActivitiesComponentStrings
                                      .tooltipMarkVisible
                                  : ActivitiesComponentStrings
                                      .tooltipMarkHidden,
                              onPressed: () {
                                setState(() {
                                  a.isHidden = !a.isHidden!;
                                  _recordStateChange();
                                });
                              },
                            ),
                            Expanded(
                                child: Padding(
                                    padding: const EdgeInsets.only(left: 1.0),
                                    child: Text(
                                        a.title ??
                                            ActivitiesComponentStrings
                                                .textUntitledActivity,
                                        style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: activityHeaderTextColor),
                                        overflow: TextOverflow.ellipsis))),
                            PopupMenuButton<String>(
                              icon: Icon(Icons.more_vert,
                                  size: 15,
                                  color:
                                      activityHeaderTextColor.withOpacity(0.8)),
                              tooltip: ActivitiesComponentStrings
                                  .tooltipActivityOptions,
                              color: isDark ? Colors.grey[800] : Colors.white,
                              splashRadius: 10,
                              padding: EdgeInsets.zero,
                              itemBuilder: (_) => [
                                PopupMenuItem(
                                    value: 'rename',
                                    height: 30,
                                    child: Text(
                                        ActivitiesComponentStrings.menuRename,
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: isDark
                                                ? Colors.white
                                                : Colors.black))),
                                PopupMenuItem(
                                    value: 'details',
                                    height: 30,
                                    child: Text(
                                        ActivitiesComponentStrings.menuDetails,
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: isDark
                                                ? Colors.white
                                                : Colors.black))),
                                PopupMenuItem(
                                    value: 'delete',
                                    height: 30,
                                    child: Text(
                                        ActivitiesComponentStrings.menuDelete,
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: isDark
                                                ? Colors.white
                                                : Colors.black))),
                              ],
                              onSelected: (v) {
                                _hideAssignmentDetailOverlay();
                                if (v == 'delete') {
                                  setState(() {
                                    _bundle!.activities!.remove(a);
                                    _activityAssignments.remove(a);
                                    _selectedActivities.remove(a);
                                    _updateFilteredActivities();
                                    _recalculateUserAssignedHours();
                                    _recordStateChange();
                                  });
                                } else if (v == 'rename') {
                                  _showRenameDialog(a);
                                } else if (v == 'details') {
                                  showDialog(
                                    context: context,
                                    builder: (ctx) => DetailDialog(
                                      title: a.title ??
                                          ActivitiesComponentStrings
                                              .textUntitledActivity,
                                      htmlDescription: a.description,
                                      canEdit: true,
                                      onEditPressed: () =>
                                          _showActivityDescriptionEditor(a),
                                    ),
                                  );
                                }
                              },
                            ),
                          ]))),
                  Expanded(
                      child: ValueListenableBuilder<double>(
                          valueListenable: _currentPanOffsetNotifier,
                          builder: (context, currentPanOffsetValue, child) {
                            return ClipRect(
                                child: Transform.translate(
                                    offset: Offset(currentPanOffsetValue, 0),
                                    child: SizedBox(
                                      height: 24,
                                      child: RepaintBoundary(
                                        child: CustomPaint(
                                          foregroundPainter:
                                              VerticalGridLinesPainter(
                                            start: _timelineStart!,
                                            end: _timelineEnd!,
                                            pps: _basePps * _scale,
                                            viewHeight: 24,
                                            isDarkMode: isDark,
                                          ),
                                          child: const SizedBox
                                              .shrink(), // MODIFICATION: Removed the child container that had its own color. This area is now transparent, allowing the parent's color to show through.
                                        ),
                                      ),
                                    )));
                          })),
                ]),
              ),
              ...activityContentChildren,
            ]),
          );
        },
      ),
    );
  }

  Widget _buildUserRow(ActivityModel activity, ActivityUserInfoModel userInfo,
      List<ActivityAssignmentModel> assignments, double timelineWidth) {
    if (assignments.isEmpty &&
        (_copyDragPreview == null ||
            _copyDragPreview?.userInfo != userInfo.id ||
            _copyDragSource?.activityId != activity.id)) {
      return const SizedBox.shrink();
    }
    final isDark = ActivityConstants.isDarkMode(context);
    final isHostingPreview =
        assignments.any((u) => u.data?['isDragPreview'] == true);
    final color = ActivityConstants.darkUserColors[
        userInfo.hashCode % ActivityConstants.darkUserColors.length];
    final avatarTextColor = Colors.white;
    final List<ActivityAssignmentModel> assignmentsToRender =
        assignments.toList();
    if (_copyDragPreview != null &&
        _copyDragPreview?.userInfo == userInfo.id &&
        _copyDragSource?.activityId == activity.id) {
      assignmentsToRender.add(_copyDragPreview!);
    }

    // --- OPTIMIZATION START ---
    // The expensive part of the row (the timeline with all assignment bars)
    // is built here once and passed as a 'child' to the ValueListenableBuilder.
    // This prevents it from being rebuilt on every pan update. It will only be
    // rebuilt when the underlying data changes (e.g., on zoom, data edit, etc.).
    final Widget timelineContent = SizedBox(
      width: timelineWidth,
      height: 26,
      child: RepaintBoundary(
        child: CustomPaint(
          painter: VerticalGridLinesPainter(
              start: _timelineStart!,
              end: _timelineEnd!,
              pps: _basePps * _scale,
              viewHeight: 26,
              isDarkMode: isDark),
          child: Stack(
            children: assignmentsToRender.map((u) {
              final bool isPreview = u.data?['isDragPreview'] == true;
              Color itemBarColor = isPreview ? color.withOpacity(0.6) : color;
              if (activity.isHidden!) {
                itemBarColor =
                    (isDark ? Colors.grey.shade600 : Colors.grey.shade500)
                        .withOpacity(isPreview ? 0.5 : 0.7);
              }
              final bool isDraggable = !isPreview && !activity.isHidden!;
              Widget timelineRowWidget = TimelineRow(
                key: ValueKey(
                    "assign_${u.id}_${u.startTime?.millisecondsSinceEpoch}_${u.endTime?.millisecondsSinceEpoch}_${u.places.length}_${u.events.length}_${isPreview}_${activity.isHidden!}"),
                start: _timelineStart!,
                end: _timelineEnd!,
                itemStart: u.startTime!,
                itemEnd: u.endTime!,
                barColor: itemBarColor,
                onTapBar: isPreview || activity.isHidden!
                    ? null
                    : (details) =>
                        _showAssignmentDetailOverlay(u, details.globalPosition),
                onDragStart: _hideAssignmentDetailOverlay,
                onDragEnd: isPreview || activity.isHidden!
                    ? (ns, ne) {}
                    : (finalStart, finalEnd) {
                        if (_timelineStart == null || _timelineEnd == null) {
                          return;
                        }
                        final DateTimeRange finalClampedRange =
                            TimeClampingService.clampDateTimeRange(
                                initialStartTime: finalStart,
                                itemDuration: finalEnd.difference(finalStart),
                                timelineStart: _timelineStart!,
                                timelineEnd: _timelineEnd!,
                                minAllowedDuration:
                                    ActivityConstants.kMinTimeLength);
                        if (u.startTime != finalClampedRange.start ||
                            u.endTime != finalClampedRange.end) {
                          setState(() {
                            u.startTime = finalClampedRange.start;
                            u.endTime = finalClampedRange.end;
                            _recalculateUserAssignedHours();
                            _recordStateChange();
                          });
                        }
                      },
                draggable: isDraggable &&
                    !_isModifierKeyPressedForScroll &&
                    _copyDragSource == null,
                zoomScale: _scale,
                onPlaceOrEventDropped: isPreview || activity.isHidden!
                    ? null
                    : (droppedItemData) {
                        _handlePlaceOrEventDropOnAssignment(u, droppedItemData);
                      },
                assignment: u,
                isDarkMode: isDark,
              );
              if (isDraggable) {
                return GestureDetector(
                  onHorizontalDragStart: (details) {
                    if (!_isModifierKeyPressedForScroll) {
                      return;
                    }
                    _hideAssignmentDetailOverlay();
                    _gestureDragStartX = details.globalPosition.dx;
                    setState(() {
                      _copyDragSource = u;
                      _copyDragPreview = ActivityAssignmentModel(
                        activityId: u.activityId,
                        userInfo: u.userInfo,
                        user: u.user,
                        startTime: u.startTime,
                        endTime: u.endTime,
                        places: List.from(u.places),
                        events: List.from(u.events),
                        data: {'isDragPreview': true},
                      );
                    });
                  },
                  onHorizontalDragUpdate: (details) {
                    if (_copyDragSource != u) return;
                    if (!_isModifierKeyPressedForScroll) {
                      setState(() {
                        _copyDragSource = null;
                        _copyDragPreview = null;
                      });
                      return;
                    }
                    final pps = _basePps * _scale;
                    if (pps == 0) return;
                    final double dragDeltaX =
                        details.globalPosition.dx - _gestureDragStartX;
                    final Duration timeDelta =
                        Duration(seconds: (dragDeltaX / pps).round());
                    final DateTime previewStartTime =
                        _copyDragSource!.startTime!.add(timeDelta);
                    final Duration originalDuration = _copyDragSource!.endTime!
                        .difference(_copyDragSource!.startTime!);
                    final Duration snapStep = _scale < 0.5
                        ? ActivityConstants.kSnapStepCoarse
                        : ActivityConstants.kSnapStepFine;
                    DateTime snappedStartTime = previewStartTime;
                    if (snapStep.inSeconds > 0) {
                      final int numSnapSteps = (previewStartTime
                                  .difference(_timelineStart!)
                                  .inSeconds /
                              snapStep.inSeconds)
                          .round();
                      snappedStartTime = _timelineStart!.add(
                          Duration(seconds: numSnapSteps * snapStep.inSeconds));
                    }
                    final clampedRange = TimeClampingService.clampDateTimeRange(
                        initialStartTime: snappedStartTime,
                        itemDuration: originalDuration,
                        timelineStart: _timelineStart!,
                        timelineEnd: _timelineEnd!,
                        minAllowedDuration: ActivityConstants.kMinTimeLength);
                    if (_copyDragPreview?.startTime != clampedRange.start ||
                        _copyDragPreview?.endTime != clampedRange.end) {
                      setState(() {
                        _copyDragPreview = ActivityAssignmentModel(
                            activityId: _copyDragPreview!.activityId,
                            userInfo: _copyDragPreview!.userInfo,
                            user: _copyDragPreview!.user,
                            startTime: clampedRange.start,
                            endTime: clampedRange.end,
                            places: _copyDragPreview!.places,
                            events: _copyDragPreview!.events,
                            data: _copyDragPreview!.data);
                      });
                    }
                  },
                  onHorizontalDragEnd: (details) {
                    if (_copyDragSource != u || _copyDragPreview == null) {
                      return;
                    }

                    final newAssignment = ActivityAssignmentModel(
                      activityId: _copyDragSource!.activityId,
                      userInfo: _copyDragSource!.userInfo,
                      user: _copyDragSource!.user,
                      startTime: _copyDragPreview!.startTime,
                      endTime: _copyDragPreview!.endTime,
                      places: List.from(_copyDragSource!.places),
                      events: List.from(_copyDragSource!.events),
                      data: null,
                    );

                    _activityAssignments
                        .putIfAbsent(activity, () => [])
                        .add(newAssignment);
                    _copyDragSource = null;
                    _copyDragPreview = null;
                    _recalculateUserAssignedHours();

                    _recordStateChange();
                  },
                  onHorizontalDragCancel: () {
                    if (_copyDragSource == u) {
                      setState(() {
                        _copyDragSource = null;
                        _copyDragPreview = null;
                      });
                    }
                  },
                  child: timelineRowWidget,
                );
              }
              return timelineRowWidget;
            }).toList(),
          ),
        ),
      ),
    );
    // --- OPTIMIZATION END ---

    return Container(
        height: 26,
        decoration: BoxDecoration(
            color: isHostingPreview && !activity.isHidden!
                ? color.withOpacity(0.1)
                : Colors.transparent,
            border: Border(
                bottom: BorderSide(
                    color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
                    width: 0.5))),
        child: Row(children: [
          SizedBox(
              width: ActivityConstants.kTimelineLabelWidth,
              child: Row(children: [
                const SizedBox(width: 4),
                Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: color,
                        border: Border.all(
                            color: color.withOpacity(0.7), width: 1.0)),
                    child: Center(
                        child: Text(userInfo.getInitials(),
                            style: TextStyle(
                                fontSize: 9,
                                color: avatarTextColor,
                                fontWeight: FontWeight.bold)))),
                const SizedBox(width: 3),
                Expanded(
                    child: Text(userInfo.toFullNameString(),
                        style: TextStyle(
                            fontSize: 11,
                            color: isDark ? Colors.white70 : Colors.black87),
                        overflow: TextOverflow.ellipsis)),
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert,
                      size: 11,
                      color: isDark ? Colors.white54 : Colors.black45),
                  tooltip:
                      ActivitiesComponentStrings.tooltipUserAssignmentOptions,
                  color: isDark ? Colors.grey[800] : Colors.white,
                  splashRadius: 9,
                  padding: EdgeInsets.zero,
                  itemBuilder: (_) => [
                    PopupMenuItem(
                        value: 'delete_user_from_activity',
                        height: 28,
                        child: Text(
                            ActivitiesComponentStrings
                                .menuRemoveUserFromActivity,
                            style: TextStyle(
                                fontSize: 11,
                                color: isDark ? Colors.white : Colors.black))),
                  ],
                  onSelected: (v) {
                    _hideAssignmentDetailOverlay();
                    if (v == 'delete_user_from_activity') {
                      setState(() {
                        _activityAssignments[activity]?.removeWhere((assign) =>
                            assign.userInfo == userInfo.id &&
                            assign.data?['isDragPreview'] != true);
                        _recalculateUserAssignedHours();
                        _recordStateChange();
                      });
                    }
                  },
                ),
              ])),
          ValueListenableBuilder<double>(
              valueListenable: _currentPanOffsetNotifier,
              // By passing the pre-built 'timelineContent' as the child,
              // the builder function only has to do a cheap transform,
              // not rebuild the entire timeline row on pan.
              child: timelineContent,
              builder: (context, currentPanOffsetValue, child) {
                return ClipRect(
                    child: Transform.translate(
                        offset: Offset(currentPanOffsetValue, 0),
                        child: child));
              }),
        ]));
  }
}
