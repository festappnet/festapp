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
      state = json['state'] as String? ?? 'ready',
      position = json['position'] as int? ?? 0,
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
  final String id, kind, status, state;
  bool get isReady => state == 'ready';
  final int section, sequence, position;
  final int? occasionId;
  final String? occasionTitle;
  final DateTime? occurredAt, day;
  final String? occasionLink;
  final Map<String, dynamic> data;
  bool get isSummary => data['activityCount'] is int;
}

/// The token server owns prepared catalogs. Only a confirmed open sees them.
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
  String? user, viewToken, _viewRevision;
  int _generation = 0, _revision = 0, _badgeRequest = 0;
  int _loadedCount = 30;
  Future<void>? _badgeInFlight,
      _openInFlight,
      _refreshInFlight,
      _settingsInFlight;
  (int, int)? _badgeScope;
  bool _unsupported = false, _retainView = false;
  bool enabled = false,
      unread = false,
      loading = false,
      failed = false,
      pageFailed = false;
  bool panelOpen = false,
      foreground = true,
      refreshFailed = false,
      truncated = false;
  bool preparing = false,
      expired = false,
      viewLimit = false,
      settingsLoading = false,
      settingsFailed = false;
  int snapshot = 0;
  int? previousReadThrough;
  DateTime? snapshotAt, snapshotDay;
  List<NotificationItem> items = [];
  List<Map<String, dynamic>> occasions = [];
  dynamic nextCursor, settingsCursor;
  Timer? _timer;
  bool get hasReadyItems => items.any((item) => item.isReady);
  Map<String, dynamic> get _scope => {
    'p_organization': organization,
    'p_current_occasion': currentOccasion,
  };
  Map<String, dynamic> get _viewScope => {
    ..._scope,
    'p_view': viewToken,
    'p_timezone': displayTimezone,
    if (_viewRevision != null) 'p_revision': _viewRevision,
  };

  bool isUnread(NotificationItem item) =>
      item.isReady &&
      (item.isRead != null
          ? !item.isRead!
          : previousReadThrough != null &&
                item.sequence > previousReadThrough! &&
                item.sequence <= snapshot);

  Map<String, dynamic>? selectionScope(NotificationItem item) {
    if (!item.isReady ||
        !item.isSummary ||
        organization == null ||
        viewToken == null ||
        preparing) {
      return null;
    }
    _retainView = true;
    return {
      'id': item.id,
      'viewToken': viewToken,
      'organization': organization,
      'snapshot': snapshot,
      'timezone': displayTimezone,
      'snapshotAt': snapshotAt?.toUtc().toIso8601String(),
      if (item.data['afterSequence'] != null)
        'afterSequence': item.data['afterSequence'],
      'throughSequence': item.sequence > 0 ? item.sequence : snapshot,
      'markRead': isUnread(item),
    };
  }

  Future<void> markRead(NotificationItem item) async {
    if (organization == null || viewToken == null || !isUnread(item)) return;
    final generation = _generation;
    final result = await _read('mark_notification_center_view_item_read', {
      'p_organization': organization,
      'p_scope': {'id': item.id, 'viewToken': viewToken},
    });
    if (generation == _generation && result == true) {
      item.isRead = true;
      if (!panelOpen && _retainView) {
        _releaseView();
        _retainView = false;
      }
      notifyListeners();
    }
  }

  void _invalidateBadge() {
    _badgeRequest++;
    _badgeInFlight = null;
    _badgeScope = null;
  }

  void _clearPrivate() {
    items = [];
    _viewRevision = null;
    occasions = [];
    viewToken = null;
    nextCursor = settingsCursor = null;
    snapshot = 0;
    previousReadThrough = null;
    snapshotAt = snapshotDay = null;
    preparing = expired = viewLimit = false;
    _loadedCount = 30;
  }

  void _releaseView() {
    final token = viewToken;
    final params = {..._viewScope, 'p_mode': 'close'};
    viewToken = null;
    if (token != null) {
      unawaited(
        _read(
          'get_notification_center_view',
          params,
        ).then<void>((_) {}, onError: (Object _) {}),
      );
    }
  }

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
    if (!identityChanged && !_retainView) _releaseView();
    _generation++;
    _revision++;
    _invalidateBadge();
    _openInFlight = _refreshInFlight = _settingsInFlight = null;
    user = userId;
    organization = organizationId;
    currentOccasion = occasionId;
    if (identityChanged || invalidate) enabled = unread = false;
    failed = pageFailed = loading = refreshFailed = settingsLoading =
        settingsFailed = false;
    panelOpen = false;
    truncated = false;
    _unsupported = false;
    _retainView = false;
    _clearPrivate();
    displayTimezone = 'UTC';
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
        Duration(seconds: panelOpen ? (preparing ? 1 : 15) : 60),
        (_) => refresh(),
      );
    }
  }

  bool _accept(Map result, {bool opening = false, bool append = false}) {
    if (result['viewSupported'] != true) {
      _unsupported = true;
      enabled = unread = false;
      _clearPrivate();
      failed = true;
      _timer?.cancel();
      return false;
    }
    final state = result['state'];
    if (state == 'denied') {
      _revision++;
      enabled = unread = false;
      _clearPrivate();
      failed = true;
      _timer?.cancel();
      return false;
    }
    if (result['viewToken'] != null) viewToken = result['viewToken'].toString();
    if (state == 'preparing') {
      _viewRevision = null;
      preparing = true;
      expired = viewLimit = false;
      items = (result['items'] as List? ?? [])
          .map((e) => NotificationItem.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      nextCursor = result['nextCursor'];
      _schedule();
      return false;
    }
    if (state == 'expired' || state == 'view_limit') {
      _clearPrivate();
      expired = state == 'expired';
      viewLimit = state == 'view_limit';
      _schedule();
      return false;
    }
    if (state != 'ready' || viewToken == null) {
      throw StateError('Invalid notification view response');
    }
    preparing = expired = viewLimit = false;
    final rows = (result['items'] as List? ?? [])
        .map((e) => NotificationItem.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    if (result['unchanged'] == true) {
      // Current rights, privacy, read state and bounded live display facts were
      // revalidated by the server before omitting the payload.
    } else if (append) {
      final known = items.map((e) => e.id).toSet();
      items.addAll(rows.where((e) => known.add(e.id)));
    } else {
      items = rows;
    }
    if (!append && result['revision'] is String) {
      _viewRevision = result['revision'] as String;
    }
    _loadedCount = items.length.clamp(30, 100);
    snapshot = result['snapshot'] as int? ?? snapshot;
    previousReadThrough =
        result['previousReadThrough'] as int? ?? previousReadThrough;
    snapshotAt =
        DateTime.tryParse(result['snapshotAt']?.toString() ?? '') ?? snapshotAt;
    snapshotDay =
        DateTime.tryParse(result['snapshotDay']?.toString() ?? '') ??
        snapshotDay;
    nextCursor = result['nextCursor'];
    truncated = result['truncated'] == true;
    if (opening) {
      if (result['acknowledged'] != true) {
        throw StateError('Notification open was not acknowledged');
      }
      _invalidateBadge();
      if (result['unread'] is bool) unread = result['unread'] as bool;
    } else if (result['unread'] is bool) {
      unread = result['unread'] as bool;
    }
    _schedule();
    return true;
  }

  Future<void> open() {
    if (_openInFlight case final pending?) return pending;
    late final Future<void> pending;
    pending = _open().whenComplete(() {
      if (identical(_openInFlight, pending)) _openInFlight = null;
    });
    _openInFlight = pending;
    return pending;
  }

  Future<void> _open() async {
    if (_unsupported || organization == null || user == null || loading) return;
    if (!preparing && viewToken != null) {
      if (_retainView) {
        viewToken = null;
      } else {
        _releaseView();
      }
    }
    _retainView = false;
    // A new open must pass its current authorization gate before presenting
    // private rows retained from the previous dialog.
    if (!preparing) {
      items = [];
      _viewRevision = null;
    }
    panelOpen = true;
    final generation = _generation, revision = ++_revision;
    loading = true;
    failed = pageFailed = refreshFailed = false;
    _schedule();
    notifyListeners();
    final params = {
      ..._scope,
      'p_timezone': preparing && viewToken != null
          ? displayTimezone
          : _timezone(),
      'p_mode': 'open',
      if (preparing && viewToken != null) 'p_view': viewToken,
      'p_limit': 30,
    };
    try {
      final result = await _read('get_notification_center_view', params);
      if (generation != _generation || revision != _revision) {
        if (result['viewToken'] != null) {
          unawaited(
            _read('get_notification_center_view', {
              ...params,
              'p_view': result['viewToken'],
              'p_mode': 'close',
            }).then<void>((_) {}, onError: (Object _) {}),
          );
        }
        return;
      }
      displayTimezone = params['p_timezone'] as String;
      _accept(result as Map, opening: true);
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

  Future<void> refresh() {
    if (_refreshInFlight case final pending?) return pending;
    late final Future<void> pending;
    pending = _refresh().whenComplete(() {
      if (identical(_refreshInFlight, pending)) _refreshInFlight = null;
    });
    _refreshInFlight = pending;
    return pending;
  }

  Future<void> _refresh() async {
    if (!foreground || user == null || organization == null) return;
    if (!panelOpen) {
      await refreshBadge();
      return;
    }
    if (loading) return;
    if (preparing && viewToken == null) {
      await open();
      return;
    }
    if (viewToken == null || expired || viewLimit) return;
    final generation = _generation, revision = _revision;
    try {
      final result = await _read('get_notification_center_view', {
        ..._viewScope,
        'p_mode': preparing ? 'open' : 'refresh',
        'p_limit': _loadedCount,
      });
      if (generation != _generation || revision != _revision) return;
      _accept(result as Map, opening: preparing);
      refreshFailed = false;
      notifyListeners();
    } catch (error) {
      if (generation == _generation &&
          revision == _revision &&
          !_accessFailure(error)) {
        refreshFailed = true;
        notifyListeners();
      }
    }
  }

  void close({bool retainView = false}) {
    _revision++;
    panelOpen = false;
    loading = false;
    preparing = false;
    _openInFlight = _refreshInFlight = null;
    _retainView = retainView;
    if (!retainView) _releaseView();
    _schedule();
  }

  Future<void> loadMore() async {
    if (nextCursor == null || loading || preparing || viewToken == null) return;
    final generation = _generation, revision = _revision;
    loading = true;
    pageFailed = false;
    notifyListeners();
    try {
      final result = await _read('get_notification_center_view', {
        ..._viewScope,
        'p_mode': 'page',
        'p_cursor': nextCursor,
        'p_limit': 30,
      });
      if (generation != _generation || revision != _revision) return;
      _accept(result as Map, append: true);
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

  Future<void> releaseOtherViews() async {
    if (organization == null || user == null || loading) return;
    final generation = _generation;
    await _read('get_notification_center_view', {
      ..._scope,
      'p_mode': 'close_all',
    });
    if (generation != _generation) return;
    viewToken = null;
    viewLimit = false;
    await open();
  }

  Future<void> loadSettings({bool more = false}) {
    if (_settingsInFlight case final pending?) return pending;
    late final Future<void> pending;
    pending = _loadSettings(more: more).whenComplete(() {
      if (identical(_settingsInFlight, pending)) _settingsInFlight = null;
    });
    _settingsInFlight = pending;
    return pending;
  }

  Future<void> _loadSettings({required bool more}) async {
    if (organization == null ||
        user == null ||
        (more && settingsCursor == null)) {
      return;
    }
    final generation = _generation;
    settingsLoading = true;
    settingsFailed = false;
    notifyListeners();
    try {
      final result = await _read('get_notification_center_settings', {
        'p_organization': organization,
        'p_after': more ? settingsCursor : 0,
      });
      if (generation != _generation) return;
      final rows = (result['items'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      occasions = more ? [...occasions, ...rows] : rows;
      settingsCursor = result['nextCursor'];
    } catch (error) {
      if (generation == _generation && !_accessFailure(error)) {
        settingsFailed = true;
      }
    } finally {
      if (generation == _generation) {
        settingsLoading = false;
        notifyListeners();
      }
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
    _clearPrivate();
    _timer?.cancel();
    notifyListeners();
    return true;
  }

  void setForeground(bool value) {
    if (foreground == value) return;
    foreground = value;
    if (!value) _invalidateBadge();
    _schedule();
    if (value && user != null) {
      unawaited(panelOpen ? refresh() : refreshBadge());
    }
  }

  Future<void> refreshBadge() {
    if (_unsupported || user == null || organization == null || !foreground) {
      return Future.value();
    }
    final scope = (_generation, _revision);
    if (_badgeInFlight != null && _badgeScope == scope) return _badgeInFlight!;
    _badgeScope = scope;
    late final Future<void> pending;
    pending = _readBadge().whenComplete(() {
      if (identical(_badgeInFlight, pending)) {
        _badgeInFlight = null;
        _badgeScope = null;
      }
    });
    _badgeInFlight = pending;
    return pending;
  }

  Future<void> _readBadge() async {
    final generation = _generation,
        revision = _revision,
        request = ++_badgeRequest;
    try {
      final result = await _read('get_notification_center_prepared_badge', {
        'p_organization': organization,
      });
      if (generation != _generation ||
          revision != _revision ||
          request != _badgeRequest) {
        return;
      }
      if (result['viewSupported'] != true) {
        _unsupported = true;
        enabled = unread = false;
        _clearPrivate();
        _timer?.cancel();
        notifyListeners();
        return;
      }
      if (result['state'] == 'denied') {
        enabled = unread = false;
        _clearPrivate();
        _timer?.cancel();
        notifyListeners();
        return;
      }
      enabled = result['enabled'] == true;
      if (result['state'] == 'preparing') {
        items = [];
        _viewRevision = null;
        if (panelOpen) {
          preparing = true;
          _schedule();
        }
      }
      if (result['unread'] is bool) unread = result['unread'] as bool;
      notifyListeners();
    } on PostgrestException catch (error) {
      if (generation != _generation ||
          revision != _revision ||
          request != _badgeRequest) {
        return;
      }
      if (_accessFailure(error)) return;
      if (error.code == 'PGRST202' || error.code == '42883') {
        _unsupported = true;
        enabled = false;
        _clearPrivate();
        _timer?.cancel();
        notifyListeners();
      }
    } catch (_) {
      /* Keep the last confirmed badge while offline. */
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
      _invalidateBadge();
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
    if (!_retainView) _releaseView();
    _generation++;
    _timer?.cancel();
    super.dispose();
  }
}
