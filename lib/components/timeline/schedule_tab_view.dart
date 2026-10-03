import 'package:fstapp/components/navigation/routed_day_tabs.dart';
import 'package:fstapp/services/time_helper.dart';
import 'package:fstapp/styles/styles_config.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/theme_config.dart';
import 'schedule_timeline.dart';
import 'schedule_helper.dart';

class ScheduleTabView extends StatefulWidget {
  final String dayParameter;
  final DateTime? defaultDateTime;
  final Function(int)? onEventPressed;
  final List<TimeBlockItem> events;
  final Function(
          BuildContext, List<TimeBlockGroup>, TimeBlockItem? parentEventId)?
      onAddNewEvent;
  final bool Function()? showAddNewEventButton;

  const ScheduleTabView({
    super.key,
    this.dayParameter = 'day',
    required this.events,
    this.onAddNewEvent,
    this.showAddNewEventButton,
    this.onEventPressed,
    this.defaultDateTime,
  });

  @override
  _ScheduleTabViewState createState() => _ScheduleTabViewState();
}

class _ScheduleTabViewState extends State<ScheduleTabView> {
  List<TimeBlockGroup> datedEvents = [];

  @override
  Widget build(BuildContext context) {
    List<Widget> programLineChildren = [];

    datedEvents = TimeBlockHelper.splitTimeBlocksByDate(
      widget.events,
      context,
      AppConfig.daySplitHour,
    );

    if (datedEvents.isEmpty) {
      DateTime defaultTime = widget.defaultDateTime ?? TimeHelper.now();
      datedEvents.add(TimeBlockGroup(
          title: defaultTime.weekdayToString(context),
          events: [],
          dateTime: defaultTime));
    }

    for (var eventsByDay in datedEvents) {
      var eventGroups =
          TimeBlockHelper.groupEventsByFeatureSettings(eventsByDay.events);
      var timeline = ScheduleTimeline(
        eventGroups: eventGroups,
        onEventPressed: widget.onEventPressed,
        showAddNewEventButton: widget.showAddNewEventButton,
        onAddNewEvent: widget.onAddNewEvent,
      );
      programLineChildren.add(SingleChildScrollView(child: timeline));
    }

    return Container(
      constraints: const BoxConstraints(maxWidth: 400),
      child: RoutedDayTabs(
        initialIndex: getInitialIndex(),
        days: datedEvents.map((day) => day.dateTime!).toList(),
        parameter: widget.dayParameter,
        child: Scaffold(
          appBar: TabBar(
            isScrollable: datedEvents.length > 4,
            tabAlignment: datedEvents.length > 4
                ? TabAlignment.center
                : TabAlignment.fill,
            unselectedLabelColor: Colors.grey,
            labelColor: ThemeConfig.timelineTabLabelColor(context),
            indicatorColor: ThemeConfig.timelineTabIndicatorColor(context),
            indicatorWeight: 3.0,
            indicatorSize: TabBarIndicatorSize.label,
            indicatorPadding: const EdgeInsets.symmetric(vertical: 12.0),
            tabs: [
              for (var e in datedEvents)
                Tab(
                  child: Text(
                    StylesConfig.formatDateTimeForTab(context, e.dateTime!),
                    style: StylesConfig.timeLineTabNameTextStyle,
                    maxLines: 1,
                  ),
                )
            ],
          ),
          body: TabBarView(
            children: programLineChildren,
          ),
        ),
      ),
    );
  }

  int getInitialIndex() => TimeHelper.getTimeNowIndexFromDays(
        datedEvents.map((e) => e.dateTime!.weekday),
      );
}
