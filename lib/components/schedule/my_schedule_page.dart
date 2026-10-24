import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/components/activities/activity_data_helper.dart';
import 'package:fstapp/components/features/feature_service.dart';
import 'package:fstapp/components/features/schedule_feature.dart';
import 'package:fstapp/components/timeline/advanced_timeline_controller.dart';
import 'package:fstapp/components/timeline/advanced_timeline_day_list.dart';
import 'package:fstapp/components/users/user_info_model.dart';
import 'package:fstapp/data_services/auth_service.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/components/schedule/event_edit_page.dart';
import 'package:fstapp/components/map/map_navigation.dart';
import 'package:fstapp/components/map/public_map_session.dart';
import 'package:fstapp/router_service.dart';
import 'package:festapp_core/program.dart';
import 'package:fstapp/components/schedule/db_events.dart';
import 'package:fstapp/components/schedule/schedule_strings.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/data_services/offline_data_service.dart';
import 'package:fstapp/data_services/client_sync/client_sync_runtime.dart';
import 'package:fstapp/data_services/saved_program_pending_state.dart';
import 'package:fstapp/services/connectivity_service.dart';
import 'package:fstapp/components/timeline/schedule_helper.dart';
import 'package:fstapp/components/timeline/schedule_timeline.dart';
import 'package:fstapp/components/timeline/light_timeline_view.dart';
import 'package:fstapp/components/schedule/event_page.dart';
import 'package:fstapp/components/schedule/program_notification_settings.dart';
import 'package:fstapp/app_router.gr.dart';
import 'package:fstapp/components/users/companion/companion_dialog.dart';
import 'package:fstapp/components/users/companion/db_companions.dart';

import 'package:fstapp/styles/styles_config.dart';
import 'package:fstapp/theme_config.dart';

@RoutePage()
class MySchedulePage extends StatefulWidget {
  static const ROUTE = "myschedule";

  const MySchedulePage({super.key});

  @override
  _MySchedulePageState createState() => _MySchedulePageState();
}

class _MySchedulePageState extends State<MySchedulePage> {
  bool _fullEventsLoaded = false;
  bool? _isAdvancedTimeline = false;
  bool _isLightTimeline = false;
  final Map<int, String?> _eventAndActivitiesDescriptions = {};
  int? _openId;
  int _loadRevision = 0;
  bool _hasOwnedCompanions = false;

  @override
  void initState() {
    super.initState();
    savedProgramPendingState.addListener(_refreshPendingProgram);
    ClientSyncRuntime.projectionEpoch.addListener(_onProjectionChanged);
  }

  @override
  void dispose() {
    _loadRevision++;
    savedProgramPendingState.removeListener(_refreshPendingProgram);
    ClientSyncRuntime.projectionEpoch.removeListener(_onProjectionChanged);
    super.dispose();
  }

  void _refreshPendingProgram() {
    if (mounted) unawaited(loadDataOffline());
  }

  void _onProjectionChanged() {
    if (mounted && ClientSyncRuntime.isV1Selected) unawaited(loadData());
  }

  @override
  Future<void> didChangeDependencies() async {
    super.didChangeDependencies();
    var scheduleFeat =
        FeatureService.getFeatureDetails(ScheduleFeature.metaSchedule);
    if (scheduleFeat is ScheduleFeature &&
        (scheduleFeat.scheduleType == ScheduleFeature.scheduleTypeAdvanced ||
            scheduleFeat.scheduleType == ScheduleFeature.scheduleTypeLight)) {
      _isAdvancedTimeline = true;
    }
    if (scheduleFeat is ScheduleFeature &&
        scheduleFeat.scheduleType == ScheduleFeature.scheduleTypeLight) {
      _isLightTimeline = true;
    }
    await loadDataOffline();
    if (!shouldLoadSavedProgramOnline(
      isV1Selected: ClientSyncRuntime.isV1Selected,
      isOffline: ConnectivityService.isOfflineNotifier.value,
      hasPendingMutation: savedProgramPendingState.hasPending,
    )) {
      return;
    }
    await loadData();
  }

  MyEventsBundle? _data;

