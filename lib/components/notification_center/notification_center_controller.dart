import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef NotificationRead = Future<dynamic> Function(
    String, Map<String, dynamic>);

class NotificationItem {
  NotificationItem.fromJson(Map<String, dynamic> json)
      : id = json['id'].toString(),
        kind = json['kind'] as String? ?? '',
        status = json['status'] as String? ?? '',
        occurredAt = DateTime.tryParse(json['occurredAt']?.toString() ?? ''),
        occasionLink = json['occasionLink'] as String?,
        data = Map<String, dynamic>.from(json['data'] as Map? ?? {});
  final String id, kind, status;
  final DateTime? occurredAt;
  final String? occasionLink;
  final Map<String, dynamic> data;
}

class NotificationGroup {
  NotificationGroup.fromJson(Map<String, dynamic> json)
      : key = json['key'] as String,
        kind = json['kind'] as String? ?? '',
        section = json['section'] as int? ?? 2,
        occasionId = json['occasionId'] as int?,
        occasionTitle = json['occasionTitle'] as String?,
        count = json['count'] as int? ?? 0,
        day = json['day'] as String?,
        items = (json['items'] as List? ?? [])
            .map((e) => NotificationItem.fromJson(Map<String, dynamic>.from(e)))
            .toList();
  final String key, kind;
  final int section, count;
  final int? occasionId;
  final String? occasionTitle, day;
  final List<NotificationItem> items;
  int? cursor;
  bool expanded = false, busy = false, failed = false, loaded = false;
}

/// Only open acknowledges. Generation and revision fences reject stale polls.
class NotificationCenterController extends ChangeNotifier {
  NotificationCenterController({NotificationRead? read})
      : _read = read ??
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
  List<NotificationGroup> groups = [];
  List<Map<String, dynamic>> occasions = [];
  dynamic nextCursor;
  Timer? _timer;
  bool _unsupported = false;
  Map<String, dynamic> get _scope =>
      {'p_organization': organization, 'p_current_occasion': currentOccasion};

  void configure(
      {required String? userId,
      required int? organizationId,
      int? occasionId,
      bool invalidate = false}) {
    if (!invalidate &&
        user == userId &&
        organization == organizationId &&
        currentOccasion == occasionId) return;
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
    panelOpen = false;
    groups = [];
    occasions = [];
    refreshFailed = false;
    _schedule();
    if ((identityChanged || invalidate) && user != null && organization != null)
      unawaited(refreshBadge());
    notifyListeners();
  }

  void _schedule() {
    _timer?.cancel();
    if (!_unsupported && foreground && user != null && organization != null) {
      _timer = Timer.periodic(
          Duration(seconds: panelOpen ? 15 : 60), (_) => refresh());
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
          revision != _revision) return;
      final captured = <NotificationGroup, Set<String>>{
        for (final group in groups)
          group: group.items.map((item) => item.id).toSet(),
      };
      final ids = captured.values.expand((value) => value).toSet().toList();
      final updates = <String, NotificationItem>{};
      for (var start = 0; start < ids.length; start += 200) {
        final result = await _read('get_notification_center_updates', {
          'p_organization': organization,
          'p_snapshot': snapshot,
          'p_ids': ids.sublist(start, (start + 200).clamp(0, ids.length)),
        });
        if (generation != _generation || revision != _revision) return;
        for (final row in result['items'] as List? ?? []) {
          final item =
              NotificationItem.fromJson(Map<String, dynamic>.from(row));
          updates[item.id] = item;
        }
      }
      // Preserve position and expansion, update known facts and remove revoked data.
      for (final group in captured.keys) {
        group.items.removeWhere((item) =>
            captured[group]!.contains(item.id) &&
            !updates.containsKey(item.id));
        for (var index = 0; index < group.items.length; index++) {
          group.items[index] =
              updates[group.items[index].id] ?? group.items[index];
        }
        if (group.items.isEmpty) groups.remove(group);
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
        !const {'42501', '28000', 'PGRST301'}.contains(error.code))
      return false;
    _revision++;
    enabled = unread = loading = false;
    failed = true;
    groups = [];
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
    if (_unsupported || user == null || organization == null || !foreground)
      return;
    final generation = _generation,
        revision = _revision,
        request = ++_badgeRequest;
    try {
      final result = await _read(
          'get_notification_center_badge', {'p_organization': organization});
      if (generation != _generation ||
          revision != _revision ||
          request != _badgeRequest) return;
      enabled = result['enabled'] == true;
      unread = result['unread'] == true;
      notifyListeners();
    } on PostgrestException catch (error) {
      if (generation != _generation ||
          revision != _revision ||
          request != _badgeRequest) return;
      if (_accessFailure(error)) return;
      // A deployment without the additive RPC has one capability outcome.
      if (error.code == 'PGRST202' || error.code == '42883') {
        _unsupported = true;
        enabled = false;
        _timer?.cancel();
        notifyListeners();
      }
    } catch (_) {/* Preserve the last confirmed badge while offline. */}
  }

