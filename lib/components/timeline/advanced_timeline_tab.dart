import 'package:fstapp/components/navigation/routed_day_tabs.dart';
// advanced_timeline_tab.dart
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:fstapp/services/time_helper.dart';
import 'package:fstapp/app_config.dart';
import 'advanced_timeline_controller.dart';
import 'advanced_timeline_day_list.dart';
import 'advanced_timeline_view.dart';
import 'schedule_helper.dart'; // Assuming this is a local file

class AdvancedTimelineTab extends StatefulWidget {
  final String dayParameter;
  final DateTime? defaultDateTime;
  final AdvancedTimelineController controller;

  const AdvancedTimelineTab({
    super.key,
    this.dayParameter = 'preview-day',
    required this.controller,
    this.defaultDateTime,
  });

  @override
  _AdvancedTimelineTabState createState() => _AdvancedTimelineTabState();
}

class _AdvancedTimelineTabState extends State<AdvancedTimelineTab> {
  int? _openId;

  @override
  Widget build(BuildContext context) {
    // 1) Weekday labels
    final weekdays = List.generate(
        7,
        (i) => DateFormat.E(context.locale.toString())
            .format(DateTime(2020, 1, 6 + i))
            .toUpperCase());

    // 2) Split into days
    final datedEvents = TimeBlockHelper.splitTimeBlocksByDate(
      widget.controller.events,
      context,
      AppConfig.daySplitHour,
    );

    if (datedEvents.isEmpty) {
      final dt = widget.defaultDateTime ?? TimeHelper.now();
      datedEvents.add(TimeBlockGroup(
        title: dt.weekdayToString(context),
        events: [],
        dateTime: dt,
      ));
    }

    return RoutedDayTabs(
      days: datedEvents.map((day) => day.dateTime!).toList(),
      parameter: widget.dayParameter,
      initialIndex: TimeHelper.getTimeNowIndexFromDays(
          datedEvents.map((e) => e.dateTime!.weekday)),
      child: Builder(builder: (ctx) {
        final controller = DefaultTabController.of(ctx);
        return Scaffold(
          body: SafeArea(
            child: Column(children: [
              const SizedBox(height: 4),

              // ——— Animated Day‐Tabs ———
              AnimatedBuilder(
                animation: controller.animation!,
                builder: (_, __) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AdvancedTimelineView(
                      weekdays: weekdays,
                      groups: datedEvents,
                      maxTabBarWidth: 300,
                      padding: const EdgeInsets.symmetric(vertical: 0),
                    ),
                  );
                },
              ),

              // ——— Events list & “Add” button per day ———
              Expanded(
                child: TabBarView(
                  controller: controller,
                  children: [
                    for (var dayGroup in datedEvents)
                      DayList(
                        dayGroup: dayGroup,
                        controller: widget.controller,
                        openId: _openId,
                        onToggle: (id) =>
                            setState(() => _openId = _openId == id ? null : id),
                      ),
                  ],
                ),
              ),
            ]),
          ),
        );
      }),
    );
  }
}
