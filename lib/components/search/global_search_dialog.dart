import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/components/images/image_url_helper.dart';
import 'package:fstapp/components/information/info_page.dart';
import 'package:fstapp/components/map/map_navigation.dart';
import 'package:fstapp/components/schedule/event_model.dart';
import 'package:fstapp/components/schedule/event_page.dart';
import 'package:fstapp/components/schedule/schedule_strings.dart';
import 'package:fstapp/components/search/db_search.dart';
import 'package:fstapp/components/search/search_result_model.dart';
import 'package:fstapp/components/search/search_strings.dart';
import 'package:fstapp/components/speakers/speaker_medallion.dart';
import 'package:fstapp/components/speakers/speaker_model.dart';
import 'package:fstapp/components/speakers/speakers_bundle.dart';
import 'package:fstapp/components/html/html_helper.dart';
import 'package:fstapp/data_services/client_sync/client_sync_runtime.dart';
import 'package:fstapp/data_services/offline_data_service.dart';
import 'package:fstapp/database_tables/tb.dart';
import 'package:fstapp/router_service.dart';
import 'package:fstapp/services/time_helper.dart';
import 'package:fstapp/theme_config.dart';

/// Global search overlay across locally cached program, places, information,
/// songs, games, news and speakers.
class GlobalSearchDialog extends StatefulWidget {
  final Future<List<SearchResultModel>> Function(String query) search;
  final Future<SpeakersBundle?> Function() loadSpeakers;

  const GlobalSearchDialog({
    super.key,
    Future<List<SearchResultModel>> Function(String query)? search,
    Future<SpeakersBundle?> Function()? loadSpeakers,
  })  : search = search ?? DbSearch.search,
        loadSpeakers = loadSpeakers ?? OfflineDataService.getSpeakers;

  /// Guards against stacking dialogs when opened repeatedly (e.g. Ctrl+F
  /// pressed while the search is already showing).
  static bool _isShowing = false;

  static Future<void> show(BuildContext context) async {
    if (_isShowing) return;
    _isShowing = true;
    try {
      await showDialog(
        context: context,
        barrierColor: Colors.black.withValues(alpha: 0.5),
        builder: (_) => GlobalSearchDialog(),
      );
    } finally {
      _isShowing = false;
    }
  }

  @override
  State<GlobalSearchDialog> createState() => _GlobalSearchDialogState();
}

