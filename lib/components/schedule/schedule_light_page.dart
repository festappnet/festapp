import 'package:auto_route/auto_route.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:fstapp/app_router.gr.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:festapp_core/map.dart';
import 'package:fstapp/components/schedule/db_events.dart';
import 'package:fstapp/components/schedule/schedule_strings.dart';
import 'package:fstapp/components/_shared/async_reload_coordinator.dart';
import 'package:fstapp/components/users/user_strings.dart';
import 'package:festapp_core/program.dart';
import 'package:fstapp/components/schedule/my_schedule_page.dart';
import 'package:fstapp/components/schedule/timetable_page.dart';
import 'package:fstapp/components/features/feature_constants.dart';
import 'package:fstapp/components/features/feature_service.dart';
import 'package:fstapp/components/occasion/add_new_event_dialog.dart';
import 'package:fstapp/components/timeline/light_timeline_view.dart';
import 'package:fstapp/components/timeline/schedule_helper.dart';
import 'package:fstapp/components/unit/views/unit_page.dart';
import 'package:fstapp/data_services/data_extensions.dart';
import 'package:fstapp/data_services/offline_data_service.dart';
import 'package:fstapp/data_services/client_sync/client_sync_runtime.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/router_service.dart';
import 'package:fstapp/data_services/auth_service.dart';
import 'package:fstapp/components/users/views/login_page.dart';
import 'package:fstapp/components/users/views/user_page.dart';
import 'package:fstapp/services/time_helper.dart';
import 'package:fstapp/services/toast_helper.dart';
import 'package:fstapp/theme_config.dart';
import 'package:fstapp/widgets/logo_widget.dart';
import 'package:package_info_plus/package_info_plus.dart';

@RoutePage()
class ScheduleLightPage extends StatefulWidget {
  static const ROUTE = "scheduleLight";

  const ScheduleLightPage({super.key});

  @override
  State<ScheduleLightPage> createState() => _ScheduleLightPageState();
}

