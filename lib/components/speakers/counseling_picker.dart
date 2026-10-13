import 'package:collection/collection.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/components/map/map_navigation.dart';
import 'package:fstapp/components/schedule/db_events.dart';
import 'package:fstapp/components/schedule/event_model.dart';
import 'package:fstapp/components/schedule/schedule_strings.dart';
import 'package:fstapp/components/speakers/counseling_availability.dart';
import 'package:fstapp/components/speakers/db_speakers.dart';
import 'package:fstapp/components/speakers/speaker_avatar.dart';
import 'package:fstapp/components/speakers/speaker_medallion.dart';
import 'package:fstapp/components/speakers/speaker_model.dart';
import 'package:fstapp/components/speakers/speakers_bundle.dart';
import 'package:fstapp/components/speakers/speakers_strings.dart';
import 'package:fstapp/components/speakers/topic_picker.dart';
import 'package:fstapp/components/offline/offline_strings.dart';
import 'package:fstapp/data_services/auth_service.dart';
import 'package:fstapp/data_services/offline_data_service.dart';
import 'package:fstapp/data_services/client_sync/client_sync_runtime.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/services/connectivity_service.dart';
import 'package:fstapp/services/exception_handler.dart';
import 'package:fstapp/services/time_helper.dart';
import 'package:fstapp/services/toast_helper.dart';
import 'package:fstapp/theme_config.dart';
import 'package:fstapp/widgets/buttons_helper.dart';

/// The counseling rozcestník flow, as an inline (non-scrolling) Column so it can
/// live directly on the entry event page (above the description) as well as on a
/// standalone page. The user picks an area (areas with no free slots are greyed
/// but still tappable), then sees the competent counselors and their slots and
/// books / cancels with one click (slot = event → sign in / sign out).
class CounselingPicker extends StatefulWidget {
  /// When set, the flow is scoped to this parent event's day — only that day's
  /// counselors/slots/counts are shown (the rozcestník is per day). Null shows
  /// all future slots (standalone page).
  final DateTime? day;

  const CounselingPicker({super.key, this.day});

  @override
  State<CounselingPicker> createState() => _CounselingPickerState();
}

class _CounselingPickerState extends State<CounselingPicker> {
  bool _isLoading = true;
  bool _isLoadingAvailability = false;

  SpeakersBundle _bundle = SpeakersBundle.empty();
  List<EventModel> _myReservations = [];
  List<CounselingTopicOverview> _topicOverview = [];
  int? _selectedTopicId;
  CounselingAvailability? _availability;

  /// Live counseling data (overview / availability) failed while offline —
  /// the slot step shows OfflineStrings.counselingNeedsConnection instead.
  bool _liveDataOffline = false;

  int get _occasionId => RightsService.currentOccasionId()!;

  /// Area ids that currently have a free future slot; null while the overview
  /// has not loaded yet (→ nothing greyed as a safe fallback).
  Set<int>? get _availableTopicIds => _topicOverview.isEmpty
      ? null
      : _topicOverview.where((o) => o.hasFree).map((o) => o.topicId).toSet();

  /// Occupancy per area (occupied, total future slots) for the trailing badge —
  /// same shape the program's capacity chip uses.
  Map<int, ({int occupied, int total})> get _occupancyByTopic => {
        for (final o in _topicOverview)
          o.topicId: (
            occupied: o.totalFutureSlots - o.freeFutureSlots,
            total: o.totalFutureSlots,
          )
      };

  /// [from, to) UTC bounds of the parent event's day, or null (all future).
  DateTime? _windowFrom;
  DateTime? _windowTo;

  void _computeWindow() {
    final d = widget.day;
    if (d == null) {
      _windowFrom = null;
      _windowTo = null;
      return;
    }
    final local = d.toOccasionTime();
    final startLocal = DateTime(local.year, local.month, local.day);
    _windowFrom = startLocal.toUtcFromOccasionTime();
    _windowTo = startLocal.add(const Duration(days: 1)).toUtcFromOccasionTime();
  }

