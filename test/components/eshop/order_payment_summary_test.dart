import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/eshop/views/order_payment_summary.dart';
import 'package:fstapp/theme_config.dart';
import 'package:fstapp/widgets/dependency_material_bridge.dart';

import '../../support/fixtures/widget_environment_fixture.dart';

void main() {
  WidgetEnvironmentFixture.register();
  Future<void> open(
    WidgetTester tester,
    Map<String, dynamic> payment, {
    bool card = false,
  }) async {
    final env = WidgetEnvironmentFixture(
      locale: const Locale('cs'),
      translations: jsonDecode(
        File('assets/translations/cs.json').readAsStringSync(),
      ),
    );
    await env.pumpWidget(
      tester,
      MaterialApp(
        builder: DependencyMaterialBridge.builder,
        home: Scaffold(
          body: SizedBox(
            width: 340,
            child: OrderPaymentSummary(
              payment: payment,
              total: 2800,
              currencyCode: 'CZK',
              isCard: card,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('paid summary is one amount row without repeated zero balances', (
    tester,
  ) async {
    await open(tester, {
      'status': 'fully_paid',
      'received': 2800,
      'returned': 0,
      'totalOutstanding': 0,
      'dueNow': 0,
      'overpaid': 0,
    });
    expect(find.text('Platba'), findsOneWidget);
    expect(find.byType(SelectableText), findsOneWidget);
    expect(
      tester.widget<SelectableText>(find.byType(SelectableText)).data,
      contains(' / '),
    );
    for (final label in [
      'Vráceno',
      'Zbývá k úhradě',
      'Aktuálně k úhradě',
      'Přeplatek',
    ]) {
      expect(find.text(label), findsNothing);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'refund keeps its amount and never makes gross paid appear green',
    (tester) async {
      await open(tester, {
        'status': 'fully_paid',
        'received': 2800,
        'returned': 500,
        'totalOutstanding': 0,
        'dueNow': 0,
        'overpaid': 0,
      });
      expect(find.text('Vráceno'), findsOneWidget);
      final amount = tester.widget<SelectableText>(find.byType(SelectableText));
      expect(
        amount.style?.color,
        isNot(
          ThemeConfig.greenColor(
            tester.element(find.byType(OrderPaymentSummary)),
          ),
        ),
      );
      expect(find.text('Aktuálně k úhradě'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('distinct deposit due, balance and overpayment remain explicit', (
    tester,
  ) async {
    await open(tester, {
      'status': 'deposit_paid',
      'received': 900,
      'returned': 0,
      'totalOutstanding': 1900,
      'dueNow': 100,
      'overpaid': 20,
      'depositAmount': 1000,
      'depositDeadline': '2027-01-01T12:00:00Z',
      'finalDeadline': '2027-02-01T12:00:00Z',
    });
    for (final label in ['Zbývá k úhradě', 'Aktuálně k úhradě', 'Přeplatek']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.textContaining('2027'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'cancelled balances do not request payment while receipts remain visible',
    (tester) async {
      await open(tester, {
        'status': 'cancelled',
        'received': 900,
        'returned': 500,
        'totalOutstanding': 1900,
        'dueNow': 100,
        'overpaid': 20,
        'depositAmount': 1000,
        'depositDeadline': '2027-01-01T12:00:00Z',
      });
      expect(find.text('Vráceno'), findsOneWidget);
      expect(find.text('Přeplatek'), findsOneWidget);
      expect(find.text('Zbývá k úhradě'), findsNothing);
      expect(find.text('Aktuálně k úhradě'), findsNothing);
      expect(find.textContaining('2027'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'unknown is not zero; card dispute and no-payment states stay distinct',
    (tester) async {
      await open(tester, {
        'status': 'unknown',
        'received': null,
        'returned': null,
      });
      expect(
        find.textContaining('Platební stav nelze spolehlivě určit'),
        findsOneWidget,
      );
      expect(
        tester.widget<SelectableText>(find.byType(SelectableText)).data,
        isNot(startsWith('0')),
      );
      await open(tester, {
        'status': 'disputed',
        'received': 2800,
        'returned': 0,
      }, card: true);
      expect(find.text('Platnost vstupenek je pozastavena.'), findsWidgets);
      await open(tester, {
        'status': 'not_required_yet',
        'received': 0,
        'returned': 0,
      });
      expect(find.text('Zatím nic neplatíte'), findsOneWidget);
      expect(
        tester.widget<SelectableText>(find.byType(SelectableText)).data,
        isNot(contains(' / ')),
      );
      expect(tester.takeException(), isNull);
    },
  );
}