class _GlobalSearchDialogState extends State<GlobalSearchDialog> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;
  bool _loading = false;
  String _query = '';
  List<SearchResultModel> _results = [];
  int _requestId = 0;

  /// Cached events (by id) from the last offline sync, used to render program
  /// results exactly like the schedule: time range, place, occupancy and the
  /// current user's sign-in state — none of which the search RPC returns.
  final Map<int, EventModel> _eventsById = {};

  /// Full speaker records from the offline bundle. Search results only carry a
  /// name and short snippet; the cached record adds the photo, roles and bio
  /// needed by the profile dialog.
  final Map<int, SpeakerModel> _speakersById = {};
  Future<void> _speakersLoaded = Future.value();

  @override
  void initState() {
    super.initState();
    _loadEvents();
    _speakersLoaded = _loadSpeakers();
    ClientSyncRuntime.projectionEpoch.addListener(_onProjectionChanged);
  }

  void _onProjectionChanged() {
    _loadEvents();
    _speakersLoaded = _loadSpeakers();
    if (_controller.text.trim().isNotEmpty) {
      _run(_controller.text);
    }
  }

  Future<void> _loadEvents() async {
    try {
      final events = await OfflineDataService.getAllEvents();
      if (!mounted) return;
      setState(() {
        _eventsById
          ..clear()
          ..addEntries(
              events.where((e) => e.id != null).map((e) => MapEntry(e.id!, e)));
      });
    } catch (_) {
      // No cache available → program rows fall back to RPC fields only.
    }
  }

  Future<void> _loadSpeakers() async {
    try {
      final bundle = await widget.loadSpeakers();
      if (!mounted || bundle == null) return;
      setState(() {
        _speakersById
          ..clear()
          ..addEntries(bundle.speakers
              .where((s) => s.id != null)
              .map((s) => MapEntry(s.id!, s)));
      });
    } catch (_) {
      // No cache available → speaker rows fall back to the type icon.
    }
  }

  @override
  void dispose() {
    ClientSyncRuntime.projectionEpoch.removeListener(_onProjectionChanged);
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () => _run(value));
  }

  Future<void> _run(String value) async {
    final q = value.trim();
    final reqId = ++_requestId;
    setState(() {
      _query = q;
      _loading = q.isNotEmpty;
      if (q.isEmpty) _results = [];
    });
    if (q.isEmpty) return;
    final res = await widget.search(q);
    if (!mounted || reqId != _requestId) return;
    setState(() {
      _results = res;
      _loading = false;
    });
  }

  Future<void> _openResult(SearchResultModel r) async {
    if (r.entityType == 'speaker') {
      await _speakersLoaded;
      if (mounted) await _showSpeakerProfile(r);
      return;
    }

    Navigator.of(context).pop();
    // Public places use MapNavigation so warm and cold visits share the same
    // session contract. Other result types remain direct section routes.
    switch (r.entityType) {
      case 'event':
        RouterService.navigateOccasion(
            context, "${EventPage.ROUTE}/${r.entityId}");
        break;
      case 'place':
        MapNavigation.openPlace(context, r.entityId);
        break;
      case 'info':
        RouterService.navigateOccasion(
            context, "${InfoPage.ROUTE}/${r.entityId}");
        break;
      case 'song':
        RouterService.navigateOccasion(context, "songbook");
        break;
      case 'game':
        RouterService.navigateOccasion(context, "game");
        break;
      case 'news':
        RouterService.navigateOccasion(context, "news");
        break;
    }
  }

  Future<void> _showSpeakerProfile(SearchResultModel result) {
    final speaker = _speakersById[result.entityId];
    final fallbackDetail = _plainSnippet(result.snippet);
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        key: const Key('speaker-profile-dialog'),
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480, maxHeight: 640),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(dialogContext).pop(),
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  child: SpeakerMedallion(
                    imageUrl: speaker?.image,
                    name: speaker?.title ?? result.title,
                    detailText: speaker == null ? fallbackDetail : null,
                    pills: splitSpeakerRoles(speaker?.subtitle),
                    bioHtml: speaker?.description,
                    photoRadius: 82,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 48),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 8, 8),
              child: Row(
                children: [
                  const Icon(Icons.search),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      autofocus: true,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: SearchStrings.hint,
                        border: InputBorder.none,
                      ),
                      onChanged: _onChanged,
                      onSubmitted: _run,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(child: _buildBody(theme)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_query.isEmpty) {
      return _centeredHint(SearchStrings.emptyPrompt);
    }
    if (_results.isEmpty) {
      return _centeredHint(SearchStrings.noResults);
    }

    final children = <Widget>[];
    for (final group in SearchStrings.groupOrder) {
      var items = _results.where((r) => r.entityType == group).toList();
      if (items.isEmpty) continue;
      // Program results: running events first, then upcoming, then past —
      // keeping the relevance order within each bucket (indexed sort, because
      // List.sort is not stable).
      if (group == 'event') {
        final now = TimeHelper.now();
        final indexed = items.asMap().entries.toList()
          ..sort((a, b) {
            final byBucket = _temporalBucket(a.value, now)
                .compareTo(_temporalBucket(b.value, now));
            return byBucket != 0 ? byBucket : a.key.compareTo(b.key);
          });
        items = indexed.map((e) => e.value).toList();
      }
      children.add(_groupHeader(theme, group, items.length));
      for (var i = 0; i < items.length; i++) {
        children.add(_resultTile(theme, items[i], group));
        if (i < items.length - 1) {
          children.add(const Divider(height: 1, indent: 68, endIndent: 16));
        }
      }
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 8),
      children: children,
    );
  }

  /// Section header for a result group, e.g. the blue "Program" label, with a
  /// muted count so the list reads as structured sections.
  Widget _groupHeader(ThemeData theme, String group, int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            SearchStrings.groupTitle(group).toUpperCase(),
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$count',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _resultTile(ThemeData theme, SearchResultModel r, String group) {
    // Program results mirror the schedule row (time / place / occupancy /
    // sign-in); everything else is a compact title + one-line description.
    if (group == 'event') return _eventTile(theme, r);
    return _genericTile(theme, r, group);
  }

  /// Fixed-height row scaffold so the list keeps a stable rhythm regardless of
  /// how much text each result carries.
  Widget _rowScaffold(
    ThemeData theme, {
    required Widget leading,
    required Widget child,
    required VoidCallback onTap,
    Widget? trailing,
    double minHeight = 58,
  }) {
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: minHeight),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              leading,
              const SizedBox(width: 12),
              Expanded(child: child),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                trailing,
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _genericTile(ThemeData theme, SearchResultModel r, String group) {
    final hasTitle = r.title?.isNotEmpty ?? false;
    final snippet = _plainSnippet(r.snippet);
    // Title-less entities (e.g. news) put their snippet on the main line.
    final titleText = hasTitle ? r.title! : snippet;
    final subtitleText = hasTitle ? snippet : '';

    return _rowScaffold(
      theme,
      leading: _leading(theme, group, _leadingImageUrl(r, group)),
      onTap: () => _openResult(r),
      trailing: _chevron(theme),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titleText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          if (subtitleText.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              subtitleText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }

  /// Temporal ordering bucket: 0 = running right now, 1 = upcoming, 2 = past.
  /// Falls back to the result's start time when the full event model (with an
  /// end time) isn't loaded.
  int _temporalBucket(SearchResultModel r, DateTime now) {
    final model = _eventsById[r.entityId];
    if (model != null) {
      if (model.endTime.isBefore(now)) return 2;
      if (model.startTime.isBefore(now)) return 0;
      return 1;
    }
    final start = r.startTime;
    if (start == null) return 1;
    return start.isBefore(now) ? 2 : 1;
  }

  Widget _eventTile(ThemeData theme, SearchResultModel r) {
    final model = _eventsById[r.entityId];
    final titleText =
        (model?.title?.isNotEmpty ?? false) ? model!.title! : (r.title ?? '');
    final cancelled = model?.isCancelled ?? false;
    final timeStr = model != null
        ? model.durationTimeString()
        : (r.startTime != null ? DateFormat.Hm().format(r.startTime!) : '');
    final start = model?.startTime ?? r.startTime;
    final dateStr = start != null
        ? DateFormat("EEE d.M.", context.locale.languageCode).format(start)
        : '';
    final placeTitle =
        model?.place?.title ?? (r.extra['place_title'] as String?);
    final supportsSignIn = model != null &&
        EventModel.isEventSupportingSignIn(model) &&
        model.participantCapacityLabel != null &&
        !cancelled;
    final now = TimeHelper.now();
    final isNow = model != null &&
        !cancelled &&
        model.startTime.isBefore(now) &&
        model.endTime.isAfter(now);
    final isPast = _temporalBucket(r, now) == 2;

    final tile = _rowScaffold(
      theme,
      minHeight: 62,
      leading: _leading(theme, 'event', _leadingImageUrl(r, 'event')),
      onTap: () => _openResult(r),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (supportsSignIn) _capacityChip(theme, model),
          if (supportsSignIn) const SizedBox(width: 8),
          _chevron(theme),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titleText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              decoration:
                  cancelled ? TextDecoration.lineThrough : TextDecoration.none,
            ),
          ),
          const SizedBox(height: 3),
          _eventMetaLine(theme, timeStr, placeTitle,
              dateStr: dateStr, isNow: isNow, isPast: isPast),
        ],
      ),
    );
    // Past events read as archive: the whole row dims.
    return isPast ? Opacity(opacity: 0.55, child: tile) : tile;
  }

  /// Small colored pill ("RIGHT NOW" / "ENDED") prefixed to a program row's
  /// meta line — same look as the badges in the schedule views.
  Widget _metaBadge(Color background, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  /// "pá 14.8. 17:30 - 19:30 · Place" meta line for a program result: a small
  /// day chip, then the time range, optionally prefixed with the red
  /// "RIGHT NOW" or grey "ENDED" badge.
  Widget _eventMetaLine(ThemeData theme, String timeStr, String? place,
      {String dateStr = '', bool isNow = false, bool isPast = false}) {
    final color = theme.colorScheme.onSurfaceVariant;
    final style = theme.textTheme.bodySmall?.copyWith(color: color);
    final children = <Widget>[];
    if (isNow) {
      children
        ..add(Builder(
            builder: (context) => _metaBadge(
                ThemeConfig.redColor(context), ScheduleStrings.rightNow)))
        ..add(const SizedBox(width: 6));
    } else if (isPast) {
      children
        ..add(_metaBadge(Colors.grey.shade600, ScheduleStrings.ended))
        ..add(const SizedBox(width: 6));
    }
    if (dateStr.isNotEmpty) {
      children
        ..add(Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            dateStr,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ))
        ..add(const SizedBox(width: 6));
    }
    if (timeStr.isNotEmpty) {
      children
        ..add(Icon(Icons.schedule, size: 13, color: color))
        ..add(const SizedBox(width: 4))
        ..add(Text(timeStr, style: style));
    }
    if (place != null && place.isNotEmpty) {
      if (children.isNotEmpty) {
        children.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text('·', style: style),
        ));
      }
      children
        ..add(Icon(Icons.place_outlined, size: 13, color: color))
        ..add(const SizedBox(width: 4))
        ..add(Flexible(
          child: Text(place,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
        ));
    }
    if (children.isEmpty) return const SizedBox.shrink();
    return Row(children: children);
  }

  /// Occupancy badge mirroring the schedule's capacity chip: a filled
  /// primary-colour pill when the current user is signed in, muted text
  /// otherwise.
  Widget _capacityChip(ThemeData theme, EventModel model) {
    final text = model.participantCapacityLabel;
    if (text == null) return const SizedBox.shrink();
    if (model.isSignedIn == true) {
      final fg = theme.cardColor;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: theme.primaryColor,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text,
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: fg, fontWeight: FontWeight.w600)),
            const SizedBox(width: 4),
            Icon(Icons.people, size: 14, color: fg),
          ],
        ),
      );
    }
    final fg = theme.colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(text, style: theme.textTheme.labelSmall?.copyWith(color: fg)),
        const SizedBox(width: 4),
        Icon(Icons.people, size: 14, color: fg),
      ],
    );
  }

  Widget _chevron(ThemeData theme) => Icon(
        Icons.chevron_right,
        size: 18,
        color: ThemeConfig.grey600(context),
      );

  /// Custom image for a result, if it has one: a program's header image or a
  /// speaker's avatar. Everything else (and any result without an image) keeps
  /// the tinted type icon, so the leading column stays visually unified.
  String? _leadingImageUrl(SearchResultModel r, String group) {
    switch (group) {
      case 'event':
        final img = _eventsById[r.entityId]?.data?[Tb.events.dataHeaderImage];
        return (img is String && img.isNotEmpty) ? img : null;
      case 'speaker':
        return _speakersById[r.entityId]?.image;
      default:
        return null;
    }
  }

  /// A 40×40 circular leading slot: the custom image when present, otherwise
  /// the tinted type icon (also used while loading or on error).
  Widget _leading(ThemeData theme, String group, String? imageUrl) {
    if (imageUrl == null || imageUrl.isEmpty) {
      return _leadingIcon(theme, group);
    }
    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: ImageUrlHelper.transformImageUrl(imageUrl,
            width: ImageUrlHelper.thumbnailWidth),
        width: 40,
        height: 40,
        fit: BoxFit.cover,
        placeholder: (_, __) => _leadingIcon(theme, group),
        errorWidget: (_, __, ___) => _leadingIcon(theme, group),
      ),
    );
  }

  Widget _leadingIcon(ThemeData theme, String group) {
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.10),
        shape: BoxShape.circle,
      ),
      child: Icon(
        _groupIcon(group),
        size: 20,
        color: theme.colorScheme.primary,
      ),
    );
  }

  IconData _groupIcon(String group) {
    switch (group) {
      case 'event':
        return Icons.event_outlined;
      case 'speaker':
        return Icons.record_voice_over_outlined;
      case 'place':
        return Icons.place_outlined;
      case 'song':
        return Icons.music_note_outlined;
      case 'game':
        return Icons.sports_esports_outlined;
      case 'news':
        return Icons.campaign_outlined;
      case 'info':
      default:
        return Icons.info_outline;
    }
  }

  /// Snippets are already clean plain text (the server's `f_html_snippet` and
  /// the offline index both strip markup and add an ellipsis when they truncate).
  /// Strip once more as a safety net in case a raw-HTML fragment slips through.
  String _plainSnippet(String? html) {
    if (html == null || html.isEmpty) return '';
    return HtmlHelper.htmlToPlainText(html);
  }

  Widget _centeredHint(String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(text, textAlign: TextAlign.center),
        ),
      );
}