  @override
  void initState() {
    super.initState();
    _computeWindow();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadInitial());
  }

  Future<void> _loadInitial() async {
    // Paint-from-cache: seed the areas and counselor medallions from the
    // synced speakers cache so they are visible offline; the live pass below
    // overwrites them when it succeeds.
    final cached = await OfflineDataService.getSpeakers();
    if (cached != null && mounted) {
      setState(() => _bundle = cached);
    }
    try {
      // includeDescription: the expanded counselor medallion shows the bio.
      final bundle =
          await DbSpeakers.getSpeakers(_occasionId, includeDescription: true);
      final reservations = await _loadReservations();
      final overview = await DbSpeakers.getCounselingTopicsOverview(_occasionId,
          from: _windowFrom, to: _windowTo);
      if (mounted) {
        setState(() {
          _bundle = bundle;
          _myReservations = reservations;
          _topicOverview = overview;
          _liveDataOffline = false;
        });
      }
    } catch (e) {
      // Slot availability is live-only by design. Treat a failed request as
      // offline whenever it's a network/timeout/server-unreachable error OR the
      // device reports no connection — a weak signal or a server outage counts
      // as offline too, not just a missing interface. The cached areas stay
      // usable and the slot step shows a readable notice; genuine server errors
      // keep today's toast.
      if (ExceptionHandler.isNetworkError(e) ||
          await ConnectivityService.isOffline()) {
        if (mounted) setState(() => _liveDataOffline = true);
      } else if (mounted) {
        await ExceptionHandler.handle(context, error: e);
      }
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<List<EventModel>> _loadReservations() async {
    if (!AuthService.isLoggedIn()) return [];
    final all = ClientSyncRuntime.isV1Selected
        ? await OfflineDataService.getAllEvents()
        : await DbEvents.getAllEvents(_occasionId, false);
    return all
        .where((e) => e.isCounselingSlot && (e.isSignedIn == true))
        .toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
  }

  Future<void> _selectTopic(int topicId) async {
    setState(() {
      _selectedTopicId = topicId;
      _availability = null;
      _isLoadingAvailability = true;
      _liveDataOffline = false;
    });
    CounselingAvailability? avail;
    try {
      avail = await DbSpeakers.getCounselingAvailability(_occasionId, topicId,
          from: _windowFrom, to: _windowTo);
    } catch (e) {
      // Network/timeout/server-unreachable error or no connection → readable
      // inline notice in the slot area (weak signal & server outage count as
      // offline); genuine server errors keep today's toast.
      if (ExceptionHandler.isNetworkError(e) ||
          await ConnectivityService.isOffline()) {
        _liveDataOffline = true;
      } else if (mounted) {
        await ExceptionHandler.handle(context, error: e);
      }
    }
    if (mounted) {
      setState(() {
        _availability = avail;
        _isLoadingAvailability = false;
      });
    }
  }

  Future<void> _bookSlot(int slotId) async {
    if (!AuthService.isLoggedIn()) {
      ToastHelper.Show(context, SpeakersStrings.signInToReserve,
          severity: ToastSeverity.NotOk);
      return;
    }
    await DbEvents.signInToEvent(context, slotId);
    await _reloadAfterChange();
  }

  Future<void> _cancelReservation(int eventId) async {
    await DbEvents.signOutFromEvent(context, eventId);
    await _reloadAfterChange();
  }

  /// Refresh reservations, the per-area overview (greying) and the currently
  /// shown availability after a booking / cancellation.
  Future<void> _reloadAfterChange() async {
    try {
      final reservations = await _loadReservations();
      final overview = await DbSpeakers.getCounselingTopicsOverview(_occasionId,
          from: _windowFrom, to: _windowTo);
      CounselingAvailability? avail = _availability;
      if (_selectedTopicId != null) {
        avail = await DbSpeakers.getCounselingAvailability(
            _occasionId, _selectedTopicId!,
            from: _windowFrom, to: _windowTo);
      }
      if (mounted) {
        setState(() {
          _myReservations = reservations;
          _topicOverview = overview;
          _availability = avail;
        });
      }
    } catch (e) {
      // Offline the sign-in/out itself already showed the offline message —
      // keep the current state quietly instead of a second toast or a
      // refresh into a lying state. Online errors keep today's toast.
      if (!ExceptionHandler.isNetworkError(e) && mounted) {
        await ExceptionHandler.handle(context, error: e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    // Already booked (the limit is typically 1 counseling reservation): show
    // just the reservation with a cancel option — no area picker (decision
    // from user).
    if (_myReservations.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _sectionTitle(SpeakersStrings.yourReservation),
          ..._myReservations.map(_buildReservationTile),
        ],
      );
    }
    // Two-step: pick an area, then the area list is replaced by the counselors +
    // times for that area (with a way back).
    return _selectedTopicId == null ? _buildAreaStep() : _buildCounselorStep();
  }

  Widget _buildAreaStep() {
    final visibleTopics = _bundle.topics.where((t) => !t.isHidden).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _sectionTitle(SpeakersStrings.chooseAreaPrompt),
        TopicPicker(
          topics: visibleTopics,
          selectedTopicId: null,
          onSelected: _selectTopic,
          availableTopicIds: _availableTopicIds,
          occupancyByTopic: _occupancyByTopic,
        ),
      ],
    );
  }

  Widget _buildCounselorStep() {
    final topic =
        _bundle.topics.firstWhereOrNull((t) => t.id == _selectedTopicId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() {
              _selectedTopicId = null;
              _availability = null;
            }),
            icon: const Icon(Icons.arrow_back, size: 18),
            label: Text(SpeakersStrings.chooseArea),
          ),
        ),
        _sectionTitle(topic?.title ?? ""),
        const SizedBox(height: 8),
        _buildAvailability(),
      ],
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          text,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
      );

  /// Visible area titles a counselor (speaker) is competent in, via the bundle.
  List<String> _areasForCounselor(int counselorId) {
    final topicIds = _bundle.topicsBySpeaker[counselorId] ?? const <int>[];
    return _bundle.topics
        .where((t) =>
            t.id != null &&
            topicIds.contains(t.id) &&
            !t.isHidden &&
            (t.title?.isNotEmpty ?? false))
        .map((t) => t.title!)
        .toList();
  }

  /// The counselor (speaker) behind a reservation, for the medallion photo.
  SpeakerModel? _speakerForReservation(EventModel e) {
    final ids = e.id == null
        ? const <int>[]
        : (_bundle.speakersByEvent[e.id!] ?? const <int>[]);
    for (final sid in ids) {
      final sp = _bundle.speakerById(sid);
      if (sp != null) return sp;
    }
    return null;
  }

  /// Areas the counselor of this reservation is competent in — resolved through
  /// the bundle (event → speaker → topics) so the user can see the focus of the
  /// counselor they booked. Hidden areas and unnamed ones are dropped.
  List<String> _areasForReservation(EventModel e) {
    final speakerIds = e.id == null
        ? const <int>[]
        : (_bundle.speakersByEvent[e.id!] ?? const <int>[]);
    final titles = <String>[];
    final seen = <String>{};
    for (final sid in speakerIds) {
      for (final title in _areasForCounselor(sid)) {
        if (seen.add(title)) titles.add(title);
      }
    }
    return titles;
  }

  /// Compact reservation card: counselor photo + slot title + time (with the
  /// live badge) and a chevron in the header, the practical row (place +
  /// cancel) beneath. Reads unmistakably as "this is booked"; tapping it
  /// opens the counselor's full profile (photo + bio) in a dialog.
  Widget _buildReservationTile(EventModel e) {
    final areas = _areasForReservation(e);
    final speaker = _speakerForReservation(e);
    final now = TimeHelper.now();
    final isCurrent =
        !e.isCancelled && e.startTime.isBefore(now) && e.endTime.isAfter(now);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: ThemeConfig.whiteColor(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ThemeConfig.grey300(context)),
      ),
      child: InkWell(
        onTap: speaker == null
            ? null
            : () => _showCounselorProfileDialog(
                  context,
                  imageUrl: speaker.image,
                  name: speaker.title,
                  detailText: speaker.subtitle,
                  areas: areas,
                  bioHtml: speaker.description,
                  placeId: e.place?.id,
                  placeTitle: e.place?.title,
                  timeText: e.durationString(context),
                  footerBuilder: (ctx) => Center(
                    child: TextButton(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        _cancelReservation(e.id!);
                      },
                      child: Text(SpeakersStrings.cancelReservation),
                    ),
                  ),
                ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: identity + time; the chevron alone on the right so
              // nothing else reads as part of the "open detail" affordance.
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SpeakerAvatar(imageUrl: speaker?.image, radius: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(e.title ?? "",
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            if (isCurrent)
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
                            Flexible(
                              child: Text(e.durationString(context),
                                  style: TextStyle(
                                      color: ThemeConfig.grey700(context),
                                      fontSize: 13)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (speaker != null)
                    Icon(Icons.chevron_right,
                        size: 22, color: ThemeConfig.grey700(context)),
                ],
              ),
              // Practical row, clearly separate from the header: where it
              // happens on the left, the cancel action on the right.
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                runSpacing: 4,
                children: [
                  if (e.place?.title != null && e.place!.title!.isNotEmpty)
                    _placeLink(context, e.place!.id, e.place!.title)
                  else
                    const SizedBox.shrink(),
                  TextButton(
                    onPressed: () => _cancelReservation(e.id!),
                    child: Text(SpeakersStrings.cancelReservation),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvailability() {
    if (_isLoadingAvailability) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    // Slots are live-only: offline the picker degrades to this readable notice.
    if (_liveDataOffline) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(OfflineStrings.counselingNeedsConnection,
            style: TextStyle(color: ThemeConfig.grey700(context))),
      );
    }
    final counselors = _availability?.counselors ?? const [];
    // Flatten to (counselor, slot) rows sorted by time — all available times and
    // who the counselor is at each, like a normal program list.
    final rows = <({CounselorModel counselor, CounselingSlot slot})>[];
    for (final c in counselors) {
      for (final s in c.slots) {
        rows.add((counselor: c, slot: s));
      }
    }
    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(SpeakersStrings.noCounselorsForArea),
      );
    }
    rows.sort((a, b) => (a.slot.startTime ?? DateTime(0))
        .compareTo(b.slot.startTime ?? DateTime(0)));
    final children = <Widget>[];
    if (!AuthService.isLoggedIn()) {
      children.add(Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
        child: Text(SpeakersStrings.signInToReserve,
            style: TextStyle(color: ThemeConfig.redColor(context))),
      ));
    }
    for (var i = 0; i < rows.length; i++) {
      if (i > 0) children.add(_hairline(context));
      final c = rows[i].counselor;
      final s = rows[i].slot;
      final hm = DateFormat.Hm(context.locale.languageCode);
      children.add(_CounselorSlotTile(
        counselor: c,
        slot: s,
        speaker: _bundle.speakerById(c.id),
        areas: _areasForCounselor(c.id),
        startTimeText:
            s.startTime != null ? hm.format(s.startTime!.toOccasionTime()) : "",
        endTimeText:
            s.endTime != null ? hm.format(s.endTime!.toOccasionTime()) : "",
        isLoggedIn: AuthService.isLoggedIn(),
        onBook: () => _bookSlot(s.id),
        onCancel: () => _cancelReservation(s.id),
      ));
    }
    return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }

  Widget _hairline(BuildContext context) => Container(
        height: 1,
        color: ThemeConfig.blackColor(context).withValues(alpha: 0.08),
      );
}