  Future<void> loadData() async {
    if (!AuthService.isLoggedIn()) {
      return;
    }
    final loadRevision = ++_loadRevision;
    final companions = await DbCompanions.getAllCompanions();
    if (!mounted || loadRevision != _loadRevision) return;
    _hasOwnedCompanions = companions.isNotEmpty;
    late final MyEventsBundle data;
    if (!_fullEventsLoaded) {
      final loaded = await DbEvents.getMyEventsAndActivities(
          RightsService.currentOccasionId()!, true);
      if (loaded == null) return;
      data = loaded;
      if (!mounted || loadRevision != _loadRevision) return;
      for (final entry in data.events.asMap().entries) {
        final e = entry.value;
        if (e.id != null) {
          _eventAndActivitiesDescriptions[e.id!] = e.description;
        }
      }
      for (var e in data.activities) {
        _eventAndActivitiesDescriptions[e.id.hashCode] = e.description;
      }
      _fullEventsLoaded = true;
    } else {
      final loaded = await DbEvents.getMyEventsAndActivities(
          RightsService.currentOccasionId()!, false);
      if (loaded == null) return;
      data = loaded;
      if (!mounted || loadRevision != _loadRevision) return;
      for (final entry in data.events.asMap().entries) {
        final e = entry.value;
        if (e.id != null &&
            _eventAndActivitiesDescriptions.containsKey(e.id!)) {
          data.events[entry.key] = e.copyWith(description: _eventAndActivitiesDescriptions[e.id!]);
        }
      }
      for (var e in data.activities) {
        if (_eventAndActivitiesDescriptions.containsKey(e.id)) {
          e.description = _eventAndActivitiesDescriptions[e.id];
        }
      }
    }

    var actDots =
        ActivityDataHelper.activitiesToTimeBlocks(data.activities, data.events);

    var events = data.events
        .where((e) => canBeShownInMySchedule(RightsService.currentUser(), e));
    late final List<TimeBlockItem> dots;
    if (_isAdvancedTimeline ?? false) {
      dots = events.map((e) => TimeBlockItem.fromEventModel(e)).toList();
    } else {
      dots = events.map((e) => TimeBlockItem.fromEventModelAsChild(e)).toList();
    }

    dots.addAll(actDots);
    dots.sort((a, b) => a.startTime.compareTo(b.startTime));
    if (!mounted || loadRevision != _loadRevision) return;
    _data = data;
    _dots = dots;
    setState(() {});
  }

  bool canBeShownInMySchedule(UserInfoModel? userInfo, EventModel e) {
    return e.isInMySchedule == true ||
        ((e.isGroupEvent ?? false) && (userInfo?.hasGroup() ?? false)) ||
        (e.isSignedIn ?? false);
  }

  Future<void> loadDataOffline() async {
    final loadRevision = ++_loadRevision;
    var offlineEvents = await OfflineDataService.getAllEvents();
    offlineEvents = await OfflineDataService.updateEventsWithMySchedule(offlineEvents);
    offlineEvents = await OfflineDataService.updateEventsWithGroupName(offlineEvents);
    var userInfo = await OfflineDataService.getUserInfo();

    final myEvents = offlineEvents
        .where((e) => canBeShownInMySchedule(userInfo, e))
        .toList(growable: false);

    var activities = await OfflineDataService.getAllActivities();

    // init _eventAndActivitiesDescriptions
    for (var e in myEvents) {
      if (e.id != null) _eventAndActivitiesDescriptions[e.id!] = e.description;
    }
    for (var e in activities) {
      _eventAndActivitiesDescriptions[e.id.hashCode] = e.description;
    }

    var actDots =
        ActivityDataHelper.activitiesToTimeBlocks(activities, offlineEvents);

    final dots = (_isAdvancedTimeline ?? false)
        ? myEvents.map((e) => TimeBlockItem.fromEventModel(e)).toList()
        : myEvents.map((e) => TimeBlockItem.fromEventModelAsChild(e)).toList();
    dots.addAll(actDots);
    dots.sort((a, b) => a.startTime.compareTo(b.startTime));

    if (!mounted || loadRevision != _loadRevision) return;
    _events
      ..clear()
      ..addAll(myEvents);
    _dots = dots;
    setState(() {});
  }

  Future<void> _handleSignIn(int id) async {
    await DbEvents.signInToEvent(context, id);
    await loadData();
  }

  Future<void> _handleSignOut(int id) async {
    await DbEvents.signOutFromEvent(context, id);
    await loadData();
  }

  Future<void> _handleAdd(int id) async {
    await DbEvents.addToMySchedule(context, id);
    await loadData();
  }

  Future<void> _handleRemove(int id) async {
    await DbEvents.removeFromMySchedule(context, id);
    await loadData();
  }

  void _eventPressed(int id) {
    RouterService.navigateOccasion(context, "${EventPage.ROUTE}/$id")
        .then((_) => loadData());
  }

  Future<void> _goToMap(int placeId) async {
    final result = await MapNavigation.openPlace(context, placeId);
    if (mounted && result.kind == MapVisitKind.returned) await loadData();
  }

  bool _isUserApprover() => RightsService.isApprover();

  Future<void> _handleScanButtonPressed(
      BuildContext context, int eventId) async {
    RouterService.navigatePageInfo(context, CheckRoute(id: eventId));
  }

  Future<void> _handleCompanionButtonPressed(
      BuildContext context, TimeBlockItem timeBlockItem) async {
    final companions = await DbCompanions.getAllCompanions();
    if (!mounted || !context.mounted) return;
    showDialog(
      context: context,
      builder: (dialogContext) => CompanionAttendanceDialog(
        eventId: timeBlockItem.id,
        companions: companions,
        refreshData: () async {
          await loadData();
        },
        canSignIn: () {
          final currentItem = _dots?.firstWhereOrNull(
              (element) => element.id == timeBlockItem.id);
          return currentItem?.canSignIn() ?? false;
        },
      ),
    );
  }

