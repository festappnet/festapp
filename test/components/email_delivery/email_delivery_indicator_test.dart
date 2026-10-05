import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/email_delivery/email_delivery_indicator.dart';

void main() {
  const summary = {
    'state': 'bounce',
    'kind': 'order_tickets',
    'attention_count': 1,
    'messages': [
      {'state': 'bounce', 'kind': 'order_tickets'}
    ]
  };
  for (final state in ['open', 'click', 'delivery', 'accepted', 'pending', 'bounce']) {
    testWidgets('double check only marks observed engagement: $state',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: EmailDeliveryIndicator(summary: {'state': state}))));
      expect(find.byIcon(Icons.done_all),
          ['open', 'click'].contains(state) ? findsOneWidget : findsNothing);
      if (['open', 'click'].contains(state)) {
        expect(find.byIcon(Icons.mail_outline), findsOneWidget);
        final envelope = tester.getRect(find.byIcon(Icons.mail_outline));
        final checks = tester.getRect(find.byIcon(Icons.done_all));
        expect(checks.bottom, greaterThan(envelope.bottom));
        expect(checks.right, greaterThanOrEqualTo(envelope.right));
        expect(tester.takeException(), isNull);
      }
    });
  }
  testWidgets(
      'email explanation is directly tappable, accessible and does not activate its row',
      (tester) async {
    var rowTaps = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: GestureDetector(
                onTap: () => rowTaps++,
                child: const EmailDeliveryIndicator(summary: summary)))));
    expect(find.byType(Tooltip), findsOneWidget);
    expect(tester.getSize(find.byType(IconButton)), const Size(48, 48));
    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(rowTaps, 0);
  });
  testWidgets('keyboard focus and Enter show explanation', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: EmailDeliveryIndicator(summary: summary))));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
  });
  testWidgets(
      'narrow screens show a bottom sheet and older bundle stays neutral',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: EmailDeliveryIndicator())));
    expect(find.byIcon(Icons.mail_outline), findsOneWidget);
    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
