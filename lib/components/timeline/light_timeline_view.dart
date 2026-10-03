import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/components/features/feature_constants.dart';
import 'package:fstapp/components/features/feature_service.dart';
import 'package:fstapp/components/schedule/schedule_strings.dart';
import 'package:fstapp/components/timeline/schedule_helper.dart';
import 'package:fstapp/services/time_helper.dart';
import 'package:fstapp/styles/styles_config.dart';
import 'package:fstapp/theme_config.dart';

/// Third schedule design — light, airy variant inspired by the
/// "studentský velehrad" program layout. Renders day tabs with an
/// accent-underline indicator, a flat list of `time · title · place`
/// rows separated by hairline dividers, and cream-tinted child cards
/// for expandable parent events.
///
/// Mirrors the advanced view's pattern: all day-grouping happens in
/// build() and a fresh DefaultTabController is keyed by occasion, dated-day
/// identity, and target index so tab state regenerates correctly when events
/// load asynchronously.
class LightTimelineView extends StatefulWidget {
  final List<TimeBlockItem> events;
  final int? sessionOccasionId;
  final void Function(int eventId)? onEventPressed;
  final bool Function()? showAddNewEventButton;
  final void Function(BuildContext context, List<TimeBlockGroup> groups,
      TimeBlockItem? parent)? onAddNewEvent;
  final DateTime? defaultDateTime;

  const LightTimelineView({
    super.key,
    required this.events,
    this.sessionOccasionId,
    this.onEventPressed,
    this.showAddNewEventButton,
    this.onAddNewEvent,
    this.defaultDateTime,
  });

  @override
  State<LightTimelineView> createState() => _LightTimelineViewState();
}

class _LightTimelineViewState extends State<LightTimelineView> {
  int? _openId;

  @override
  Widget build(BuildContext context) {
    final sorted = [...widget.events]
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    final days = TimeBlockHelper.splitTimeBlocksByDate(
      sorted,
      context,
      AppConfig.daySplitHour,
    );

    if (days.isEmpty) {
      return Container(
        color: ThemeConfig.whiteColor(context),
        alignment: Alignment.center,
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Text(
            ScheduleStrings.noEvents,
            style: TextStyle(color: _mutedText(context), fontSize: 14),
          ),
        ),
      );
    }

    final initialIndex = widget.sessionOccasionId == null
        ? _computeInitialIndex(days)
        : scheduleDaySessionSelection.resolveInitialIndex(
            occasionId: widget.sessionOccasionId!,
            dayGroups: days,
            now: TimeHelper.now(),
          );

