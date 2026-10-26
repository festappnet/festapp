import 'package:fstapp/data_services/authorization_capabilities.dart';
import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fstapp/app_router.gr.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:festapp_core/map.dart';
import 'package:fstapp/router_service.dart';
import 'package:fstapp/components/timeline/schedule_tab_view.dart';
import 'package:fstapp/components/timeline/schedule_helper.dart';
import 'package:festapp_core/program.dart';
import 'package:fstapp/components/_shared/async_reload_coordinator.dart';
import 'package:fstapp/data_services/auth_service.dart';
import 'package:fstapp/data_services/data_extensions.dart';
import 'package:fstapp/components/schedule/db_events.dart';
import 'package:fstapp/data_services/offline_data_service.dart';
import 'package:fstapp/data_services/client_sync/client_sync_runtime.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/components/occasion/add_new_event_dialog.dart';
import 'package:fstapp/components/schedule/my_schedule_page.dart';
import 'package:fstapp/components/features/feature_constants.dart';
import 'package:fstapp/components/features/feature_service.dart';
import 'package:fstapp/components/schedule/timetable_page.dart';
import 'package:fstapp/services/time_helper.dart';
import 'package:fstapp/services/toast_helper.dart';
import 'package:fstapp/styles/styles.dart';
import 'package:fstapp/theme_config.dart';
import 'package:fstapp/widgets/logo_widget.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../unit/views/unit_page.dart';

@RoutePage()
class ScheduleBasicPage extends StatefulWidget {
  static const ROUTE = "scheduleBasic";

  const ScheduleBasicPage({super.key});

  @override
  _ScheduleBasicPageState createState() => _ScheduleBasicPageState();
}

