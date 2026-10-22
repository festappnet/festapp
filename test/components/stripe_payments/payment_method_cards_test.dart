import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/stripe_payments/payment_method_cards.dart';

import '../../support/fixtures/widget_environment_fixture.dart';

void main() {
  WidgetEnvironmentFixture.register();
  late Map<String, dynamic> catalog;
  setUpAll(() {
    catalog =
        jsonDecode(File('assets/translations/cs.json').readAsStringSync());
  });

  Future<void> mount(
    WidgetTester tester, {
    bool canSelectStripe = true,
    double width = 720,
    double textScale = 1,
    Brightness brightness = Brightness.light,
    ValueChanged<FormPaymentMethod>? onChanged,
  }) async {
    var selected = FormPaymentMethod.bank;
    await WidgetEnvironmentFixture(
            locale: const Locale('cs'), translations: catalog)
        .pumpWidget(
            tester,
            MaterialApp(
              theme: ThemeData(brightness: brightness),
              home: Scaffold(
                  body: SingleChildScrollView(
                      child: SizedBox(
                width: width,
                child: MediaQuery(
                  data:
                      MediaQueryData(textScaler: TextScaler.linear(textScale)),
                  child: StatefulBuilder(
                      builder: (context, setState) => PaymentMethodCards(
                            value: selected,
                            canSelectStripe: canSelectStripe,
                            onChanged: (value) {
                              setState(() => selected = value);
                              onChanged?.call(value);
                            },
                          )),
                ),
              ))),
            ));
    await tester.pumpAndSettle();
  }

  Finder card(FormPaymentMethod method) =>
      find.byKey(ValueKey('payment-method-${method.name}'));

  testWidgets('selects exactly one policy with pointer and keyboard',
      (tester) async {
    FormPaymentMethod? chosen;
    await mount(tester, onChanged: (value) => chosen = value);
    await tester.tap(card(FormPaymentMethod.both));
    await tester.pump();
    expect(chosen, FormPaymentMethod.both);
    expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);

    // InkWell keeps the cards in the platform focus traversal and action system.
    final context =
        tester.element(find.text(catalog['PaymentMethods']['onlyStripe']));
    Focus.of(context).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(chosen, FormPaymentMethod.stripe);
    expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
  });

  testWidgets('unavailable Stripe cannot be selected; bank stays operable',
      (tester) async {
    FormPaymentMethod? chosen;
    await mount(tester,
        canSelectStripe: false, onChanged: (value) => chosen = value);
    await tester.tap(card(FormPaymentMethod.stripe));
    await tester.tap(card(FormPaymentMethod.both));
    expect(chosen, isNull);
    await tester.tap(card(FormPaymentMethod.bank));
    expect(chosen, FormPaymentMethod.bank);
  });

  testWidgets(
      'narrow dark layout accommodates enlarged labels without overflow',
      (tester) async {
    await mount(tester, width: 320, textScale: 2, brightness: Brightness.dark);
    expect(tester.getTopLeft(card(FormPaymentMethod.stripe)).dy,
        greaterThan(tester.getBottomLeft(card(FormPaymentMethod.bank)).dy));
    expect(tester.takeException(), isNull);
    final semantics = tester.ensureSemantics();
    expect(find.bySemanticsLabel(RegExp(catalog['PaymentMethods']['onlyBank'])),
        findsOneWidget);
    semantics.dispose();
  });
}
