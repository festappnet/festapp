import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/notification_center/notification_center_controller.dart';
import 'package:fstapp/components/notification_center/notification_center_panel.dart';
import '../../support/fixtures/localization_log_fixture.dart';

void main() {
  setUp(() {
    final logs = LocalizationLogFixture.install(expectedMissingCatalog: true);
    addTearDown(logs.dispose);
  });
  test('open acknowledges once and late badge cannot restore unread', () async {
    final badge = Completer<dynamic>();
    final calls = <String>[];
    final controller = NotificationCenterController(read: (name, params) async {
      calls.add(name);
      if (name == 'get_notification_center_badge') return badge.future;
      return {'snapshot': 7, 'groups': [], 'occasions': []};
    });
    addTearDown(controller.dispose);
    controller.configure(userId: 'user', organizationId: 1);
    await controller.open();
    badge.complete({'enabled': true, 'unread': true});
    await Future<void>.delayed(Duration.zero);
    expect(controller.unread, isFalse);
    expect(calls.where((c) => c == 'open_notification_center').length, 1);
  });
  test('a badge started during open cannot undo the confirmed acknowledgement',
      () async {
    final acknowledgement = Completer<dynamic>();
    final badge = Completer<dynamic>();
    var badges = 0;
    final controller = NotificationCenterController(read: (name, params) async {
      if (name == 'get_notification_center_badge') {
        badges++;
        return badges == 1 ? {'enabled': true, 'unread': true} : badge.future;
      }
      return acknowledgement.future;
    });
    addTearDown(controller.dispose);
    controller.configure(userId: 'user', organizationId: 1);
    await Future<void>.delayed(Duration.zero);
    final open = controller.open();
    final poll = controller.refreshBadge();
    acknowledgement.complete({'snapshot': 7, 'groups': [], 'occasions': []});
    await open;
    badge.complete({'enabled': true, 'unread': true});
    await poll;
    expect(controller.unread, isFalse);
  });
  test('logout rejects a pending open and clears personal data', () async {
    final open = Completer<dynamic>();
    final controller = NotificationCenterController(
        read: (name, params) async => name == 'open_notification_center'
            ? open.future
            : {'enabled': true, 'unread': true});
    addTearDown(controller.dispose);
    controller.configure(userId: 'first', organizationId: 1);
    final pending = controller.open();
    controller.configure(userId: null, organizationId: 1);
    open.complete({
      'snapshot': 8,
      'groups': [
        {'key': 'secret', 'count': 1}
      ],
      'occasions': []
    });
    await pending;
    expect(controller.groups, isEmpty);
    expect(controller.enabled, isFalse);
  });
  test(
      'failed acknowledgement preserves unread and expanding never acknowledges',
      () async {
    var fail = true;
    final calls = <String>[];
    final controller = NotificationCenterController(read: (name, params) async {
      calls.add(name);
      if (name == 'get_notification_center_badge')
        return {'enabled': true, 'unread': true};
      if (name == 'open_notification_center' && fail)
        throw StateError('offline');
      return {
        'items': [
          {
            'id': 'one',
            'kind': 'order_created',
            'data': {'orderId': 1}
          }
        ],
        'nextCursor': 4
      };
    });
    addTearDown(controller.dispose);
    controller.configure(userId: 'user', organizationId: 1);
    await Future<void>.delayed(Duration.zero);
    await controller.open();
    expect(controller.unread, isTrue);
    expect(controller.failed, isTrue);
    fail = false;
    final group = NotificationGroup.fromJson(
        {'key': 'orders', 'count': 8, 'kind': 'order_created'});
    await controller.expand(group);
    expect(group.expanded, isTrue);
    expect(group.items.single.data['orderId'], 1);
    expect(calls.where((c) => c == 'open_notification_center').length, 1);
  });
  testWidgets('polling pauses in background and panel polls do not acknowledge',
      (tester) async {
    final calls = <String>[];
    final controller = NotificationCenterController(read: (name, params) async {
      calls.add(name);
      if (name == 'get_notification_center_badge')
        return {'enabled': true, 'unread': true};
      return {'snapshot': 3, 'groups': [], 'occasions': []};
    });
    addTearDown(controller.dispose);
    controller.configure(userId: 'user', organizationId: 1);
    await tester.pump();
    await tester.pump(const Duration(seconds: 59));
    expect(calls.length, 1);
    await tester.pump(const Duration(seconds: 1));
    expect(calls.length, 2);
    await controller.open();
    await tester.pump(const Duration(seconds: 15));
    expect(controller.unread, isTrue);
    expect(calls.where((c) => c == 'open_notification_center').length, 1);
    controller.setForeground(false);
    final stopped = calls.length;
    await tester.pump(const Duration(minutes: 2));
    expect(calls.length, stopped);
  });
  test('pagination failure keeps snapshot and never acknowledges', () async {
    final calls = <String>[];
    final controller = NotificationCenterController(read: (name, params) async {
      calls.add(name);
      if (name == 'get_notification_center_page') throw StateError('offline');
      return {'enabled': true, 'unread': true};
    });
    addTearDown(controller.dispose);
    controller.configure(userId: 'user', organizationId: 1);
    final group = NotificationGroup.fromJson({'key': 'orders', 'count': 1});
    controller.groups = [group];
    controller.snapshot = 9;
    controller.nextCursor = {'key': 'older'};
    await controller.loadMore();
    expect(controller.groups.single, same(group));
    expect(controller.pageFailed, isTrue);
    expect(controller.failed, isFalse);
    expect(calls, isNot(contains('open_notification_center')));
  });
  test(
      'background updates batch loaded IDs and remove revoked rows without ack',
      () async {
    final batchSizes = <int>[];
    final controller = NotificationCenterController(read: (name, params) async {
      if (name == 'get_notification_center_badge')
        return {'enabled': true, 'unread': false};
      expect(name, 'get_notification_center_updates');
      final ids = params['p_ids'] as List;
      batchSizes.add(ids.length);
      return {
        'items': ids
            .where((id) => id != '0')
            .map((id) => {
                  'id': id,
                  'kind': 'order_created',
                  'status': 'paid',
                  'data': {}
                })
            .toList()
      };
    });
    addTearDown(controller.dispose);
    controller.configure(userId: 'user', organizationId: 1);
    await Future<void>.delayed(Duration.zero);
    final group = NotificationGroup.fromJson({
      'key': 'orders',
      'count': 201,
      'items': List.generate(
          201, (index) => {'id': '$index', 'kind': 'order_created', 'data': {}})
    });
    group.expanded = true;
    controller.groups = [group];
    controller.panelOpen = true;
    await controller.refresh();
    expect(batchSizes, [200, 1]);
    expect(group.items.length, 200);
    expect(group.items.first.id, '1');
    expect(group.items.first.status, 'paid');
    expect(group.expanded, isTrue);
  });
  test(
      'permission failure clears retained content while network failure keeps it',
      () async {
    var denied = false;
    final controller = NotificationCenterController(read: (name, params) async {
      if (name == 'get_notification_center_badge')
        return {'enabled': true, 'unread': false};
      if (denied)
        throw const PostgrestException(
            message: 'notification_read_denied', code: '42501');
      throw StateError('offline');
    });
    addTearDown(controller.dispose);
    controller.configure(userId: 'user', organizationId: 1);
    await Future<void>.delayed(Duration.zero);
    controller.groups = [
      NotificationGroup.fromJson({
        'key': 'orders',
        'count': 1,
        'items': [
          {'id': 'secret', 'data': {}}
        ]
      })
    ];
    controller.panelOpen = true;
    await controller.refresh();
    expect(controller.groups.single.items.single.id, 'secret');
    expect(controller.refreshFailed, isTrue);
    denied = true;
    await controller.refresh();
    expect(controller.groups, isEmpty);
    expect(controller.enabled, isFalse);
  });
  testWidgets(
      'panel is accessible at mobile, breakpoint and desktop with large text',
      (tester) async {
    final controller =
        NotificationCenterController(read: (_, params) async => {});
    addTearDown(controller.dispose);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final width in [320.0, 719.0, 720.0, 1100.0]) {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(MaterialApp(
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(2)),
              child: child!),
          home: Builder(
              builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () => showDialog<void>(
                          context: context,
                          builder: (_) => NotificationCenterPanel(
                              controller: controller,
                              anchor: Rect.fromLTWH(width - 96, 16, 48, 48),
                              onDetail: (_) {})),
                      child: const Text('Open'))))));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('NotificationCenter.empty'), findsOneWidget);
      final surface = find.descendant(
          of: find.byType(Dialog),
          matching: find.byWidgetPredicate((widget) =>
              widget is Material && widget.type == MaterialType.card));
      final rect = tester.getRect(surface);
      if (width >= 720) {
        // Follow the bell's bottom and right edges, even with a short inbox.
        expect(rect.top, 72);
        expect(rect.right, width - 48);
      } else {
        expect(rect.center.dy, closeTo(500, 1));
      }
      expect(tester.takeException(), isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(NotificationCenterPanel), findsNothing);
    }
  });
  testWidgets('new arrivals stay inline and group expansion stays in panel',
      (tester) async {
    final controller = NotificationCenterController(
        read: (_, params) async => {
              'items': [
                {
                  'id': 'one',
                  'kind': 'order_created',
                  'status': 'paid',
                  'data': {'orderSymbol': '001234'}
                }
              ]
            });
    addTearDown(controller.dispose);
    controller.groups = [
      NotificationGroup.fromJson({
        'key': 'orders',
        'kind': 'order_created',
        'count': 7,
        'section': 1,
        'occasionTitle': 'A long event title ' * 4
      })
    ];
    controller.unread = true;
    await tester.pumpWidget(MaterialApp(
        home:
            NotificationCenterPanel(controller: controller, onDetail: (_) {})));
    expect(find.text('NotificationCenter.newItems'), findsOneWidget);
    expect(find.text('001234'), findsNothing);
    await tester.tap(find.text('NotificationCenter.kinds.order_created'));
    await tester.pumpAndSettle();
    expect(find.text('001234'), findsOneWidget);
    expect(find.byType(NotificationCenterPanel), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'problem reasons, partial counts and capacity have safe actionable presentation',
      (tester) async {
    tester.view.physicalSize = const Size(1100, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller =
        NotificationCenterController(read: (_, params) async => {});
    addTearDown(controller.dispose);
    controller.groups = [
      NotificationGroup.fromJson({
        'key': 'mail',
        'kind': 'email_problem',
        'count': 1,
        'items': [
          {
            'id': 'mail',
            'kind': 'email_problem',
            'status': 'active',
            'data': {
              'reason': 'complaint',
              'messageId': 'message',
              'recipient': 'jana@example.invalid',
              'customerName': 'Jana Nováková'
            }
          }
        ]
      }),
      NotificationGroup.fromJson({
        'key': 'offer',
        'kind': 'offer_accepted',
        'count': 1,
        'items': [
          {
            'id': 'offer',
            'kind': 'offer_accepted',
            'status': 'ordered',
            'data': {'count': 2}
          }
        ]
      }),
      NotificationGroup.fromJson({
        'key': 'capacity',
        'kind': 'capacity_full',
        'count': 1,
        'items': [
          {
            'id': 'capacity',
            'kind': 'capacity_full',
            'status': 'active',
            'data': {'remainingPublic': 0, 'limit': 10, 'heldForWaiting': 3}
          }
        ]
      }),
    ];
    var details = 0;
    await tester.pumpWidget(MaterialApp(
        home: NotificationCenterPanel(
            controller: controller, onDetail: (_) => details++)));
    await tester.pumpAndSettle();
    expect(find.text('jana@example.invalid - Jana Nováková'), findsOneWidget);
    expect(find.textContaining('NotificationCenter.reasons.complaint'),
        findsOneWidget);
    expect(find.text('NotificationCenter.detail'), findsOneWidget);
    await tester.tap(find.text('NotificationCenter.detail'));
    expect(details, 1);
    for (final key in ['places', 'capacity', 'heldForWaiting']) {
      final field = find.textContaining('NotificationCenter.$key');
      await tester.scrollUntilVisible(field, 100,
          scrollable: find.byType(Scrollable).first);
      expect(field, findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });
  testWidgets('bulk email incidents collapse and preserve each message kind',
      (tester) async {
    final controller = NotificationCenterController(
        read: (_, params) async => {
              'items': [
                {
                  'id': 'first',
                  'kind': 'email_problem',
                  'data': {
                    'messageKind': 'registration',
                    'reason': 'bounce',
                    'messageId': 'first-message'
                  }
                },
                {
                  'id': 'second',
                  'kind': 'email_problem',
                  'data': {
                    'messageKind': 'reset_password',
                    'reason': 'bounce',
                    'messageId': 'second-message'
                  }
                },
              ]
            });
    addTearDown(controller.dispose);
    controller.groups = [
      NotificationGroup.fromJson(
          {'key': 'email-group', 'kind': 'email_problem', 'count': 2})
    ];
    await tester.pumpWidget(MaterialApp(
        home:
            NotificationCenterPanel(controller: controller, onDetail: (_) {})));
    expect(find.text('2'), findsOneWidget);
    expect(
        find.textContaining('EmailDelivery.kind.registration'), findsNothing);
    await tester.tap(find.text('NotificationCenter.kinds.email_problem'));
    await tester.pumpAndSettle();
    expect(
        find.textContaining('EmailDelivery.kind.registration'), findsOneWidget);
    expect(find.textContaining('EmailDelivery.kind.reset_password'),
        findsOneWidget);
  });
}