/// Opens a counselor's full profile — the same flat medallion used everywhere
/// (big photo, name, detail, areas as pills, HTML bio) plus the slot's place —
/// in a dialog. Shared by the reservation card and the slot rows so "tap for
/// detail" behaves identically before and after booking.
Future<void> _showCounselorProfileDialog(
  BuildContext context, {
  String? imageUrl,
  String? name,
  String? detailText,
  List<String> areas = const [],
  String? bioHtml,
  int? placeId,
  String? placeTitle,
  Widget Function(BuildContext ctx)? footerBuilder,

  /// The slot's date + time, shown muted in the anchored bottom area (under
  /// the action button when there is one).
  String? timeText,
}) {
  return showDialog(
    context: context,
    builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Practical info (place) left, close right — above the profile.
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 12, 0),
              child: Row(
                children: [
                  Expanded(
                    child: (placeTitle != null && placeTitle.isNotEmpty)
                        ? Align(
                            alignment: Alignment.centerLeft,
                            child: _placeLink(ctx, placeId, placeTitle),
                          )
                        : const SizedBox.shrink(),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
            ),
            // Only the profile scrolls; the header and the action bar below
            // stay anchored so the primary action is always one tap away.
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: SpeakerMedallion(
                  imageUrl: imageUrl,
                  name: name,
                  detailText: detailText,
                  pills: areas,
                  bioHtml: bioHtml,
                  photoRadius: 82,
                ),
              ),
            ),
            if (footerBuilder != null ||
                (timeText != null && timeText.isNotEmpty)) ...[
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (footerBuilder != null) footerBuilder(ctx),
                    if (timeText != null && timeText.isNotEmpty) ...[
                      if (footerBuilder != null) const SizedBox(height: 8),
                      Text(
                        timeText,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: ThemeConfig.grey700(ctx), fontSize: 13),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

/// A place row that navigates to the place on the map when it has an id —
/// underlined label + chevron to read as a link (mirrors the event page's
/// place item). Falls back to a plain muted label when there is no place id.
Widget _placeLink(BuildContext context, int? placeId, String? placeTitle) {
  final title = placeTitle ?? "";
  if (title.isEmpty) return const SizedBox.shrink();
  final fg = ThemeConfig.grey700(context);
  if (placeId == null) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.location_on_outlined, size: 16, color: fg),
        const SizedBox(width: 6),
        Flexible(
          child: Text(title, style: TextStyle(color: fg, fontSize: 13)),
        ),
      ],
    );
  }
  return InkWell(
    borderRadius: BorderRadius.circular(6),
    onTap: () => MapNavigation.openPlace(context, placeId),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.location_on_outlined, size: 16, color: fg),
          const SizedBox(width: 6),
          Flexible(
            child: Text(title,
                style: TextStyle(
                    color: fg,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    decoration: TextDecoration.underline,
                    decorationColor: fg.withValues(alpha: 0.6))),
          ),
          Icon(Icons.chevron_right, size: 16, color: fg),
        ],
      ),
    ),
  );
}

