// day_list.dart
import 'package:flutter/material.dart';
import 'package:fstapp/components/activities/activities_component_strings.dart';
import 'package:fstapp/components/features/feature_constants.dart';
import 'package:fstapp/components/users/companion/companion_visibility.dart';
import 'package:fstapp/components/features/feature_service.dart';
// ignore: unused_import
import 'package:fstapp/components/features/schedule_feature.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/widgets/detail_dialog.dart';
import 'package:fstapp/services/web_styles_helper.dart';
import 'package:fstapp/styles/styles_config.dart';
import 'package:fstapp/theme_config.dart';
import 'package:fstapp/data_services/auth_service.dart';
import 'package:fstapp/services/time_helper.dart';
import 'package:fstapp/components/html/html_helper.dart';
import 'package:fstapp/widgets/buttons_helper.dart';
import 'package:fstapp/components/html/html_view.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'schedule_helper.dart';
import 'advanced_timeline_controller.dart';
import 'package:fstapp/app_config.dart';
import 'schedule_timeline.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/schedule/schedule_strings.dart';
import 'package:fstapp/components/users/user_strings.dart';

class DayList extends StatelessWidget {
  final TimeBlockGroup dayGroup;
  final AdvancedTimelineController controller;
  final int? openId;
  final void Function(int) onToggle;

  const DayList({
    super.key,
    required this.dayGroup,
    required this.controller,
    required this.onToggle,
    this.openId,
  });

  @override
  Widget build(BuildContext context) {
    final events = dayGroup.events;

    if (events.isEmpty && controller.emptyContent != null) {
      return controller.emptyContent!;
    }

    final List<TimeBlockGroup> groupedEvents =
        controller.customSplitter?.call(events, context) ??
            TimeBlockHelper.groupEventsByFeatureSettings(events);

    final children = <Widget>[];

    for (var group in groupedEvents) {
      if (group.title.isNotEmpty) {
        children.add(_section(group.title));
      }
      children.addAll(group.events.map((e) => _buildCard(e, context)));
    }

    if (FeatureService.isFeatureEnabled(FeatureConstants.mySchedule) &&
        (controller.showAddNewEventButton?.call() ?? false) &&
        controller.onAddNewEvent != null) {
      children.add(
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 28.0),
            child: TextButton.icon(
              onPressed: () =>
                  controller.onAddNewEvent?.call(context, [dayGroup], null),
              icon: const Icon(Icons.add_circle_outline, size: 24),
              label: Text(ScheduleStrings.addToSchedule),
              style: TextButton.styleFrom(
                foregroundColor: ThemeConfig.timelineAddNewEventColor(context),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
            ),
          ),
        ),
      );
    }

    return ListView(padding: dayListContentPadding, children: children);
  }

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Center(
            child: Text(t,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600))),
      );

  Widget _buildCard(TimeBlockItem e, BuildContext context) {
    return _EventCard(
      key: ValueKey(e.id),
      event: e,
      expanded: openId == e.id,
      controller: controller,
      onToggle: () => onToggle(e.id),
    );
  }
}

const double _kMinWidthForInlineButtons = 420.0;
const bool _kUsePastelBackground = false;
const EdgeInsets dayListContentPadding = EdgeInsets.fromLTRB(
  0,
  4,
  0,
  // The occasion Scaffold lays out this list above its NavigationBar.
  16,
);

bool isDark(context) => Theme.of(context).brightness == Brightness.dark;

class _EventCard extends StatefulWidget {
  final TimeBlockItem event;
  final bool expanded;
  final AdvancedTimelineController controller;
  final VoidCallback onToggle;

  const _EventCard({
    super.key,
    required this.event,
    required this.expanded,
    required this.controller,
    required this.onToggle,
  });

  @override
  _EventCardState createState() => _EventCardState();
}

