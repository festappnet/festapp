import 'package:fstapp/components/eshop/views/order_payment_bank_options.dart';
import 'package:fstapp/components/eshop/models/order_payment_actions.dart';
import 'package:fstapp/components/forms/payment_method_strings.dart';
import 'package:fstapp/widgets/dependency_material_bridge.dart';

import '../../../support/fixtures/localization_log_fixture.dart';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/eshop/views/add_cash_payment_dialog.dart';
import 'package:fstapp/components/_shared/common_strings.dart';

void main() {
  // This suite intentionally uses untranslated key fallback (no catalog).
  setUp(() {
    final logs = LocalizationLogFixture.install(expectedMissingCatalog: true);
    addTearDown(logs.dispose);
  });
  testWidgets('AddCashPaymentDialog renders and validates input', (
    WidgetTester tester,
  ) async {
    // Determine screen size to avoid overflow
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        builder: DependencyMaterialBridge.builder,
        home: Scaffold(
          body: AddCashPaymentDialog(
            unitId: 100,
            currency: 'CZK',
            variableSymbol: '123456',
            paymentInfoId: 555,
          ),
        ),
      ),
    );

    // Check availability of widgets
    // Note: Strings might be untranslated keys if EasyLocalization not loaded.
    // We search by Type or Key if needed.

    expect(
      find.byType(TextFormField),
      findsOneWidget,
    ); // Amount only (Note is in collapsed ExpansionTile)

    // Open ExpansionTile
    await tester.tap(find.text(CommonStrings.advancedSettings));
    await tester.pumpAndSettle();

    expect(find.byType(TextFormField), findsNWidgets(2)); // Amount + Note

    // Input Amount
    await tester.enterText(find.byType(TextFormField).first, "100");
    await tester.pump();

    // We can't verify DB call without mocking static DbOrders.
    // But we verified the widget pumps and interacts.
  });
  for (final scenario
      in <
        ({
          String name,
          OrderPaymentActions actions,
          bool setup,
          bool pair,
          bool history,
        })
      >[
        (
          name: 'no bank',
          actions: const OrderPaymentActions(
            bankState: 'absent',
            canConfigureBank: true,
          ),
          setup: true,
          pair: false,
          history: false,
        ),
        (
          name: 'no setup rights',
          actions: const OrderPaymentActions(bankState: 'absent'),
          setup: false,
          pair: false,
          history: false,
        ),
        (
          name: 'empty active bank',
          actions: const OrderPaymentActions(
            bankState: 'configured',
            pairingAccountId: 9,
          ),
          setup: false,
          pair: true,
          history: false,
        ),
        (
          name: 'bank permission missing',
          actions: const OrderPaymentActions(bankState: 'restricted'),
          setup: false,
          pair: false,
          history: false,
        ),
        (
          name: 'detached personal history',
          actions: const OrderPaymentActions(
            bankState: 'absent',
            canConfigureBank: true,
            historyAccounts: [PaymentHistoryAccount(9, 'Historický účet')],
          ),
          setup: false,
          pair: false,
          history: true,
        ),
        (
          name: 'cash with bank history',
          actions: const OrderPaymentActions(
            bankState: 'configured',
            historyAccounts: [PaymentHistoryAccount(9, 'Účet')],
          ),
          setup: false,
          pair: false,
          history: true,
        ),
      ]) {
    testWidgets('cash banking options: ${scenario.name}', (tester) async {
      var pairCalls = 0, historyCalls = 0, setupCalls = 0;
      await tester.pumpWidget(
        MaterialApp(
          builder: DependencyMaterialBridge.builder,
          home: Scaffold(
            body: OrderPaymentBankOptions(
              actions: scenario.actions,
              onPair: () => pairCalls++,
              onHistory: (_) => historyCalls++,
              onConfigure: () => setupCalls++,
            ),
          ),
        ),
      );
      expect(
        find.text(PaymentMethodStrings.text('configureBank')),
        scenario.setup ? findsOneWidget : findsNothing,
      );
      expect(
        find.byIcon(Icons.account_balance),
        scenario.pair ? findsOneWidget : findsNothing,
      );
      expect(
        find.byIcon(Icons.history),
        scenario.history ? findsOneWidget : findsNothing,
      );
      if (scenario.setup)
        await tester.tap(find.text(PaymentMethodStrings.text('configureBank')));
      if (scenario.pair) await tester.tap(find.byIcon(Icons.account_balance));
      if (scenario.history) await tester.tap(find.byIcon(Icons.history));
      expect(pairCalls, scenario.pair ? 1 : 0);
      expect(historyCalls, scenario.history ? 1 : 0);
      expect(setupCalls, scenario.setup ? 1 : 0);
    });
  }

  testWidgets('return from bank settings retains decimal cash draft and note', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: DependencyMaterialBridge.builder,
        home: Builder(
          builder: (context) => Scaffold(
            body: AddCashPaymentDialog(
              unitId: 1,
              currency: 'CZK',
              variableSymbol: '',
              paymentInfoId: 2,
              bankOptions: OrderPaymentBankOptions(
                actions: const OrderPaymentActions(
                  bankState: 'absent',
                  canConfigureBank: true,
                ),
                onConfigure: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (context) => Scaffold(
                      body: TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Back from settings'),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextFormField).first, '250,50');
    await tester.tap(find.text(CommonStrings.advancedSettings));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).last,
      'Převzato u vstupu',
    );
    await tester.tap(find.byType(InputDecorator).at(1));
    await tester.pumpAndSettle();
    final chosenDay = DateTime.now().day == 10 ? 11 : 10;
    await tester.tap(find.text('$chosenDay').last);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    final dateBefore =
        (tester.widget<InputDecorator>(find.byType(InputDecorator).at(1)).child
                as Text)
            .data;
    await tester.ensureVisible(
      find.text(PaymentMethodStrings.text('configureBank')),
    );
    await tester.tap(find.text(PaymentMethodStrings.text('configureBank')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Back from settings'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextFormField>(find.byType(TextFormField).first)
          .controller!
          .text,
      '250,50',
    );
    expect(
      tester
          .widget<TextFormField>(find.byType(TextFormField).last)
          .controller!
          .text,
      'Převzato u vstupu',
    );
    expect(
      (tester.widget<InputDecorator>(find.byType(InputDecorator).at(1)).child
              as Text)
          .data,
      dateBefore,
    );
    final form = tester.state<FormState>(find.byType(Form));
    expect(form.validate(), isTrue);
    await tester.enterText(find.byType(TextFormField).first, '250,501');
    expect(form.validate(), isFalse);
  });
}
