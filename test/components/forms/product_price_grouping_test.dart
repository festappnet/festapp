import 'dart:convert';
import 'dart:io';
import 'package:easy_localization/src/localization.dart';
import 'package:easy_localization/src/translations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/eshop/models/product_model.dart';
import 'package:fstapp/components/eshop/orders_strings.dart';
import 'package:fstapp/components/features/deposit_feature.dart';
import 'package:fstapp/components/features/ticket_feature.dart';
import 'package:fstapp/components/forms/widgets_editor/ticket_product_editor_row.dart';
import 'package:fstapp/components/occasion/occasion_link_model.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';
import 'package:fstapp/data_services/rights_service.dart';

void main() {
  setUpAll(() => Localization.load(const Locale('cs'), translations: Translations(
      jsonDecode(File('assets/translations/cs.json').readAsStringSync()) as Map<String,dynamic>)));
  tearDown(() => RightsService.occasionLinkModelNotifier.value = null);
  void occasion({bool tickets = false, String mode = 'virtual'}) {
    RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(occasion: OccasionModel(
      isOpen: true, isHidden: false, isPromoted: false,
      features: [TicketFeature(code: 'ticket', isEnabled: tickets),
        DepositFeature(code: 'deposit', isEnabled: true, mode: mode)],
    ));
  }
  test('valid filter follows ticket/application terminology', () {
    occasion();
    expect(OrdersStrings.validTickets, 'Platné přihlášky');
    occasion(tickets: true);
    expect(OrdersStrings.validTickets, 'Platné vstupenky');
  });
  for (final width in [240.0, 760.0]) {
    for (final brightness in Brightness.values) {
      testWidgets('price and surcharge stay grouped and editable at $width/$brightness', (tester) async {
        occasion();
        final product = ProductModel(title: 'Bez slevy', price: 4500, currencyCode: 'CZK')
          ..metaSurchargeAmount = 150
          ..metaSurchargeCurrency = 'EUR';
        await tester.pumpWidget(MaterialApp(theme: ThemeData(brightness: brightness),
          home: Scaffold(body: SingleChildScrollView(child: SizedBox(width: width,
            child: TicketProductEditorRow(product: product, onDelete: () {}, availableCurrencies: ['CZK','EUR']))))));
        Finder field(String label) => find.byWidgetPredicate((w) => w is TextField && w.decoration?.labelText == label);
        final price = field('Cena');
        final surcharge = field('Doplatek');
        expect(price, findsOneWidget);
        expect(surcharge, findsOneWidget);
        if (width > 480) {
          expect(tester.getRect(price).top, tester.getRect(surcharge).top);
          expect(tester.getRect(price).right, lessThan(tester.getRect(surcharge).left));
        } else {
          expect(tester.getRect(surcharge).top, greaterThan(tester.getRect(price).bottom));
        }
        await tester.enterText(surcharge, '-50');
        expect(product.metaSurchargeAmount, -50);
        expect(product.price, 4500);
        expect(product.currencyCode, 'CZK');
        expect(product.metaSurchargeCurrency, 'EUR');
        expect(tester.takeException(), isNull);
      });
    }
  }
}