class _ScheduleLightPageState extends State<ScheduleLightPage>
    with WidgetsBindingObserver {
  final AsyncReloadCoordinator _reloadCoordinator = AsyncReloadCoordinator();
  static bool _fullDataGloballyLoaded = false;

  List<TimeBlockItem> _dots = [];
  List<EventModel> _events = [];
  static final Map<int, String?> _eventDescriptions = {};

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
    await _loadPlacesForEvents(
        events, (_) async => OfflineDataService.getAllPlaces());
    final dots = events
        .filterRootEvents()
        .where((event) => !event.isCounselingSlot)
        .map(TimeBlockItem.fromEventModel)
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
        await _loadOfflineThenFast();
        if (!_fullDataGloballyLoaded) {
          await _loadFullData();
          _fullDataGloballyLoaded = true;
        }
      });

  Future<void> _loadOfflineThenFast() async {
    if (_events.isEmpty) {
      var offline = await OfflineDataService.getAllEvents();
      offline = await OfflineDataService.updateEventsWithGroupName(offline);
      await _loadPlacesForEvents(
          offline, (_) async => await OfflineDataService.getAllPlaces());
      _events = offline;
      for (var e in _events) {
        if (e.id != null) _eventDescriptions[e.id!] = e.description;
      }
      _dots = _events
          .filterRootEvents()
          .where((e) => !e.isCounselingSlot)
          .map((e) => TimeBlockItem.fromEventModel(e))
          .toList();
    }
    if (mounted) setState(() {});

    final fast =
        await DbEvents.getAllEvents(RightsService.currentOccasionId()!, false);
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
        .map((e) => TimeBlockItem.fromEventModel(e))
        .toList();
    if (mounted) setState(() {});
  }

  Future<void> _loadFullData() async {
    final full =
        await DbEvents.getAllEvents(RightsService.currentOccasionId()!, true);
    for (var e in full) {
      if (e.id != null) _eventDescriptions[e.id!] = e.description;
    }
    _events = full;
    _dots = _events
        .filterRootEvents()
        .where((e) => !e.isCounselingSlot)
        .map((e) => TimeBlockItem.fromEventModel(e))
        .toList();
    await OfflineDataService.saveAllEvents(_events);
    if (mounted) setState(() {});
  }

  Future<void> _loadPlacesForEvents(List<EventModel> events,
      Future<List<PlaceModel>> Function(List<int>) fetchPlaces) async {
    final placeIds = events
        .map((e) => e.place?.id)
        .where((id) => id != null)
        .cast<int>()
        .toSet()
        .toList();
    if (placeIds.isEmpty) return;
    final places = await fetchPlaces(placeIds);
    final byId = {for (final p in places) p.id: p};
    for (final entry in events.asMap().entries) {
          final e = entry.value;
      if (e.place?.id != null && byId.containsKey(e.place!.id)) {
        events[entry.key] = e.copyWith(place: byId[e.place!.id]);
      }
    }
  }

  void _schedulePressed() {
    RouterService.navigateOccasion(context, TimetablePage.ROUTE)
        .then((_) => loadData());
  }

  void _mySchedulePressed() {
    RouterService.navigateOccasion(context, MySchedulePage.ROUTE)
        .then((_) => loadData());
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
        children: [
          Container(
            // Soft brand tint over the white surface — gives the top header
            // its own visual zone without going back to a saturated dark
            // bar. Themed: alpha of `darkColor` = seed1 in light mode.
            color: ThemeConfig.darkColor(context).withValues(alpha: 0.06),
            child: SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        GestureDetector(
                          onTap: () => RouterService.navigate(context,
                              "${UnitPage.ROUTE}/${RightsService.currentUnit()!.id!}"),
                          onDoubleTap: () async {
                            final info = await PackageInfo.fromPlatform();
                            ToastHelper.Show(context,
                                "${info.appName} ${info.version}+${info.buildNumber}");
                            if (RightsService.isEditor()) {
                              TimeHelper.toggleTimeTravel?.call();
                              setState(() {});
                            }
                          },
                          child: const Padding(
                            padding: EdgeInsets.symmetric(
                                horizontal: 4, vertical: 4),
                            child: LogoWidget(height: 40, programVariant: true),
                          ),
                        ),
                        const Spacer(),
                        if (FeatureService.isFeatureEnabled(
                            FeatureConstants.mySchedule))
                          _HeaderIconButton(
                            icon: Icons.favorite_border,
                            label: CommonStrings.mySchedule,
                            onPressed: _mySchedulePressed,
                          ),
                        if (FeatureService.isFeatureEnabled(
                            FeatureConstants.timetable))
                          _HeaderIconButton(
                            icon: Icons.calendar_month_outlined,
                            label: CommonStrings.schedule,
                            onPressed: _schedulePressed,
                          ),
                        // GlobalSearch moves profile/sign-in into the app bar.
                        if (FeatureService.isFeatureEnabled(
                            FeatureConstants.globalSearch))
                          _HeaderIconButton(
                            icon: AuthService.isLoggedIn()
                                ? Icons.account_circle
                                : Icons.account_circle_outlined,
                            label: AuthService.isLoggedIn()
                                ? (RightsService.currentUser()?.name ??
                                    ScheduleStrings.profile)
                                : UserStrings.signIn,
                            onPressed: () {
                              final f = AuthService.isLoggedIn()
                                  ? RouterService.navigateOccasion(
                                      context, UserPage.ROUTE)
                                  : RouterService.navigate(
                                      context, LoginPage.ROUTE);
                              f.then((_) => loadData());
                            },
                          ),
                      ],
                    ),
                  ),
                  // Hairline that bridges the header (white) into the tab bar
                  // (also white). Keeps the airy feel but separates the two.
                  Container(
                    height: 1,
                    color:
                        ThemeConfig.blackColor(context).withValues(alpha: 0.06),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: LightTimelineView(
              key: _dots.isEmpty ? UniqueKey() : ValueKey(_dots.length),
              events: _dots,
              sessionOccasionId: RightsService.currentOccasionId(),
              onEventPressed: _eventPressed,
              showAddNewEventButton: RightsService.isEditor,
              onAddNewEvent: (ctx, groups, p) =>
                  AddNewEventDialog.showAddEventDialog(ctx, groups, p)
                      .then((_) => loadData()),
              defaultDateTime: RightsService.currentOccasion()?.startTime,
            ),
          ),
        ],
      ),
    );
  }
}

/// Flat icon + label, color = appBarColorNegative — mirrors the header
/// buttons used by the advanced SchedulePage so the brand bar looks
/// consistent across schedule types.
class _HeaderIconButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const _HeaderIconButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final color = ThemeConfig.blackColor(context);
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(24),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                  color: color, fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}