    return Container(
      color: ThemeConfig.whiteColor(context),
      child: DefaultTabController(
        key: ValueKey<String>(
          'LightTimelineView_TabController_${widget.sessionOccasionId}_'
          '${days.map((day) => day.dateTime?.millisecondsSinceEpoch ?? 0).join('_')}_'
          '$initialIndex',
        ),
        length: days.length,
        initialIndex: initialIndex,
        child: _LightTabSelectionObserver(
          onChanged: (index) {
            final occasionId = widget.sessionOccasionId;
            if (occasionId != null && index < days.length) {
              scheduleDaySessionSelection.remember(occasionId, days[index]);
            }
          },
          child: Column(
            children: [
              // Brand-identity day tab strip — thin white dividers + thin
              // underline on the active day on a saturated app-bar background.
              // Built to match the configured visual identity (thin lines on
              // solid color), not the advanced pill style.
              // Day tabs — mirrors the advanced view's structure (chevrons,
              // weekday+date+today dot) but uses a thin rounded underline
              // instead of a filled pill so the strip stays airy.
              _LightDayTabBar(
                weekdays: _weekdays(context),
                days: days,
              ),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                        maxWidth: StylesConfig.formMaxWidth),
                    child: TabBarView(
                      children: days
                          .map((day) => _DayList(
                                day: day,
                                openId: _openId,
                                onToggle: (id) => setState(() =>
                                    _openId = (_openId == id) ? null : id),
                                onEventPressed: widget.onEventPressed,
                                showAddNewEventButton:
                                    widget.showAddNewEventButton,
                                onAddNewEvent: widget.onAddNewEvent,
                              ))
                          .toList(),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  int _computeInitialIndex(List<TimeBlockGroup> days) {
    if (days.isEmpty) return 0;
    final now = TimeHelper.now();

    // Prefer the day that contains an event happening right now.
    for (var i = 0; i < days.length; i++) {
      for (final e in days[i].events) {
        if (e.startTime.isBefore(now) && e.endTime.isAfter(now)) {
          return i;
        }
      }
    }
    // Otherwise, the first day on/after today (day-key compared).
    final nowDay = DateTime(now.year, now.month, now.day);
    for (var i = 0; i < days.length; i++) {
      final d = days[i].dateTime;
      if (d != null && !d.isBefore(nowDay)) return i;
    }
    // …or the first day matching widget.defaultDateTime.
    final def = widget.defaultDateTime;
    if (def != null) {
      for (var i = 0; i < days.length; i++) {
        final d = days[i].dateTime;
        if (d != null &&
            d.year == def.year &&
            d.month == def.month &&
            d.day == def.day) {
          return i;
        }
      }
    }
    return 0;
  }
}

class _LightTabSelectionObserver extends StatefulWidget {
  const _LightTabSelectionObserver({
    required this.child,
    required this.onChanged,
  });

  final Widget child;
  final ValueChanged<int> onChanged;

  @override
  State<_LightTabSelectionObserver> createState() =>
      _LightTabSelectionObserverState();
}

class _LightTabSelectionObserverState
    extends State<_LightTabSelectionObserver> {
  TabController? _controller;
  int? _lastIndex;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = DefaultTabController.of(context);
    if (identical(controller, _controller)) return;
    _controller?.removeListener(_onControllerChanged);
    _controller = controller;
    _lastIndex = controller.index;
    controller.addListener(_onControllerChanged);
  }

  void _onControllerChanged() {
    final index = _controller?.index;
    if (index == null || index == _lastIndex) return;
    _lastIndex = index;
    widget.onChanged(index);
  }

  @override
  void dispose() {
    _controller?.removeListener(_onControllerChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

// ---------------------------------------------------------------------------
// Flat, non-tabbed list of the same rows — used to render an event's
// sub-program with the identical look of the main (light) schedule page.
// ---------------------------------------------------------------------------
class LightSubprogramList extends StatefulWidget {
  final List<TimeBlockItem> events;
  final void Function(int eventId)? onEventPressed;
  final bool Function()? showAddNewEventButton;
  final void Function(BuildContext context, List<TimeBlockGroup> groups,
      TimeBlockItem? parent)? onAddNewEvent;

  const LightSubprogramList({
    super.key,
    required this.events,
    this.onEventPressed,
    this.showAddNewEventButton,
    this.onAddNewEvent,
  });

  @override
  State<LightSubprogramList> createState() => _LightSubprogramListState();
}

class _LightSubprogramListState extends State<LightSubprogramList> {
  int? _openId;

  @override
  Widget build(BuildContext context) {
    final sorted = [...widget.events]
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    final canAdd =
        FeatureService.isFeatureEnabled(FeatureConstants.mySchedule) &&
            (widget.showAddNewEventButton?.call() ?? false) &&
            widget.onAddNewEvent != null;

    final sections = TimeBlockHelper.groupEventsByFeatureSettings(sorted);
    final children = <Widget>[];
    for (final section in sections) {
      if (section.title.isNotEmpty) {
        children.add(_SectionHeader(label: section.title));
      }
      for (var i = 0; i < section.events.length; i++) {
        final e = section.events[i];
        final hasChildren = e.haveChildren();
        final isOpen = hasChildren && _openId == e.id;
        children.add(_EventRow(
          event: e,
          isOpen: isOpen,
          showEndTime: true,
          onTap: hasChildren
              ? () => setState(() => _openId = _openId == e.id ? null : e.id)
              : (widget.onEventPressed != null
                  ? () => widget.onEventPressed!(e.id)
                  : null),
          onChildTap: widget.onEventPressed,
        ));
        if (i < section.events.length - 1) {
          children.add(_RowDivider());
        }
      }
    }

    if (canAdd) {
      children.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: _AddEventButton(
            onPressed: () => widget.onAddNewEvent!(context, sections, null),
          ),
        ),
      ));
    }

    if (children.isEmpty) return const SizedBox.shrink();
    return Container(
      color: ThemeConfig.whiteColor(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Day-grouped, continuously-scrolling light list for the "My program" page.
// Unlike the main schedule (LightTimelineView) this is NOT tabbed — every day
// is stacked in one scroll under a left-aligned day header with a trailing
// hairline rule, matching the production layout. Reuses the same
// `_EventRow` / `_SectionHeader` / `_RowDivider` primitives so a My-program row
// is visually identical to a main-schedule row.
// ---------------------------------------------------------------------------
class LightMyScheduleList extends StatefulWidget {
  final List<TimeBlockItem> events;
  final void Function(int eventId)? onEventPressed;
  final Widget? emptyContent;

  const LightMyScheduleList({
    super.key,
    required this.events,
    this.onEventPressed,
    this.emptyContent,
  });

  @override
  State<LightMyScheduleList> createState() => _LightMyScheduleListState();
}

class _LightMyScheduleListState extends State<LightMyScheduleList> {
  int? _openId;

  @override
  Widget build(BuildContext context) {
    final sorted = [...widget.events]
      ..sort((a, b) => a.startTime.compareTo(b.startTime));

    if (sorted.isEmpty) {
      return Container(
        color: ThemeConfig.whiteColor(context),
        alignment: Alignment.topCenter,
        child: widget.emptyContent ??
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 88, 24, 24),
              child: Text(ScheduleStrings.noEvents,
                  style: TextStyle(color: _mutedText(context), fontSize: 14)),
            ),
      );
    }

    final days = TimeBlockHelper.splitTimeBlocksByDate(
      sorted,
      context,
      AppConfig.daySplitHour,
    );

    final children = <Widget>[];
    for (final day in days) {
      children.add(_LightDayHeader(group: day));
      final sections = TimeBlockHelper.groupEventsByFeatureSettings(day.events);
      for (final section in sections) {
        if (section.title.isNotEmpty) {
          children.add(_SectionHeader(label: section.title));
        }
        for (var i = 0; i < section.events.length; i++) {
          final e = section.events[i];
          final hasChildren = e.haveChildren();
          final isOpen = hasChildren && _openId == e.id;
          children.add(_EventRow(
            event: e,
            isOpen: isOpen,
            showEndTime: true,
            onTap: hasChildren
                ? () => setState(() => _openId = _openId == e.id ? null : e.id)
                : (widget.onEventPressed != null
                    ? () => widget.onEventPressed!(e.id)
                    : null),
            onChildTap: widget.onEventPressed,
          ));
          if (i < section.events.length - 1) {
            children.add(_RowDivider());
          }
        }
      }
    }

    return Container(
      color: ThemeConfig.whiteColor(context),
      child: ListView(
        padding: const EdgeInsets.only(top: 4, bottom: 24),
        children: children,
      ),
    );
  }
}

/// Left-aligned day header for the My-program list: bold weekday + smaller
/// muted "d. M." date, followed by a hairline rule that fills the row.
class _LightDayHeader extends StatelessWidget {
  final TimeBlockGroup group;
  const _LightDayHeader({required this.group});

  @override
  Widget build(BuildContext context) {
    final dt = group.dateTime;
    var weekday = group.title;
    if (weekday.isNotEmpty) {
      weekday = weekday[0].toUpperCase() + weekday.substring(1);
    }
    final dateLabel = dt != null ? DateFormat('d. M.').format(dt) : '';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 26, 20, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            weekday,
            style: TextStyle(
              fontSize: 23,
              fontWeight: FontWeight.w800,
              color: _strongText(context),
              letterSpacing: 0.2,
            ),
          ),
          if (dateLabel.isNotEmpty) ...[
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                dateLabel,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: _mutedText(context),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
          const SizedBox(width: 14),
          Expanded(
            child: Container(height: 1, color: _hairline(context)),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// One day's list of rows.
// ---------------------------------------------------------------------------
class _DayList extends StatelessWidget {
  final TimeBlockGroup day;
  final int? openId;
  final void Function(int eventId) onToggle;
  final void Function(int eventId)? onEventPressed;
  final bool Function()? showAddNewEventButton;
  final void Function(BuildContext context, List<TimeBlockGroup> groups,
      TimeBlockItem? parent)? onAddNewEvent;

  const _DayList({
    required this.day,
    required this.openId,
    required this.onToggle,
    required this.onEventPressed,
    required this.showAddNewEventButton,
    required this.onAddNewEvent,
  });

  @override
  Widget build(BuildContext context) {
    final events = day.events;
    final canAdd =
        FeatureService.isFeatureEnabled(FeatureConstants.mySchedule) &&
            (showAddNewEventButton?.call() ?? false) &&
            onAddNewEvent != null;

    if (events.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(ScheduleStrings.noEvents,
                  style: TextStyle(color: _mutedText(context), fontSize: 14)),
              if (canAdd) ...[
                const SizedBox(height: 12),
                _AddEventButton(
                  onPressed: () => onAddNewEvent!(context, [day], null),
                ),
              ],
            ],
          ),
        ),
      );
    }

    // Group by admin-configured rule (time-of-day or place) — sections with
    // empty titles flatten naturally.
    final sections = TimeBlockHelper.groupEventsByFeatureSettings(events);

    final children = <Widget>[];
    for (var s = 0; s < sections.length; s++) {
      final section = sections[s];
      if (section.title.isNotEmpty) {
        children.add(_SectionHeader(label: section.title));
      }
      for (var i = 0; i < section.events.length; i++) {
        final e = section.events[i];
        final hasChildren = e.haveChildren();
        final isOpen = hasChildren && openId == e.id;
        children.add(_EventRow(
          event: e,
          isOpen: isOpen,
          onTap: hasChildren
              ? () => onToggle(e.id)
              : (onEventPressed != null ? () => onEventPressed!(e.id) : null),
          onChildTap: onEventPressed,
        ));
        if (i < section.events.length - 1) {
          children.add(_RowDivider());
        }
      }
    }

    if (canAdd) {
      children.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: _AddEventButton(
            onPressed: () => onAddNewEvent!(context, [day], null),
          ),
        ),
      ));
    }

    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      children: children,
    );
  }
}

class _AddEventButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _AddEventButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final accent = _accent(context);
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(Icons.add_circle_outline, size: 20, color: accent),
      label: Text(
        ScheduleStrings.addToSchedule,
        style: TextStyle(
          color: accent,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
          side: BorderSide(color: accent.withValues(alpha: 0.25), width: 1),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 10),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          color: _mutedText(context),
          letterSpacing: 1.4,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _RowDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      color: _hairline(context),
      margin: const EdgeInsets.symmetric(horizontal: 20),
    );
  }
}