/// One counselor slot styled exactly like a "My program" / timeline row:
/// the start time stacked over the (smaller, muted) end time in a narrow
/// left column, the counselor's name beside it with the place chip (dot +
/// muted label) beneath, and the status pill (volno / obsazeno /
/// rezervováno) trailing before the chevron. Tapping the row opens the
/// counselor's full profile in a dialog — where the anchored "sign up"
/// action lives. Booking happens ONLY via that explicit button — never on a
/// plain row tap (decision from user).
class _CounselorSlotTile extends StatelessWidget {
  final CounselorModel counselor;
  final CounselingSlot slot;
  final SpeakerModel? speaker;
  final List<String> areas;
  final String startTimeText;
  final String endTimeText;
  final bool isLoggedIn;
  final VoidCallback onBook;
  final VoidCallback onCancel;

  const _CounselorSlotTile({
    required this.counselor,
    required this.slot,
    required this.speaker,
    required this.areas,
    required this.startTimeText,
    required this.endTimeText,
    required this.isLoggedIn,
    required this.onBook,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final strong = ThemeConfig.blackColor(context);
    final muted = ThemeConfig.grey700(context);
    final sp = speaker;
    final detail =
        (counselor.subtitle != null && counselor.subtitle!.isNotEmpty)
            ? counselor.subtitle
            : sp?.subtitle;
    final place = slot.placeTitle;
    // Full "when": weekday + date + from–to, for the detail dialog.
    final st = slot.startTime?.toOccasionTime();
    final dialogTimeText = st == null
        ? null
        : "${DateFormat("EEEE d. M.", context.locale.languageCode).format(st)}"
            " $startTimeText${endTimeText.isNotEmpty ? " - $endTimeText" : ""}";
    // Time styles mirror the My-program timeline: start keeps the visual
    // weight, the end a step smaller and muted underneath.
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
    return InkWell(
      onTap: () => _showCounselorProfileDialog(
        context,
        imageUrl: counselor.image,
        name: counselor.title,
        detailText: detail,
        areas: areas,
        bioHtml: sp?.description,
        placeId: slot.place,
        placeTitle: slot.placeTitle,
        // No footer at all when there is nothing to act on (taken by someone
        // else) so the dialog doesn't render an empty anchored bar.
        footerBuilder: (slot.isSignedIn || !slot.isFull) ? _dialogAction : null,
        timeText: dialogTimeText,
      ),
      hoverColor: strong.withValues(alpha: 0.03),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 64,
              child: endTimeText.isNotEmpty
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(startTimeText, style: startStyle),
                        const SizedBox(height: 2),
                        Text(endTimeText, style: endStyle),
                      ],
                    )
                  : Text(startTimeText, style: startStyle),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(counselor.title ?? "",
                      style: TextStyle(
                          color: strong,
                          fontSize: 16,
                          height: 1.3,
                          fontWeight: FontWeight.w600)),
                  if (place != null && place.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: _placeChip(context, place),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 10),
              child: _statusPill(context),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, size: 22, color: muted),
          ],
        ),
      ),
    );
  }

  /// The place as the timeline's place chip: a small dot + muted label.
  Widget _placeChip(BuildContext context, String label) {
    final muted = ThemeConfig.grey700(context);
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
      ],
    );
  }

  /// The action anchored at the bottom of the profile dialog — always
  /// visible (the bio scrolls behind it), full width so it reads as THE
  /// action: sign-up for a free slot, the cancel anti-action for a reserved
  /// one (both close the dialog first), a red note when not signed in,
  /// nothing when the slot is taken by someone else.
  Widget _dialogAction(BuildContext ctx) {
    final s = slot;
    if (s.isSignedIn) {
      // The anti-action stays quiet — a plain text button like the one on
      // the reservation card, not a big filled bar.
      return Center(
        child: TextButton(
          onPressed: () {
            Navigator.of(ctx).pop();
            onCancel();
          },
          child: Text(SpeakersStrings.cancelReservation),
        ),
      );
    }
    if (s.isFull) return const SizedBox.shrink();
    if (!isLoggedIn) {
      return Text(SpeakersStrings.signInToReserve,
          textAlign: TextAlign.center,
          style: TextStyle(color: ThemeConfig.redColor(ctx)));
    }
    return ButtonsHelper.actionButton(
      context: ctx,
      icon: Icons.login,
      label: SpeakersStrings.signUp,
      expand: true,
      onPressed: () {
        Navigator.of(ctx).pop();
        onBook();
      },
    );
  }

  /// volno / obsazeno / rezervováno — the classic status pill, coloured by
  /// state (mirrors the program's capacity chip position on the time row).
  Widget _statusPill(BuildContext context) {
    final s = slot;
    if (s.isSignedIn) {
      return _pill(SpeakersStrings.reserved, Theme.of(context).primaryColor,
          Colors.white);
    }
    if (!s.isFull) {
      return _pill(SpeakersStrings.slotFree, ThemeConfig.greenColor(context),
          Colors.white);
    }
    return _pill(SpeakersStrings.slotTaken, ThemeConfig.grey300(context),
        ThemeConfig.grey700(context));
  }

  Widget _pill(String text, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
        child: Text(text,
            style: TextStyle(
                color: fg, fontSize: 12, fontWeight: FontWeight.w600)),
      );
}