class _ScheduleBasicPageState extends State<ScheduleBasicPage>
    with WidgetsBindingObserver {
  final AsyncReloadCoordinator _reloadCoordinator = AsyncReloadCoordinator();
  static bool _fullDataGloballyLoaded = false;

  List<TimeBlockItem> _dots = [];
  List<EventModel> _events = [];
  static final Map<int, String?> _eventDescriptions = {};
  String? userName;

  @override
  void initState() {
    super.initState();
    if (!ClientSyncRuntime.isV1Selected) {
      WidgetsBinding.instance.addObserver(this);
    }
    ClientSyncRuntime.projectionEpoch.addListener(_onProjectionChanged);
    loadData();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      loadData();
    }
  }

  @override
  void dispose() {
    _reloadCoordinator.dispose();
    WidgetsBinding.instance.removeObserver(this);
    ClientSyncRuntime.projectionEpoch.removeListener(_onProjectionChanged);
    super.dispose();
  }

  void _onProjectionChanged() {
    if (ClientSyncRuntime.isV1Selected) {
      unawaited(_reloadProjectedEvents());
    }
  }

  Future<void> _reloadProjectedEvents() async {
    var events = await OfflineDataService.getAllEvents();
    events = await OfflineDataService.updateEventsWithGroupName(events);
    await loadPlacesForEvents(
        events, (_) async => OfflineDataService.getAllPlaces());
    final dots = events
        .filterRootEvents()
        .where((event) => !event.isCounselingSlot)
        .map(TimeBlockItem.fromEventModelBasicTimeline)
        .toList();
    if (!mounted) return;
    setState(() {
      _events = events;
      _dots = dots;
      for (final event in events) {
        if (event.id != null) _eventDescriptions[event.id!] = event.description;
      }
    });
  }

  Future<void> loadData() => _reloadCoordinator.run(() async {
        if (ClientSyncRuntime.isV1Selected) {
          await _reloadProjectedEvents();
          return;
        }
        await _loadOfflineDataThenFast();
        if (!_fullDataGloballyLoaded) {
          await _loadFullData();
          _fullDataGloballyLoaded = true;
        }
      });

  Future<void> _loadOfflineDataThenFast() async {
    if (_events.isEmpty) {
      var offline = await OfflineDataService.getAllEvents();
      offline = await OfflineDataService.updateEventsWithGroupName(offline);
      await loadPlacesForEvents(
          offline, (ids) async => (await OfflineDataService.getAllPlaces()));

      if (AuthService.isLoggedIn()) {
        var userInfo = await OfflineDataService.getUserInfo();
        userName = userInfo?.name ?? "";
      }
      _events = offline;
      for (var e in _events) {
        if (e.id != null) _eventDescriptions[e.id!] = e.description;
      }
      _dots = _events
          .filterRootEvents()
          .where((e) => !e.isCounselingSlot)
          .map((e) => TimeBlockItem.fromEventModelBasicTimeline(e))
          .toList();
    }

    if (mounted) {
      setState(() {});
    }

    final fast = await DbEvents.getAllEvents(
      RightsService.currentOccasionId()!,
      false,
    );

    for (final entry in fast.asMap().entries) {
      final e = entry.value;
      if (e.id != null && _eventDescriptions.containsKey(e.id!)) {
        fast[entry.key] = e.copyWith(description: _eventDescriptions[e.id!]);
      }
    }

    _events = fast;

    _dots = _events
        .filterRootEvents()
        .where((e) => !e.isCounselingSlot)
        .map((e) => TimeBlockItem.fromEventModelBasicTimeline(e))
        .toList();

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadFullData() async {
    final full = await DbEvents.getAllEvents(
      RightsService.currentOccasionId()!,
      true,
    );
    for (var e in full) {
      if (e.id != null) _eventDescriptions[e.id!] = e.description;
    }
    _events = full;

    _dots = _events
        .filterRootEvents()
        .where((e) => !e.isCounselingSlot)
        .map((e) => TimeBlockItem.fromEventModelBasicTimeline(e))
        .toList();
    await OfflineDataService.saveAllEvents(_events);
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> loadPlacesForEvents(List<EventModel> events,
      Future<List<PlaceModel>> Function(List<int>) fetchPlaces) async {
    var placeIds = events
        .map((e) => e.place?.id)
        .where((id) => id != null)
        .cast<int>()
        .toSet()
        .toList();
    if (placeIds.isEmpty) return;
    var places = await fetchPlaces(placeIds);
    var placesById = {for (var place in places) place.id: place};

    for (final entry in events.asMap().entries) {
      final event = entry.value;
      if (event.place?.id != null && placesById.containsKey(event.place!.id)) {
        events[entry.key] = event.copyWith(place: placesById[event.place!.id]);
      }
    }
  }

  void _schedulePressed() {
    RouterService.navigateOccasion(context, TimetablePage.ROUTE)
        .then((value) => loadData());
  }

  void _mySchedulePressed() {
    RouterService.navigateOccasion(context, MySchedulePage.ROUTE)
        .then((value) => loadData());
  }

  void _eventPressed(int id) {
    context.router.push(EventRoute(id: id)).then((_) => loadData());
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      bottom: false,
      left: false,
      right: false,
      child: Column(
        mainAxisSize: MainAxisSize.max,
        children: <Widget>[
          Container(
            color: ThemeConfig.logoBackgroundColor(context),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
                child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      GestureDetector(
                        onTap: () async {
                          RouterService.navigate(context,
                              "${UnitPage.ROUTE}/${RightsService.currentUnit()!.id!}");
                        },
                        onDoubleTap: () async {
                          var packageInfo = await PackageInfo.fromPlatform();
                          ToastHelper.Show(context,
                              "${packageInfo.appName} ${packageInfo.version}+${packageInfo.buildNumber}");
                          if (RightsService.hasCapability(
                              AuthorizationCapabilities.scheduleWrite)) {
                            TimeHelper.toggleTimeTravel?.call();
                            setState(() {});
                          }
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: LogoWidget(width: 64, programVariant: true),
                        ),
                      ),
                      const Spacer(),
                      if (FeatureService.isFeatureEnabled(
                          FeatureConstants.mySchedule))
                        Column(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              CircularButton(
                                onPressed: _mySchedulePressed,
                                backgroundColor:
                                    ThemeConfig.profileButtonColor(context),
                                child: Icon(Icons.favorite,
                                    color: ThemeConfig.profileButtonTextColor(
                                        context)),
                              ),
                              Text(CommonStrings.mySchedule),
                            ]),
                      if (FeatureService.isFeatureEnabled(
                          FeatureConstants.timetable))
                        Column(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              CircularButton(
                                onPressed: _schedulePressed,
                                backgroundColor:
                                    ThemeConfig.profileButtonColor(context),
                                child: Icon(Icons.calendar_month,
                                    color: ThemeConfig.profileButtonTextColor(
                                        context)),
                              ),
                              Text(CommonStrings.schedule),
                            ]),
                    ]),
              ),
            ),
          ),
          Expanded(
            child: ScheduleTabView(
              key: _dots.isEmpty ? UniqueKey() : ValueKey(_dots.length),
              events: _dots,
              onEventPressed: _eventPressed,
              showAddNewEventButton: () => RightsService.hasCapability(
                  AuthorizationCapabilities.scheduleWrite),
              onAddNewEvent: (context, p, _) =>
                  AddNewEventDialog.showAddEventDialog(context, p)
                      .then((_) => loadData()),
              defaultDateTime: RightsService.currentOccasion()?.startTime,
            ),
          ),
        ],
      ),
    );
  }
}
