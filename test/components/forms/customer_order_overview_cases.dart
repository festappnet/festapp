import 'package:fstapp/components/discount_codes/discount_summary.dart';

import 'dart:async';

import 'package:fstapp/components/forms/customer_order_changes.dart';
import 'package:fstapp/components/forms/customer_order_changes_client.dart';
import 'package:fstapp/widgets/dependency_material_bridge.dart';

import '../../support/fixtures/localization_log_fixture.dart';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:festapp_core/forms.dart';
import 'package:fstapp/components/forms/views/customer_order_overview.dart';

Map<String, dynamic> fixture({String ticketState = 'unused'}) => {
  'code': 200,
  'root': {'id': 1, 'symbol': 'ROOT', 'title': 'Synthetic'},
  'serverTime': '2026-10-15T12:00:00Z',
  'people': [
    {'id': 1, 'label': 'Waiting', 'effectiveLifecycle': 'offered'},
    {'id': 2, 'label': 'Accepted', 'effectiveLifecycle': 'admitted'},
  ],
  'offers': [
    {
      'pendingPlaces': 1,
      'effectiveStatus': 'pending',
      'expiresAt': '2026-10-16',
    },
  ],
  'orders': [
    {
      'symbol': 'CHILD',
      'state': 'paid',
      'total': 1000,
      'currency': 'CZK',
      'items': [
        {
          'title': 'Místo',
          'price': 450,
          'currency': 'CZK',
          'spotGroupTitle': '7',
          'spotTitle': '3',
        },
      ],
      'payment': {
        'status': 'deposit_paid',
        'received': 300,
        'totalOutstanding': 700,
        'returned': 0,
        'overpaid': 0,
        'instructionsAvailable': true,
        'dueNow': 700,
        'publicAccount': '123/0100',
        'referenceKind': 'VS',
        'reference': '123',
      },
      'tickets': [
        {'id': 2, 'label': 'Accepted', 'displayStatus': ticketState},
      ],
    },
  ],
};
void main() {
  // This suite intentionally uses untranslated key fallback (no catalog).
  setUp(() {
    final logs = LocalizationLogFixture.install(expectedMissingCatalog: true);
    addTearDown(logs.dispose);
  });
  testWidgets(
    'discounted overview shows original item before the shared net summary',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 2200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final data = fixture();
      final order = (data['orders'] as List).first as Map<String, dynamic>;
      order['total'] = 70;
      order.remove('payment');
      order['items'] = [
        {'title': 'Vstupné', 'price': 70, 'basePrice': 100, 'currency': 'CZK'},
      ];
      order['discount'] = {
        'code': 'SLEVAAAA',
        'base': 100,
        'discount': 30,
        'net': 70,
        'currency': 'CZK',
      };
      await tester.pumpWidget(
        MaterialApp(
          builder: DependencyMaterialBridge.builder,
          home: Scaffold(
            body: SingleChildScrollView(
              child: CustomerOrderOverviewView(
                load: () async => CustomerOrderOverview(data),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining(RegExp(r'^Vstupné: 100\s*Kč$')),
        findsOneWidget,
      );
      expect(find.byType(DiscountSummary), findsOneWidget);
      expect(find.textContaining('OrderOverview.total:'), findsNothing);
      expect(
        tester.getTopLeft(find.byType(DiscountSummary)).dy,
        greaterThan(
          tester
              .getBottomLeft(
                find.textContaining(RegExp(r'^Vstupné: 100\s*Kč$')),
              )
              .dy,
        ),
      );
      expect(order['items'][0]['price'], 70);
    },
  );
  testWidgets(
    'partial overview keeps separate payment facts and refresh observes usage',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 2200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var calls = 0;
      var fail = false;
      await tester.pumpWidget(
        MaterialApp(
          builder: DependencyMaterialBridge.builder,
          home: Scaffold(
            body: SingleChildScrollView(
              child: CustomerOrderOverviewView(
                load: () async {
                  calls++;
                  if (fail) throw StateError('offline');
                  return CustomerOrderOverview(
                    fixture(ticketState: calls == 1 ? 'unused' : 'used'),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('CHILD'), findsOneWidget);
      expect(
        find.text('OrderOverview.table: 7 · OrderOverview.seat: 3'),
        findsOneWidget,
      );
      expect(find.textContaining('300 CZK'), findsOneWidget);
      expect(find.textContaining('700 CZK'), findsNWidgets(2));
      expect(find.byType(Checkbox), findsNothing);
      expect(find.byType(TextButton), findsOneWidget);
      await tester.tap(find.byType(TextButton));
      await tester.pumpAndSettle();
      expect(find.textContaining('OrderOverview.used'), findsOneWidget);
      fail = true;
      await tester.tap(find.byType(TextButton));
      await tester.pumpAndSettle();
      expect(find.text('CHILD'), findsNothing);
      expect(find.text('OrderOverview.failed'), findsOneWidget);
      fail = false;
      await tester.tap(find.byType(TextButton));
      await tester.pumpAndSettle();
      expect(find.text('CHILD'), findsOneWidget);
    },
  );
  testWidgets(
    'customer change requires explicit confirmation and retries exact command',
    (tester) async {
      final api = _ChangeApi();
      var changes = 0;
      await tester.pumpWidget(
        MaterialApp(
          builder: DependencyMaterialBridge.builder,
          home: Scaffold(
            body: SingleChildScrollView(
              child: CustomerOrderChanges(
                scope: CustomerOrderScope('a' * 64, 1, changeToken: 'b' * 64),
                data: CustomerOrderOverview(fixture()),
                client: api,
                onChanged: () async {
                  changes++;
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(api.calls.map((c) => c['action']), ['resolve', 'preview']);
      expect(changes, 0);
      await tester.tap(find.text('CustomerSelfService.confirmRequest'));
      await tester.pumpAndSettle();
      expect(find.text('CustomerSelfService.failed'), findsOneWidget);
      await tester.tap(find.text('CustomerSelfService.confirmRequest'));
      await tester.pumpAndSettle();
      final commands = api.calls
          .where((c) => c['action'] == 'command')
          .toList();
      expect(commands.length, 2);
      expect(commands[0], commands[1]);
      expect(changes, 1);
      expect(find.text('CustomerSelfService.confirmRequest'), findsNothing);
    },
  );

  testWidgets('customer self-service rejects obsolete date-change deep links', (
    tester,
  ) async {
    final api = _ChangeApi(
      operation: 'move',
      preview: Future.value({
        'code': 200,
        'effect': 'move',
        'fingerprint': 'move',
        'target': {
          'title': 'Večerní termín',
          'tickets': [
            {
              'products': [
                {
                  'title': 'Vstup na večer',
                  'price': 1000,
                  'currency_code': 'CZK',
                },
              ],
            },
          ],
        },
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        builder: DependencyMaterialBridge.builder,
        home: Scaffold(
          body: SingleChildScrollView(
            child: CustomerOrderChanges(
              scope: CustomerOrderScope('a' * 64, 1, changeToken: 'b' * 64),
              data: CustomerOrderOverview(fixture()),
              client: api,
              onChanged: () async {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Večerní termín'), findsNothing);
    expect(find.text('Vstup na večer: 1000 CZK'), findsNothing);
    expect(find.text('CustomerSelfService.confirm'), findsNothing);
    expect(find.text('CustomerSelfService.unavailable'), findsOneWidget);
    expect(api.calls.where((c) => c['action'] == 'preview'), isEmpty);
    expect(api.calls.where((c) => c['action'] == 'command'), isEmpty);
  });

  testWidgets('customer cancellation sends only checked tickets', (
    tester,
  ) async {
    final api = _ChangeApi();
    final data = fixture()
      ..['allowedActions'] = [
        {'operation': 'edit', 'enabled': true, 'fields': []},
        {
          'operation': 'cancel',
          'enabled': true,
          'tickets': [
            {'id': 1},
            {'id': 2},
          ],
        },
      ];
    await tester.pumpWidget(
      MaterialApp(
        builder: DependencyMaterialBridge.builder,
        home: Scaffold(
          body: SingleChildScrollView(
            child: CustomerOrderChanges(
              scope: CustomerOrderScope('a' * 64, 1),
              data: CustomerOrderOverview(data),
              client: api,
              onChanged: () async {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('CustomerSelfService.cancelTickets'));
    await tester.pumpAndSettle();
    expect(find.byType(CheckboxListTile), findsNWidgets(2));
    await tester.tap(find.byType(CheckboxListTile).last);
    await tester.pump();
    await tester.ensureVisible(find.text('CustomerSelfService.sendLink'));
    await tester.tap(find.text('CustomerSelfService.sendLink'));
    await tester.pumpAndSettle();
    expect(api.calls.single['action'], 'challenge');
    expect(api.calls.single['payload']['ticketIds'], [1]);
  });

  testWidgets('customer change ignores preview arriving after scope changes', (
    tester,
  ) async {
    final gate = Completer<Map<String, dynamic>>();
    final api = _ChangeApi(preview: gate.future);
    Widget surface(CustomerOrderScope scope) => MaterialApp(
      builder: DependencyMaterialBridge.builder,
      home: Scaffold(
        body: SingleChildScrollView(
          child: CustomerOrderChanges(
            scope: scope,
            data: CustomerOrderOverview(fixture()),
            client: api,
            onChanged: () async {},
          ),
        ),
      ),
    );
    await tester.pumpWidget(
      surface(CustomerOrderScope('a' * 64, 1, changeToken: 'b' * 64)),
    );
    await tester.pump();
    await tester.pumpWidget(surface(CustomerOrderScope('c' * 64, 2)));
    gate.complete({
      'code': 200,
      'effect': 'request_cancel',
      'fingerprint': 'old',
    });
    await tester.pumpAndSettle();
    expect(find.text('CustomerSelfService.confirmRequest'), findsNothing);
    expect(api.calls.where((c) => c['action'] == 'command'), isEmpty);
  });
}

class _ChangeApi implements CustomerOrderChangesApi {
  _ChangeApi({this.preview, this.operation = 'cancel'});
  final String operation;
  final Future<Map<String, dynamic>>? preview;
  final calls = <Map<String, dynamic>>[];
  var failures = 0;
  @override
  Future<Map<String, dynamic>> call(Map<String, dynamic> body) async {
    calls.add(Map.of(body));
    switch (body['action']) {
      case 'resolve':
        return {
          'code': 200,
          'orderId': 1,
          'operation': operation,
          'payload': operation == 'move'
              ? {'targetFormId': 2}
              : {'reason': 'Změna plánů'},
        };
      case 'preview':
        return preview ??
            Future.value({
              'code': 200,
              'effect': 'request_cancel',
              'fingerprint': 'fresh',
            });
      case 'challenge':
        return {'code': 202};
      case 'command':
        if (failures++ == 0) throw const CustomerOrderChangeException('failed');
        return {'code': 200};
      default:
        throw StateError('unexpected action');
    }
  }
}
