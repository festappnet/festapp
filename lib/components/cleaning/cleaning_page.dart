import 'dart:async';
import 'dart:convert';

import 'package:auto_route/auto_route.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart' show Uint8List;
import 'package:flutter/material.dart';
import 'package:fstapp/components/cleaning/cleaning_status.dart';
import 'package:fstapp/components/cleaning/cleaning_strings.dart';
import 'package:fstapp/components/cleaning/db_cleaning.dart';
import 'package:fstapp/components/cleaning/models/cleaning_place_status.dart';
import 'package:fstapp/components/cleaning/cleaning_report_flow.dart';
import 'package:fstapp/components/cleaning/models/cleaning_report.dart';
import 'package:fstapp/components/cleaning/models/cleaning_data.dart';
import 'package:fstapp/components/cleaning/widgets/cleaning_blocked_banner.dart';
import 'package:fstapp/components/cleaning/widgets/cleaning_crew_report_card.dart';
import 'package:fstapp/components/cleaning/widgets/cleaning_history_row.dart';
import 'package:fstapp/components/cleaning/widgets/cleaning_legend.dart';
import 'package:fstapp/components/cleaning/widgets/cleaning_report_hint.dart';
import 'package:fstapp/components/cleaning/widgets/cleaning_summary_banner.dart';
import 'package:fstapp/components/cleaning/widgets/cleaning_tile.dart';
import 'package:fstapp/components/features/feature_constants.dart';
import 'package:fstapp/components/features/feature_service.dart';
import 'package:fstapp/components/map/map_navigation.dart';
import 'package:fstapp/components/offline/offline_strings.dart';
import 'package:fstapp/data_services/offline_data_service.dart';
import 'package:fstapp/data_services/client_sync/client_sync_runtime.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/services/exception_handler.dart';
import 'package:fstapp/services/connectivity_service.dart';
import 'package:fstapp/services/toast_helper.dart';
import 'package:fstapp/styles/styles_config.dart';
import 'package:fstapp/theme_config.dart';
import 'package:fstapp/widgets/navigate_back_button.dart';
import 'package:intl/intl.dart';

/// Cleaning service page. Shows a grid of toilets colored by their derived
/// status; tapping a toilet opens the report dialog. Every participant can
/// report (Q7). The cleaning crew additionally sees the reported notes/times
/// and can mark a whole toilet as cleaned.
///
/// Top-level occasion route (own Scaffold, like CounselingPage) with an optional
/// `:id` deep-link that opens the report dialog for that toilet directly —
/// groundwork for QR stickers (Q5).
@RoutePage()
class CleaningPage extends StatefulWidget {
  static const ROUTE = "cleaning";

  final int? id;

  const CleaningPage({@pathParam this.id, super.key});

  @override
  State<CleaningPage> createState() => _CleaningPageState();
}

class _CleaningPageState extends State<CleaningPage> {
  static const Duration _pollInterval = Duration(seconds: 30);

  List<CleaningPlaceStatus> _places = [];
  List<CleaningReport> _reports = [];
  bool _loading = true;
  bool _isBlocked = false;
  bool _notificationsMuted = false;
  bool _showHistory = false;
  bool _exportingHistory = false;
  bool _deepLinkHandled = false;
  Timer? _pollTimer;

  /// Set when the page renders from the offline cache (live fetch failed);
  /// carries the cache age for the banner. Null = live data.
  DateTime? _cacheFetchedAt;

  bool get _isCrew => RightsService.isCleaningCrew();
  int get _occasionId => RightsService.currentOccasionId()!;

