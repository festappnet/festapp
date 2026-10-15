import '../../support/fixtures/localization_log_fixture.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:festapp_core/forms.dart';
import 'package:fstapp/components/forms/views/customer_order_overview.dart';

Map<String, dynamic> fixture({String ticketState = 'unused'}) => {
      'code': 200,
      'root': {'id': 1, 'symbol': 'ROOT', 'title': 'Synthetic'},
      'serverTime': '2026-10-15T12:00:00Z',
      'people': [
        {'id': 1, 'label': 'Waiting', 'effectiveLifecycle': 'offered'},
        {'id': 2, 'label': 'Accepted', 'effectiveLifecycle': 'admitted'}
      ],
      'offers': [
        {
          'pendingPlaces': 1,
          'effectiveStatus': 'pending',
          'expiresAt': '2026-10-16'
        }
      ],
      'orders': [
        {
          'symbol': 'CHILD',
          'state': 'paid',
          'total': 1000,
          'currency': 'CZK',
          'items': [],
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
            'reference': '123'
          },
          'tickets': [
            {'id': 2, 'label': 'Accepted', 'displayStatus': ticketState}
          ]
        }
      ]
    };
void main() {
  // This suite intentionally uses untranslated key fallback (no catalog).
  setUp(() {
    final logs = LocalizationLogFixture.install(expectedMissingCatalog: true);
    addTearDown(logs.dispose);
  });
  testWidgets(
      'partial overview keeps separate payment facts and refresh observes usage',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var calls = 0;
    var fail = false;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body:
        SingleChildScrollView(child: CustomerOrderOverviewView(load: () async {
      calls++;
      if (fail) throw StateError('offline');
      return CustomerOrderOverview(
          fixture(ticketState: calls == 1 ? 'unused' : 'used'));
    })))));
    await tester.pumpAndSettle();
    expect(find.text('CHILD'), findsOneWidget);
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
  });
}