// ---------------------------------------------------------------------------
// One row: time | title | place | (chevron). Expanding reveals child cards.
// ---------------------------------------------------------------------------
class _EventRow extends StatelessWidget {
  final TimeBlockItem event;
  final bool isOpen;
  final VoidCallback? onTap;
  final void Function(int eventId)? onChildTap;
  final bool showEndTime;

  const _EventRow({
    required this.event,
    required this.isOpen,
    required this.onTap,
    required this.onChildTap,
    this.showEndTime = false,
  });

  @override
  Widget build(BuildContext context) {
    final hasChildren = event.haveChildren();
    final strong = _strongText(context);
    final muted = _mutedText(context);
    final now = TimeHelper.now();
    final isNow = !event.isCancelled &&
        event.startTime.isBefore(now) &&
        event.endTime.isAfter(now);

    // Variant C (My schedule): start over end in a narrow column — the end
    // time a step smaller and muted so the start keeps the visual weight.
    final showTimeRange = showEndTime && event.endTime.isAfter(event.startTime);
    final startStyle = TextStyle(
      color: strong,
      fontSize: 14,
      fontWeight: FontWeight.w500,
      fontFeatures: const [FontFeature.tabularFigures()],
      letterSpacing: 0.2,
    );
    final endStyle = TextStyle(
      color: muted,
      fontSize: 12.5,
      fontWeight: FontWeight.w500,
      fontFeatures: const [FontFeature.tabularFigures()],
      letterSpacing: 0.2,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Stack(
          children: [
            InkWell(
              onTap: onTap,
              hoverColor: _strongText(context).withValues(alpha: 0.03),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: showEndTime ? 64 : 56,
                      child: showTimeRange
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(DateFormat.Hm().format(event.startTime),
                                    style: startStyle),
                                const SizedBox(height: 2),
                                Text(DateFormat.Hm().format(event.endTime),
                                    style: endStyle),
                              ],
                            )
                          : Text(DateFormat.Hm().format(event.startTime),
                              style: startStyle),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (isNow)
                            const Padding(
                              padding: EdgeInsets.only(bottom: 4),
                              child: _RightNowBadge(),
                            ),
                          Text(
                            event.title.isNotEmpty
                                ? event.title
                                : (event.data?.toString() ?? ''),
                            style: TextStyle(
                              color: strong,
                              fontSize: 16,
                              height: 1.3,
                              fontWeight: FontWeight.w600,
                              decoration: event.isCancelled
                                  ? TextDecoration.lineThrough
                                  : TextDecoration.none,
                            ),
                          ),
                          // With the wider from–to time column (My schedule)
                          // the place moves under the title as a second line.
                          if (showEndTime && event.timeBlockPlace != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: _PlaceChip(
                                  label: event.timeBlockPlace!.title,
                                  maxWidth: double.infinity),
                            ),
                        ],
                      ),
                    ),
                    if (event.capacityLabel != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 10),
                        child: _CapacityChip(event: event),
                      ),
                    if (!showEndTime && event.timeBlockPlace != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 10),
                        child: _PlaceChip(label: event.timeBlockPlace!.title),
                      ),
                    if (hasChildren)
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: AnimatedRotation(
                          duration: const Duration(milliseconds: 180),
                          turns: isOpen ? 0.5 : 0.0,
                          child: Icon(Icons.keyboard_arrow_down,
                              color: muted, size: 22),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            // Left strip for the currently-running event — soft cue
            // without dominating the row; red to match the badge.
            if (isNow)
              Positioned(
                left: 0,
                top: 8,
                bottom: 8,
                child: Container(
                  width: 3,
                  decoration: BoxDecoration(
                    color: ThemeConfig.redColor(context),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
          ],
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox(width: double.infinity, height: 0),
          secondChild: _ChildrenList(
            children: event.children ?? const [],
            onChildTap: onChildTap,
          ),
          crossFadeState:
              isOpen ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 180),
          sizeCurve: Curves.easeInOut,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Sub-events rendered as cream-tinted cards.
// ---------------------------------------------------------------------------
class _ChildrenList extends StatelessWidget {
  final List<TimeBlockItem> children;
  final void Function(int eventId)? onChildTap;

  const _ChildrenList({
    required this.children,
    required this.onChildTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 18),
      child: Column(
        children: children
            .map((c) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _ChildCard(event: c, onTap: onChildTap),
                ))
            .toList(),
      ),
    );
  }
}