  bool get _showProgramNotificationSettings =>
      FeatureService.isProgramNotificationsEnabled();

  Future<void> _openProgramNotificationSettings() => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (sheetContext) => SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(sheetContext).bottom + 12,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: StylesConfig.appMaxWidth),
                child: ProgramNotificationSettingsCard(),
              ),
            ),
          ),
        ),
      );

  List<Widget>? _programNotificationActions(Color color) =>
      _showProgramNotificationSettings
          ? [
              IconButton(
                tooltip: ScheduleStrings.programRemindersTitle,
                onPressed: _openProgramNotificationSettings,
                icon: Icon(Icons.notifications_outlined, color: color),
              ),
            ]
          : null;

  @override
  Widget build(BuildContext context) {
    final Widget commonEmptyContent = Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 88, 24, 24),
        child: Text(
          ScheduleStrings.myScheduleEmpty,
          style: const TextStyle(fontSize: 20),
        ),
      ),
    );

    // Light schedule type renders "My program" as a single continuous scroll
    // of light rows grouped by day (no cards, no day tabs) — matching the
    // production layout and the main light schedule's row style.
    if (_isLightTimeline) {
      return Scaffold(
        backgroundColor: ThemeConfig.whiteColor(context),
        appBar: AppBar(
          backgroundColor: ThemeConfig.whiteColorDarker(context),
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: true,
          title: Text(
            CommonStrings.mySchedule,
            style: TextStyle(
              color: ThemeConfig.blackColor(context),
              fontWeight: FontWeight.w700,
            ),
          ),
          leading: BackButton(
            color: ThemeConfig.blackColor(context),
            onPressed: () => RouterService.popOrHome(context),
          ),
          actions: _programNotificationActions(ThemeConfig.blackColor(context)),
        ),
        body: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: _dots == null
                ? const Center(child: CircularProgressIndicator())
                : ConstrainedBox(
                    constraints:
                        BoxConstraints(maxWidth: StylesConfig.appMaxWidth),
                    child: LightMyScheduleList(
                      events: _dots!,
                      onEventPressed: _eventPressed,
                      emptyContent: commonEmptyContent,
                    ),
                  ),
          ),
        ),
      );
    }

    Widget body = (_isAdvancedTimeline == true)
        ? DayList(
            dayGroup: TimeBlockGroup(title: "", events: _dots!),
            controller: AdvancedTimelineController(
              events: _dots!,
              onEventPressed: _eventPressed,
              showAddNewEventButton: RightsService.isEditor,
              onSignInEvent: _handleSignIn,
              onSignOutEvent: _handleSignOut,
              onAddToProgramEvent: _handleAdd,
              onRemoveFromProgramEvent: _handleRemove,
              onEditEvent: (c, ev) => RouterService.navigateOccasion(
                      context, "${EventEditPage.ROUTE}/$ev")
                  .then((_) => loadData()),
              onPlaceTap: (c, pl) => _goToMap(pl.id),
              customSplitter: TimeBlockHelper.splitTimeBlocksByDay,
              animateEventRemoval: true,
              emptyContent: commonEmptyContent,
              isUserApprover: _isUserApprover,
              onScanButtonPressed: _handleScanButtonPressed,
              onCompanionButtonPressed: _handleCompanionButtonPressed,
              hasOwnedCompanions: _hasOwnedCompanions,
            ),
            openId: _openId,
            onToggle: (id) =>
                setState(() => _openId = _openId == id ? null : id),
          )
        : SingleChildScrollView(
            child: ScheduleTimeline(
            eventGroups: TimeBlockHelper.splitTimeBlocksByDay(_dots!, context),
            onEventPressed: _eventPressed,
            nodePosition: 0.3,
            emptyContent: commonEmptyContent,
          ));

    return Scaffold(
        appBar: AppBar(
          title: Text(CommonStrings.mySchedule,
              style: TextStyle(color: ThemeConfig.appBarColorNegative())),
          leading: BackButton(
            color: ThemeConfig.appBarColorNegative(),
            onPressed: () => RouterService.popOrHome(context),
          ),
          actions: _programNotificationActions(
            ThemeConfig.appBarColorNegative(),
          ),
        ),
        body: SafeArea(
          child: Align(
              alignment: Alignment.topCenter,
              child: _dots == null
                  ? const Center(child: CircularProgressIndicator())
                  : ConstrainedBox(
                      constraints:
                          BoxConstraints(maxWidth: StylesConfig.appMaxWidth),
                      child: body)),
        ));
  }

  final List<EventModel> _events = [];
  List<TimeBlockItem>? _dots = [];
}
