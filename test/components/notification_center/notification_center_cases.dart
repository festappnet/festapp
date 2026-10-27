import 'package:festapp_core/time.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:fstapp/components/notification_center/notification_center_calendar.dart';
import 'package:fstapp/widgets/dependency_material_bridge.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/notification_center/notification_center_controller.dart';
import 'package:fstapp/components/notification_center/notification_center_panel.dart';

import '../../support/fixtures/localization_log_fixture.dart';

import 'package:fstapp/components/notification_center/notification_item_presenter.dart';

NotificationItem row(
  String id, {
  int? occasion = 1,
  String title = 'Same title',
  String kind = 'order_created',
  int section = 2,
  Map<String, dynamic> data = const {},
}) => NotificationItem.fromJson({
  'id': id,
  'occasionId': occasion,
  'occasionTitle': title,
  'kind': kind,
  'section': section,
  'occasionLink': occasion == null ? null : 'event-$occasion',
  'occurredAt': '2026-10-26T12:00:00Z',
  'data': data,
});
Map<String, dynamic> opened([List<Map<String, dynamic>> items = const []]) => {
  'feedSupported': true,
  'timelineSupported': true,
  'snapshot': 7,
  'feedItems': items,
  'items': items,
  'snapshotAt': '2026-10-26T12:00:00Z',
  'occasions': [],
};
Map<String, dynamic> badge({bool unread = true}) => {
  'feedSupported': true,
  'timelineSupported': true,
  'enabled': true,
  'unread': unread,
};

