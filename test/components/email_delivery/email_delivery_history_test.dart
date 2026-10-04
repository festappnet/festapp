import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/email_delivery/email_delivery_history.dart';

void main() {
  testWidgets(
      'history scopes one page request, filters and shows attempt errors without bodies',
      (tester) async {
    final calls = <Map<String, dynamic>>[];
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: EmailDeliveryHistory(
                occasionId: 3,
                orderId: 7,
                read: (name, args) async {
                  calls.add({'name': name, ...args});
                  if (name == 'get_email_delivery_detail')
                    return {
                      'message': {'tracking_policy': 'disabled'},
                      'attempts': [
                        {
                          'state': 'unknown',
                          'at': '2026-10-03',
                          'error': 'transport_ambiguous'
                        }
                      ],
                      'events': []
                    };
                  return [
                    {
                      'id': 1,
                      'message_id': 'fixture',
                      'message_kind': 'order_tickets',
                      'state': 'unknown'
                    }
                  ];
                }))));
    await tester.pumpAndSettle();
    expect(calls.length, 1);
    expect(calls.single['p_order'], 7);
    expect(calls.single['p_occasion'], 3);
    await tester.tap(find.byType(ListTile));
    await tester.pumpAndSettle();
    expect(find.textContaining('transport_ambiguous'), findsOneWidget);
    expect(calls.last['p_message'], 'fixture');
    Navigator.of(tester.element(find.byType(AlertDialog))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButton<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('EmailDelivery.state.bounce').last);
    await tester.pumpAndSettle();
    expect(calls.last['p_state'], 'bounce');
    expect(calls.last.containsKey('p_before'), false);
  });
  testWidgets(
      'organization switch clears occasion scope in both page and overview',
      (tester) async {
    final calls = <Map<String, dynamic>>[];
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: EmailDeliveryHistory(
      embedded: true,
      occasionId: 3,
      organizationId: 2,
      read: (name, args) async {
        calls.add({'name': name, ...args});
        return name == 'get_email_delivery_overview'
            ? <String, dynamic>{}
            : <dynamic>[];
      },
    ))));
    await tester.pumpAndSettle();
    expect(calls.length, 2);
    expect(
        calls.every(
            (call) => call['p_occasion'] == 3 && call['p_organization'] == 2),
        isTrue);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(calls.length, 4);
    expect(
        calls.skip(2).every((call) =>
            call['p_occasion'] == null && call['p_organization'] == 2),
        isTrue);
  });
  testWidgets('order-only history keeps scope and filters read-only',
      (tester) async {
    final calls = <Map<String, dynamic>>[];
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: EmailDeliveryHistory(
      occasionId: 3,
      organizationId: 2,
      embedded: true,
      ordersOnly: true,
      read: (name, args) async {
        calls.add({'name': name, ...args});
        return <dynamic>[];
      },
    ))));
    await tester.pumpAndSettle();
    expect(calls.single['name'], 'get_email_delivery_page');
    expect(calls.single['p_orders_only'], true);
    expect(calls.single['p_occasion'], 3);
    expect(find.byType(SwitchListTile), findsNothing);
    await tester.tap(find.byType(DropdownButton<String>).last);
    await tester.pumpAndSettle();
    expect(find.text('EmailDelivery.kind.registration'), findsNothing);
    expect(find.text('EmailDelivery.kind.sign_in'), findsNothing);
    expect(find.text('EmailDelivery.kind.reset_password'), findsNothing);
    await tester.tap(find.text('EmailDelivery.kind.order_update').last);
    await tester.pumpAndSettle();
    expect(calls.last['p_kind'], 'order_update');
    expect(calls.last['p_orders_only'], true);
    expect(calls.every((call) => call['name'] == 'get_email_delivery_page'),
        isTrue);
  });
}
