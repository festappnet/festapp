import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/components/navigation/navigation_paths.dart';
import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/app_router.gr.dart';
import 'package:fstapp/components/navigation/routed_tab_scaffold.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/schedule/exclusivity_content.dart';
import 'package:fstapp/components/schedule/schedule_strings.dart';
import 'package:fstapp/components/schedule/schedule_content.dart';
import 'package:fstapp/components/event_feedback/event_feedback_admin_content.dart';
import 'package:fstapp/components/event_feedback/event_feedback_strings.dart';
import 'package:fstapp/components/features/feature_constants.dart';
import 'package:fstapp/components/features/feature_service.dart';

@RoutePage(name: 'ScheduleTabsRoute')
class ScheduleTab extends StatelessWidget {
  const ScheduleTab({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: RightsService.occasionLinkModelNotifier,
      builder: (context, _) => _build(context));
  Widget _build(BuildContext context) {
    Localizations.localeOf(context);
    return RoutedTabScaffold(tabs: [
      RoutedTabDefinition(
          slug: NavigationPaths.schedule,
          route: const ScheduleScheduleRoute(),
          label: CommonStrings.schedule,
          icon: Icons.calendar_month),
      RoutedTabDefinition(
          slug: NavigationPaths.suspicious,
          route: const ScheduleSuspiciousRoute(),
          label: ScheduleStrings.suspiciousEvents,
          icon: Icons.warning_amber_rounded),
      RoutedTabDefinition(
          slug: NavigationPaths.exclusivity,
          route: const ScheduleExclusivityRoute(),
          label: ScheduleStrings.exclusivity,
          icon: Icons.punch_clock_rounded),
      if (FeatureService.isFeatureEnabled(FeatureConstants.eventFeedback))
        RoutedTabDefinition(
            slug: NavigationPaths.feedback,
            route: const ScheduleFeedbackRoute(),
            label: EventFeedbackStrings.featureTitle,
            icon: Icons.sentiment_satisfied_alt),
    ]);
  }
}

@RoutePage()
class ScheduleSchedulePage extends StatelessWidget {
  const ScheduleSchedulePage({super.key});
  @override
  Widget build(BuildContext context) => ScheduleContent();
}

@RoutePage()
class ScheduleSuspiciousPage extends StatefulWidget {
  const ScheduleSuspiciousPage({super.key});
  @override
  State<ScheduleSuspiciousPage> createState() => _ScheduleSuspiciousPageState();
}

class _ScheduleSuspiciousPageState extends State<ScheduleSuspiciousPage>
    with AutoRouteAwareStateMixin<ScheduleSuspiciousPage> {
  final _key = GlobalKey<ScheduleContentState>();
  @override
  void didChangeTabRoute(TabPageRoute previousRoute) =>
      _key.currentState?.reloadIfClean();
  @override
  Widget build(BuildContext context) =>
      ScheduleContent(key: _key, suspiciousOnly: true);
}

@RoutePage()
class ScheduleExclusivityPage extends StatelessWidget {
  const ScheduleExclusivityPage({super.key});
  @override
  Widget build(BuildContext context) => ExclusivityContent();
}

@RoutePage()
class ScheduleFeedbackPage extends StatelessWidget {
  const ScheduleFeedbackPage({super.key});
  @override
  Widget build(BuildContext context) => EventFeedbackAdminContent();
}
