// advanced_timeline_view.dart
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:fstapp/styles/styles_config.dart';
import 'package:fstapp/components/schedule/schedule_strings.dart';
import 'package:fstapp/theme_config.dart';
import 'package:fstapp/services/time_helper.dart';
import 'schedule_helper.dart'; // Assuming this is a local file

/// Tab header widget with scrollable, centered tabs and inline arrow navigation.
/// Tab header widget with scrollable, centered tabs and inline arrow navigation.
class AdvancedTimelineView extends StatelessWidget {
  /// Localized weekday labels (e.g., ['MON', 'TUE', ...]).
  final List<String> weekdays;

  /// Groups corresponding to each tab (must have a non-null dateTime).
  final List<TimeBlockGroup> groups;

  /// Maximum width for the TabBar (e.g., StylesConfig.formMaxWidth).
  final double maxTabBarWidth;

  /// Optional padding around the widget.
  final EdgeInsetsGeometry padding;

  const AdvancedTimelineView({
    super.key,
    required this.weekdays,
    required this.groups,
    this.maxTabBarWidth = StylesConfig.formMaxWidth,
    this.padding = StylesConfig.tabHeaderPadding,
  });

  @override
  Widget build(BuildContext context) {
    final controller = DefaultTabController.of(context);
    final animation = controller.animation!;
    final todayDate =
        TimeHelper.now(); // changed from `final today = TimeHelper.now().day;`

    // Total extra width to accommodate both arrows (approx. IconButton width)
    const arrowTotalWidth = 96.0;

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: ThemeConfig.tabHeaderColor(context),
        border: StylesConfig.headerBorder(),
      ),
      child: Center(
        child: ConstrainedBox(
          // Limit overall tab header width + arrows
          constraints: BoxConstraints(
            maxWidth: maxTabBarWidth + arrowTotalWidth,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Back arrow, right next to tabs
              AnimatedBuilder(
                animation: animation,
                builder: (ctx, _) {
                  final canGoBack = controller.index > 0;
                  return IconButton(
                    icon: const Icon(Icons.chevron_left),
                    color: ThemeConfig.tabTextColor(context),
                    onPressed: canGoBack
                        ? () => controller.animateTo(controller.index - 1)
                        : null,
                  );
                },
              ),

              // Scrollable tabs
              Flexible(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxTabBarWidth),
                  child: TabBar(
                    controller: controller,
                    isScrollable: true,
                    tabAlignment: TabAlignment.center,
                    indicator: BoxDecoration(
                      color: ThemeConfig.indicatorColor(context),
                      border: StylesConfig.indicatorBorder(),
                      borderRadius: BorderRadius.circular(
                          StylesConfig.indicatorRoundness),
                    ),
                    indicatorSize: TabBarIndicatorSize.tab,
                    labelColor: Colors.transparent,
                    unselectedLabelColor: Colors.transparent,
                    tabs: List.generate(groups.length, (i) {
                      final group = groups[i];
                      final isToday = group.dateTime!.year == todayDate.year &&
                          group.dateTime!.month == todayDate.month &&
                          group.dateTime!.day == todayDate.day;

                      return SizedBox(
                        width: 42,
                        height: 60,
                        child: AnimatedBuilder(
                          animation: animation,
                          builder: (ctx, _) {
                            final diff =
                                (animation.value - i).abs().clamp(0.0, 1.0);
                            final factor = 1.0 - diff;
                            final labelColor = Color.lerp(
                              ThemeConfig.tabTextColor(context),
                              ThemeConfig.indicatorTextColor(context),
                              factor,
                            )!;
                            return Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  weekdays[group.dateTime!.weekday - 1],
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: labelColor,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  DateFormat.Md(context.locale.toString())
                                      .format(group.dateTime!),
                                  style: TextStyle(
                                      fontSize: 10, color: labelColor),
                                ),
                                if (isToday) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    ScheduleStrings.today.toUpperCase(),
                                    style: TextStyle(
                                      fontSize: 8,
                                      height: 1,
                                      color: ThemeConfig.redColor(context),
                                    ),
                                  ),
                                ],
                              ],
                            );
                          },
                        ),
                      );
                    }),
                  ),
                ),
              ),

              // Forward arrow, directly adjacent
              AnimatedBuilder(
                animation: animation,
                builder: (ctx, _) {
                  final canGoForward = controller.index < groups.length - 1;
                  return IconButton(
                    icon: const Icon(Icons.chevron_right),
                    color: ThemeConfig.tabTextColor(context),
                    onPressed: canGoForward
                        ? () => controller.animateTo(controller.index + 1)
                        : null,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
