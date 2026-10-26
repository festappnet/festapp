import 'dart:async';

import 'notification_center_calendar.dart';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef NotificationRead = Future<dynamic> Function(
  String,
  Map<String, dynamic>,
);

class NotificationItem {
  NotificationItem.fromJson(Map<String, dynamic> json)
    : id = json['id'].toString(),
      section = json['section'] as int? ?? 2,
      sequence = json['sequence'] as int? ?? 0,
      occasionId = json['occasionId'] as int?,
      occasionTitle = json['occasionTitle'] as String?,
      kind = json['kind'] as String? ?? '',
      status = json['status'] as String? ?? '',
      occurredAt = DateTime.tryParse(json['occurredAt']?.toString() ?? ''),
      occasionLink = json['occasionLink'] as String?,
      data = Map<String, dynamic>.from(json['data'] as Map? ?? {});
  final String id, kind, status;
  final int section, sequence;
  final int? occasionId;
  final String? occasionTitle;
  final DateTime? occurredAt;
  final String? occasionLink;
  final Map<String, dynamic> data;
  bool get isPeriod => kind == 'order_activity_group';
  Map<String, dynamic> get period =>
      Map<String, dynamic>.from(data['period'] as Map);
}

class NotificationPeriodState {
  bool expanded = false, loading = false, failed = false;
  int request = 0;
  List<NotificationItem> items = [];
  dynamic nextCursor;
}

/// Only open acknowledges. Generation and revision fences reject stale polls.
class NotificationCenterController extends ChangeNotifier {
  NotificationCenterController({NotificationRead? read})
    : _read =
          read ??
          ((name, params) =>
              Supabase.instance.client.rpc(name, params: params));
  final NotificationRead _read;
  int? organization, currentOccasion;
  String? user;
  int _generation = 0, _revision = 0, _badgeRequest = 0;
  bool enabled = false,
      unread = false,
      loading = false,
      failed = false,
      pageFailed = false;
  bool panelOpen = false, foreground = true, refreshFailed = false;
  int snapshot = 0;
  DateTime? snapshotAt;
  List<Map<String, dynamic>> periods = [];
  final Map<String, NotificationPeriodState> periodStates = {};
  NotificationPeriodState periodState(NotificationItem item) =>
      periodStates.putIfAbsent(item.id, NotificationPeriodState.new);
  Map<String, dynamic> get _timelineScope => {
    ..._scope,
    'p_snapshot': snapshot,
    'p_snapshot_at': snapshotAt!.toIso8601String(),
  };
  List<NotificationItem> items = [];
  List<Map<String, dynamic>> occasions = [];
  dynamic nextCursor;
  Timer? _timer;
  bool _unsupported = false;
  Map<String, dynamic> get _scope => {
    'p_organization': organization,
    'p_current_occasion': currentOccasion,
  };

  void configure({
    required String? userId,
    required int? organizationId,
    int? occasionId,
    bool invalidate = false,
  }) {
    if (!invalidate &&
        user == userId &&
        organization == organizationId &&
        currentOccasion == occasionId) {
      return;
    }
    final identityChanged = user != userId || organization != organizationId;
    _generation++;
    _revision++;
    user = userId;
    organization = organizationId;
    currentOccasion = occasionId;
    if (identityChanged || invalidate) enabled = unread = false;
    failed = pageFailed = loading = false;
    nextCursor = null;
    snapshot = 0;
    snapshotAt = null;
    periods = [];
    periodStates.clear();
    panelOpen = false;
    items = [];
    occasions = [];
    refreshFailed = false;
    _schedule();
    if ((identityChanged || invalidate) &&
        user != null &&
        organization != null) {
      unawaited(refreshBadge());
    }
    notifyListeners();
  }

  void _schedule() {
    _timer?.cancel();
    if (!_unsupported && foreground && user != null && organization != null) {
      _timer = Timer.periodic(
        Duration(seconds: panelOpen ? 15 : 60),
        (_) => refresh(),
      );
    }
  }

