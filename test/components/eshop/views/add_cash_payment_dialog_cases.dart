import 'package:fstapp/components/_shared/copy_button.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:fstapp/components/eshop/models/payment_refund_recipient.dart';
import 'package:fstapp/components/eshop/models/transaction_model.dart';
import 'package:fstapp/components/eshop/db_orders.dart';

import 'dart:async';

import 'package:fstapp/components/eshop/payment_operation_strings.dart';
import 'package:fstapp/components/eshop/models/payment_operation_context.dart';
import 'package:fstapp/components/eshop/views/order_payment_bank_options.dart';
import 'package:fstapp/components/eshop/models/order_payment_actions.dart';
import 'package:fstapp/components/forms/payment_method_strings.dart';
import 'package:fstapp/widgets/dependency_material_bridge.dart';
import 'package:fstapp/widgets/app_dialog.dart';

import '../../../support/fixtures/localization_log_fixture.dart';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/eshop/views/payment_operation_dialog.dart';
import 'package:fstapp/components/_shared/common_strings.dart';

void main() {
  // This suite intentionally uses untranslated key fallback (no catalog).
  setUp(() {
    final logs = LocalizationLogFixture.install(expectedMissingCatalog: true);
    addTearDown(logs.dispose);
  });
  testWidgets('PaymentOperationDialog renders and validates input', (
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
          body: PaymentOperationDialog(
            orderId: 5,
            context: const PaymentOperationContext(
              methods: [
                PaymentOperationMethod(
                  id: 'cash',
                  displayName: 'Hotově',
                  record: true,
                  verification: 'local_commit',
                ),
              ],
            ),
            currency: 'CZK',
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
            showBankSetup: true,
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
          ),
          setup: false,
          pair: false,
          history: false,
        ),
        (
          name: 'cash with bank history',
          actions: const OrderPaymentActions(bankState: 'configured'),
          setup: false,
          pair: false,
          history: false,
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
            body: PaymentOperationDialog(
              orderId: 5,
              context: const PaymentOperationContext(
                methods: [
                  PaymentOperationMethod(
                    id: 'cash',
                    displayName: 'Hotově',
                    record: true,
                    verification: 'local_commit',
                  ),
                ],
              ),
              currency: 'CZK',
              bankOptions: OrderPaymentBankOptions(
                actions: const OrderPaymentActions(
                  bankState: 'absent',
                  canConfigureBank: true,
                  showBankSetup: true,
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
  const cashContext = PaymentOperationContext(
    available: '1000.00',
    currency: 'EUR',
    methods: [
      PaymentOperationMethod(
        id: 'cash',
        displayName: 'Cash',
        record: true,
        refund: true,
        verification: 'local_commit',
      ),
    ],
  );
  Future<void> operation(
    WidgetTester tester, {
    bool refund = false,
    List<PaymentRefundRecipient> recipients = const [],
    String currency = 'EUR',
    PaymentOperationContext context = cashContext,
    PaymentOperationSubmit? submit,
    PaymentOperationSubmit? preview,
    PaymentOperationSubmit? instructions,
    Map<String, dynamic>? pending,
  }) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: DependencyMaterialBridge.builder,
        home: Scaffold(
          body: PaymentOperationDialog(
            orderId: 9,
            currency: currency,
            context: context,
            refund: refund,
            refundRecipients: recipients,
            onSubmit: submit,
            onBankInstructions: instructions,
            initialPendingPayload: pending,
            onPreview:
                preview ??
                (_) async => {
                  'netAfter': '699.50',
                  'availableAfter': '699.50',
                  'paidThreshold': '1000.00',
                  'eligibleAfter': false,
                  'lifecyclePreserved': false,
                  'currency': 'EUR',
                },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  TransactionModel incoming({
    String account = '19-2000145399/0800',
    String currency = 'CZK',
    String source = 'banksync_api',
    double amount = 1000,
    bool voided = false,
    String name = 'Eva Nováková',
  }) => TransactionModel(
    counterAccount: account,
    currency: currency,
    ingestSource: source,
    amount: amount,
    voided: voided,
    counterAccountName: name,
  );

  test('refund recipients use incoming bank facts and deduplicate IBANs', () {
    final recipients = PaymentRefundRecipient.fromTransactions([
      incoming(),
      incoming(account: 'CZ6508000000192000145399'),
      incoming(source: 'manual', account: 'DE89370400440532013000'),
      incoming(amount: -100, account: 'DE89370400440532013000'),
      incoming(voided: true, account: 'DE89370400440532013000'),
      incoming(currency: 'USD', account: 'DE89370400440532013000'),
      incoming(account: 'invalid'),
    ], 'CZK');
    expect(recipients, hasLength(1));
    expect(recipients.single.iban, 'CZ6508000000192000145399');
    expect(recipients.single.name, 'Eva Nováková');
    expect(
      PaymentRefundRecipient.fromTransactions([
        incoming(account: '2000145399', name: ''),
      ], 'CZK'),
      isEmpty,
    );
  });

  testWidgets(
    'refund prefills amount and incoming recipient and tracks account edits',
    (tester) async {
      final recipients = PaymentRefundRecipient.fromTransactions([
        incoming(),
      ], 'CZK');
      await operation(
        tester,
        refund: true,
        currency: 'CZK',
        recipients: recipients,
        context: const PaymentOperationContext(
          available: '750.50',
          methods: [
            PaymentOperationMethod(
              id: 'bank',
              displayName: 'Bank',
              refund: true,
              verification: 'bank_event',
              instructions: true,
            ),
          ],
        ),
      );
      final amount = find.byKey(const ValueKey('paymentAmount'));
      final name = find.widgetWithText(
        TextFormField,
        PaymentOperationStrings.text('recipientName'),
      );
      final iban = find.widgetWithText(
        TextFormField,
        PaymentOperationStrings.text('recipientIban'),
      );
      expect(tester.widget<TextFormField>(amount).controller!.text, '750.50');
      expect(
        tester.widget<TextFormField>(name).controller!.text,
        'Eva Nováková',
      );
      expect(
        tester.widget<TextFormField>(iban).controller!.text,
        recipients.single.iban,
      );
      expect(
        find.text(PaymentOperationStrings.text('incomingAccountHint')),
        findsOneWidget,
      );
      await tester.enterText(iban, 'DE89370400440532013000');
      await tester.pump();
      expect(
        find.text(PaymentOperationStrings.text('incomingAccountHint')),
        findsNothing,
      );
      expect(
        find.text(PaymentOperationStrings.text('manualAccountHint')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'refund with multiple incoming accounts requires recipient choice',
    (tester) async {
      final recipients = PaymentRefundRecipient.fromTransactions([
        incoming(),
        incoming(account: 'DE89370400440532013000', name: 'Marta'),
      ], 'CZK');
      await operation(
        tester,
        refund: true,
        recipients: recipients,
        context: const PaymentOperationContext(
          available: '1000',
          methods: [
            PaymentOperationMethod(
              id: 'bank',
              displayName: 'Bank',
              refund: true,
              verification: 'bank_event',
              instructions: true,
            ),
          ],
        ),
      );
      final iban = find.widgetWithText(
        TextFormField,
        PaymentOperationStrings.text('recipientIban'),
      );
      expect(tester.widget<TextFormField>(iban).controller!.text, isEmpty);
      final dropdown = tester.widget<DropdownButtonFormField<String>>(
        find.byKey(const ValueKey('refundRecipientAccount')),
      );
      dropdown.onChanged!('DE89370400440532013000');
      await tester.pump();
      expect(
        tester.widget<TextFormField>(iban).controller!.text,
        'DE89370400440532013000',
      );
    },
  );

  const bankContext = PaymentOperationContext(
    available: '1000',
    methods: [
      PaymentOperationMethod(
        id: 'bank',
        displayName: 'Bank',
        instructions: true,
        verification: 'bank_event',
      ),
    ],
  );
  testWidgets(
    'CZK QR explains the foreign account restriction before dispatch',
    (tester) async {
      var calls = 0;
      await operation(
        tester,
        refund: true,
        currency: 'CZK',
        context: bankContext,
        recipients: const [
          PaymentRefundRecipient(
            iban: 'SK1211100000001571891008',
            name: 'Jan Novák',
          ),
        ],
        instructions: (_) async {
          calls++;
          return {};
        },
      );
      await tester.tap(find.byType(ElevatedButton));
      await tester.pumpAndSettle();
      expect(
        find.text(PaymentOperationStrings.text('qrDomesticAccountRequired')),
        findsOneWidget,
      );
      expect(
        find.text(PaymentOperationStrings.text('bankQrFailed')),
        findsNothing,
      );
      expect(calls, 0);
    },
  );

  testWidgets(
    'QR failure displays a known server reason and hides unknown details',
    (tester) async {
      String? errorCode = 'REFUND_AVAILABLE_EXCEEDED';
      await operation(
        tester,
        refund: true,
        context: bankContext,
        recipients: const [
          PaymentRefundRecipient(
            iban: 'DE89370400440532013000',
            name: 'Jan Novák',
          ),
        ],
        instructions: (_) async {
          if (errorCode != null) throw PaymentInstructionsException(errorCode!);
          throw StateError('private upstream detail');
        },
      );
      await tester.tap(find.byType(ElevatedButton));
      await tester.pumpAndSettle();
      expect(
        find.text(PaymentOperationStrings.text('exceedsAvailable')),
        findsOneWidget,
      );
      errorCode = null;
      await tester.tap(find.byType(ElevatedButton));
      await tester.pumpAndSettle();
      expect(
        find.text(PaymentOperationStrings.text('bankQrFailed')),
        findsOneWidget,
      );
      expect(find.textContaining('private upstream detail'), findsNothing);
    },
  );

  testWidgets(
    'refund exposes bank QR before submitting and preserves cash choice',
    (tester) async {
      Map<String, dynamic>? submitted;
      var writes = 0;
      await operation(
        tester,
        refund: true,
        context: PaymentOperationContext(
          available: '1000.00',
          currency: 'EUR',
          methods: [
            ...cashContext.methods,
            const PaymentOperationMethod(
              id: 'bank',
              displayName: 'Bank',
              instructions: true,
              verification: 'bank_event',
            ),
          ],
        ),
        submit: (_) async {
          writes++;
          return {};
        },
        instructions: (input) async {
          submitted = input;
          return {
            'method': 'bank',
            'verification': 'bank_event',
            'purpose': 'bank_refund_instruction',
            'allowed': true,
            'sourceMethod': 'bank',
            'sourceOrderId': 9,
            'sourcePaymentId': 55,
            'payload': 'BCD\n002\n1\nSCT',
            'amount': '50.00',
            'recipientName': 'Jana Novakova',
            'recipientIban': 'CZ6508000000192000145399',
            'reference': '6817',
          };
        },
      );
      expect(find.byKey(const ValueKey('refundMethod_cash')), findsOneWidget);
      expect(find.byKey(const ValueKey('refundMethod_bank')), findsOneWidget);
      expect(find.byIcon(Icons.qr_code_2), findsOneWidget);
      expect(submitted, isNull);
      await tester.tap(find.byKey(const ValueKey('refundMethod_bank')));
      await tester.pumpAndSettle();
      expect(submitted, isNull);
      await tester.enterText(find.byKey(const ValueKey('paymentAmount')), '50');
      await tester.enterText(
        find.widgetWithText(
          TextFormField,
          PaymentOperationStrings.text('recipientName'),
        ),
        'Jana Novakova',
      );
      await tester.enterText(
        find.widgetWithText(
          TextFormField,
          PaymentOperationStrings.text('recipientIban'),
        ),
        'CZ6508000000192000145399',
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      final generate = find.widgetWithText(
        ElevatedButton,
        PaymentOperationStrings.text('prepareBank'),
      );
      await tester.ensureVisible(generate);
      await tester.tap(generate);
      await tester.pumpAndSettle();
      expect(writes, 0);
      expect(submitted?.containsKey('clientIntentId'), false);
      expect(submitted?.containsKey('operation'), false);
      expect(submitted?['amount'], '50');
      expect(
        find.text(PaymentOperationStrings.text('bankQrReady')),
        findsOneWidget,
      );
      for (final copy in tester.widgetList<CopyButton>(
        find.byType(CopyButton),
      )) {
        final value = find.text(copy.value);
        final button = find.byWidget(copy);
        expect(
          tester.getCenter(button).dy,
          closeTo(tester.getCenter(value).dy, 0.1),
        );
      }
    },
  );

  testWidgets(
    'legacy bank write capability cannot enable a new QR without its codec',
    (tester) async {
      const context = PaymentOperationContext(
        currency: 'USD',
        methods: [
          PaymentOperationMethod(
            id: 'bank',
            displayName: 'Bank',
            refund: true,
            verification: 'bank_event',
          ),
        ],
      );
      expect(context.canRefund, isFalse);
      await operation(tester, refund: true, currency: 'USD', context: context);
      expect(find.byKey(const ValueKey('refundMethod_bank')), findsNothing);
    },
  );

  testWidgets(
    'cash-only server capabilities never synthesize a bank refund choice',
    (tester) async {
      await operation(tester, refund: true);
      expect(find.byKey(const ValueKey('refundMethod_bank')), findsNothing);
      expect(find.byKey(const ValueKey('refundMethod_cash')), findsOneWidget);
    },
  );

  testWidgets('new plus rejects negative and overprecision without dispatch', (
    tester,
  ) async {
    var calls = 0;
    await operation(
      tester,
      submit: (_) async {
        calls++;
        return {'code': 200};
      },
    );
    await tester.enterText(find.byKey(const ValueKey('paymentAmount')), '-300');
    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('paymentAmount')))
          .controller!
          .text,
      '',
    );
    await tester.enterText(find.byKey(const ValueKey('paymentAmount')), '0');
    expect(tester.state<FormState>(find.byType(Form)).validate(), isFalse);
    await tester.enterText(
      find.byKey(const ValueKey('paymentAmount')),
      '12.345',
    );
    expect(tester.state<FormState>(find.byType(Form)).validate(), isFalse);
    expect(calls, 0);
  });
  testWidgets(
    'uncertain cash refund retries identical positive payload with original date',
    (tester) async {
      final payloads = <Map<String, dynamic>>[];
      await operation(
        tester,
        refund: true,
        submit: (payload) async {
          payloads.add(Map.from(payload));
          throw StateError('timeout after commit');
        },
      );
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('paymentAmount')))
            .controller!
            .text,
        '1000.00',
      );
      await tester.enterText(
        find.byKey(const ValueKey('paymentAmount')),
        '300,50',
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(
          ElevatedButton,
          PaymentOperationStrings.text('recordCashRefund'),
        ),
      );
      await tester.pumpAndSettle();
      expect(payloads.single['amount'], '300.50');
      expect(payloads.single['currency'], 'EUR');
      expect(payloads.single['operation'], 'prepare_refund');
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('paymentAmount')))
            .enabled,
        isFalse,
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(
          ElevatedButton,
          PaymentOperationStrings.text('verifySameCommand'),
        ),
      );
      await tester.pumpAndSettle();
      expect(payloads, hasLength(2));
      expect(payloads.first, payloads.last);
    },
  );
  testWidgets('saving fences double submit and dismissal until real receipt', (
    tester,
  ) async {
    final result = Completer<Map<String, dynamic>>();
    var calls = 0;
    await operation(
      tester,
      refund: true,
      submit: (_) {
        calls++;
        return result.future;
      },
    );
    await tester.enterText(find.byKey(const ValueKey('paymentAmount')), '10');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(
        ElevatedButton,
        PaymentOperationStrings.text('recordCashRefund'),
      ),
    );
    await tester.pump();
    expect(calls, 1);
    expect(
      tester.widget<AppAlertDialog>(find.byType(AppAlertDialog)).dismissible,
      isFalse,
    );
    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNull,
    );
    result.completeError(StateError('uncertain'));
    await tester.pumpAndSettle();
  });
  testWidgets(
    'reopened bank request preserves original RF and pending status without dispatch',
    (tester) async {
      var calls = 0;
      await operation(
        tester,
        refund: true,
        context: const PaymentOperationContext(
          available: '700',
          pending: '300',
          currency: 'EUR',
          requests: [
            {
              'id': 'request-1',
              'method': 'bank',
              'verification': 'bank_event',
              'purpose': 'bank_refund_instruction',
              'instructionAllowed': true,
              'sourceMethod': 'bank',
              'sourceOrderId': 9,
              'status': 'pending',
              'canReopen': true,
              'canCancel': true,
              'amount': '300.00',
              'instructions': {
                'method': 'bank',
                'verification': 'bank_event',
                'purpose': 'bank_refund_instruction',
                'allowed': true,
                'sourceMethod': 'bank',
                'sourceOrderId': 9,
                'sourcePaymentId': 55,
                'payload': 'BCD\n002\n1\nSCT',
                'format': 'epc',
                'reference': 'RF18539007547034',
                'sourceAccount': 'CZ6508000000192000145399',
                'recipientIban': 'DE89370400440532013000',
                'recipientName': 'Marta',
              },
            },
          ],
        ),
        submit: (_) async {
          calls++;
          throw StateError('must not dispatch');
        },
      );
      tester.view.physicalSize = const Size(360, 800);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('RF18539007547034'), findsOneWidget);
      expect(
        find.text(PaymentOperationStrings.text('bankPrepared')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('paymentAmount')), findsNothing);
      expect(
        find.widgetWithText(
          ElevatedButton,
          PaymentOperationStrings.text('prepareBank'),
        ),
        findsNothing,
      );
      expect(calls, 0);
    },
  );
  test('missing operation context fails closed; completed cash correction remains reachable', () {
    expect(const PaymentOperationContext().canRecord, isFalse);
    expect(const PaymentOperationContext().canRefund, isFalse);
    expect(
      const PaymentOperationContext(
        requests: [
          {'status': 'succeeded', 'canCorrect': true},
        ],
      ).canRefund,
      isTrue,
    );
  });
  testWidgets(
    'an external descriptor uses the same refund form and pending receipt',
    (tester) async {
      Map<String, dynamic>? submitted;
      await operation(
        tester,
        refund: true,
        context: const PaymentOperationContext(
          available: '25.50',
          currency: 'EUR',
          methods: [
            PaymentOperationMethod(
              id: 'other_gateway',
              displayName: 'Other Gateway',
              refund: true,
              verification: 'verified_provider_observation',
            ),
          ],
        ),
        submit: (payload) async {
          submitted = Map.from(payload);
          return {
            'code': 200,
            'nextAction': 'processing',
            'request': {
              'id': 'remote-1',
              'method': 'other_gateway',
              'status': 'pending',
              'canReopen': true,
              'canCancel': false,
              'amount': '10',
            },
          };
        },
      );
      await tester.enterText(find.byKey(const ValueKey('paymentAmount')), '10');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(
          ElevatedButton,
          '${PaymentOperationStrings.text('refundVia')} Other Gateway',
        ),
      );
      await tester.pumpAndSettle();
      expect(submitted?['method'], 'other_gateway');
      expect(submitted?['operation'], 'prepare_refund');
      expect(
        find.text(PaymentOperationStrings.text('providerPending')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('paymentAmount')), findsNothing);
      tester.view.physicalSize = const Size(360, 800);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'refund submit waits for current server preview and ignores stale amount responses',
    (tester) async {
      final first = Completer<Map<String, dynamic>>(),
          second = Completer<Map<String, dynamic>>();
      final inputs = <Map<String, dynamic>>[];
      await operation(
        tester,
        refund: true,
        preview: (input) {
          inputs.add(Map.from(input));
          return inputs.length == 1 ? first.future : second.future;
        },
      );
      final amount = find.byKey(const ValueKey('paymentAmount'));
      await tester.enterText(amount, '300.00');
      await tester.pump(const Duration(milliseconds: 350));
      expect(
        tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
        isNull,
      );
      await tester.enterText(amount, '250.50');
      await tester.pump(const Duration(milliseconds: 350));
      first.complete({
        'netAfter': '700.00',
        'availableAfter': '700.00',
        'paidThreshold': '1000.00',
        'eligibleAfter': false,
        'lifecyclePreserved': false,
        'currency': 'EUR',
      });
      await tester.pump();
      expect(find.text(PaymentOperationStrings.text('netAfter')), findsNothing);
      expect(
        tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
        isNull,
      );
      second.complete({
        'netAfter': '749.50',
        'availableAfter': '749.50',
        'paidThreshold': '1000.00',
        'eligibleAfter': false,
        'lifecyclePreserved': false,
        'currency': 'EUR',
      });
      await tester.pumpAndSettle();
      expect(
        find.text(PaymentOperationStrings.text('netAfter')),
        findsOneWidget,
      );
      expect(
        find.text(PaymentOperationStrings.text('belowThreshold')),
        findsOneWidget,
      );
      expect(inputs.last['amount'], '250.50');
      expect(
        tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
        isNotNull,
      );
    },
  );
  testWidgets(
    'read-only pending refund grants neither minus nor reopen or cancellation',
    (tester) async {
      const readOnly = PaymentOperationContext(
        requests: [
          {
            'id': 'hidden-bank',
            'method': 'bank',
            'status': 'pending',
            'canReopen': false,
            'canCancel': false,
            'instructions': {'reference': 'PRIVATE-REFERENCE'},
          },
        ],
      );
      expect(readOnly.canRefund, isFalse);
      expect(
        const PaymentOperationContext(
          requests: [
            {'method': 'bank', 'status': 'pending'},
          ],
        ).canRefund,
        isFalse,
      );
      await operation(tester, refund: true, context: readOnly);
      expect(find.text('PRIVATE-REFERENCE'), findsNothing);
      expect(
        find.text(PaymentOperationStrings.text('bankPrepared')),
        findsNothing,
      );
      expect(find.byType(CheckboxListTile), findsNothing);
      expect(
        find.text(PaymentOperationStrings.text('cancelPending')),
        findsNothing,
      );
      expect(
        tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
        isNull,
      );
    },
  );
  testWidgets(
    'disabled bank instructions retain truthful cancellation without a QR',
    (tester) async {
      const context = PaymentOperationContext(
        requests: [
          {
            'id': 'disabled-bank',
            'method': 'bank',
            'verification': 'bank_event',
            'status': 'pending',
            'canReopen': false,
            'canCancel': true,
            'amount': '20',
            'instructionAllowed': false,
            'purpose': 'bank_refund_instruction',
            'sourceMethod': 'bank',
            'sourceOrderId': 9,
            'instructions': {
              'payload': 'SHOULD-NOT-RENDER',
              'reference': 'PRIVATE-REFERENCE',
            },
          },
        ],
      );
      expect(context.canViewHistory, isTrue);
      await operation(tester, refund: true, context: context);
      expect(find.text('PRIVATE-REFERENCE'), findsNothing);
      expect(find.byType(QrImageView), findsNothing);
      expect(find.byType(CheckboxListTile), findsOneWidget);
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      expect(
        find.text(PaymentOperationStrings.text('cancelPending')),
        findsOneWidget,
      );
    },
  );

  testWidgets('reopen permission alone never grants bank cancellation', (
    tester,
  ) async {
    const readOnly = PaymentOperationContext(
      requests: [
        {
          'id': 'read-bank',
          'method': 'bank',
          'verification': 'bank_event',
          'purpose': 'bank_refund_instruction',
          'instructionAllowed': true,
          'sourceMethod': 'bank',
          'sourceOrderId': 9,
          'status': 'pending',
          'canReopen': true,
          'canCancel': false,
          'amount': '20',
          'instructions': {'reference': 'ORIGINAL-REFERENCE'},
        },
      ],
    );
    expect(readOnly.canRefund, isTrue);
    await operation(tester, refund: true, context: readOnly);
    expect(find.text('ORIGINAL-REFERENCE'), findsOneWidget);
    expect(find.byType(CheckboxListTile), findsNothing);
    expect(
      find.text(PaymentOperationStrings.text('cancelPending')),
      findsNothing,
    );
  });
  testWidgets(
    'reopened uncertain operation restores original positive amount and date without dispatch',
    (tester) async {
      final original = {
        'operation': 'prepare_refund',
        'orderId': 9,
        'method': 'cash',
        'currency': 'EUR',
        'amount': '30.50',
        'receivedAt': '2026-11-10T09:01:00Z',
        'note': 'Original note',
      };
      final calls = <Map<String, dynamic>>[];
      await operation(
        tester,
        refund: true,
        context: const PaymentOperationContext(
          requests: [
            {
              'id': 'another-request',
              'method': 'bank',
              'status': 'pending',
              'canReopen': true,
              'canCancel': true,
              'instructions': {'reference': 'DO-NOT-SUBSTITUTE'},
            },
          ],
        ),
        pending: original,
        submit: (input) async {
          calls.add(Map.from(input));
          throw StateError('still uncertain');
        },
      );
      expect(calls, isEmpty);
      expect(find.text('DO-NOT-SUBSTITUTE'), findsNothing);
      final amount = tester.widget<TextFormField>(
        find.byKey(const ValueKey('paymentAmount')),
      );
      expect(amount.controller!.text, '30.50');
      expect(amount.enabled, isFalse);
      await tester.tap(
        find.widgetWithText(
          ElevatedButton,
          PaymentOperationStrings.text('verifySameCommand'),
        ),
      );
      await tester.pumpAndSettle();
      expect(calls.single, original);
    },
  );
  testWidgets(
    'proven rollback unlocks draft while uncertainty keeps original payload frozen',
    (tester) async {
      final original = {
        'operation': 'prepare_refund',
        'orderId': 9,
        'method': 'cash',
        'currency': 'EUR',
        'amount': '30.50',
        'receivedAt': '2026-11-10T09:01:00Z',
      };
      await operation(
        tester,
        refund: true,
        pending: original,
        submit: (_) async =>
            throw const PaymentOperationRejected('AMOUNT_REJECTED'),
      );
      await tester.tap(
        find.widgetWithText(
          ElevatedButton,
          PaymentOperationStrings.text('verifySameCommand'),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('paymentAmount')))
            .enabled,
        isTrue,
      );
      expect(
        find.text(PaymentOperationStrings.text('notApplied')),
        findsOneWidget,
      );
      // Finish the read-only preview timer; no payment retry occurs automatically.
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'bank instructions without an available codec never claim a prepared QR',
    (tester) async {
      await operation(
        tester,
        refund: true,
        currency: 'USD',
        context: const PaymentOperationContext(
          currency: 'USD',
          requests: [
            {
              'id': 'manual-usd',
              'method': 'bank',
              'verification': 'bank_event',
              'purpose': 'bank_refund_instruction',
              'instructionAllowed': true,
              'sourceMethod': 'bank',
              'sourceOrderId': 9,
              'status': 'pending',
              'canReopen': true,
              'canCancel': true,
              'amount': '20.00',
              'instructions': {
                'format': null,
                'payload': null,
                'reference': '12345',
                'currency': 'USD',
              },
            },
          ],
        ),
      );
      expect(
        find.text(PaymentOperationStrings.text('bankManualPrepared')),
        findsOneWidget,
      );
      expect(
        find.text(PaymentOperationStrings.text('bankPrepared')),
        findsNothing,
      );
    },
  );
}