void main() {
  setUp(() {
    final logs = LocalizationLogFixture.install(expectedMissingCatalog: true);
    addTearDown(logs.dispose);
  });
  test(
    'unread rows retain the pre-open watermark until the next open',
    () async {
      var watermark = 4;
      final c = NotificationCenterController(
        read: (name, params) async {
          if (name == 'get_notification_center_badge') return badge();
          if (name == 'open_notification_center') {
            return {...opened(), 'previousReadThrough': watermark};
          }
          return opened([
            {'id': 'read', 'sequence': 4},
            {'id': 'new', 'sequence': 5},
          ]);
        },
      );
      addTearDown(c.dispose);
      c.configure(userId: 'u', organizationId: 1);
      await c.open();
      expect(c.unread, isFalse);
      expect(c.isUnread(c.items.first), isFalse);
      expect(c.isUnread(c.items.last), isTrue);
      expect(
        c.isUnread(NotificationItem.fromJson({'id': 'future', 'sequence': 8})),
        isFalse,
      );
      c.close();
      watermark = 7;
      await c.open();
      expect(c.items.any(c.isUnread), isFalse);
      c.configure(userId: 'other', organizationId: 1);
      expect(c.previousReadThrough, isNull);
    },
  );
  test('older backends do not invent an unread watermark', () async {
    final c = NotificationCenterController(
      read: (name, params) async => name == 'get_notification_center_badge'
          ? badge()
          : opened([
              {'id': 'unknown', 'sequence': 5},
            ]),
    );
    addTearDown(c.dispose);
    c.configure(userId: 'u', organizationId: 1);
    await c.open();
    expect(c.isUnread(c.items.single), isFalse);
  });
  for (final brightness in Brightness.values) {
    testWidgets('unread indication fits narrow ${brightness.name} panel', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = NotificationCenterController();
      addTearDown(c.dispose);
      c.snapshot = 7;
      c.previousReadThrough = 4;
      c.items = [
        for (final sequence in [4, 5])
          NotificationItem.fromJson({
            'id': '$sequence',
            'sequence': sequence,
            'kind': 'order_created',
            'occurredAt': '2026-10-26T12:00:00Z',
          }),
      ];
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          builder: DependencyMaterialBridge.builder,
          home: NotificationCenterPanel(controller: c, onDetail: (_) {}),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(
        find.bySemanticsLabel(RegExp('NotificationCenter.newNotification')),
        findsOneWidget,
      );
      final oldRow = find.byKey(const ValueKey('notification-item-4'));
      final newRow = find.byKey(const ValueKey('notification-item-5'));
      expect(tester.widget<Material>(oldRow).color, Colors.transparent);
      expect(tester.widget<Material>(newRow).color, isNot(Colors.transparent));
      for (final entry in [
        (oldRow, FontWeight.w400),
        (newRow, FontWeight.w600),
      ]) {
        final title = find.descendant(
          of: entry.$1,
          matching: find.text('NotificationCenter.kinds.order_created'),
        );
        expect(tester.widget<Text>(title).style?.fontWeight, entry.$2);
      }
      semantics.dispose();
    });
  }
  test('open acknowledges once and late badge cannot restore unread', () async {
    final pending = Completer<dynamic>();
    final calls = <String>[];
    final c = NotificationCenterController(
      read: (name, params) async {
        calls.add(name);
        if (name == 'get_notification_center_badge') return pending.future;
        return opened();
      },
    );
    addTearDown(c.dispose);
    c.configure(userId: 'u', organizationId: 1);
    await c.open();
    pending.complete(badge());
    await Future<void>.delayed(Duration.zero);
    expect(c.unread, isFalse);
    expect(calls.where((name) => name == 'open_notification_center').length, 1);
  });
  test('badge begun during acknowledgement cannot undo it', () async {
    final pending = Completer<dynamic>(), polling = Completer<dynamic>();
    var polls = 0;
    final c = NotificationCenterController(
      read: (name, params) async {
        if (name == 'get_notification_center_badge') {
          polls++;
          if (polls == 1) return badge();
          return polling.future;
        }
        return pending.future;
      },
    );
    addTearDown(c.dispose);
    c.configure(userId: 'u', organizationId: 1);
    await Future<void>.delayed(Duration.zero);
    final open = c.open();
    final poll = c.refreshBadge();
    pending.complete(opened());
    await open;
    expect(c.failed, isFalse);
    polling.complete(badge());
    await poll;
    expect(c.unread, isFalse);
  });
  test('identity reset rejects a pending snapshot', () async {
    final pending = Completer<dynamic>();
    final c = NotificationCenterController(
      read: (name, params) async =>
          name == 'get_notification_center_badge' ? badge() : pending.future,
    );
    addTearDown(c.dispose);
    c.configure(userId: 'u', organizationId: 1);
    final open = c.open();
    c.configure(userId: null, organizationId: null);
    pending.complete(
      opened([
        {'id': 'secret'},
      ]),
    );
    await open;
    expect(c.items, isEmpty);
    expect(c.enabled, isFalse);
  });
  test(
    'capability absence hides center without detection acknowledgement',
    () async {
      final calls = <String>[];
      final c = NotificationCenterController(
        read: (name, params) async {
          calls.add(name);
          return {'enabled': true};
        },
      );
      addTearDown(c.dispose);
      c.configure(userId: 'u', organizationId: 1);
      await Future<void>.delayed(Duration.zero);
      await c.open();
      expect(c.enabled, isFalse);
      expect(calls, ['get_notification_center_badge']);
    },
  );
  test(
    'failed open preserves unread and pagination never acknowledges',
    () async {
      final calls = <String>[];
      final c = NotificationCenterController(
        read: (name, params) async {
          calls.add(name);
          if (name == 'get_notification_center_badge') return badge();
          if (name == 'open_notification_center') throw StateError('offline');
          return {
            'items': [
              {'id': 'sixth'},
            ],
          };
        },
      );
      addTearDown(c.dispose);
      c.configure(userId: 'u', organizationId: 1);
      await Future<void>.delayed(Duration.zero);
      await c.open();
      expect(c.failed, isTrue);
      expect(c.unread, isTrue);
      c.snapshotAt = DateTime.utc(2026, 10, 26);
      c.nextCursor = 'cursor';
      await c.loadMore();
      expect(c.items.single.id, 'sixth');
      expect(
        calls.where((name) => name == 'open_notification_center').length,
        1,
      );
      expect(calls, contains('get_notification_center_overview'));
    },
  );
  testWidgets('polling pauses in background and does not acknowledge', (
    tester,
  ) async {
    final calls = <String>[];
    final c = NotificationCenterController(
      read: (name, params) async {
        calls.add(name);
        return name == 'get_notification_center_badge' ? badge() : opened();
      },
    );
    addTearDown(c.dispose);
    c.configure(userId: 'u', organizationId: 1);
    await tester.pump();
    await tester.pump(const Duration(seconds: 60));
    expect(calls.length, 2);
    await c.open();
    await tester.pump(const Duration(seconds: 15));
    expect(c.unread, isTrue);
    expect(calls.where((name) => name == 'open_notification_center').length, 1);
    c.setForeground(false);
    final count = calls.length;
    await tester.pump(const Duration(minutes: 2));
    expect(calls.length, count);
  });
  test('pagination failure retains items and snapshot', () async {
    final c = NotificationCenterController(
      read: (name, params) async {
        if (name == 'get_notification_center_overview')
          throw StateError('offline');
        return badge();
      },
    );
    addTearDown(c.dispose);
    c.configure(userId: 'u', organizationId: 1);
    final item = row('retained');
    c.items = [item];
    c.snapshot = 9;
    c.snapshotAt = DateTime.utc(2026, 10, 26);
    c.nextCursor = 'cursor';
    await c.loadMore();
    expect(c.items.single, same(item));
    expect(c.snapshot, 9);
    expect(c.pageFailed, isTrue);
  });
  test(
    'hydration batches IDs, removes revoked and preserves section/order',
    () async {
      final batches = <int>[];
      final c = NotificationCenterController(
        read: (name, params) async {
          if (name == 'get_notification_center_badge') {
            return badge(unread: false);
          }
          expect(name, 'get_notification_center_overview');
          final ids = params['p_ids'] as List;
          batches.add(ids.length);
          return {
            'items': ids
                .where((id) => id != '0')
                .toList()
                .reversed
                .map(
                  (id) => {
                    'id': id,
                    'kind': 'order_created',
                    'status': 'paid',
                    'data': {},
                  },
                )
                .toList(),
          };
        },
      );
      addTearDown(c.dispose);
      c.configure(userId: 'u', organizationId: 1);
      await Future<void>.delayed(Duration.zero);
      c.items = List.generate(201, (i) => row('$i', section: 1));
      c.panelOpen = true;
      await c.refresh();
      expect(batches, [200, 1]);
      expect(c.items.length, 200);
      expect(c.items.first.id, '1');
      expect(c.items.first.status, 'paid');
      expect(c.items.first.section, 1);
    },
  );
  test(
    'permission failure clears private content, network failure retains it',
    () async {
      var denied = false;
      final c = NotificationCenterController(
        read: (name, params) async {
          if (name == 'get_notification_center_badge') return badge();
          if (denied) {
            throw const PostgrestException(message: 'denied', code: '42501');
          }
          throw StateError('offline');
        },
      );
      addTearDown(c.dispose);
      c.configure(userId: 'u', organizationId: 1);
      await Future<void>.delayed(Duration.zero);
      c.items = [row('secret')];
      c.panelOpen = true;
      await c.refresh();
      expect(c.items.single.id, 'secret');
      expect(c.refreshFailed, isTrue);
      denied = true;
      await c.refresh();
      expect(c.items, isEmpty);
      expect(c.enabled, isFalse);
    },
  );
  test(
    'presenter uses contact fallback, historical count and neutral form labels',
    () {
      expect(
        NotificationItemPresenter(
          row(
            '1',
            data: {
              'contact': {'name': '  ', 'email': ' user@example.invalid '},
              'orderSymbol': 'HIDDEN',
              'count': 1,
            },
          ),
        ).details,
        ['user@example.invalid'],
      );
      expect(
        NotificationItemPresenter(row('2', data: {'count': 2})).details,
        contains('NotificationCenter.places.other'),
      );
      expect(
        NotificationItemPresenter(
          row(
            '3',
            data: {
              'count': 1,
              'formContext': {'allowsMultiple': true},
            },
          ),
        ).details,
        contains('NotificationCenter.places.one'),
      );
      for (final kind in ['form_opened', 'form_closed']) {
        final p = NotificationItemPresenter(row(kind, kind: kind));
        expect(p.details, contains('NotificationCenter.form'));
        expect(p.hasDetail, isFalse);
      }
      expect(
        NotificationItemPresenter(row('unknown', kind: 'unrecognized')).title,
        'NotificationCenter.title',
      );
    },
  );
  testWidgets(
    'panel is accessible at mobile, breakpoint and desktop with large text',
    (tester) async {
      final controller = NotificationCenterController(
        read: (_, params) async => {},
      );
      addTearDown(controller.dispose);
      controller.items = [
        row(
          'responsive',
          occasion: 1,
          title: 'Country bál 2026 - dlouhý název akce',
          data: {
            'contact': {
              'email':
                  'very.long.email.address.for.the.customer@example.invalid',
            },
            'count': 2,
          },
        ),
      ];
      controller.items.add(
        row(
          'responsive-email',
          occasion: null,
          kind: 'email_problem',
          section: 0,
          data: {
            'messageId': 'synthetic-message',
            'recipient':
                'very.long.recipient.address.for.the.customer@example.invalid',
            'reason': 'bounce',
            'messageKind': 'registration',
          },
        ),
      );
      controller.occasions = [
        {'id': 1, 'title': 'Country bál 2026'},
      ];
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final width in [320.0, 719.0, 720.0, 1100.0]) {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(
          MaterialApp(
            builder: DependencyMaterialBridge.wrapBuilder(
              (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(2)),
                child: child!,
              ),
            ),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => NotificationCenterPanel(
                      controller: controller,
                      anchor: Rect.fromLTWH(width - 96, 16, 48, 48),
                      onDetail: (_) {},
                    ),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(
          find.text('Country bál 2026 - dlouhý název akce'),
          findsOneWidget,
        );
        final surface = find.descendant(
          of: find.byType(Dialog),
          matching: find.byWidgetPredicate(
            (widget) => widget is Material && widget.type == MaterialType.card,
          ),
        );
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
    },
  );
  testWidgets(
    'flat occasion blocks merge pages, retain same-name identities and detail navigation',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final calls = <String>[];
      final c = NotificationCenterController(
        read: (name, params) async {
          calls.add(name);
          return {
            'items': [
              {
                'id': 'sixth',
                'occasionId': 1,
                'occasionTitle': 'Same title',
                'kind': 'form_opened',
                'section': 2,
                'data': {},
              },
            ],
          };
        },
      );
      addTearDown(c.dispose);
      c.items = [
        row(
          'first',
          data: {
            'orderSymbol': 'HIDDEN',
            'orderId': 1,
            'contact': {'email': 'contact@example.invalid'},
          },
        ),
        row('second', occasion: 2),
        row('cancelled', kind: 'order_cancelled'),
      ];
      c.occasions = [
        {'id': 1, 'title': 'Same title'},
        {'id': 2, 'title': 'Same title'},
      ];
      c.snapshotAt = DateTime.utc(2026, 10, 26);
      c.nextCursor = 'cursor';
      c.unread = true;
      final selected = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          builder: DependencyMaterialBridge.builder,
          home: NotificationCenterPanel(
            controller: c,
            onDetail: (item) => selected.add(item.id),
          ),
        ),
      );
      expect(find.text('Same title'), findsNWidgets(2));
      expect(find.byType(PopupMenuButton<bool>), findsNWidgets(2));
      expect(find.byIcon(Icons.expand_more), findsNothing);
      expect(find.text('HIDDEN'), findsNothing);
      await tester.tap(find.text('contact@example.invalid'));
      expect(selected, ['first']);
      await c.loadMore();
      await tester.pumpAndSettle();
      expect(find.text('Same title'), findsNWidgets(2));
      expect(find.text('NotificationCenter.kinds.form_opened'), findsOneWidget);
      expect(calls, ['get_notification_center_overview']);
      expect(c.unread, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'email and bank incidents retain actionable details and safe affected links',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = NotificationCenterController(read: (_, params) async => {});
      addTearDown(c.dispose);
      c.items = [
        row(
          'email',
          occasion: null,
          kind: 'email_problem',
          section: 0,
          data: {
            'messageId': 'message',
            'recipient': 'recipient@example.invalid',
            'reason': 'bounce',
            'messageKind': 'registration',
          },
        ),
        row(
          'bank',
          occasion: null,
          kind: 'bank_problem',
          section: 0,
          data: {
            'affectedOccasions': [
              {'title': 'Affected', 'link': 'event'},
            ],
          },
        ),
        row(
          'full',
          kind: 'capacity_full',
          data: {'remainingPublic': 0, 'limit': 10, 'heldForWaiting': 3},
        ),
      ];
      final targets = <NotificationItem>[];
      await tester.pumpWidget(
        MaterialApp(
          builder: DependencyMaterialBridge.builder,
          home: NotificationCenterPanel(controller: c, onDetail: targets.add),
        ),
      );
      expect(find.textContaining('recipient@example.invalid'), findsOneWidget);
      expect(
        find.textContaining('EmailDelivery.kind.registration'),
        findsOneWidget,
      );
      await tester.tap(find.textContaining('recipient@example.invalid'));
      expect(targets.single.data['messageId'], 'message');
      await tester.tap(find.text('Affected'));
      expect(targets.last.data['relatedOrders'], isTrue);
      expect(tester.takeException(), isNull);
    },
  );
  test(
    'device calendar partitions are contiguous and preserve DST day lengths',
    () {
      OccasionTimeContext.initializeTimeZones();
      final zone = tz.getLocation('Europe/Prague');
      for (final sample in [
        (DateTime.utc(2026, 10, 27, 12), '2026-10-25', 25),
        (DateTime.utc(2026, 3, 31, 12), '2026-03-29', 23),
      ]) {
        final at = sample.$1;
        final oldest = at.subtract(const Duration(days: 40));
        final periods = NotificationCenterCalendar.periods(
          at,
          oldest,
          localize: (value) => tz.TZDateTime.from(value, zone),
          midnight: (y, m, d) => tz.TZDateTime(zone, y, m, d),
        );
        expect(
          DateTime.parse(periods.first['endAt'] as String),
          at.subtract(const Duration(hours: 24)),
        );
        for (var i = 1; i < periods.length; i++) {
          expect(periods[i]['endAt'], periods[i - 1]['startAt']);
        }
        final changed = periods.singleWhere((p) => p['firstDay'] == sample.$2);
        expect(
          DateTime.parse(changed['endAt'] as String)
              .difference(DateTime.parse(changed['startAt'] as String))
              .inHours,
          sample.$3,
        );
        expect(periods.last['unit'], 'week');
        expect(
          DateTime.parse(periods.last['startAt'] as String).isAfter(oldest),
          isFalse,
        );
      }
      expect(
        NotificationCenterCalendar.periods(DateTime.utc(2026, 10, 26), null),
        isEmpty,
      );
    },
  );

  testWidgets(
    'summary opens the common destination without expansion or filters',
    (tester) async {
      final c = NotificationCenterController();
      addTearDown(c.dispose);
      c.items = [
        row(
          'summary',
          data: {
            'activityCount': 35,
            'relatedOrders': true,
            'contact': {'name': 'Petra'},
          },
        ),
        row('form', kind: 'form_closed', section: 0),
      ];
      final targets = <NotificationItem>[];
      await tester.pumpWidget(
        MaterialApp(
          builder: DependencyMaterialBridge.builder,
          home: NotificationCenterPanel(controller: c, onDetail: targets.add),
        ),
      );
      expect(find.text('Same title'), findsOneWidget);
      expect(find.byIcon(Icons.expand_more), findsNothing);
      expect(find.byType(FilterChip), findsNothing);
      expect(find.textContaining('2026'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('notification-item-summary')));
      expect(targets.single.data['relatedOrders'], isTrue);
      expect(targets.single.occasionLink, 'event-1');
      expect(targets.single.data['orderId'], isNull);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'summary hydration updates full count without moving or acknowledging',
    () async {
      final calls = <String>[];
      final c = NotificationCenterController(
        read: (name, params) async {
          calls.add(name);
          if (name == 'get_notification_center_badge')
            return badge(unread: false);
          expect(params['p_ids'], ['summary']);
          return {
            'items': [
              {
                'id': 'summary',
                'kind': 'order_created',
                'section': 2,
                'sequence': 99,
                'occurredAt': '2026-11-01T12:00:00Z',
                'occasionLink': 'event-1',
                'data': {'activityCount': 34, 'relatedOrders': true},
              },
            ],
          };
        },
      );
      addTearDown(c.dispose);
      c.configure(userId: 'u', organizationId: 1);
      await Future<void>.delayed(Duration.zero);
      c.snapshot = 7;
      c.previousReadThrough = 4;
      final original = NotificationItem.fromJson({
        'id': 'summary',
        'section': 1,
        'sequence': 5,
        'occasionId': 1,
        'occurredAt': '2026-10-26T12:00:00Z',
        'data': {'activityCount': 35, 'relatedOrders': true},
      });
      c.items = [original];
      c.panelOpen = true;
      await c.refresh();
      final refreshed = c.items.single;
      expect(refreshed.data['activityCount'], 34);
      expect(refreshed.section, 1);
      expect(refreshed.sequence, 5);
      expect(refreshed.occurredAt, original.occurredAt);
      expect(c.isUnread(refreshed), isTrue);
      expect(calls, isNot(contains('open_notification_center')));
    },
  );

  test('summary hydration rejects stale identities', () async {
    final pending = Completer<dynamic>();
    final c = NotificationCenterController(
      read: (name, _) async =>
          name == 'get_notification_center_badge' ? badge() : pending.future,
    );
    addTearDown(c.dispose);
    c.configure(userId: 'u', organizationId: 1);
    await Future<void>.delayed(Duration.zero);
    c.panelOpen = true;
    c.items = [
      row('summary', data: {'activityCount': 35, 'relatedOrders': true}),
    ];
    final refresh = c.refresh();
    await Future<void>.delayed(Duration.zero);
    c.configure(userId: 'other', organizationId: 1);
    pending.complete({
      'items': [
        {
          'id': 'summary',
          'data': {'activityCount': 40},
        },
      ],
    });
    await refresh;
    expect(c.items, isEmpty);
  });
}