  bool _refreshing = false;
  Future<void> refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    final generation = _generation, revision = _revision;
    try {
      await refreshBadge();
      if (!panelOpen ||
          loading ||
          !foreground ||
          organization == null ||
          user == null ||
          generation != _generation ||
          revision != _revision) {
        return;
      }
      final captured = [
        ...items.where((item) => !item.isPeriod),
        for (final state in periodStates.values) ...state.items,
      ].map((item) => item.id).toSet();
      final ids = captured.toList();
      final updates = <String, NotificationItem>{};
      for (var start = 0; start < ids.length; start += 200) {
        final result = await _read('get_notification_center_updates', {
          'p_organization': organization,
          'p_snapshot': snapshot,
          'p_ids': ids.sublist(start, (start + 200).clamp(0, ids.length)),
        });
        if (generation != _generation || revision != _revision) return;
        for (final row in result['items'] as List? ?? []) {
          final item = NotificationItem.fromJson(
            Map<String, dynamic>.from(row),
          );
          updates[item.id] = item;
        }
      }
      final headers = items.where((item) => item.isPeriod).toList();
      final counts = <String, Map<String, dynamic>>{};
      for (var start = 0; start < headers.length; start += 200) {
        final result = await _read(
          'get_notification_center_timeline_group_updates',
          {
            ..._timelineScope,
            'p_groups': headers
                .sublist(start, (start + 200).clamp(0, headers.length))
                .map(
                  (item) => {
                    'id': item.id,
                    'occasionId': item.occasionId,
                    'period': item.period,
                  },
                )
                .toList(),
          },
        );
        if (generation != _generation || revision != _revision) return;
        for (final row in result['groups'] as List? ?? []) {
          final value = Map<String, dynamic>.from(row);
          counts[value['id'] as String] = value;
        }
      }
      // Live facts may change, but snapshot positions and date boundaries stay fixed.
      NotificationItem hydrate(NotificationItem item) {
        final update = updates[item.id];
        if (update == null) return item;
        return NotificationItem.fromJson({
          'id': update.id,
          'kind': update.kind,
          'status': update.status,
          'occurredAt': item.occurredAt?.toIso8601String(),
          'section': item.section,
          'sequence': item.sequence,
          'occasionId': item.occasionId,
          'occasionTitle': update.occasionTitle,
          'occasionLink': update.occasionLink,
          'data': update.data,
        });
      }

      items.removeWhere(
        (item) => item.isPeriod
            ? (counts[item.id]?['count'] as int? ?? 0) == 0
            : captured.contains(item.id) && !updates.containsKey(item.id),
      );
      items = items.map((item) {
        if (!item.isPeriod) return hydrate(item);
        final count = counts[item.id]!;
        return NotificationItem.fromJson({
          'id': item.id,
          'kind': item.kind,
          'section': item.section,
          'occasionId': item.occasionId,
          'occasionTitle': count['occasionTitle'],
          'occasionLink': item.occasionLink,
          'occurredAt': item.occurredAt?.toIso8601String(),
          'data': {...item.data, 'count': count['count']},
        });
      }).toList();
      periodStates.removeWhere((id, _) => !items.any((item) => item.id == id));
      for (final state in periodStates.values) {
        state.items.removeWhere(
          (item) => captured.contains(item.id) && !updates.containsKey(item.id),
        );
        state.items = state.items.map(hydrate).toList();
      }
      refreshFailed = false;
      notifyListeners();
    } catch (error) {
      if (generation == _generation &&
          revision == _revision &&
          !_accessFailure(error)) {
        refreshFailed = true;
        notifyListeners();
      }
    } finally {
      _refreshing = false;
    }
  }

  bool _accessFailure(Object error) {
    if (error is! PostgrestException ||
        !const {'42501', '28000', 'PGRST301'}.contains(error.code)) {
      return false;
    }
    _revision++;
    enabled = unread = loading = false;
    failed = true;
    items = [];
    periodStates.clear();
    occasions = [];
    nextCursor = null;
    _timer?.cancel();
    notifyListeners();
    return true;
  }

  void setForeground(bool value) {
    if (foreground == value) return;
    foreground = value;
    _schedule();
    if (value && user != null) unawaited(refreshBadge());
  }

  Future<void> refreshBadge() async {
    if (_unsupported || user == null || organization == null || !foreground) {
      return;
    }
    final generation = _generation,
        revision = _revision,
        request = ++_badgeRequest;
    try {
      final result = await _read('get_notification_center_badge', {
        'p_organization': organization,
      });
      if (generation != _generation ||
          revision != _revision ||
          request != _badgeRequest) {
        return;
      }
      if (result['timelineSupported'] != true) {
        _unsupported = true;
        enabled = unread = false;
        _timer?.cancel();
        notifyListeners();
        return;
      }
      enabled = result['enabled'] == true;
      unread = result['unread'] == true;
      notifyListeners();
    } on PostgrestException catch (error) {
      if (generation != _generation ||
          revision != _revision ||
          request != _badgeRequest) {
        return;
      }
      if (_accessFailure(error)) return;
      // A deployment without the additive RPC has one capability outcome.
      if (error.code == 'PGRST202' || error.code == '42883') {
        _unsupported = true;
        enabled = false;
        _timer?.cancel();
        notifyListeners();
      }
    } catch (_) {
      /* Preserve the last confirmed badge while offline. */
    }
  }

  Future<void> open() async {
    if (_unsupported || organization == null || user == null || loading) return;
    panelOpen = true;
    _schedule();
    final generation = _generation, revision = ++_revision;
    loading = true;
    failed = pageFailed = refreshFailed = false;
    notifyListeners();
    try {
      final result = await _read('open_notification_center', {
        ..._scope,
        'p_limit': 30,
      });
      if (generation != _generation || revision != _revision) return;
      if (result['timelineSupported'] != true) {
        _unsupported = true;
        enabled = unread = false;
        items = [];
        _timer?.cancel();
        failed = true;
        return;
      }
      final newSnapshot = result['snapshot'] as int? ?? 0;
      final at = DateTime.parse(result['snapshotAt'] as String);
      final calendar = NotificationCenterCalendar.periods(
        at,
        DateTime.tryParse(result['oldestOrderAt']?.toString() ?? ''),
      );
      final timeline = await _read('get_notification_center_timeline', {
        ..._scope,
        'p_snapshot': newSnapshot,
        'p_snapshot_at': at.toIso8601String(),
        'p_periods': calendar,
        'p_limit': 30,
      });
      if (generation != _generation || revision != _revision) return;
      snapshot = newSnapshot;
      snapshotAt = at;
      periods = calendar;
      periodStates.clear();
      items = (timeline['items'] as List? ?? [])
          .map((e) => NotificationItem.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      occasions = (result['occasions'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      nextCursor = timeline['nextCursor'];
      _badgeRequest++; // Reject badge reads that began while acknowledgement was pending.
      unread = false;
    } catch (error) {
      if (generation == _generation &&
          revision == _revision &&
          !_accessFailure(error)) {
        failed = true;
      }
    } finally {
      if (generation == _generation && revision == _revision) {
        loading = false;
        notifyListeners();
      }
    }
  }

  void close() {
    panelOpen = false;
    _schedule();
  }

  Future<void> loadMore() async {
    if (nextCursor == null || loading) return;
    final generation = _generation, revision = _revision;
    loading = true;
    pageFailed = false;
    notifyListeners();
    try {
      final result = await _read('get_notification_center_timeline', {
        ..._timelineScope,
        'p_periods': periods,
        'p_cursor': nextCursor,
        'p_limit': 30,
      });
      if (generation != _generation || revision != _revision) return;
      final known = items.map((e) => e.id).toSet();
      items.addAll(
        (result['items'] as List? ?? [])
            .map((e) => NotificationItem.fromJson(Map<String, dynamic>.from(e)))
            .where((e) => known.add(e.id)),
      );
      nextCursor = result['nextCursor'];
    } catch (error) {
      if (generation == _generation &&
          revision == _revision &&
          !_accessFailure(error)) {
        pageFailed = true;
      }
    } finally {
      if (generation == _generation && revision == _revision) {
        loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> togglePeriod(NotificationItem item) async {
    final state = periodState(item);
    state.expanded = !state.expanded;
    notifyListeners();
    if (state.expanded && state.items.isEmpty && !state.loading) {
      await loadPeriod(item);
    }
  }

  Future<void> loadPeriod(NotificationItem item) async {
    final state = periodState(item);
    if (state.loading || (state.items.isNotEmpty && state.nextCursor == null))
      return;
    final generation = _generation,
        revision = _revision,
        request = ++state.request;
    state.loading = true;
    state.failed = false;
    notifyListeners();
    try {
      final result = await _read('get_notification_center_timeline_group', {
        ..._timelineScope,
        'p_occasion': item.occasionId,
        'p_period': item.period,
        'p_cursor': state.nextCursor,
        'p_limit': 30,
      });
      if (generation != _generation ||
          revision != _revision ||
          !identical(periodStates[item.id], state) ||
          request != state.request)
        return;
      final known = state.items.map((item) => item.id).toSet();
      state.items.addAll(
        (result['items'] as List? ?? [])
            .map(
              (row) =>
                  NotificationItem.fromJson(Map<String, dynamic>.from(row)),
            )
            .where((item) => known.add(item.id)),
      );
      state.nextCursor = result['nextCursor'];
    } catch (error) {
      if (generation == _generation &&
          revision == _revision &&
          identical(periodStates[item.id], state) &&
          !_accessFailure(error)) {
        state.failed = true;
      }
    } finally {
      if (generation == _generation &&
          revision == _revision &&
          identical(periodStates[item.id], state)) {
        state.loading = false;
        notifyListeners();
      }
    }
  }

  Future<bool> mute(Map<String, dynamic> occasion, bool muted) async {
    if (occasion['saving'] == true) return false;
    final generation = _generation;
    occasion['saving'] = true;
    notifyListeners();
    try {
      await _read('set_notification_center_muted', {
        'p_organization': organization,
        'p_occasion': occasion['id'],
        'p_muted': muted,
      });
      if (generation != _generation) return false;
      occasion['muted'] = muted;
      notifyListeners();
      unawaited(refreshBadge());
      return true;
    } catch (error) {
      if (generation == _generation) _accessFailure(error);
      return false;
    } finally {
      if (generation == _generation) {
        occasion['saving'] = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _generation++;
    _timer?.cancel();
    super.dispose();
  }
}
