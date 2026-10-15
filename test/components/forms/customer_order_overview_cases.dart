import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/forms/models/customer_order_overview.dart';
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
  test('view parser only accepts standalone query links', () {
    final scope = CustomerOrderScope('a' * 64, 1);
    expect(CustomerOrderScope.fromUri(scope.uri)!.orderId, 1);
    expect(
      CustomerOrderScope.fromUri(
        Uri.parse('/form/test?order_id=1&token=${'a' * 64}'),
      ),
      isNull,
    );
    expect(
      CustomerOrderScope.fromUri(
        Uri.parse('/order#order?order_id=1&token=${'a' * 64}'),
      ),
      isNull,
    );
    expect(
      () => CustomerOrderScope.fromUri(Uri.parse('/order?order_id=0&token=x')),
      throwsStateError,
    );
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