  @override
  void initState() {
    super.initState();
    _loadData();
    // Live data matters for the crew; poll quietly while the page is open.
    if (_isCrew && !ClientSyncRuntime.isV1Selected) {
      _pollTimer =
          Timer.periodic(_pollInterval, (_) => _loadData(silent: true));
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadData({bool silent = false}) async {
    if (!shouldLoadLiveCleaningData(
      isClientSyncV1: ClientSyncRuntime.isV1Selected,
      isCleaningCrew: _isCrew,
    )) {
      final cached = await OfflineDataService.getCleaningStatus();
      if (!mounted) return;
      setState(() {
        _places = cached?.places ?? [];
        _reports = [];
        _isBlocked =
            RightsService.currentOccasionUser()?.isCleaningBlocked ?? false;
        _cacheFetchedAt = cached?.fetchedAt;
        _loading = false;
      });
      _maybeHandleDeepLink();
      return;
    }
    Future<CleaningData> fetch() async {
      final status = await DbCleaning.getStatus(_occasionId);
      // Refresh-on-read: keep the offline copy of the public statuses fresh.
      await OfflineDataService.saveCleaningStatus(
          status.places, DateTime.now());
      // The crew fetches resolved reports too so the History tab needs no reload.
      final reports = _isCrew
          ? await DbCleaning.getReports(_occasionId, includeResolved: true)
          : <CleaningReport>[];
      return CleaningData(
          status.places, reports, status.isBlocked, status.notificationsMuted);
    }

    CleaningData? data;
    if (silent) {
      // Background poll: swallow transient errors instead of popping UI.
      try {
        data = await fetch();
      } catch (_) {
        return;
      }
    } else {
      try {
        data = await fetch();
      } catch (e) {
        // Live fetch failed (typically offline): render the cached public
        // statuses with their age instead. Crew controls need live data and
        // are hidden in this mode. With no cache, keep today's error UI.
        final cached = await OfflineDataService.getCleaningStatus();
        if (!mounted) return;
        if (cached != null) {
          setState(() {
            _places = cached.places;
            _reports = [];
            _cacheFetchedAt = cached.fetchedAt;
            _loading = false;
          });
          _maybeHandleDeepLink();
          return;
        }
        await ExceptionHandler.handle(context, error: e);
      }
    }
    if (!mounted) return;
    setState(() {
      if (data != null) {
        _places = data.places;
        _reports = data.reports;
        _isBlocked = data.isBlocked;
        _notificationsMuted = data.notificationsMuted;
        _cacheFetchedAt = null;
      }
      _loading = false;
    });
    _maybeHandleDeepLink();
  }

  /// When opened via `cleaning/:id`, open the report dialog for that toilet once
  /// the status list is available.
  void _maybeHandleDeepLink() {
    if (_deepLinkHandled || widget.id == null) return;
    _deepLinkHandled = true;
    CleaningPlaceStatus? place;
    for (final p in _places) {
      if (p.place == widget.id) {
        place = p;
        break;
      }
    }
    if (place != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openReportDialog(place!);
      });
    }
  }

  Future<void> _openReportDialog(CleaningPlaceStatus place) async {
    // Blocked reporters (anti-spam ban) still see the page but cannot report.
    if (_isBlocked && !_isCrew) {
      ToastHelper.Show(context, CleaningStrings.blockedMessage,
          severity: ToastSeverity.NotOk);
      return;
    }
    final changed = await CleaningReportFlow.report(
      context,
      placeId: place.place,
      placeTitle: place.title,
      onShowOnMap: () => MapNavigation.openPlace(context, place.place),
    );
    if (changed && mounted) await _loadData();
  }

  void _openMapFiltered() {
    MapNavigation.openCategory(
      context,
      CleaningStatusHelper.toiletPlaceTypeCode,
    );
  }

  Future<void> _resolvePlace(int placeId) async {
    await ExceptionHandler.guardVoid(
      context,
      futureFunction: () async {
        await DbCleaning.resolvePlace(placeId);
        if (!mounted) return;
        ToastHelper.Show(context, CleaningStrings.cleanedConfirm);
        await _loadData();
      },
    );
  }

  /// Toggles the current user's cleaning-notification opt-out (self-service).
  Future<void> _setNotificationsMuted(bool muted) async {
    // Optimistic: reflect the switch immediately, revert on failure.
    setState(() => _notificationsMuted = muted);
    try {
      await DbCleaning.setNotificationsMuted(
          occasionId: _occasionId, muted: muted);
    } catch (_) {
      if (!mounted) return;
      setState(() => _notificationsMuted = !muted);
      ToastHelper.Show(context, CleaningStrings.reportError,
          severity: ToastSeverity.NotOk);
    }
  }