class _ChildCard extends StatelessWidget {
  final TimeBlockItem event;
  final void Function(int eventId)? onTap;

  const _ChildCard({required this.event, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final accent = _accent(context);
    final strong = _strongText(context);
    final muted = _mutedText(context);
    final bg = _cardBg(context);
    final border = _strongText(context).withValues(alpha: 0.10);
    final image = event.imageUrl;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap == null ? null : () => onTap!(event.id),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: border, width: 1),
          ),
          padding: const EdgeInsets.all(18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if ((event.eventType ?? '').isNotEmpty) ...[
                      Text(
                        event.eventType!.toUpperCase(),
                        style: TextStyle(
                          fontSize: 11,
                          color: muted,
                          letterSpacing: 1.3,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 6),
                    ],
                    Text(
                      event.title,
                      style: TextStyle(
                        color: strong,
                        fontSize: 15,
                        height: 1.3,
                        fontWeight: FontWeight.w700,
                        decoration: event.isCancelled
                            ? TextDecoration.lineThrough
                            : TextDecoration.none,
                      ),
                    ),
                    if (event.timeBlockPlace != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        event.timeBlockPlace!.title,
                        style: TextStyle(
                            color: accent,
                            fontSize: 13,
                            fontWeight: FontWeight.w600),
                      ),
                    ],
                    if (event.capacityLabel != null) ...[
                      const SizedBox(height: 10),
                      _CapacityChip(event: event),
                    ],
                  ],
                ),
              ),
              if (image != null && image.isNotEmpty) ...[
                const SizedBox(width: 14),
                ClipOval(
                  child: SizedBox(
                    width: 52,
                    height: 52,
                    child: CachedNetworkImage(
                      imageUrl: image,
                      fit: BoxFit.cover,
                      placeholder: (_, __) =>
                          Container(color: bg.withValues(alpha: 0.6)),
                      errorWidget: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Capacity indicator — display only (no inline action). Mirrors the advanced
// view's two-state visual: filled primary-colour pill with white text+icon
// when the current user is signed in, otherwise a plain grey "N/M + people"
// inline (no pill, no border).
// ---------------------------------------------------------------------------
class _CapacityChip extends StatelessWidget {
  final TimeBlockItem event;

  const _CapacityChip({required this.event});

  @override
  Widget build(BuildContext context) {
    final isSignedIn = event.isSignedIn();
    final text = event.capacityLabel;
    if (text == null) return const SizedBox.shrink();

    if (isSignedIn) {
      final bg = Theme.of(context).primaryColor;
      final fg = Theme.of(context).cardColor;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(text,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.0,
                    color: fg,
                    fontWeight: FontWeight.w500,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  )),
            ),
            const SizedBox(width: 4),
            Icon(Icons.people, size: 14, color: fg),
          ],
        ),
      );
    }

    final fg = Colors.grey;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(text,
              style: TextStyle(
                fontSize: 13,
                height: 1.0,
                color: fg,
                fontWeight: FontWeight.w500,
                fontFeatures: const [FontFeature.tabularFigures()],
              )),
        ),
        const SizedBox(width: 4),
        Icon(Icons.people, size: 14, color: fg),
      ],
    );
  }
}

