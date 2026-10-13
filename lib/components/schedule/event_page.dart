import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fstapp/app_router.gr.dart';
import 'package:fstapp/components/features/schedule_feature.dart';
import 'package:fstapp/router_service.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/components/timeline/light_timeline_view.dart';
import 'package:fstapp/components/schedule/event_model.dart';
import 'package:fstapp/components/schedule/event_participants_access.dart';
import 'package:fstapp/components/schedule/event_page_theme.dart';
import 'package:fstapp/components/schedule/saved_program_ui.dart';
import 'package:fstapp/components/schedule/schedule_strings.dart';
import 'package:fstapp/components/users/user_strings.dart';
import 'package:fstapp/components/groups/user_group_info_model.dart';
import 'package:fstapp/data_services/auth_service.dart';
import 'package:fstapp/components/users/companion/db_companions.dart';
import 'package:fstapp/components/users/companion/companion_visibility.dart';
import 'package:fstapp/data_services/data_extensions.dart';
import 'package:fstapp/components/schedule/db_events.dart';
import 'package:fstapp/components/groups/db_groups.dart';
import 'package:fstapp/components/users/db_users.dart';
import 'package:fstapp/data_services/offline_data_service.dart';
import 'package:fstapp/data_services/client_sync/client_sync_runtime.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/components/users/companion/companion_model.dart';
import 'package:fstapp/components/users/user_info_model.dart';
import 'package:fstapp/components/features/feature_constants.dart';
import 'package:fstapp/components/features/feature_service.dart';
import 'package:fstapp/components/event_feedback/event_feedback_widget.dart';
import 'package:fstapp/components/occasion/add_new_event_dialog.dart';
import 'package:fstapp/components/schedule/event_edit_page.dart';
import 'package:fstapp/components/html/rich_html_editor_controller.dart';
import 'package:fstapp/components/html/editable_html_field.dart';
import 'package:fstapp/services/dialog_helper.dart';
import 'package:fstapp/services/time_helper.dart';
import 'package:fstapp/services/connectivity_service.dart';
import 'package:fstapp/components/timeline/schedule_helper.dart';
import 'package:fstapp/services/web_styles_helper.dart';
import 'package:fstapp/services/toast_helper.dart';
import 'package:fstapp/theme_config.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/users/companion/companion_dialog.dart';
import 'package:fstapp/components/html/html_view.dart';
import 'package:fstapp/widgets/buttons_helper.dart';
import 'package:fstapp/widgets/navigate_back_button.dart';
import 'package:fstapp/styles/styles_config.dart';
import 'package:fstapp/components/images/zoomable_image/zoomable_image.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:fstapp/components/images/image_url_helper.dart';
import 'package:fstapp/components/speakers/db_speakers.dart';
import 'package:fstapp/components/speakers/speakers_bundle.dart';
import 'package:fstapp/components/speakers/speaker_model.dart';
import 'package:fstapp/components/speakers/speaker_medallion.dart';
import 'package:fstapp/components/speakers/counseling_page.dart';
import 'package:fstapp/components/speakers/counseling_picker.dart';
import 'package:fstapp/database_tables/tb.dart';
import '../map/map_navigation.dart';
import 'event_metadata_item.dart';
import '../map/public_map_session.dart';

@RoutePage()
class EventPage extends StatefulWidget {
  static const ROUTE = "event";
  int? id;

  EventPage({@pathParam this.id, super.key});

  @override
  _EventPageState createState() => _EventPageState();
}

class _EventPageState extends State<EventPage> {
  final _htmlSave = HtmlSaveCoordinator();
  final List<TimeBlockItem> _childDots = [];
  EventModel? _event;
  SpeakersBundle? _speakersBundle;
  UserGroupInfoModel? _groupInfoModel;

  List<UserInfoModel> _participants = [];
  List<UserInfoModel> _queriedParticipants = [];
  List<CompanionModel> _companions = [];

  bool isLoadingEvent = true;
  bool _isUpdatingSavedProgram = false;
  int _savedProgramMutationRevision = 0;
  final ValueNotifier<bool> _canSaveSavedProgram = ValueNotifier(false);

  final ScrollController _scrollController = ScrollController();
  bool _blockScroll = false;

  /// Measured (exact) height of the expanded header content, used as the
  /// SliverAppBar's expandedHeight so it never clips nor overflows.
  final GlobalKey _headerMeasureKey = GlobalKey();
  double? _measuredExpandedHeight;

  /// Height of the pinned (fully collapsed) header bar.
  static const double _collapsedHeaderHeight = 78;

  _EventPageState();