  /// Crew blocks a repeat offender straight from their report (confirm first).
  Future<void> _blockReporter(CleaningReport report) async {
    final userId = report.createdBy;
    if (userId == null) return;
    final name = report.createdByName ?? CleaningStrings.anonymous;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(CleaningStrings.blockReporter),
        content: Text(CleaningStrings.blockReporterConfirm(name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(CleaningStrings.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(CleaningStrings.blockReporter),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await ExceptionHandler.guardVoid(
      context,
      futureFunction: () async {
        await DbCleaning.setReporterBlocked(
          occasionId: _occasionId,
          userId: userId,
          blocked: true,
        );
        if (!mounted) return;
        ToastHelper.Show(context, CleaningStrings.reporterBlocked);
        await _loadData();
      },
    );
  }

  /// Builds a plain-text export of the whole report history and saves it.
  Future<void> _exportHistory(List<CleaningReport> history) async {
    setState(() => _exportingHistory = true);
    try {
      final occasionTitle =
          RightsService.currentOccasion()?.title ?? CleaningStrings.pageTitle;
      final text = _buildHistoryText(occasionTitle, history);
      final bytes = <int>[0xEF, 0xBB, 0xBF, ...utf8.encode(text)];
      await FileSaver.instance.saveFile(
        name: 'cleaning_history',
        bytes: Uint8List.fromList(bytes),
        fileExtension: 'txt',
        mimeType: MimeType.text,
      );
    } finally {
      if (mounted) setState(() => _exportingHistory = false);
    }
  }

  /// One line per report: `date time · WC · type · "note" · reporter · state`,
  /// extra (duplicate) notes indented below. Header = occasion + export date.
  String _buildHistoryText(String occasionTitle, List<CleaningReport> history) {
    final dateFmt = DateFormat('yyyy-MM-dd HH:mm');
    final buf = StringBuffer();
    buf.writeln(occasionTitle);
    buf.writeln(
        '${CleaningStrings.historyTitle} · ${dateFmt.format(DateTime.now())}');
    buf.writeln('');
    for (final r in history) {
      final reporter = r.createdByName ?? CleaningStrings.anonymous;
      final state = r.resolvedAt != null
          ? CleaningStrings.historyCleanedAt(dateFmt.format(r.resolvedAt!))
          : CleaningStrings.historyOpen;
      final parts = <String>[
        dateFmt.format(r.createdAt),
        r.placeTitle,
        CleaningStrings.problemLabel(r.problemType),
        if (r.note != null && r.note!.isNotEmpty) '„${r.note}"',
        reporter,
        state,
      ];
      buf.writeln(parts.join(' · '));
      for (final note in r.extraNotes) {
        buf.writeln('    „$note"');
      }
    }
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const ScheduleBackButton(),
        title: Text(CleaningStrings.pageTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.map_outlined),
            tooltip: CleaningStrings.toiletsOnMap,
            onPressed: _openMapFiltered,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: CleaningStrings.refresh,
            onPressed: () => _loadData(),
          ),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: StylesConfig.appMaxWidth),
          child: ValueListenableBuilder<bool>(
            valueListenable: ConnectivityService.isOfflineNotifier,
            builder: (context, _, __) => RefreshIndicator(
              onRefresh: () => _loadData(),
              child: _buildBody(context),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    // Feature gate: the page is reachable via deep-link even when the occasion
    // has the cleaning feature turned off — show a plain notice instead of data.
    if (!FeatureService.isFeatureEnabled(FeatureConstants.cleaning)) {
      return _buildFeatureDisabled(context);
    }
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_places.isEmpty) {
      return _buildEmptyState(context);
    }

    final reportsByPlace = <int, List<CleaningReport>>{};
    for (final r in _reports) {
      reportsByPlace.putIfAbsent(r.place, () => []).add(r);
    }
    final problemPlaces =
        _places.where((p) => p.status != CleaningStatus.green).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        // Cached statuses: say how old they are (freshness matters here).
        if (shouldShowCleaningOfflineBanner(
          cacheFetchedAt: _cacheFetchedAt,
          isOffline: ConnectivityService.isOfflineNotifier.value,
        )) ...[
          _buildCacheAgeBanner(context),
          const SizedBox(height: 12),
        ],
        // Crew get the operational overview; a plain participant gets a simple
        // "pick a toilet and report" hint (or the blocked notice) — nothing
        // crew-oriented.
        if (_isCrew)
          CleaningSummaryBanner(places: _places)
        else if (_isBlocked)
          const CleaningBlockedBanner()
        else
          const CleaningReportHint(),
        const SizedBox(height: 18),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 118,
            childAspectRatio: 1.02,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
          itemCount: _places.length,
          itemBuilder: (context, index) =>
              CleaningTile(place: _places[index], onTap: _openReportDialog),
        ),
        const SizedBox(height: 16),
        const CleaningLegend(),
        // Crew-only: "Current / History" tabs over the detailed reports.
        // Hidden when rendering from cache — mute/block/resolve/history all
        // need live data.
        if (_isCrew && _cacheFetchedAt == null) ...[
          const SizedBox(height: 28),
          _buildCrewSection(context, problemPlaces, reportsByPlace),
        ],
      ],
    );
  }

  /// "Last updated {time}" strip shown above cached (offline) statuses.
  Widget _buildCacheAgeBanner(BuildContext context) {
    final time = DateFormat('d. M. HH:mm').format(_cacheFetchedAt!);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: ThemeConfig.grey300(context).withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off, size: 18, color: ThemeConfig.grey600(context)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              "${OfflineStrings.youAreOffline} ${OfflineStrings.lastUpdated(time)}",
              style:
                  TextStyle(color: ThemeConfig.grey600(context), fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  /// Crew section: "Current / History" tabs. Current shows the actionable
  /// problem cards; History lists every report (incl. resolved) with a .txt
  /// export.
  Widget _buildCrewSection(
    BuildContext context,
    List<CleaningPlaceStatus> problemPlaces,
    Map<int, List<CleaningReport>> reportsByPlace,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Self-service opt-out: each crew member can turn cleaning push
        // notifications off for themselves.
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          secondary: Icon(
            _notificationsMuted
                ? Icons.notifications_off_outlined
                : Icons.notifications_active_outlined,
            color: ThemeConfig.grey600(context),
          ),
          title: Text(CleaningStrings.notifyOnReports),
          value: !_notificationsMuted,
          onChanged: (on) => _setNotificationsMuted(!on),
        ),
        const Divider(height: 8),
        const SizedBox(height: 8),
        Center(
          child: SegmentedButton<bool>(
            segments: [
              ButtonSegment(
                value: false,
                icon: const Icon(Icons.assignment_outlined),
                label: Text(CleaningStrings.tabCurrent),
              ),
              ButtonSegment(
                value: true,
                icon: const Icon(Icons.history),
                label: Text(CleaningStrings.tabHistory),
              ),
            ],
            selected: {_showHistory},
            onSelectionChanged: (s) => setState(() => _showHistory = s.first),
          ),
        ),
        const SizedBox(height: 16),
        if (!_showHistory)
          _buildCurrentReports(problemPlaces, reportsByPlace)
        else
          _buildHistory(context),
      ],
    );
  }

  Widget _buildCurrentReports(
    List<CleaningPlaceStatus> problemPlaces,
    Map<int, List<CleaningReport>> reportsByPlace,
  ) {
    if (problemPlaces.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(
          CleaningStrings.allClean,
          textAlign: TextAlign.center,
          style: TextStyle(color: ThemeConfig.grey600(context)),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final place in problemPlaces)
          CleaningCrewReportCard(
            place: place,
            // Only open reports are actionable in the Current tab.
            reports: (reportsByPlace[place.place] ?? const [])
                .where((r) => r.resolvedAt == null)
                .toList(),
            onResolve: () => _resolvePlace(place.place),
            onBlock: _blockReporter,
          ),
      ],
    );
  }

  Widget _buildHistory(BuildContext context) {
    final history = _reports; // already sorted newest-first by the RPC
    if (history.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(
          CleaningStrings.historyEmpty,
          textAlign: TextAlign.center,
          style: TextStyle(color: ThemeConfig.grey600(context)),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: double.infinity,
          child: FilledButton.tonalIcon(
            onPressed: _exportingHistory ? null : () => _exportHistory(history),
            icon: _exportingHistory
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download),
            label: Text(CleaningStrings.download),
          ),
        ),
        const SizedBox(height: 12),
        for (final r in history) CleaningHistoryRow(report: r),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 90),
        Icon(Icons.cleaning_services_outlined,
            size: 56, color: ThemeConfig.grey600(context)),
        const SizedBox(height: 16),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              CleaningStrings.noToilets,
              textAlign: TextAlign.center,
              style:
                  TextStyle(color: ThemeConfig.grey600(context), fontSize: 16),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFeatureDisabled(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 90),
        Icon(Icons.cleaning_services_outlined,
            size: 56, color: ThemeConfig.grey600(context)),
        const SizedBox(height: 16),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              CleaningStrings.featureDisabled,
              textAlign: TextAlign.center,
              style:
                  TextStyle(color: ThemeConfig.grey600(context), fontSize: 16),
            ),
          ),
        ),
      ],
    );
  }
}
