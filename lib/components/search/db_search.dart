import 'package:fstapp/components/features/feature_constants.dart';
import 'package:fstapp/components/features/feature_service.dart';
import 'package:fstapp/components/information/information_model.dart';
import 'package:fstapp/components/search/offline_search_index.dart';
import 'package:fstapp/components/search/search_result_model.dart';
import 'package:fstapp/data_services/client_sync/client_sync_runtime.dart';
import 'package:fstapp/data_services/offline_data_service.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/services/app_logger.dart';

/// Data access for the GlobalSearch feature.
///
/// Queries always use local cached projections. The index lazily rebuilds on
/// first use and whenever [ClientSyncRuntime.searchProjectionEpoch] changes.
/// Per-user and live-state changes do not invalidate searchable text.
class DbSearch {
  static const int _limit = 50;
  static final OfflineSearchIndexCache _offlineIndex = OfflineSearchIndexCache(
    loadDocuments: _loadDocuments,
    readEpoch: () => ClientSyncRuntime.searchProjectionEpoch.value,
    limit: _limit,
  );

  static Future<List<SearchResultModel>> search(String query) async {
    final q = query.trim();
    if (q.isEmpty) return [];
    if (!FeatureService.isFeatureEnabled(FeatureConstants.globalSearch)) {
      return [];
    }
    final occasionId = RightsService.currentOccasionId();
    if (occasionId == null) return [];

    return _offlineIndex.search(q);
  }

  /// Rebuilds the offline search index from cached events / places / news.
  /// Called after an offline sync completes.
  static Future<void> rebuildOfflineIndex() async {
    try {
      await _offlineIndex.rebuild();
    } catch (_) {
      // Keep the previous index. A later query retries because its epoch was
      // not accepted by the failed rebuild.
      AppLogger.warning('Offline search index rebuild failed');
    }
  }

  static Future<List<OfflineSearchDocument>> _loadDocuments() async {
    final docs = <OfflineSearchDocument>[];

    for (final e in await OfflineDataService.getAllEvents()) {
      if (e.isCounselingSlot) continue;
      docs.add(OfflineSearchDocument(
        entityType: 'event',
        entityId: e.id ?? 0,
        title: e.title,
        snippet: e.description,
        startTime: e.startTime,
        searchText: '${e.title ?? ''} ${e.description ?? ''}',
      ));
    }
    for (final p in await OfflineDataService.getAllPlaces()) {
      docs.add(OfflineSearchDocument(
        entityType: 'place',
        entityId: p.id ?? 0,
        title: p.title,
        snippet: p.description,
        searchText: '${p.title ?? ''} ${p.description ?? ''}',
      ));
    }
    for (final n in await OfflineDataService.getAllMessages()) {
      docs.add(OfflineSearchDocument(
        entityType: 'news',
        entityId: n.id,
        title: null,
        snippet: n.message,
        searchText: n.message ?? '',
      ));
    }

    // Information / songs / games keep the same feature gating as their
    // source projections.
    final songbookEnabled =
        FeatureService.isFeatureEnabled(FeatureConstants.songbook);
    final gameEnabled = FeatureService.isFeatureEnabled(FeatureConstants.game);
    for (final info in await OfflineDataService.getAllInfo()) {
      if (info.isHidden == true) continue;
      final String entityType;
      if (info.type == InformationModel.songType) {
        if (!songbookEnabled) continue;
        entityType = 'song';
      } else if (info.type == InformationModel.gameType) {
        if (!gameEnabled) continue;
        entityType = 'game';
      } else {
        entityType = 'info';
      }
      docs.add(OfflineSearchDocument(
        entityType: entityType,
        entityId: info.id ?? 0,
        title: info.title,
        snippet: info.description,
        searchText: '${info.title ?? ''} ${info.description ?? ''}',
      ));
    }

    // Speakers / counselors are core: always indexed (no feature gate,
    // matching the server-side branch — decision R7). parentId carries the
    // speaker's first non-slot event so the offline result opens a page where
    // the medallion shows.
    final bundle = await OfflineDataService.getSpeakers();
    if (bundle != null) {
      for (final s in bundle.speakers) {
        if (s.isHidden || s.id == null) continue;
        final firstEvent = bundle.speakersByEvent.entries
            .firstWhere((e) => e.value.contains(s.id),
                orElse: () => const MapEntry(-1, []))
            .key;
        docs.add(OfflineSearchDocument(
          entityType: 'speaker',
          entityId: s.id!,
          title: s.title,
          snippet:
              (s.subtitle?.isNotEmpty ?? false) ? s.subtitle : s.description,
          parentId: firstEvent > 0 ? firstEvent : null,
          searchText:
              '${s.title ?? ''} ${s.subtitle ?? ''} ${s.description ?? ''}',
        ));
      }
    }
    return docs;
  }
}
