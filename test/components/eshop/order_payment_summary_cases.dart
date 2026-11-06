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
    bool noticeOnly = false,
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
        locale: const Locale('cs'),
        supportedLocales: const [Locale('cs')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        builder: DependencyMaterialBridge.builder,
        home: Scaffold(
          body: SizedBox(
            width: 340,
            child: noticeOnly
                ? OrderPaymentOverdueNotice(
                    payment: payment,
                    currencyCode: 'CZK',
                    isCard: card,
                  )
                : OrderPaymentSummary(
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

  testWidgets(
    'overdue notice uses server due date and preserves partial balance',
    (tester) async {
      await open(tester, {
        'status': 'partially_paid',
        'overdue': true,
        'dueNow': 100,
        'totalOutstanding': 1900,
        'dueAt': '2027-01-01T12:00:00Z',
        'finalDeadline': '2027-02-01T12:00:00Z',
      }, noticeOnly: true);
      expect(find.text('Po splatnosti'), findsOneWidget);
      expect(find.textContaining('Aktuálně k úhradě: 100'), findsOneWidget);
      expect(find.textContaining('Zbývá k úhradě: 1900'), findsOneWidget);
      expect(find.textContaining('2027'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final payment in [
    {
      'status': 'unpaid',
      'overdue': false,
      'dueNow': 100,
      'dueAt': '2000-01-01T12:00:00Z',
    },
    {'status': 'cancelled', 'overdue': true, 'dueNow': 100},
    {'status': 'unknown', 'dueNow': null},
  ]) {
    testWidgets(
      'overdue notice never infers debt or overrides cancellation: $payment',
      (tester) async {
        await open(tester, payment, noticeOnly: true);
        expect(find.text('Po splatnosti'), findsNothing);
        expect(find.byIcon(Icons.schedule_outlined), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'ordinary unpaid summary keeps its final deadline without a deposit',
    (tester) async {
      await open(tester, {
        'status': 'unpaid',
        'received': 0,
        'returned': 0,
        'totalOutstanding': 2800,
        'dueNow': 2800,
        'finalDeadline': '2027-02-01T12:00:00Z',
      });
      expect(find.textContaining('2027'), findsOneWidget);
      expect(find.text('Po splatnosti'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

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