  Future<void> open() async {
    if (organization == null || user == null || loading) return;
    panelOpen = true;
    _schedule();
    final generation = _generation, revision = ++_revision;
    loading = true;
    failed = pageFailed = refreshFailed = false;
    notifyListeners();
    try {
      final result =
          await _read('open_notification_center', {..._scope, 'p_limit': 30});
      if (generation != _generation || revision != _revision) return;
      snapshot = result['snapshot'] as int? ?? 0;
      groups = (result['groups'] as List? ?? [])
          .map((e) => NotificationGroup.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      occasions = (result['occasions'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      nextCursor = result['nextCursor'];
      _badgeRequest++; // Reject badge reads that began while acknowledgement was pending.
      unread = false;
    } catch (error) {
      if (generation == _generation &&
          revision == _revision &&
          !_accessFailure(error)) failed = true;
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
      final result = await _read('get_notification_center_page', {
        ..._scope,
        'p_snapshot': snapshot,
        'p_cursor': nextCursor,
        'p_limit': 30
      });
      if (generation != _generation || revision != _revision) return;
      final known = groups.map((e) => e.key).toSet();
      groups.addAll((result['groups'] as List? ?? [])
          .map((e) => NotificationGroup.fromJson(Map<String, dynamic>.from(e)))
          .where((e) => !known.contains(e.key)));
      nextCursor = result['nextCursor'];
    } catch (error) {
      if (generation == _generation &&
          revision == _revision &&
          !_accessFailure(error)) pageFailed = true;
    } finally {
      if (generation == _generation && revision == _revision) {
        loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> expand(NotificationGroup group, {bool more = false}) async {
    if (group.busy) return;
    if (!more) {
      group.expanded = !group.expanded;
      notifyListeners();
      if (!group.expanded || group.loaded) return;
    }
    final generation = _generation, revision = _revision;
    group.busy = true;
    group.failed = false;
    notifyListeners();
    try {
      final result = await _read('get_notification_center_group', {
        'p_organization': organization,
        'p_group_key': group.key,
        'p_snapshot': snapshot,
        'p_cursor': more ? group.cursor : null,
        'p_limit': 5
      });
      if (generation != _generation || revision != _revision) return;
      if (!more || !group.loaded) group.items.clear();
      group.loaded = true;
      group.items.addAll((result['items'] as List? ?? [])
          .map((e) => NotificationItem.fromJson(Map<String, dynamic>.from(e))));
      group.cursor = result['nextCursor'] as int?;
    } catch (error) {
      if (generation == _generation &&
          revision == _revision &&
          !_accessFailure(error)) group.failed = true;
    } finally {
      if (generation == _generation && revision == _revision) {
        group.busy = false;
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
        'p_muted': muted
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