class _EventCardState extends State<_EventCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _removeAnimationController;
  late Animation<double> _opacityAnimation;
  late Animation<double> _sizeAnimation;
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    _removeAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _opacityAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
        CurvedAnimation(
            parent: _removeAnimationController, curve: Curves.easeOut));
    _sizeAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
        CurvedAnimation(
            parent: _removeAnimationController, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _isDisposed = true;
    _removeAnimationController.dispose();
    super.dispose();
  }

  Future<void> _handleRemoveEvent(int eventId) async {
    if (!mounted) return;
    if (widget.controller.animateEventRemoval) {
      await _removeAnimationController.forward();
      if (!mounted || _isDisposed) return;
      await widget.controller.onRemoveFromProgramEvent?.call(eventId);
    } else {
      await widget.controller.onRemoveFromProgramEvent?.call(eventId);
    }
  }

  Future<void> _handleSignOutEvent(int eventId) async {
    if (!mounted) return;
    if (widget.controller.animateEventRemoval) {
      await _removeAnimationController.forward();
      if (!mounted || _isDisposed) return;
      await widget.controller.onSignOutEvent?.call(eventId);
    } else {
      await widget.controller.onSignOutEvent?.call(eventId);
    }
  }

  Future<void> _toggleInlineDetails() async {
    final shouldReveal = !widget.expanded;
    widget.onToggle();
    if (!shouldReveal) return;

    // AnimatedCrossFade needs one animation cycle before ensureVisible can
    // measure the expanded card. Without this, a final-row detail can open
    // underneath the persistent bottom navigation and appear to do nothing.
    await Future<void>.delayed(const Duration(milliseconds: 220));
    if (!mounted || !widget.expanded) return;
    await Scrollable.ensureVisible(
      context,
      alignment: 1,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  Color _toPastel(BuildContext context, Color color) {
    final HSLColor hslColor = HSLColor.fromColor(color);
    final double saturated =
        isDark(context) ? hslColor.saturation * 0.5 : hslColor.saturation * 0.9;
    final double lightened = isDark(context)
        ? hslColor.lightness * 0.5 + 0.0
        : hslColor.lightness * 0.35 + 0.5;
    return hslColor
        .withSaturation(saturated.clamp(0.0, 1.0))
        .withLightness(lightened.clamp(0.0, 1.0))
        .toColor();
  }

  bool _shouldShowScanButton(BuildContext context, TimeBlockItem event,
      AdvancedTimelineController controller) {
    if (event.isCancelled) return false;
    return AuthService.isLoggedIn() &&
        event.isSupportingSignIn() &&
        (controller.isUserApprover?.call() ?? false) &&
        FeatureService.isFeatureEnabled(FeatureConstants.entryCode);
  }

  bool _shouldShowCompanionButton(BuildContext context, TimeBlockItem event,
      AdvancedTimelineController controller) {
    return canShowCompanionAttendanceAction(
      isLoggedIn: AuthService.isLoggedIn(),
      eventSupportsSignIn: event.isSupportingSignIn(),
      featureEnabled:
          FeatureService.isFeatureEnabled(FeatureConstants.companions),
      hasOwnedCompanions: controller.hasOwnedCompanions,
    );
  }

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
    final expanded = widget.expanded;
    final controller = widget.controller;

    final bool isActivity = event.isActivity;

    const stripeW = 6.0, stripeH = 58.0;
    final Color eventSpecificColor =
        ThemeConfig.eventTypeToColor(context, event.eventType);
    final Color effectiveBaseColor =
        isActivity ? Theme.of(context).primaryColor : eventSpecificColor;
    final cardColor = _kUsePastelBackground
        ? _toPastel(context, effectiveBaseColor)
        : Theme.of(context).cardColor;

    Widget stripeWidget;
    if (event.isCancelled) {
      stripeWidget =
          Container(width: stripeW, height: stripeH, color: Colors.grey);
    } else if (isActivity) {
      stripeWidget = Container(
          width: stripeW,
          height: stripeH,
          color: Theme.of(context).primaryColor);
    } else if (!_kUsePastelBackground) {
      stripeWidget =
          Container(width: stripeW, height: stripeH, color: eventSpecificColor);
    } else {
      stripeWidget = const SizedBox.shrink();
    }

    final imageUrl = event.imageUrl;
    final capEvent = event.maxParticipants > 0 && !isActivity;
    final screenWidth = MediaQuery.of(context).size.width;
    final showInlineButtons = screenWidth >= _kMinWidthForInlineButtons;
    final hasDescription = !HtmlHelper.isHtmlEmptyOrNull(event.description);
    final hasPlace = event.timeBlockPlace?.title != null;
    final isEditor = RightsService.isEditor();
    final haveChildren = event.haveChildren();

    final hasDetails = hasDescription || hasPlace || haveChildren;

    // An event is interactive if it has details or special actions.
    final bool isInteractive;
    if (isActivity) {
      isInteractive = hasDetails;
    } else {
      isInteractive = hasDetails || isEditor || event.isSupportingSignIn();
    }

    // It can expand inline if it's interactive and the description isn't too long.
    final bool canExpandInline;
    if (isActivity) {
      canExpandInline = isInteractive &&
          !HtmlHelper.isHtmlLong(event.description, lengthThreshold: 250);
    } else {
      canExpandInline =
          isInteractive && !HtmlHelper.isHtmlLong(event.description);
    }

    // A chevron is shown if it's interactive but can't expand inline (implying a detail page/dialog).
    final bool showChevronRight =
        isInteractive && !canExpandInline && controller.onEventPressed != null;

    final now = TimeHelper.now();
    final bool isCurrentEvent = !event.isCancelled &&
        event.startTime.isBefore(now) &&
        event.endTime.isAfter(now);

    final buttonTextColor = _kUsePastelBackground
        ? (isDark(context) ? Colors.white : Colors.black87)
        : ThemeConfig.blackColor(context).withOpacityUniversal(context, 0.7);

    final selectedColor = _kUsePastelBackground
        ? (isDark(context) ? Colors.white : Colors.black87)
        : Theme.of(context).primaryColor;

    final unselectedColor = _kUsePastelBackground
        ? (isDark(context) ? Colors.white70 : Colors.black54)
        : Colors.grey;

    final signInSignOutButtonBorderColor = _kUsePastelBackground
        ? (isDark(context) ? Colors.white30 : Colors.black26)
        : ThemeConfig.blackColor(context).withOpacityUniversal(context, 0.3);

    final Color eventPastelColorForText = _kUsePastelBackground
        ? _toPastel(context, eventSpecificColor)
        : cardColor;
    final capTextColor =
        event.isSignedIn() ? eventPastelColorForText : unselectedColor;

    Widget buildSharedContent() {
      final eventGroups = haveChildren
          ? TimeBlockHelper.splitTimeBlockByPlace(event.children!)
          : <TimeBlockGroup>[];

      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Builder(builder: (context) {
            // Use Builder to get context for selectedColor if needed here
            List<Widget> actionButtons = [];

            // Companion Button
            if (_shouldShowCompanionButton(context, event, controller)) {
              actionButtons.add(TextButton.icon(
                onPressed: () =>
                    controller.onCompanionButtonPressed?.call(context, event),
                icon:
                    Icon(Icons.people_outline, size: 14, color: selectedColor),
                label: Text(CommonStrings.companions,
                    style: TextStyle(color: selectedColor)),
                style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 4)),
              ));
            }

            // Scan Button
            if (_shouldShowScanButton(context, event, controller)) {
              actionButtons.add(TextButton.icon(
                onPressed: () =>
                    controller.onScanButtonPressed?.call(context, event.id),
                icon:
                    Icon(Icons.qr_code_scanner, size: 14, color: selectedColor),
                label: Text(ScheduleStrings.scan,
                    style: TextStyle(color: selectedColor)),
                style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 4)),
              ));
            }

            // Edit Button
            if (isEditor && !isActivity) {
              actionButtons.add(TextButton.icon(
                onPressed: () =>
                    controller.onEditEvent?.call(context, event.id),
                icon: Icon(Icons.edit, size: 14, color: selectedColor),
                label: Text(CommonStrings.edit,
                    style: TextStyle(color: selectedColor)),
                style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 4)),
              ));
            }
            return Row(
              children: [
                if (event.timeBlockPlace != null)
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => controller.onPlaceTap
                            ?.call(context, event.timeBlockPlace!),
                        icon: Icon(Icons.place, size: 14, color: selectedColor),
                        label: Text(
                          event.timeBlockPlace!.title,
                          style: TextStyle(color: selectedColor),
                          overflow: TextOverflow.ellipsis,
                        ),
                        style: TextButton.styleFrom(padding: EdgeInsets.zero),
                      ),
                    ),
                  ),
                if (event.timeBlockPlace == null && actionButtons.isNotEmpty)
                  const Spacer(), // Provides space if no place, pushing actions to right

                if (actionButtons.isNotEmpty)
                  Wrap(
                    spacing:
                        8.0, // Horizontal spacing between buttons in the wrap
                    alignment: WrapAlignment.end,
                    children: actionButtons,
                  )
              ],
            );
          }),
          const SizedBox(height: 8),
          if (!event.isCancelled &&
              !isActivity &&
              capEvent &&
              AuthService.isLoggedIn() &&
              (event.isSignedIn() ||
                  (event.participants != null &&
                      event.participants! < event.maxParticipants)) &&
              !showInlineButtons) ...[
            Center(
              child: event.isSignedIn()
                  ? OutlinedButton(
                      onPressed: () => _handleSignOutEvent(event.id),
                      style: _signButtonStyle(
                          buttonTextColor, signInSignOutButtonBorderColor),
                      child: Text(UserStrings.signOut),
                    )
                  : OutlinedButton(
                      onPressed: () {
                        controller.onSignInEvent!(event.id);
                      },
                      style: _signButtonStyle(
                          buttonTextColor, signInSignOutButtonBorderColor),
                      child: Text(UserStrings.signIn),
                    ),
            ),
            const SizedBox(height: 8),
          ],
          if (!event.isCancelled &&
              event.isSupportingSignIn() &&
              !AuthService.isLoggedIn()) ...[
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: HtmlView(
                html: '''
                                <div style="color: ${ThemeConfig.redColor(context).toHexString()}; text-align: center;">
                                  <div>${UserStrings.accountRequiredToJoin}</div>
                                  <a href="${AppConfig.webLink}/login" style="color: ${ThemeConfig.redColor(context).toHexString()};">
                                    ${UserStrings.clickToSignIn}
                                  </a>
                                </div>
                              ''',
                isSelectable: true,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (haveChildren ||
              (controller.showAddNewEventButton?.call() ?? false) &&
                  !isActivity)
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 0, 0, 24),
              child: ScheduleTimeline(
                eventGroups: eventGroups,
                onEventPressed: controller.onEventPressed,
                showAddNewEventButton: () =>
                    ((controller.showAddNewEventButton?.call() ?? false) &&
                        !isActivity),
                onAddNewEvent: controller.onAddNewEvent,
                parentEvent: event,
                nodePosition: 0.35,
                isGroupTitleShown: eventGroups.length > 1,
              ),
            ),
          if (hasDescription)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child:
                  HtmlView(html: event.description ?? "", isSelectable: true),
            ),
        ],
      );
    }

    Widget inlineActionSection = const SizedBox.shrink();
    if (event.isCancelled && !event.isInMySchedule && !event.isSignedIn()) {
      inlineActionSection = Padding(
        padding: const EdgeInsets.only(right: 8.0),
        child: Text(
          CommonStrings.cancelled.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            color: ThemeConfig.redColor(context),
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    } else if (isActivity) {
      final Color activityBadgeBackgroundColor = selectedColor;
      final Color activityBadgeForegroundColor = eventPastelColorForText;

      inlineActionSection = Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: activityBadgeBackgroundColor,
          borderRadius: BorderRadius.circular(12.0),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              ActivitiesComponentStrings.activity,
              style: TextStyle(
                  fontSize: 13,
                  color: activityBadgeForegroundColor,
                  fontWeight: FontWeight.w500),
            ),
            const SizedBox(width: 5),
            Icon(Icons.groups, size: 16, color: activityBadgeForegroundColor),
          ],
        ),
      );
    } else if (capEvent) {
      final capBackgroundColor =
          event.isSignedIn() ? selectedColor : unselectedColor;

      inlineActionSection = Column(mainAxisSize: MainAxisSize.min, children: [
        if (event.capacityLabel != null)
          Row(
            children: [
              if (event.isSignedIn())
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: selectedColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Text(
                        event.capacityLabel!,
                        style: TextStyle(fontSize: 13, color: capTextColor),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.people, size: 14, color: capTextColor),
                    ],
                  ),
                )
              else
                Row(
                  children: [
                    Text(event.capacityLabel!,
                        style:
                            TextStyle(fontSize: 13, color: capBackgroundColor)),
                    const SizedBox(width: 4),
                    Icon(Icons.people, size: 14, color: capBackgroundColor),
                  ],
                ),
            ],
          ),
        if (AuthService.isLoggedIn() &&
            (event.isSignedIn() ||
                (event.participants != null &&
                    event.participants! < event.maxParticipants)) &&
            showInlineButtons) ...[
          const SizedBox(height: 4),
          event.isSignedIn()
              ? OutlinedButton(
                  onPressed: () => _handleSignOutEvent(event.id),
                  style: _signButtonStyle(
                      buttonTextColor, signInSignOutButtonBorderColor),
                  child: Text(UserStrings.signOut),
                )
              : OutlinedButton(
                  onPressed: () {
                    controller.onSignInEvent!(event.id);
                  },
                  style: _signButtonStyle(
                      buttonTextColor, signInSignOutButtonBorderColor),
                  child: Text(UserStrings.signIn),
                ),
        ],
      ]);
    } else if (event.canSaveToMySchedule()) {
      inlineActionSection = Row(
        children: ButtonsHelper.getAddToMyProgramButton(
          !event.isInMySchedule,
          () async => await controller.onAddToProgramEvent!(event.id),
          () async => await _handleRemoveEvent(event.id),
          selectedColor,
          unselectedColor,
        ),
      );
    }

    Widget cardContent = Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: StylesConfig.formMaxWidth),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: Card(
            color: event.isCancelled
                ? Theme.of(context).disabledColor.withOpacity(0.1)
                : cardColor,
            elevation: 0,
            shape: RoundedRectangleBorder(
                borderRadius:
                    BorderRadius.circular(StylesConfig.eventItemRoundness)),
            clipBehavior: Clip.hardEdge,
            child: Column(children: [
              InkWell(
                onTap: !isInteractive
                    ? null
                    : () {
                        if (canExpandInline) {
                          _toggleInlineDetails();
                        } else {
                          if (isActivity) {
                            showDialog(
                              context: context,
                              builder: (BuildContext context) {
                                return DetailDialog(
                                  title:
                                      "${event.title} ${event.durationTimeString()}",
                                  customContentWidget: buildSharedContent(),
                                );
                              },
                            );
                          } else if (controller.onEventPressed != null) {
                            controller.onEventPressed?.call(event.id);
                          }
                        }
                      },
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                  child: Row(children: [
                    stripeWidget,
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              if (event.isCancelled)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  margin: const EdgeInsets.only(right: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.grey[700],
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    CommonStrings.cancelled.toUpperCase(),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                )
                              else if (isCurrentEvent)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  margin: const EdgeInsets.only(right: 6),
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
                                ),
                              Text(event.durationTimeString(),
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: event.isCancelled
                                        ? Theme.of(context).disabledColor
                                        : ThemeConfig.blackColor(context)
                                            .withOpacityUniversal(context, 0.8),
                                  )),
                            ],
                          ),
                          Text(event.title,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                decoration: event.isCancelled
                                    ? TextDecoration.lineThrough
                                    : TextDecoration.none,
                                color: event.isCancelled
                                    ? Theme.of(context).disabledColor
                                    : null,
                              )),
                          if (!expanded)
                            (hasPlace
                                ? Text(
                                    event.timeBlockPlace!.title,
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                    style: TextStyle(
                                        color: event.isCancelled
                                            ? Theme.of(context).disabledColor
                                            : ThemeConfig.blackColor(context)
                                                .withOpacityUniversal(
                                                    context, 0.96),
                                        fontSize: 13),
                                  )
                                : const SizedBox(height: 16.0)),
                        ],
                      ),
                    ),
                    if (imageUrl != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 8.0),
                        child: Opacity(
                          opacity: event.isCancelled ? 0.5 : 1.0,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(
                                StylesConfig.imageRoundness),
                            clipBehavior: Clip.antiAlias,
                            child: SizedBox(
                              width: 58.0,
                              height: 58.0,
                              child: CachedNetworkImage(
                                  imageUrl: imageUrl, fit: BoxFit.cover),
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(width: 4),
                    inlineActionSection,
                    const SizedBox(width: 4),
                    if (canExpandInline)
                      Icon(
                        expanded ? Icons.expand_less : Icons.expand_more,
                        size: 20,
                        color: unselectedColor,
                      )
                    else if (showChevronRight)
                      Icon(Icons.chevron_right,
                          size: 20, color: unselectedColor)
                    else
                      const SizedBox(width: 20.0),
                  ]),
                ),
              ),
              if (canExpandInline)
                AnimatedCrossFade(
                  firstChild: const SizedBox.shrink(),
                  secondChild: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                    child: buildSharedContent(),
                  ),
                  crossFadeState: expanded && canExpandInline
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
                  duration: const Duration(milliseconds: 200),
                  firstCurve: Curves.easeOut,
                  secondCurve: Curves.easeIn,
                  sizeCurve: Curves.easeInOut,
                ),
            ]),
          ),
        ),
      ),
    );

    return SizeTransition(
      sizeFactor: _sizeAnimation,
      axisAlignment: -1.0,
      child: FadeTransition(opacity: _opacityAnimation, child: cardContent),
    );
  }
}

ButtonStyle _signButtonStyle(Color fg, Color bd) => OutlinedButton.styleFrom(
      foregroundColor: fg,
      side: BorderSide(color: bd),
      textStyle: const TextStyle(fontSize: 13),
      shape: RoundedRectangleBorder(
        borderRadius:
            BorderRadius.circular(StylesConfig.signInSignOutRoundness),
      ),
    );
