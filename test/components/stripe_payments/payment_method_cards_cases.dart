import 'package:fstapp/widgets/dependency_material_bridge.dart';

import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/payments/payment_method_cards.dart';

import '../../support/fixtures/widget_environment_fixture.dart';

void main() {
  WidgetEnvironmentFixture.register();
  late Map<String, dynamic> catalog;
  setUpAll(() {
    catalog = jsonDecode(
      File('assets/translations/cs.json').readAsStringSync(),
    );
  });

  Future<void> mount(
    WidgetTester tester, {
    bool canSelectOnline = true,
    bool showOnline = true,
    bool onlineFirst = false,
    double width = 720,
    double textScale = 1,
    Brightness brightness = Brightness.light,
    ValueChanged<FormPaymentMethod>? onChanged,
  }) async {
    var selected = FormPaymentMethod.bank;
    await WidgetEnvironmentFixture(
      locale: const Locale('cs'),
      translations: catalog,
    ).pumpWidget(
      tester,
      MaterialApp(
        builder: DependencyMaterialBridge.builder,
        theme: ThemeData(brightness: brightness),
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: width,
              child: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
                child: StatefulBuilder(
                  builder: (context, setState) => PaymentMethodCards(
                    value: selected,
                    showOnline: showOnline,
                    onlineFirst: onlineFirst,
                    canSelectOnline: canSelectOnline,
                    onChanged: (value) {
                      setState(() => selected = value);
                      onChanged?.call(value);
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder card(FormPaymentMethod method) =>
      find.byKey(ValueKey('payment-method-${method.name}'));

  testWidgets(
    'bank and cash fill an aligned row, then stack on narrow screens',
    (tester) async {
      await mount(tester, showOnline: false);
      final bank = tester.getRect(card(FormPaymentMethod.bank));
      final cash = tester.getRect(card(FormPaymentMethod.cash));
      expect(bank.top, cash.top);
      expect(bank.bottom, cash.bottom);
      expect(bank.width, cash.width);
      expect(cash.right - bank.left, 720);
      expect(tester.takeException(), isNull);

      await mount(tester, showOnline: false, width: 320, textScale: 2);
      expect(
        tester.getTopLeft(card(FormPaymentMethod.cash)).dy,
        greaterThan(tester.getBottomLeft(card(FormPaymentMethod.bank)).dy),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('four methods switch from stacked to aligned pairs at 600', (
    tester,
  ) async {
    for (final onlineFirst in [false, true]) {
      final order = onlineFirst
          ? [
              FormPaymentMethod.online,
              FormPaymentMethod.bank,
              FormPaymentMethod.both,
              FormPaymentMethod.cash,
            ]
          : FormPaymentMethod.values;
      for (final width in [599.0, 600.0]) {
        await mount(tester, width: width, onlineFirst: onlineFirst);
        final cards = [
          for (final method in order) tester.getRect(card(method)),
        ];
        if (width < 600) {
          for (var index = 0; index < cards.length; index++) {
            expect(cards[index].width, width);
            if (index > 0) {
              expect(cards[index].top, greaterThan(cards[index - 1].bottom));
            }
          }
        } else {
          for (final start in [0, 2]) {
            expect(cards[start].top, cards[start + 1].top);
            expect(cards[start].bottom, cards[start + 1].bottom);
            expect(cards[start].width, cards[start + 1].width);
            expect(cards[start + 1].left, greaterThan(cards[start].right));
            expect(cards[start + 1].right - cards[start].left, width);
          }
          expect(cards[2].top, greaterThan(cards[0].bottom));
          expect(cards[2].left, cards[0].left);
        }
        expect(tester.takeException(), isNull);
      }
    }

    await mount(tester, width: 720, textScale: 1.5);
    final cards = [
      for (final method in FormPaymentMethod.values)
        tester.getRect(card(method)),
    ];
    for (var index = 1; index < cards.length; index++) {
      expect(cards[index].top, greaterThan(cards[index - 1].bottom));
      expect(cards[index].width, 720);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('selects exactly one policy with pointer and keyboard', (
    tester,
  ) async {
    FormPaymentMethod? chosen;
    await mount(tester, onChanged: (value) => chosen = value);
    await tester.tap(card(FormPaymentMethod.both));
    await tester.pump();
    expect(chosen, FormPaymentMethod.both);
    expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);

    // InkWell keeps the cards in the platform focus traversal and action system.
    final context = tester.element(
      find.text(catalog['PaymentMethods']['onlyStripe']),
    );
    Focus.of(context).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(chosen, FormPaymentMethod.online);
    expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
  });

  testWidgets('unavailable Stripe cannot be selected; bank stays operable', (
    tester,
  ) async {
    FormPaymentMethod? chosen;
    await mount(
      tester,
      canSelectOnline: false,
      onChanged: (value) => chosen = value,
    );
    await tester.tap(card(FormPaymentMethod.online));
    await tester.tap(card(FormPaymentMethod.both));
    expect(chosen, isNull);
    await tester.tap(card(FormPaymentMethod.bank));
    expect(chosen, FormPaymentMethod.bank);
  });

  testWidgets(
    'narrow dark layout accommodates enlarged labels without overflow',
    (tester) async {
      await mount(
        tester,
        width: 320,
        textScale: 2,
        brightness: Brightness.dark,
      );
      expect(
        tester.getTopLeft(card(FormPaymentMethod.online)).dy,
        greaterThan(tester.getBottomLeft(card(FormPaymentMethod.bank)).dy),
      );
      expect(tester.takeException(), isNull);
      final semantics = tester.ensureSemantics();
      expect(
        find.bySemanticsLabel(RegExp(catalog['PaymentMethods']['onlyBank'])),
        findsOneWidget,
      );
      semantics.dispose();
    },
  );
}
