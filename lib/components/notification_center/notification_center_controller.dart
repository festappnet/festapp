import 'dart:async';

import 'notification_timezone.dart';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef NotificationRead = Future<dynamic> Function(
  String,
  Map<String, dynamic>,
);

class NotificationItem {
  NotificationItem.fromJson(Map<String, dynamic> json)
    : isRead = json['isRead'] as bool?,
      isSeen = json['isSeen'] as bool?,
      id = json['id'].toString(),
      section = json['section'] as int? ?? 2,
      sequence = json['sequence'] as int? ?? 0,
      occasionId = json['occasionId'] as int?,
      occasionTitle = json['occasionTitle'] as String?,
      kind = json['kind'] as String? ?? '',
      status = json['status'] as String? ?? '',
      occurredAt = DateTime.tryParse(json['occurredAt']?.toString() ?? ''),
      day = DateTime.tryParse(json['day']?.toString() ?? ''),
      occasionLink = json['occasionLink'] as String?,
      data = Map<String, dynamic>.from(json['data'] as Map? ?? {});
  bool? isRead;
  final bool? isSeen;
  final String id, kind, status;
  final int section, sequence;
  final int? occasionId;
  final String? occasionTitle;
  final DateTime? occurredAt, day;
  final String? occasionLink;
  final Map<String, dynamic> data;
  bool get isSummary => data['activityCount'] is int;
}

/// Only open acknowledges. Generation and revision fences reject stale polls.
class NotificationCenterController extends ChangeNotifier {
  NotificationCenterController({
    NotificationRead? read,
    String Function()? timezone,
  }) : _timezone = timezone ?? NotificationCenterTimezone.name,
       _read =
           read ??
           ((name, params) =>
               Supabase.instance.client.rpc(name, params: params));
  final NotificationRead _read;
  final String Function() _timezone;
  String displayTimezone = 'UTC';
  int? organization, currentOccasion;
  String? user;
  int _generation = 0, _revision = 0, _badgeRequest = 0;
  bool enabled = false,
      unread = false,
      loading = false,
      failed = false,
      pageFailed = false;
  bool panelOpen = false,
      foreground = true,
      refreshFailed = false,
      truncated = false;
  int snapshot = 0;
  // Preserve the pre-open watermark while the server acknowledges this snapshot.
  // A missing watermark on older backends must not label every row as new.
  int? previousReadThrough;
  bool isUnread(NotificationItem item) =>
      item.isRead != null ? !item.isRead! : previousReadThrough != null &&
      item.sequence > previousReadThrough! &&
      item.sequence <= snapshot;
  DateTime? snapshotAt;
  DateTime? snapshotDay;
  Map<String, dynamic> get _overviewScope => {
    ..._scope,
    'p_snapshot': snapshot,
    'p_snapshot_at': snapshotAt?.toUtc().toIso8601String(),
    'p_timezone': displayTimezone,
  };

  /// Freeze the row's scope before dismissing the overlay or changing routes.
  Map<String, dynamic>? selectionScope(NotificationItem item) {
    if (!item.isSummary || organization == null || snapshot <= 0) return null;
    return {
      'id': item.id,
      'organization': organization,
      'snapshot': snapshot,
      'timezone': displayTimezone,
      'snapshotAt': snapshotAt?.toUtc().toIso8601String(),
      if (item.data['afterSequence'] != null) 'afterSequence': item.data['afterSequence'],
      'throughSequence': item.sequence > 0 ? item.sequence : snapshot,
      'markRead': isUnread(item),
    };
  }

  Future<void> markRead(NotificationItem item) async {
    if (organization == null || !isUnread(item)) return;
    final generation = _generation;
    final result = await _read('mark_notification_center_item_read', {
      'p_organization': organization,
      'p_scope': {'id': item.id, 'snapshot': snapshot, 'throughSequence': item.sequence > 0 ? item.sequence : snapshot},
    });
    if (generation == _generation && result == true) {
      item.isRead = true;
      notifyListeners();
    }
  }

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
    truncated = false;
    snapshot = 0;
    previousReadThrough = null;
    snapshotAt = null;
    snapshotDay = null;
    displayTimezone = 'UTC';
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
      if (!panelOpen) {
        await refreshBadge();
        return;
      }
      if (loading || !foreground || organization == null || user == null) {
        return;
      }
      final captured = items.map((item) => item.id).toList();
      final result = await _read('get_notification_center_daily_overview', {
        ..._overviewScope,
        'p_ids': captured,
      });
      if (generation != _generation || revision != _revision) return;
      final updates = <String, NotificationItem>{};
      for (final row in result['items'] as List? ?? []) {
        final item = NotificationItem.fromJson(Map<String, dynamic>.from(row));
        updates[item.id] = item;
      }
      if (result['unread'] is bool) unread = result['unread'] as bool;
      truncated = result['truncated'] == true;
      // Recheck permissions and live facts without moving snapshot positions or
      // inserting arrivals. Missing IDs are revoked, not cached personal data.
      items = [
        for (final item in items)
          if (updates[item.id] case final update?)
            NotificationItem.fromJson({
              'isRead': update.isRead,
              'isSeen': update.isSeen,
              'id': update.id,
              'kind': update.kind,
              'status': update.status,
              'occurredAt': item.occurredAt?.toIso8601String(),
              'day': item.day?.toIso8601String().split('T').first,
              'section': item.section,
              'sequence': item.sequence,
              'occasionId': item.occasionId,
              'occasionTitle': update.occasionTitle,
              'occasionLink': update.occasionLink,
              'data': update.data,
            }),
      ];
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
      final zone = _timezone();
      final result = await _read('get_notification_center_daily_overview', {
        ..._scope,
        'p_timezone': zone,
        'p_open': true,
        'p_limit': 30,
      });
      if (generation != _generation || revision != _revision) return;
      if (result['dailySupported'] != true) {
        _unsupported = true;
        enabled = unread = false;
        items = [];
        _timer?.cancel();
        failed = true;
        return;
      }
      final newSnapshot = result['snapshot'] as int? ?? 0;
      final at = DateTime.parse(result['snapshotAt'] as String);
      snapshot = newSnapshot;
      previousReadThrough = result['previousReadThrough'] as int?;
      snapshotAt = at;
      snapshotDay = DateTime.tryParse(result['snapshotDay']?.toString() ?? '');
      displayTimezone = zone;
      items = (result['items'] as List? ?? [])
          .map((e) => NotificationItem.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      occasions = (result['occasions'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      nextCursor = result['nextCursor'];
      truncated = result['truncated'] == true;
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
      final result = await _read('get_notification_center_daily_overview', {
        ..._overviewScope,
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
      truncated = result['truncated'] == true;
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
