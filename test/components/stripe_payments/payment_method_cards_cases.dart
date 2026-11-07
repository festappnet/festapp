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
    'bank is the full-width primary choice and cash is a secondary radio row',
    (tester) async {
      await mount(tester, showOnline: false);
      final bank = tester.getRect(card(FormPaymentMethod.bank));
      final cash = tester.getRect(card(FormPaymentMethod.cash));
      expect(bank.width, 720);
      expect(cash.width, 720);
      expect(cash.top, greaterThan(bank.bottom));
      expect(cash.height, lessThan(bank.height));
      expect(
        tester.widget(card(FormPaymentMethod.cash)),
        isA<RadioListTile<FormPaymentMethod>>(),
      );
      expect(tester.takeException(), isNull);

      await mount(tester, showOnline: false, width: 320, textScale: 2);
      expect(
        tester.getTopLeft(card(FormPaymentMethod.cash)).dy,
        greaterThan(tester.getBottomLeft(card(FormPaymentMethod.bank)).dy),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('online choices retain aligned pairs and stack with large text', (
    tester,
  ) async {
    for (final onlineFirst in [false, true]) {
      final order = onlineFirst
          ? [
              FormPaymentMethod.online,
              FormPaymentMethod.bank,
              FormPaymentMethod.both,
            ]
          : [
              FormPaymentMethod.bank,
              FormPaymentMethod.online,
              FormPaymentMethod.both,
            ];
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
          expect(cards[0].top, cards[1].top);
          expect(cards[0].bottom, cards[1].bottom);
          expect(cards[0].width, cards[1].width);
          expect(cards[1].left, greaterThan(cards[0].right));
          expect(cards[1].right - cards[0].left, width);
          expect(cards[2].top, greaterThan(cards[0].bottom));
          expect(cards[2].width, width);
        }
        expect(
          tester.getTopLeft(card(FormPaymentMethod.cash)).dy,
          greaterThan(cards.last.bottom),
        );
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

  testWidgets('cash row is keyboard accessible and bank remains selectable', (
    tester,
  ) async {
    FormPaymentMethod? chosen;
    await mount(
      tester,
      showOnline: false,
      onChanged: (value) => chosen = value,
    );
    await tester.tap(card(FormPaymentMethod.cash));
    await tester.pump();
    expect(chosen, FormPaymentMethod.cash);
    expect(
      tester
          .widget<RadioGroup<FormPaymentMethod>>(
            find.byType(RadioGroup<FormPaymentMethod>),
          )
          .groupValue,
      FormPaymentMethod.cash,
    );
    await tester.tap(card(FormPaymentMethod.bank));
    await tester.pump();
    expect(chosen, FormPaymentMethod.bank);
    Focus.of(tester.element(find.text(catalog['PaymentMethods']['cash'])))
        .requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(chosen, FormPaymentMethod.cash);
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