  @override
  void initState() {
    super.initState();
    // Web fonts settle after first paint; remeasure the header when they do so
    // its (taller) real height replaces the fallback-font estimate.
    PaintingBinding.instance.systemFonts.addListener(_scheduleHeaderMeasure);
    ClientSyncRuntime.projectionEpoch.addListener(_onProjectionChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    loadData(widget.id!);
  }

  @override
  void didUpdateWidget(covariant EventPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Same-route navigation (event/A → event/B, e.g. the counseling-slot →
    // entry-event redirect) reuses this State; didChangeDependencies does NOT
    // fire again, so reload explicitly when the id changes.
    if (oldWidget.id != widget.id && widget.id != null) {
      setState(() {
        isLoadingEvent = true;
        _event = null;
      });
      loadData(widget.id!);
    }
  }

  @override
  void dispose() {
    _htmlSave.dispose();
    PaintingBinding.instance.systemFonts.removeListener(_scheduleHeaderMeasure);
    ClientSyncRuntime.projectionEpoch.removeListener(_onProjectionChanged);
    _canSaveSavedProgram.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onProjectionChanged() {
    if (mounted && ClientSyncRuntime.isV1Selected) {
      unawaited(_reloadCompanions());
    }
  }

  Future<void> _reloadCompanions() async {
    final companions = AuthService.isLoggedIn()
        ? await DbCompanions.getAllCompanions()
        : const <CompanionModel>[];
    if (!mounted) return;
    setState(() => _companions = companions);
  }

  void _scheduleHeaderMeasure() {
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _measureHeader());
    }
  }

  void _onPinchStart() {
    if (!_blockScroll && mounted) setState(() => _blockScroll = true);
  }

  void _onPinchEnd() {
    if (mounted) setState(() => _blockScroll = false);
  }

  @override
  Widget build(BuildContext context) => HtmlEditingScope(
      coordinator: _htmlSave, child: _buildHtmlParent(context));

  Widget _buildHtmlParent(BuildContext context) {
    if (_event == null) {
      return Scaffold(
        appBar: AppBar(leading: const ScheduleBackButton()),
        body: Center(
          child: isLoadingEvent
              ? const CircularProgressIndicator()
              : Text(ScheduleStrings.noEvents),
        ),
      );
    }
    final bool isEventCancelled = _event?.isCancelled ?? false;
    final scheduleFeature =
        FeatureService.getFeatureDetails(FeatureConstants.schedule);
    final bool childrenScheduleIsEnabled =
        scheduleFeature is ScheduleFeature && scheduleFeature.enableChildren;
    final bool showSubScheduleArea = _event?.isGroupEvent == false &&
        (_event?.childEvents.isNotEmpty == true ||
            (RightsService.isEditor() && childrenScheduleIsEnabled));

    final EventType? headerEventType = _currentEventType();
    final Color headerFg = _headerForeground();
    final double expandedContentHeight =
        _measuredExpandedHeight ?? _expandedHeaderHeight(context);
    final double expandedHeight = EventPageTheme.sliverExpandedHeight(
      expandedContentHeight,
      MediaQuery.paddingOf(context).top,
    );
    final bool showAddButton = _showAddButton(isEventCancelled);
    final bool canViewParticipants = EventParticipantsAccess.canView(
      isEditorView: RightsService.isEditorView(),
      isEditor: RightsService.isEditor(),
      isAdmin: RightsService.isAdmin(),
    );
    final onPinchStart = _onPinchStart;
    final onPinchEnd = _onPinchEnd;

    WidgetsBinding.instance.addPostFrameCallback((_) => _measureHeader());

    return Scaffold(
      backgroundColor: ThemeConfig.whiteColor(context),
      body: Stack(
        children: [
          PinchScrollScope(
            onPinchStart: _onPinchStart,
            onPinchEnd: _onPinchEnd,
            child: CustomScrollView(
              controller: _scrollController,
              physics: _blockScroll
                  ? const NeverScrollableScrollPhysics()
                  : const BouncingScrollPhysics(),
              slivers: [
                SliverAppBar(
                  pinned: true,
                  automaticallyImplyLeading: false,
                  backgroundColor: _collapsedTint(),
                  surfaceTintColor: Colors.transparent,
                  elevation: 1,
                  expandedHeight: expandedHeight,
                  collapsedHeight: _collapsedHeaderHeight,
                  flexibleSpace:
                      _buildFlexibleHeader(context, expandedContentHeight),
                ),
                SliverToBoxAdapter(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints:
                          BoxConstraints(maxWidth: StylesConfig.appMaxWidth),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Small breathing room; a touch more when the "+" overlaps here.
                          SizedBox(height: showAddButton ? 20 : 6),
                          if (isEventCancelled) // Using local variable for clarity
                            Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(8.0, 8.0, 8.0, 0),
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 10),
                                decoration: BoxDecoration(
                                  color: ThemeConfig.grey700(context),
                                  borderRadius: BorderRadius.circular(
                                      StylesConfig.commonRoundness),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.cancel_outlined,
                                        color: ThemeConfig.whiteColor(context),
                                        size: 22),
                                    const SizedBox(width: 10),
                                    Text(
                                      CommonStrings.cancelled.toUpperCase(),
                                      style: TextStyle(
                                        color: ThemeConfig.whiteColor(context),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          _buildActionButtons(context, isEventCancelled),
                          Visibility(
                            visible:
                                EventModel.isEventSupportingSignIn(_event) &&
                                    !AuthService.isLoggedIn() &&
                                    !isEventCancelled, // Hide if cancelled
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: HtmlView(
                                html: '''
                      <div style="color: ${ThemeConfig.redColor(context).toHexString()}; text-align: center;">
                        <div>${ScheduleStrings.accountRequiredToJoin}</div>
                        <a href="${AppConfig.webLink}/login" style="color: ${ThemeConfig.redColor(context).toHexString()};">
                          ${ScheduleStrings.clickHereToSignIn}
                        </a>
                      </div>
                    ''',
                                isSelectable: true,
                                fontSize: 16,
                                twoFingersOn: onPinchStart,
                                twoFingersOff: onPinchEnd,
                              ),
                            ),
                          ),
                          Visibility(
                              visible: EventModel.isEventFull(_event) &&
                                  AuthService.isLoggedIn() &&
                                  !isEventCancelled,
                              child: Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Text(
                                  ScheduleStrings.eventFullyBooked,
                                ),
                              )),
                          // Counseling rozcestník: the area picker + booking flow is
                          // shown inline, ABOVE the description, on the entry event.
                          if (_event != null &&
                              _event!.isCounselingEntry &&
                              FeatureService.isCounselingEnabled())
                            Padding(
                              padding: const EdgeInsets.all(16.0),
                              // Scope the flow to this rozcestník event's day.
                              child: CounselingPicker(day: _event!.startTime),
                            ),
                          Visibility(
                            visible: _event != null &&
                                (_event?.description != null ||
                                    (RightsService.isGroupAdmin() &&
                                        (_event!.isGroupEvent ?? false))),
                            child: Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: _buildGroupDescription(
                                  onPinchStart, onPinchEnd),
                            ),
                          ),
                          _buildSpeakersSection(
                              context, onPinchStart, onPinchEnd),
                          if (_event != null &&
                              _event!.id != null &&
                              FeatureService.isFeatureEnabled(
                                  FeatureConstants.eventFeedback) &&
                              (_event!.data?[FeatureConstants.feedbackEnabled]
                                      ?.toString() ==
                                  'true'))
                            EventFeedbackWidget(
                              eventId: _event!.id!,
                              isOpen:
                                  TimeHelper.now().isAfter(_event!.startTime),
                              isEditorPreview: RightsService.isEditor(),
                              requiresSignIn:
                                  EventModel.isEventSupportingSignIn(_event),
                              isParticipant: _event!.isSignedIn == true,
                            ),
                          if (showSubScheduleArea)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: LightSubprogramList(
                                events: _childDots,
                                onEventPressed: _eventPressed,
                                showAddNewEventButton: () =>
                                    RightsService.isEditor() &&
                                    childrenScheduleIsEnabled,
                                onAddNewEvent: (context, p, parent) =>
                                    AddNewEventDialog.showAddEventDialog(
                                            context,
                                            p,
                                            TimeBlockItem.fromEventModelAsChild(
                                                _event!))
                                        .then((_) => loadData(_event!.id!)),
                              ),
                            ),
                          Visibility(
                            visible: canViewParticipants &&
                                _event?.maxParticipants != null,
                            child: ExpansionTile(
                              title: Row(children: [
                                IconButton(
                                    onPressed: () async {
                                      await Clipboard.setData(ClipboardData(
                                          text: _participants
                                              .map((e) => e.toFullNameString())
                                              .join("\n")));
                                      ToastHelper.Show(context,
                                          ScheduleStrings.participantsCopied);
                                    },
                                    icon: const Icon(Icons.copy)),
                                Text("${CommonStrings.participants}:")
                              ]),
                              children: [
                                ListView.builder(
                                    shrinkWrap: true,
                                    padding: const EdgeInsets.all(8),
                                    physics:
                                        const NeverScrollableScrollPhysics(),
                                    itemCount: _participants.length,
                                    itemBuilder:
                                        (BuildContext context, int index) {
                                      return Padding(
                                        padding: const EdgeInsets.all(8.0),
                                        child: Row(
                                          children: [
                                            if (RightsService.isEditor())
                                              IconButton(
                                                  onPressed: () => signOutOther(
                                                      _participants[index]),
                                                  icon: const Icon(Icons
                                                      .remove_circle_outline)),
                                            Text("${_participants[index]}"),
                                          ],
                                        ),
                                      );
                                    })
                              ],
                            ),
                          ),
                          Visibility(
                            visible: _groupInfoModel != null,
                            child: ExpansionTile(
                              title: Text(_groupInfoModel?.title ?? ""),
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Padding(
                                      padding: EdgeInsets.all(8.0),
                                    ),
                                    Visibility(
                                      visible: _groupInfoModel?.participants
                                              ?.firstWhereOrNull(
                                                  (p) => p.isAdmin!) !=
                                          null,
                                      child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 8.0, horizontal: 16),
                                          child: Text(
                                              "${ScheduleStrings.moderator}: ${_groupInfoModel?.participants?.firstWhereOrNull((p) => p.isAdmin!)?.userInfo?.name ?? ""}",
                                              style: StylesConfig
                                                  .normalTextStyle)),
                                    ),
                                    Padding(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 8.0, horizontal: 16),
                                        child: Text(
                                            "${CommonStrings.participants}:",
                                            style:
                                                StylesConfig.normalTextStyle)),
                                    ListView.builder(
                                        shrinkWrap: true,
                                        padding: const EdgeInsets.all(8),
                                        physics:
                                            const NeverScrollableScrollPhysics(),
                                        itemCount: _groupInfoModel
                                                ?.participants!.length ??
                                            0,
                                        itemBuilder:
                                            (BuildContext context, int index) {
                                          return Padding(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 16.0,
                                                vertical: 4.0),
                                            child: Text(
                                                "${_groupInfoModel?.participants!.toList()[index].userInfo?.name}",
                                                style: StylesConfig
                                                    .normalTextStyle),
                                          );
                                        })
                                  ],
                                )
                              ],
                            ),
                          )
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (showAddButton) _buildFabOverlay(context, expandedContentHeight),
          // Offstage twin of the expanded header, measured to size the app bar.
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: Offstage(
              offstage: true,
              child: KeyedSubtree(
                key: _headerMeasureKey,
                child: _buildExpandedHeaderContent(
                    context, headerFg, headerEventType),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _measureHeader() {
    final BuildContext? ctx = _headerMeasureKey.currentContext;
    final Size? size = ctx?.size;
    if (size == null) return;
    final double h = size.height;
    if (h > 0 &&
        (_measuredExpandedHeight == null ||
            (_measuredExpandedHeight! - h).abs() > 0.5)) {
      if (mounted) setState(() => _measuredExpandedHeight = h);
    }
  }

  /// Resolves the configured [EventType] (code, title, color) for the current
  /// event, or null when the event has no matching type (default styling).
  EventType? _currentEventType() {
    final type = _event?.type;
    if (type == null || type.isEmpty) return null;
    final feature = FeatureService.getFeatureDetails(FeatureConstants.schedule);
    if (feature is ScheduleFeature) {
      return feature.eventTypes.firstWhereOrNull((et) => et.code == type);
    }
    return null;
  }

  /// Foreground (text / icon) color for the gradient header. Uses the event
  /// type's base color lightness so light banners (e.g. concerts) get dark
  /// content while dark banners get white content.
  /// The per-event header background image URL (stored in `data.header_image`),
  /// or null when the event has none and the computed gradient is used instead.
  String? _headerImageUrl() {
    final dynamic url = _event?.data?[Tb.events.dataHeaderImage];
    if (url is String && url.isNotEmpty) return url;
    return null;
  }

  Color _headerForeground() {
    // Image banners always carry a dark scrim, so their content is white.
    if (_headerImageUrl() != null) return Colors.white;
    final Color base = ThemeConfig.eventTypeToColor(context, _event?.type);
    return HSLColor.fromColor(base).lightness > 0.6
        ? Colors.black
        : Colors.white;
  }

  /// Whether the floating / collapsed "add to my program" action applies.
  bool _showAddButton(bool isEventCancelled) {
    return _event != null &&
        AppConfig.isOwnProgramSupported &&
        FeatureService.isFeatureEnabled(FeatureConstants.mySchedule) &&
        !(isEventCancelled && !(_event?.isInMySchedule ?? false)) &&
        (_event?.childEvents.isEmpty ?? false) &&
        ((_event?.maxParticipants ?? 0) == 0);
  }

  /// Background tint of the pinned/collapsed bar: a very light shade of the
  /// event's base colour (light grey for untyped, a pale type tint otherwise).
  Color _collapsedTint() {
    final Color base = ThemeConfig.eventTypeToColor(context, _event?.type);
    return EventPageTheme.collapsedTint(
      base,
      Theme.of(context).brightness,
    );
  }

  double _measureTextWidth(BuildContext context, String text, TextStyle style) {
    final TextPainter tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      maxLines: 1,
    )..layout();
    return tp.width;
  }

  /// Content-driven expanded header height, measured so the collapsing app bar
  /// fits the (possibly two-line) title, the badge and the wrapping meta row
  /// exactly — otherwise the flexible space would clip or overflow.
  double _expandedHeaderHeight(BuildContext context) {
    final double topInset = MediaQuery.of(context).padding.top;
    final double screenW = MediaQuery.of(context).size.width;
    final double contentW = (screenW < StylesConfig.appMaxWidth
            ? screenW
            : StylesConfig.appMaxWidth) -
        40;
    final double avail = contentW > 0 ? contentW : 200;

    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: _event?.title ?? "",
        style: const TextStyle(
            fontWeight: FontWeight.bold, fontSize: 30, height: 1.1),
      ),
      textDirection: Directionality.of(context),
      maxLines: 3,
    )..layout(maxWidth: avail);
    final double titleH = tp.height;

    final EventType? et = _currentEventType();
    final double badgeH = et != null ? 38 : 0; // badge + spacing

    // Estimate how many lines the meta Wrap takes by greedily packing items.
    double metaH = 0;
    if (_event != null) {
      const TextStyle metaStyle =
          TextStyle(fontWeight: FontWeight.bold, fontSize: 15);
      const double iconAndGap = 26; // icon(20) + gap(6)
      const double spacing = 22; // Wrap spacing between items
      final List<String> metaTexts = [];
      final String dur = _event!.durationString(context);
      if (dur.isNotEmpty) metaTexts.add(dur);
      if (_event!.place?.id != null) {
        metaTexts.add(_event!.place!.title ?? "");
      }
      final int maxP = _event!.maxParticipants ?? 0;
      final capacity = _event!.participantCapacityLabel;
      if (maxP > 0 && capacity != null) {
        metaTexts.add(capacity);
      }
      int lines = metaTexts.isEmpty ? 0 : 1;
      double lineW = 0;
      for (final t in metaTexts) {
        final double w = iconAndGap + _measureTextWidth(context, t, metaStyle);
        if (lineW == 0) {
          lineW = w;
        } else if (lineW + spacing + w <= avail) {
          lineW += spacing + w;
        } else {
          lines++;
          lineW = w;
        }
      }
      if (lines > 0) metaH = 14 + lines * 24; // spacing + lines
    }

    const double topRowH = 52; // back button row
    const double bottomPad = 20;
    final double h = topInset + topRowH + badgeH + titleH + metaH + bottomPad;
    final double min = _collapsedHeaderHeight + topInset + 8;
    return h > min ? h : min;
  }

  /// The collapsing app-bar space: cross-fades the full expanded banner (image /
  /// gradient with title, badge and meta) into the compact pinned bar as the
  /// user scrolls up, matching production.
  Widget _buildFlexibleHeader(BuildContext context, double expandedHeight) {
    final double topInset = MediaQuery.of(context).padding.top;
    final EventType? eventType = _currentEventType();
    final Color fg = _headerForeground();
    return LayoutBuilder(
      builder: (context, constraints) {
        final double maxH = expandedHeight;
        final double minH = _collapsedHeaderHeight + topInset;
        final double t = maxH > minH
            ? ((constraints.maxHeight - minH) / (maxH - minH)).clamp(0.0, 1.0)
            : 0.0;
        return Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.hardEdge,
          children: [
            // Natural height (not force-fit): if the measured app-bar height is
            // momentarily off — e.g. before the web font settles — the banner is
            // clipped by the Stack rather than throwing a RenderFlex overflow.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Opacity(
                opacity: Curves.easeIn.transform(t),
                child: IgnorePointer(
                  ignoring: t < 0.5,
                  child: _headerBackground(
                    eventType,
                    _buildExpandedHeaderContent(context, fg, eventType),
                  ),
                ),
              ),
            ),
            Opacity(
              opacity: 1 - t,
              child: IgnorePointer(
                ignoring: t >= 0.5,
                child: _buildCollapsedBar(context),
              ),
            ),
          ],
        );
      },
    );
  }

  /// The expanded banner content (back row, type badge, big title, meta row),
  /// laid over the [_headerBackground].
  Widget _buildExpandedHeaderContent(
      BuildContext context, Color fg, EventType? eventType) {
    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
            child: Row(
              children: [
                ScheduleBackButton(color: fg),
                const Spacer(),
                if (showLoginLogoutButton() &&
                    RightsService.isApprover() &&
                    FeatureService.isFeatureEnabled(
                        FeatureConstants.entryCode) &&
                    _event != null)
                  IconButton(
                    onPressed: () => RouterService.navigatePageInfo(
                        context, CheckRoute(id: _event!.id!)),
                    icon: Icon(Icons.qr_code_scanner, color: fg),
                  ),
              ],
            ),
          ),
          Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: StylesConfig.appMaxWidth),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (eventType != null) ...[
                      _buildTypeBadge(eventType, fg),
                      const SizedBox(height: 10),
                    ],
                    Text(
                      _event?.title ?? "",
                      style: TextStyle(
                        color: fg,
                        fontWeight: FontWeight.bold,
                        fontSize: 30,
                        height: 1.1,
                      ),
                    ),
                    if (_event != null) ...[
                      const SizedBox(height: 14),
                      _buildMetaRow(context, fg),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Compact pinned bar shown when the header is scrolled up: back button,
  /// single-line title, condensed meta row and the add-to-program action.
  Widget _buildCollapsedBar(BuildContext context) {
    final Color fg = ThemeConfig.blackColor(context);
    final bool showAdd = _showAddButton(_event?.isCancelled ?? false);
    return SafeArea(
      bottom: false,
      child: SizedBox(
        height: _collapsedHeaderHeight,
        child: Padding(
          padding: const EdgeInsets.only(left: 4, right: 8),
          child: Row(
            children: [
              ScheduleBackButton(color: fg),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _event?.title ?? "",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: fg, fontWeight: FontWeight.bold, fontSize: 19),
                    ),
                    if (_event != null) ...[
                      const SizedBox(height: 3),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: _joinMeta(_metaItems(context, fg,
                              iconSize: 15,
                              fontSize: 13,
                              compact: true,
                              includeParticipants: false)),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (showAdd) ...[
                const SizedBox(width: 8),
                IconButton(
                  style: savedProgramActionButtonStyle,
                  onPressed: () => _setSavedProgram(_canSaveSavedProgram.value),
                  icon: SavedProgramActionIcon(
                    canSave: _canSaveSavedProgram,
                    color: fg,
                    addIcon: Icons.add_circle_outline,
                    savedIcon: Icons.check_circle,
                    size: 30,
                    diameter: 30,
                    highlightSaved: false,
                  ),
                ),
              ] else if (_event?.participantCapacityLabel != null) ...[
                const SizedBox(width: 8),
                if (_event?.isSignedIn == true)
                  _participantPill(
                      context, fg, _event!.participantCapacityLabel!, 18, 14)
                else
                  _metaItem(Icons.people_alt_outlined,
                      _event!.participantCapacityLabel!, fg, 18, 14),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// The floating "+" overlay that tracks the header's bottom edge and fades out
  /// as the header collapses (rendered above the scroll view so it never clips).
  Widget _buildFabOverlay(BuildContext context, double expandedHeight) {
    final double topInset = MediaQuery.of(context).padding.top;
    final double minH = _collapsedHeaderHeight + topInset;
    return AnimatedBuilder(
      animation: _scrollController,
      builder: (context, _) {
        final double offset = _scrollController.hasClients
            ? _scrollController.offset.clamp(0.0, double.infinity)
            : 0.0;
        final double headerBottom = expandedHeight - offset;
        final double range = expandedHeight - minH;
        final double collapseT = range > 0
            ? ((expandedHeight - headerBottom) / range).clamp(0.0, 1.0)
            : 1.0;
        final double opacity = (1 - collapseT * 1.5).clamp(0.0, 1.0);
        if (opacity <= 0.01) return const SizedBox.shrink();
        return Positioned(
          top: headerBottom - 28,
          right: _headerActionRightInset(context),
          child: Opacity(
            opacity: opacity,
            child: IgnorePointer(
              ignoring: opacity < 0.5,
              child: _buildAddButton(context),
            ),
          ),
        );
      },
    );
  }

  /// Wraps [child] in the header banner. Priority: a per-event header image
  /// (rendered cover, under a downward dark scrim so the white content stays
  /// legible); otherwise a typed event gets a vertical monochrome gradient from
  /// the type color, and the default (untyped) event gets the brand navy→orange
  /// diagonal with a downward dark scrim.
  Widget _headerBackground(EventType? eventType, Widget child) {
    final String? imageUrl =
        ConnectivityService.isOfflineNotifier.value ? null : _headerImageUrl();
    if (imageUrl != null) {
      return Stack(
        children: [
          Positioned.fill(
            child: CachedNetworkImage(
              imageUrl: ImageUrlHelper.transformImageUrl(imageUrl,
                  width: ImageUrlHelper.fullWidth),
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) =>
                  Container(color: ThemeConfig.appBarColor()),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.10),
                    Colors.black.withValues(alpha: 0.35),
                    Colors.black.withValues(alpha: 0.70),
                  ],
                  stops: const [0.0, 0.55, 1.0],
                ),
              ),
            ),
          ),
          child,
        ],
      );
    }

    if (_event != null && eventType != null) {
      final Color base = eventType.getColor();
      final double l = HSLColor.fromColor(base).lightness;
      final Color lighter =
          base.changeColorLightness((l + 0.10).clamp(0.0, 1.0));
      return Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [base, lighter],
          ),
        ),
        child: child,
      );
    }

    final Color navy = ThemeConfig.appBarColor().changeColorLightness(0.32);
    final Color orange = ThemeConfig.seed2.changeColorLightness(0.30);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [navy, orange],
        ),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: 0.05),
              Colors.black.withValues(alpha: 0.45),
            ],
          ),
        ),
        child: child,
      ),
    );
  }

  Widget _buildTypeBadge(EventType eventType, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: fg.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        eventType.title.toUpperCase(),
        style: TextStyle(
          color: fg,
          fontWeight: FontWeight.bold,
          fontSize: 13,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildMetaRow(BuildContext context, Color fg) {
    return Wrap(spacing: 22, runSpacing: 8, children: _metaItems(context, fg));
  }

  /// The meta chips shared by the expanded header (wrapped) and the collapsed
  /// bar (condensed, single scrolling row): time, place and capacity.
  List<Widget> _metaItems(BuildContext context, Color fg,
      {double iconSize = 20,
      double fontSize = 15,
      bool compact = false,
      bool includeParticipants = true}) {
    final List<Widget> items = [];

    final String duration = compact
        ? (_event?.durationCompactString(context) ?? "")
        : (_event?.durationString(context) ?? "");
    if (duration.isNotEmpty) {
      items.add(_metaItem(Icons.access_time, duration, fg, iconSize, fontSize));
    }

    if (_event?.place?.id != null) {
      items.add(_placeItem(
          context, fg, _event?.place?.title ?? "", iconSize, fontSize));
    }

    final text = _event?.participantCapacityLabel;
    if (includeParticipants && text != null) {
      items.add(_event?.isSignedIn == true
          ? _participantPill(context, fg, text, iconSize, fontSize)
          : _metaItem(Icons.people_alt_outlined, text, fg, iconSize, fontSize));
    }

    return items;
  }

  /// Interleaves meta chips with fixed spacing for the single-row collapsed bar.
  List<Widget> _joinMeta(List<Widget> items) {
    final List<Widget> out = [];
    for (int i = 0; i < items.length; i++) {
      if (i > 0) out.add(const SizedBox(width: 14));
      out.add(items[i]);
    }
    return out;
  }

  Widget _metaItem(IconData icon, String text, Color fg,
      [double iconSize = 20, double fontSize = 15]) {
    return EventMetadataItem(
      icon: icon,
      text: text,
      color: fg,
      iconSize: iconSize,
      fontSize: fontSize,
    );
  }

  /// The circular "add to / remove from my program" button overlapping the
  /// header's bottom edge. Its fill contrasts the banner; the glyph uses the
  /// event's base color.
  Widget _buildAddButton(BuildContext context) {
    final Color fill = _headerForeground();
    final Color glyph = ThemeConfig.eventTypeToColor(context, _event?.type);
    return Material(
      color: fill,
      shape: const CircleBorder(),
      elevation: 4,
      child: InkWell(
        customBorder: const CircleBorder(),
        splashFactory: NoSplash.splashFactory,
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        onTap: () => _setSavedProgram(_canSaveSavedProgram.value),
        child: SizedBox(
          width: 56,
          height: 56,
          child: SavedProgramActionIcon(
            canSave: _canSaveSavedProgram,
            color: glyph,
            addIcon: Icons.add,
            savedIcon: Icons.check,
            size: 30,
            diameter: 56,
          ),
        ),
      ),
    );
  }

  /// Right inset for the floating header action so it hugs the centered content
  /// column edge on wide screens while staying padded on phones.
  double _headerActionRightInset(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final double sideGutter = (screenWidth - StylesConfig.appMaxWidth) / 2;
    return sideGutter > 16 ? sideGutter + 12 : 16;
  }

  /// Editor / participant actions as light tonal chips with icons in a
  /// left-aligned Wrap (matches production's redesigned action row).
  Widget _buildGroupDescription(
      VoidCallback onPinchStart, VoidCallback onPinchEnd) {
    final group = _groupInfoModel;
    final version = group?.aggregateVersion ?? 0;
    final eventId = _event?.id;
    final canEdit = RightsService.isGroupAdmin() &&
        (_event?.isGroupEvent ?? false) &&
        group != null;
    return EditableHtmlField(
        key: ValueKey('group-event-html-$eventId'),
        html: _event?.description,
        enabled: canEdit,
        owner: RightsService.isEditor() || RightsService.isOrderEditor()
            ? HtmlMediaOwner.occasion(_event?.occasionId)
            : const HtmlMediaOwner.none(),
        twoFingersOn: onPinchStart,
        twoFingersOff: onPinchEnd,
        onChanged: (_) {},
        onSave: (html) async {
          if (group == null) {
            throw StateError('Group description owner missing');
          }
          final snapshot = UserGroupInfoModel(
              id: group.id,
              title: group.title,
              description: html,
              type: group.type,
              data: group.data,
              place: group.place,
              placeId: group.placeId,
              participants: group.participants,
              persistedPlaceId: group.persistedPlaceId,
              persistedPlaceWasPrivate: group.persistedPlaceWasPrivate,
              aggregateVersion: version,
              isAdmin: group.isAdmin);
          await DbGroups.updateUserGroupInfo(snapshot);
          if (eventId != null && mounted) await loadData(eventId);
        });
  }

  Widget _buildActionButtons(BuildContext context, bool isEventCancelled) {
    final List<Widget> buttons = [];

    if (showLoginLogoutButton() &&
        !isEventCancelled &&
        !(_event?.isSignedIn ?? false) &&
        !EventModel.isEventFull(_event)) {
      buttons.add(_actionButton(
          Icons.login, UserStrings.signIn, () => signIn(context)));
    }
    if (showLoginLogoutButton() && (_event?.isSignedIn ?? false)) {
      buttons.add(_actionButton(null, UserStrings.signOut, () => signOut()));
    }
    if (canShowCompanionAttendanceAction(
      isLoggedIn: AuthService.isLoggedIn(),
      eventSupportsSignIn: EventModel.isEventSupportingSignIn(_event),
      featureEnabled: FeatureService.isCompanionsEnabled(),
      hasOwnedCompanions: _companions.isNotEmpty,
    )) {
      buttons.add(_actionButton(Icons.group_add_outlined,
          CommonStrings.companions, () => signInCompanion()));
    }
    if (showLoginLogoutButton() && RightsService.isEditor()) {
      buttons.add(_actionButton(
          Icons.person_add_alt_1, ScheduleStrings.signInOther, () async {
        _queriedParticipants = await DbUsers.getAllUsersBasics();
        _queriedParticipants.forEach((q) => {
              if (_participants.any((p) => p.id == q.id)) {q.isSignedIn = true}
            });
        if (!mounted) return;
        // ignore: use_build_context_synchronously
        DialogHelper.chooseUser(context, (person) async {
          await signIn(context, person);
          await loadData(_event!.id!);
        }, _queriedParticipants, ScheduleStrings.signInSomeone);
      }));
    }
    if (RightsService.isEditor()) {
      buttons.add(_actionButton(Icons.edit, CommonStrings.edit, () {
        RouterService.navigateOccasion(
                context, "${EventEditPage.ROUTE}/${_event!.id}")
            .then((value) => loadData(_event!.id!));
      }));
    }

    if (buttons.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Wrap(spacing: 10, runSpacing: 10, children: buttons),
    );
  }

  Widget _actionButton(IconData? icon, String label, VoidCallback onPressed) =>
      ButtonsHelper.actionButton(
          context: context, icon: icon, label: label, onPressed: onPressed);

  /// The "Speakers" (lecturers) section: a centered profile card per attached
  /// speaker — large circular photo, name and subtitle centered, HTML bio
  /// always visible below (no expansion) — never as a page banner (Julie's
  /// question #1). Empty (no widget) when the feature is off or the event has
  /// no attached speakers.
  Widget _buildSpeakersSection(BuildContext context, VoidCallback onPinchStart,
      VoidCallback onPinchEnd) {
    // Speakers are core: the section shows whenever the event has speakers
    // attached, regardless of any feature (decision R7).
    if (_event?.id == null || _speakersBundle == null) {
      return const SizedBox.shrink();
    }
    final List<SpeakerModel> speakers =
        _speakersBundle!.speakersForEvent(_event!.id!);
    if (speakers.isEmpty) return const SizedBox.shrink();

    // Borderless section: a hairline separates it from the description above,
    // and further hairlines separate multiple speaker profiles from each other.
    final divider =
        Divider(height: 24, thickness: 1, color: ThemeConfig.grey300(context));
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          divider,
          for (var i = 0; i < speakers.length; i++) ...[
            if (i > 0) divider,
            _buildSpeakerMedallion(
                context, speakers[i], onPinchStart, onPinchEnd),
          ],
        ],
      ),
    );
  }

  Widget _buildSpeakerMedallion(BuildContext context, SpeakerModel s,
      VoidCallback onPinchStart, VoidCallback onPinchEnd) {
    // Borderless, flat (2D — no shadows or elevation) profile that flows with
    // the page content: a large centered photo, the name beneath it, the
    // subtitle split into role pills and the bio always visible below —
    // nothing to expand or tap.
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 12),
      child: SpeakerMedallion(
        imageUrl: s.image,
        name: s.title,
        pills: splitSpeakerRoles(s.subtitle),
        bioHtml: s.description,
        photoRadius: 110,
        onPinchStart: onPinchStart,
        onPinchEnd: onPinchEnd,
      ),
    );
  }

  /// The capacity chip shown in the header meta row as a filled pill.
  /// The place item. Unlike the plain time meta text this is tappable (it
  /// navigates to the place on the map), so its label is underlined and it
  /// carries a trailing chevron to read as a link. It keeps the same
  /// icon+text height as the time item so both align on the meta row.
  Widget _placeItem(BuildContext context, Color fg, String text,
      double iconSize, double fontSize) {
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () async {
        final result =
            await MapNavigation.openPlace(context, _event!.place!.id!);
        if (mounted && result.kind == MapVisitKind.returned) {
          await loadData(_event!.id!);
        }
      },
      child: EventMetadataItem(
        icon: Icons.location_on_outlined,
        text: text,
        color: fg,
        iconSize: iconSize,
        fontSize: fontSize,
        isLink: true,
      ),
    );
  }

  Widget _participantPill(BuildContext context, Color fg, String text,
      double iconSize, double fontSize) {
    final colorScheme = Theme.of(context).colorScheme;
    final pill = EventPageTheme.participantPillColors(
      primary: colorScheme.primary,
      onPrimary: colorScheme.onPrimary,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: pill.background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text,
              style: TextStyle(
                  color: pill.foreground,
                  fontWeight: FontWeight.bold,
                  fontSize: fontSize)),
          const SizedBox(width: 6),
          Icon(Icons.people_alt_outlined,
              color: pill.foreground, size: iconSize),
        ],
      ),
    );
  }

  Future<void> _setSavedProgram(bool saved) async {
    final event = _event;
    if (event?.id == null) return;
    final eventId = event!.id!;
    final mutationRevision = ++_savedProgramMutationRevision;
    event.isInMySchedule = saved;
    _isUpdatingSavedProgram = true;
    _syncSavedProgramUi();
    if (event.isCancelled) setState(() {});

    final result = await DbEvents.setSavedProgram(
      context,
      eventId,
      saved,
    );
    if (!mounted ||
        _event?.id != eventId ||
        mutationRevision != _savedProgramMutationRevision) {
      return;
    }

    if (!result.wasApplied) {
      event.isInMySchedule = await OfflineDataService.isEventSaved(eventId);
      if (!mounted ||
          _event?.id != eventId ||
          mutationRevision != _savedProgramMutationRevision) {
        return;
      }
    }
    _isUpdatingSavedProgram = false;
    _savedProgramMutationRevision++;
    _syncSavedProgramUi();
    if (event.isCancelled) setState(() {});
  }

  void _syncSavedProgramUi() {
    _canSaveSavedProgram.value = _event?.canSaveEventToMyProgram() ?? false;
  }

  void _setLoadedEvent(EventModel event) {
    _event = event;
    if (mounted) _syncSavedProgramUi();
  }

  bool showLoginLogoutButton() {
    return AuthService.isLoggedIn() &&
        EventModel.isEventSupportingSignIn(_event);
  }

  Future<void> loadData(int id) async {
    // New event → its header content differs, so remeasure from scratch.
    _measuredExpandedHeight = null;
    try {
      _companions = AuthService.isLoggedIn()
          ? await DbCompanions.getAllCompanions()
          : const [];
      await loadOfflineData(widget.id!);
      if (await _redirectIfCounselingSlot()) return;

      final isOffline = ConnectivityService.isOfflineNotifier.value;
      final localOnly = ClientSyncRuntime.isV1Selected || isOffline;
      if (!localOnly) {
        await loadEvent(id);
        if (await _redirectIfCounselingSlot()) return;
      }
      if (EventParticipantsAccess.shouldLoad(
        isOffline: isOffline,
        isEditorView: RightsService.isEditorView(),
        isEditor: RightsService.isEditor(),
        isAdmin: RightsService.isAdmin(),
      )) {
        await loadParticipants(id);
      }
      if (localOnly) {
        final cachedSpeakers = await OfflineDataService.getSpeakers();
        if (cachedSpeakers != null && mounted) {
          setState(() => _speakersBundle = cachedSpeakers);
        }
      } else {
        await loadSpeakers();
      }
    } finally {
      if (mounted) setState(() => isLoadingEvent = false);
    }
  }

  /// Counseling events have no meaningful detail page — the rozcestník owns
  /// the whole flow (area picker, reservation, cancellation, counselor info).
  /// This covers both generated counseling slots and any event carrying the
  /// configured counseling event type (e.g. "Psychologické poradny"). Any
  /// navigation to such an event (timeline tap, my program, search, deep
  /// link) lands on the slot's ORIGINAL entry event (its parent), which hosts
  /// the picker inline — the standalone counseling page is only the fallback
  /// when there is no parent. Replace (not push) so back does not loop
  /// through the redirect.
  ///
  /// The rozcestník entry event itself is exempt — it *hosts* the picker
  /// inline above its description, so it must render its own page.
  Future<bool> _redirectIfCounselingSlot() async {
    final event = _event;
    if (event == null) return false;
    // The rozcestník entry event hosts the picker inline — never bounce it.
    if (event.isCounselingEntry) return false;
    final counselingType =
        FeatureService.getCounselingFeature()?.counselingEventType;
    final isCounselingTyped = counselingType != null &&
        counselingType.isNotEmpty &&
        event.type == counselingType;
    // A counseling slot / counseling-typed event is authoritative on its own:
    // don't gate on isCounselingEnabled(), which can still be false on a fresh
    // deep link before the occasion features finish loading.
    if (!event.isCounselingSlot && !isCounselingTyped) {
      return false;
    }
    // Slots are not linked to the rozcestník entry via event_groups, so find
    // the entry event by DAY: the rozcestník entry (counselingEntry flag) on
    // the same occasion-day as the slot. Falls back to any entry, and only
    // then to the standalone counseling page (normally unreachable).
    int? entryId;
    try {
      // Offline events already carry the counseling_entry flag and are
      // instant; hit the network only when no entry is cached (fresh
      // browser / not yet synced).
      var all = await OfflineDataService.getAllEvents();
      if (!all.any((e) => e.isCounselingEntry) &&
          !ClientSyncRuntime.isV1Selected &&
          !ConnectivityService.isOfflineNotifier.value) {
        final occasionId = RightsService.currentOccasionId();
        all = occasionId != null
            ? await DbEvents.getAllEvents(occasionId, false)
            : const [];
      }
      final entries = all.where((e) => e.isCounselingEntry).toList();
      final slotDay = event.startTime.toOccasionTime();
      final sameDay = entries.firstWhereOrNull((e) {
        final d = e.startTime.toOccasionTime();
        return d.year == slotDay.year &&
            d.month == slotDay.month &&
            d.day == slotDay.day;
      });
      entryId = (sameDay ?? entries.firstOrNull)?.id;
    } catch (_) {
      // Offline / RPC failure → the standalone page fallback below.
    }
    if (mounted) {
      if (entryId != null) {
        // Replace within the schedule's nested stack router (typed route).
        // An absolute replacePath would resolve the scope at the ROOT router,
        // pop the whole occasion shell and die on the '*' redirect — the URL
        // then stays on the slot (or falls back to "/").
        context.router.replace(EventRoute(id: entryId));
      } else {
        RouterService.pushReplacementOccasion(context, CounselingPage.ROUTE);
      }
    }
    return true;
  }

  /// Loads the speakers bundle for the speaker medallions. Resilient: a failure
  /// (offline, RPC error) simply leaves the section empty and never breaks the
  /// event page.
  Future<void> loadSpeakers() async {
    // Speakers are core — always loaded (decision R7).
    try {
      final occasionId = RightsService.currentOccasionId();
      if (occasionId == null) return;
      final bundle =
          await DbSpeakers.getSpeakers(occasionId, includeDescription: true);
      if (mounted) setState(() => _speakersBundle = bundle);
    } catch (_) {
      // Offline / RPC failure: fall back to the synced speakers cache so the
      // section still renders; with no cache it stays hidden as before.
      final cached = await OfflineDataService.getSpeakers();
      if (cached != null && mounted) {
        setState(() => _speakersBundle = cached);
      }
    }
  }

  Future<void> loadOfflineData(int id) async {
    final savedProgramRevisionAtLoadStart = _savedProgramMutationRevision;
    var allEvents = await OfflineDataService.getAllEvents();
    var event = allEvents.firstWhereOrNull((element) => element.id == id);
    if (event != null) {
      if ((event.isGroupEvent ?? false) && AuthService.isLoggedIn()) {
        var userInfo = await OfflineDataService.getUserInfo();
        if (userInfo?.eventUserGroup != null) {
          event.title = userInfo!.eventUserGroup!.title;
          event.isMyGroupEvent = true;
          event.description = userInfo.eventUserGroup!.description;
          event.place = userInfo.eventUserGroup!.place;
          _groupInfoModel = userInfo.eventUserGroup;
        }
      } else {
        if (event.place?.id != null) {
          var place = (await OfflineDataService.getAllPlaces())
              .firstWhereOrNull((element) => element.id == event.place!.id);
          event.place = place;
        } else {
          event.place = null;
        }
        final loadedSaved = await OfflineDataService.isEventSaved(id);
        event.isInMySchedule = reconcileLoadedSavedProgramState(
          incoming: loadedSaved,
          visible: _event?.id == id ? _event?.isInMySchedule : null,
          mutationInFlight: _isUpdatingSavedProgram,
          loadRevision: savedProgramRevisionAtLoadStart,
          currentRevision: _savedProgramMutationRevision,
        );
      }

      var childEvents = allEvents
          .where((e) => event.childEventIds?.contains(e.id) ?? false)
          .toList()
          .sortEvents();
      // The subprogram rows show the place — resolve the children's id-only
      // offline places to full models, same as the parent's place above.
      var offlinePlaces = await OfflineDataService.getAllPlaces();
      for (var child in childEvents) {
        if (child.place?.id != null) {
          child.place =
              offlinePlaces.firstWhereOrNull((p) => p.id == child.place!.id) ??
                  child.place;
        }
      }
      event.childEvents = childEvents;
      _childDots.clear();
      _childDots.addAll(
          event.childEvents.map((e) => TimeBlockItem.fromEventModelAsChild(e)));

      if (mounted) {
        setState(() {
          _setLoadedEvent(event);
        });
      }
    }
  }

  Future<void> loadParticipants(int id) async {
    _participants = await DbEvents.getParticipantsPerEvent(id);
    if (mounted) setState(() => {});
  }

  Future<void> loadEvent(int eventId) async {
    var event = await DbEvents.getEvent(eventId);

    if ((event.isGroupEvent ?? false) && (event.isMyGroupEvent ?? false)) {
      var group = RightsService.isGroupAdmin() || RightsService.isEditor()
          ? await DbGroups.getUserGroupForEdit(
              RightsService.currentUserGroup()!.id!)
          : await DbGroups.getUserGroupInfo(
              RightsService.currentUserGroup()!.id!);
      if (group == null) {
        if (mounted) RouterService.goBack(context);
        return;
      }
      event.description = group.description;
      event.title = group.title;
      event.place = group.place;
      _groupInfoModel = group;
      _setLoadedEvent(event);
      if (mounted) setState(() {});
      return;
    }

    var currentParticipants =
        await DbEvents.getParticipantsPerEventCount(eventId);
    event.currentParticipants = currentParticipants;
    _setLoadedEvent(event);
    _childDots.clear();
    _childDots.addAll(
        _event!.childEvents.map((e) => TimeBlockItem.fromEventModelAsChild(e)));
    if (mounted) setState(() {});
  }

  void _eventPressed(int id) {
    context.router
        .push(EventRoute(id: id))
        .then((value) => loadData(_event!.id!));
  }

  Future<void> signIn(BuildContext context,
      [UserInfoModel? participant]) async {
    final didSignIn =
        await DbEvents.signInToEvent(context, _event!.id!, participant);
    if (!didSignIn || participant != null || !mounted) return;

    setState(() {
      _event!.updateCurrentUserRegistration(isRegistered: true);
    });
  }

  Future<void> signOut() async {
    // Allowed for cancelled events if already signed in
    await DbEvents.signOutFromEvent(context, _event!.id!);
    await loadData(_event!.id!);
  }

  Future<void> signInCompanion() async {
    _companions = await DbCompanions.getAllCompanions();
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return CompanionAttendanceDialog(
              eventId: _event!.id!,
              canSignIn: () => _event!.canSignIn(),
              companions: _companions,
              refreshData: () async {
                await loadData(widget.id!);
                _companions = await DbCompanions.getAllCompanions();
                if (mounted) {
                  setState(() {});
                }
              },
            );
          },
        );
      },
    );
  }

  Future<String?> signOutOther(UserInfoModel participant) {
    // Allowed for cancelled events
    return showDialog<String>(
        context: context,
        builder: (BuildContext context) => AlertDialog(
              title: Text(ScheduleStrings.signOutParticipant),
              content: Text(ScheduleStrings.signOutParticipantConfirm(
                participant: participant.toString(),
                event: _event!.toString(),
              )),
              actions: <Widget>[
                TextButton(
                  onPressed: () => RouterService.goBack(context),
                  child: Text(CommonStrings.storno),
                ),
                TextButton(
                  onPressed: () async {
                    RouterService.goBack(context);
                    await DbEvents.signOutFromEvent(
                        context, _event!.id!, participant);
                    await loadData(_event!.id!);
                  },
                  child: Text(ScheduleStrings.signOutSomeone),
                ),
              ],
            ));
  }
}
