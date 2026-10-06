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
import 'package:fstapp/components/forms/widgets_editor/product_type_editor.dart';
import 'package:fstapp/components/forms/widgets_editor/default_value_helper.dart';
import 'package:fstapp/components/forms/widgets_view/form_helper.dart';
import 'package:fstapp/components/forms/models/form_field_model.dart';
import 'package:fstapp/components/forms/models/form_model.dart';
import 'package:fstapp/components/eshop/models/product_type_model.dart';
import 'package:fstapp/components/occasion/occasion_link_model.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';
import 'package:fstapp/data_services/rights_service.dart';

void main() {
  setUpAll(() => Localization.load(const Locale('cs'), translations: Translations(
      jsonDecode(File('assets/translations/cs.json').readAsStringSync()) as Map<String,dynamic>)));
  tearDown(() => RightsService.occasionLinkModelNotifier.value = null);
  void occasion({bool tickets = false, String mode = 'virtual', bool deposit = true}) {
    RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(occasion: OccasionModel(
      isOpen: true, isHidden: false, isPromoted: false,
      features: [TicketFeature(code: 'ticket', isEnabled: tickets),
        DepositFeature(code: 'deposit', isEnabled: deposit, mode: mode)],
    ));
  }
  for (final many in [false, true]) {
    testWidgets('stored default is disabled and simple product stays compact: many=$many', (tester) async {
      occasion(deposit: false);
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final product = ProductModel(id: 10, title: 'Režijní náklady akce', price: 100, currencyCode: 'CZK');
      final field = FormFieldModel(id: 3, productType: ProductTypeModel(title: 'Poplatek', products: [product]),
          data: {FormHelper.metaSelectionType: many ? FormHelper.metaSelectionTypeMany : 'single'});
      DefaultValueHelper.write(field, many ? ['10'] : '10');
      var changes = 0;
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child:
        ProductTypeEditor(form: FormModel(occasionId: 1, relatedFields: [field]), ptField: field, refresh: () => changes++)))));
      final selector = many
          ? find.byWidgetPredicate((w) => w is Checkbox && w.onChanged == null && w.value == true)
          : find.byType(Radio<String>);
      expect(selector, findsOneWidget);
      if (!many) expect(tester.widget<Radio<String>>(selector).onChanged, isNull);
      await tester.tap(selector);
      await tester.pump();
      expect(changes, 0);
      expect(many ? DefaultValueHelper.readList(field).single : DefaultValueHelper.readString(field), '10');
      expect(tester.widget<Container>(find.byKey(ObjectKey(product))).decoration, isNull);
      Finder input(String label) => find.byWidgetPredicate((w) => w is TextField && w.decoration?.labelText == label);
      final name = find.descendant(of: find.byType(TicketProductEditorRow), matching: input('Název'));
      expect(tester.getRect(name).top, tester.getRect(input('Cena')).top);
      expect(tester.takeException(), isNull);
    });
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
          expect(tester.getSize(find.byType(TicketProductEditorRow)).height, lessThan(100));
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