/// Day tab strip — same layout as `AdvancedTimelineView` (chevron arrows on
/// the sides, 42 × 60 tabs with weekday + date + today dot, locale-aware
/// label fade between active/inactive). Indicator is a thin rounded
/// underline instead of a filled pill, all colours come from
/// `ThemeConfig` so seed changes propagate.
class _LightDayTabBar extends StatelessWidget {
  final List<String> weekdays;
  final List<TimeBlockGroup> days;

  const _LightDayTabBar({required this.weekdays, required this.days});

  @override
  Widget build(BuildContext context) {
    final controller = DefaultTabController.of(context);
    final animation = controller.animation!;
    final now = TimeHelper.now();
    final accent = _accent(context);
    final inactive = ThemeConfig.tabTextColor(context);
    final activeText = ThemeConfig.blackColor(context);

    const arrowTotalWidth = 96.0;

    return Container(
      padding: StylesConfig.tabHeaderPadding,
      // `tabHeaderColor` resolves to `Theme.scaffoldBackgroundColor`, which
      // for this theme is built from `seed2` and ends up warm-tinted — that
      // clashes with the brand blue + crisp white surface. Pin the tab
      // strip to `whiteColor` so it stays in the brand palette.
      decoration: BoxDecoration(
        color: ThemeConfig.whiteColor(context),
        border: StylesConfig.headerBorder(),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
              maxWidth: StylesConfig.formMaxWidth + arrowTotalWidth),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedBuilder(
                animation: animation,
                builder: (ctx, _) {
                  final canBack = controller.index > 0;
                  return IconButton(
                    icon: const Icon(Icons.chevron_left),
                    color: inactive,
                    disabledColor: inactive.withValues(alpha: 0.3),
                    onPressed: canBack
                        ? () => controller.animateTo(controller.index - 1)
                        : null,
                  );
                },
              ),
              Flexible(
                child: ConstrainedBox(
                  constraints:
                      const BoxConstraints(maxWidth: StylesConfig.formMaxWidth),
                  child: TabBar(
                    controller: controller,
                    isScrollable: true,
                    tabAlignment: TabAlignment.center,
                    indicator: _RoundedUnderlineIndicator(
                      color: accent,
                      width: 28,
                      height: 3,
                      bottomInset: 6,
                    ),
                    indicatorSize: TabBarIndicatorSize.tab,
                    labelColor: Colors.transparent,
                    unselectedLabelColor: Colors.transparent,
                    dividerColor: Colors.transparent,
                    splashFactory: NoSplash.splashFactory,
                    tabs: List.generate(days.length, (i) {
                      final group = days[i];
                      final dt = group.dateTime;
                      final isToday = dt != null &&
                          dt.year == now.year &&
                          dt.month == now.month &&
                          dt.day == now.day;
                      return SizedBox(
                        width: 42,
                        height: 60,
                        child: AnimatedBuilder(
                          animation: animation,
                          builder: (ctx, _) {
                            final diff =
                                (animation.value - i).abs().clamp(0.0, 1.0);
                            final factor = 1.0 - diff;
                            final labelColor =
                                Color.lerp(inactive, activeText, factor)!;
                            return Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  dt == null
                                      ? group.title
                                      : weekdays[dt.weekday - 1],
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                    color: labelColor,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                // Today swaps its date for a small "TODAY"
                                // label — always full-strength so the marker
                                // reads even when another day is selected.
                                if (isToday)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 5, vertical: 1.5),
                                    decoration: BoxDecoration(
                                      color: ThemeConfig.redColor(context),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      ScheduleStrings.today.toUpperCase(),
                                      style: const TextStyle(
                                        fontSize: 8.5,
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 1,
                                      ),
                                    ),
                                  )
                                else if (dt != null)
                                  Text(
                                    DateFormat.Md(context.locale.toString())
                                        .format(dt),
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: labelColor,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures()
                                      ],
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                      );
                    }),
                  ),
                ),
              ),
              AnimatedBuilder(
                animation: animation,
                builder: (ctx, _) {
                  final canFwd = controller.index < days.length - 1;
                  return IconButton(
                    icon: const Icon(Icons.chevron_right),
                    color: inactive,
                    disabledColor: inactive.withValues(alpha: 0.3),
                    onPressed: canFwd
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

/// Soft rounded "pill" underline for the day tabs. Drawn as a centred RRect
/// at the bottom of each tab — TabBar interpolates the indicator position
/// between tabs during swipes, so we get smooth animation for free.
class _RoundedUnderlineIndicator extends Decoration {
  final Color color;
  final double width;
  final double height;
  final double bottomInset;

  const _RoundedUnderlineIndicator({
    required this.color,
    required this.width,
    required this.height,
    this.bottomInset = 0,
  });

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) =>
      _RoundedUnderlinePainter(this);
}

class _RoundedUnderlinePainter extends BoxPainter {
  final _RoundedUnderlineIndicator spec;
  _RoundedUnderlinePainter(this.spec);

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration cfg) {
    final size = cfg.size ?? Size.zero;
    final w = spec.width.clamp(0, size.width).toDouble();
    final left = offset.dx + (size.width - w) / 2;
    final top = offset.dy + size.height - spec.height - spec.bottomInset;
    final rect = Rect.fromLTWH(left, top, w, spec.height);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(spec.height / 2)),
      Paint()..color = spec.color,
    );
  }
}

/// Place rendered as a subtle chip with a leading dot — keeps the place
/// visible without competing with the title weight, ellipsised at [maxWidth].
class _PlaceChip extends StatelessWidget {
  final String label;
  final double maxWidth;
  const _PlaceChip({required this.label, this.maxWidth = 140});

  @override
  Widget build(BuildContext context) {
    final muted = _mutedText(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 5,
          height: 5,
          decoration: BoxDecoration(
            color: muted.withValues(alpha: 0.7),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: muted,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.1,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Shared helpers.
// ---------------------------------------------------------------------------
/// Localised 3-letter weekday labels for `AdvancedTimelineView` (same source
/// the advanced view itself uses — DateFormat.E with the current locale).
List<String> _weekdays(BuildContext context) => List.generate(7, (i) {
      return DateFormat.E(context.locale.toString())
          .format(DateTime(2020, 1, 6 + i))
          .toUpperCase();
    });

/// Red "RIGHT NOW" pill marking a currently running event — same look as the
/// badge in the advanced schedule view.
class _RightNowBadge extends StatelessWidget {
  const _RightNowBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: ThemeConfig.redColor(context),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        ScheduleStrings.rightNow.toUpperCase(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

Color _strongText(BuildContext context) => ThemeConfig.blackColor(context);
Color _mutedText(BuildContext context) =>
    ThemeConfig.blackColor(context).withValues(alpha: 0.55);
Color _hairline(BuildContext context) =>
    ThemeConfig.blackColor(context).withValues(alpha: 0.07);

/// Brand accent used inside the white body — currently runs, sub-card place
/// names. Pulls from the theme's primary so the body stays inside the
/// organization palette instead of using the
/// generic red highlight.
Color _accent(BuildContext context) => ThemeConfig.darkColor(context);

/// Sub-card surface — picks the theme's slightly-darker-than-white background
/// (themed via the configured seed colours instead of a hard-coded hex).
Color _cardBg(BuildContext context) => ThemeConfig.whiteColorDarker(context);
