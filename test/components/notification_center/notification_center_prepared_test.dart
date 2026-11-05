import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/notification_center/notification_center_controller.dart';

const tokenA = '00000000-0000-0000-0000-000000000001';
const tokenB = '00000000-0000-0000-0000-000000000002';
Map<String, dynamic> badge() => {
  'viewSupported': true,
  'state': 'ready',
  'enabled': true,
  'unread': true,
};
Map<String, dynamic> ready({String token = tokenA, int count = 3}) => {
  'viewSupported': true,
  'state': 'ready',
  'viewToken': token,
  'acknowledged': true,
  'unread': false,
  'snapshot': 10,
  'snapshotAt': '2026-11-05T12:00:00Z',
  'previousReadThrough': 0,
  'items': [
    {
      'id': 'occasion-kind:1:order_created:batch:0',
      'position': 1,
      'state': 'ready',
      'sequence': 10,
      'kind': 'order_created',
      'isRead': false,
      'data': {
        'activityCount': count,
        'relatedOrders': true,
        'contact': {'name': 'Jana'},
      },
    },
  ],
};
void main() {
  test(
    'same-mode opens coalesce and only a confirmed open clears the badge',
    () async {
      final pending = Completer<dynamic>();
      final calls = <Map<String, dynamic>>[];
      final c = NotificationCenterController(
        read: (name, params) async {
          if (name == 'get_notification_center_prepared_badge') return badge();
          calls.add(Map.of(params));
          if (params['p_mode'] == 'close') return {};
          return pending.future;
        },
      );
      addTearDown(c.dispose);
      c.configure(userId: 'u', organizationId: 1);
      await Future<void>.delayed(Duration.zero);
      final first = c.open(), second = c.open();
      expect(identical(first, second), true);
      expect(c.unread, true);
      pending.complete(ready());
      await first;
      expect(c.unread, false);
      expect(calls.where((x) => x['p_mode'] == 'open'), hasLength(1));
    },
  );
  test('preparing removes private data, retries the open intent, and never uses a legacy RPC', () async {
    var attempts = 0;
    final calls = <String>[];
    final c = NotificationCenterController(
      read: (name, params) async {
        calls.add(name);
        if (name == 'get_notification_center_prepared_badge') return badge();
        if (params['p_mode'] == 'close') return {};
        return ++attempts == 1
            ? {'viewSupported': true, 'state': 'preparing', 'items': []}
            : ready();
      },
    );
    addTearDown(c.dispose);
    c.configure(userId: 'u', organizationId: 1);
    await Future<void>.delayed(Duration.zero);
    c.items = [NotificationItem.fromJson(ready()['items'][0])];
    await c.open();
    expect(c.preparing, true);
    expect(c.items, isEmpty);
    expect(c.unread, true);
    await c.refresh();
    expect(c.preparing, false);
    expect(c.items.single.data['activityCount'], 3);
    expect(c.unread, false);
    expect(
      calls.every(
        (name) =>
            name == 'get_notification_center_view' ||
            name == 'get_notification_center_prepared_badge',
      ),
      true,
    );
  });
  test('a preparing slot returns at the same position after repair', () async {
    var calls = 0;
    final c = NotificationCenterController(
      read: (name, params) async {
        if (name == 'get_notification_center_prepared_badge') return badge();
        if (params['p_mode'] == 'close') return {};
        calls++;
        if (calls == 2)
          return {
            'viewSupported': true,
            'state': 'preparing',
            'viewToken': tokenA,
            'items': [
              {
                'id': 'occasion-kind:1:order_created:batch:0',
                'position': 1,
                'state': 'preparing',
              },
            ],
          };
        return ready(count: calls == 1 ? 3 : 2);
      },
    );
    addTearDown(c.dispose);
    c.configure(userId: 'u', organizationId: 1);
    await c.open();
    await c.refresh();
    expect(c.items.single.state, 'preparing');
    expect(c.items.single.data, isEmpty);
    expect(c.hasReadyItems, false);
    await c.refresh();
    expect(c.items.single.position, 1);
    expect(c.items.single.data['activityCount'], 2);
    expect(c.preparing, false);
  });
  test(
    'closing during open rejects late private data and releases its new lease',
    () async {
      final pending = Completer<dynamic>();
      final closes = <String>[];
      final c = NotificationCenterController(
        read: (name, params) async {
          if (name == 'get_notification_center_prepared_badge') return badge();
          if (params['p_mode'] == 'close') {
            closes.add(params['p_view'] as String);
            return {};
          }
          return pending.future;
        },
      );
      addTearDown(c.dispose);
      c.configure(userId: 'u', organizationId: 1);
      final opening = c.open();
      c.close();
      pending.complete(ready());
      await opening;
      await Future<void>.delayed(Duration.zero);
      expect(c.items, isEmpty);
      expect(c.panelOpen, false);
      expect(closes, [tokenA]);
    },
  );
  test('expired, quota and denied states clear private rows without history fallback', () async {
    var state = 'ready';
    final c = NotificationCenterController(
      read: (name, params) async {
        if (name == 'get_notification_center_prepared_badge') return badge();
        if (params['p_mode'] == 'close') return {};
        return state == 'ready'
            ? ready()
            : {'viewSupported': true, 'state': state, 'items': []};
      },
    );
    addTearDown(c.dispose);
    c.configure(userId: 'u', organizationId: 1);
    await c.open();
    state = 'expired';
    await c.refresh();
    expect(c.expired, true);
    expect(c.items, isEmpty);
    state = 'view_limit';
    await c.open();
    expect(c.viewLimit, true);
    state = 'ready';
    await c.open();
    state = 'denied';
    await c.refresh();
    expect(c.items, isEmpty);
    expect(c.viewToken, isNull);
    expect(c.enabled, false);
  });
  test('navigation keeps the frozen selection lease until the orders request consumes it', () async {
    final closes = <String>[];
    var opens = 0;
    final c = NotificationCenterController(
      read: (name, params) async {
        if (name == 'get_notification_center_prepared_badge') return badge();
        if (params['p_mode'] == 'close') {
          closes.add(params['p_view'] as String);
          return {};
        }
        return ready(token: ++opens == 1 ? tokenA : tokenB);
      },
    );
    addTearDown(c.dispose);
    c.configure(userId: 'u', organizationId: 1);
    await c.open();
    final scope = c.selectionScope(c.items.single)!;
    c.close(retainView: true);
    await c.open();
    expect(scope['viewToken'], tokenA);
    expect(c.viewToken, tokenB);
    expect(closes, isEmpty);
  });
  test('settings are lazy, paged and independent of opening', () async {
    var settings = 0;
    final c = NotificationCenterController(
      read: (name, params) async {
        if (name == 'get_notification_center_prepared_badge') return badge();
        if (name == 'get_notification_center_settings') {
          settings++;
          return {
            'items': [
              {'id': settings, 'title': 'Ples'},
            ],
            'nextCursor': settings == 1 ? 1 : null,
          };
        }
        if (params['p_mode'] == 'close') return {};
        return ready();
      },
    );
    addTearDown(c.dispose);
    c.configure(userId: 'u', organizationId: 1);
    await c.open();
    expect(settings, 0);
    await c.loadSettings();
    await c.loadSettings(more: true);
    expect(c.occasions, hasLength(2));
    expect(c.settingsCursor, isNull);
  });
  test('unchanged refresh keeps rows only after a server-confirmed current revision', () async {
    var calls = 0;
    final c = NotificationCenterController(
      read: (name, params) async {
        if (name == 'get_notification_center_prepared_badge') return badge();
        if (params['p_mode'] == 'close') return {};
        if (++calls == 1)
          return {...ready(), 'revision': 'current-private-revision'};
        expect(params['p_revision'], 'current-private-revision');
        return {
          ...ready(),
          'revision': 'current-private-revision',
          'unchanged': true,
          'items': [],
        };
      },
    );
    addTearDown(c.dispose);
    c.configure(userId: 'u', organizationId: 1);
    await c.open();
    final original = c.items.single;
    await c.refresh();
    expect(c.items.single, same(original));
    expect(c.items.single.data['activityCount'], 3);
  });
}
