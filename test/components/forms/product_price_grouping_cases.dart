import 'package:fstapp/widgets/dependency_material_bridge.dart';
import 'package:fstapp/components/eshop/order_item_strings.dart';
import '../../support/fixtures/widget_environment_fixture.dart';
import 'package:festapp_core/forms.dart';
import 'dart:convert';
import 'dart:io';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:festapp_core/eshop.dart';
import 'package:fstapp/components/features/deposit_feature.dart';
import 'package:fstapp/components/features/ticket_feature.dart';
import 'package:fstapp/components/forms/widgets_editor/ticket_product_editor_row.dart';
import 'package:fstapp/components/forms/widgets_editor/product_type_editor.dart';
import 'package:fstapp/components/forms/models/form_field_draft.dart';
import 'package:fstapp/components/forms/models/form_editor_draft.dart';
import 'package:fstapp/components/occasion/occasion_link_model.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';
import 'package:fstapp/data_services/rights_service.dart';

late WidgetEnvironmentFixture _environment;

void main() {
  WidgetEnvironmentFixture.register();
  setUpAll(() => _environment = WidgetEnvironmentFixture(
      locale: const Locale('cs'),
      translations:
          jsonDecode(File('assets/translations/cs.json').readAsStringSync())
              as Map<String, dynamic>));
  tearDown(() => RightsService.occasionLinkModelNotifier.value = null);
  void occasion(
      {bool tickets = false, String mode = 'virtual', bool deposit = true}) {
    RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
        occasion: OccasionModel(
      isOpen: true,
      isHidden: false,
      isPromoted: false,
      features: [
        TicketFeature(code: 'ticket', isEnabled: tickets),
        DepositFeature(code: 'deposit', isEnabled: deposit, mode: mode)
      ],
    ));
  }

  for (final many in [false, true]) {
    testWidgetsWithEnvironment(() => _environment,
        'product default can be selected and cleared while product stays compact: many=$many',
        (tester) async {
      occasion(deposit: false);
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final product = ProductModel(
          id: 10,
          title: 'Režijní náklady akce',
          price: 100,
          currencyCode: 'CZK');
      final field = FormFieldDraft(
          id: 3,
          productType: ProductTypeModel(title: 'Poplatek', products: [product]),
          data: {
            FormMetadata.metaSelectionType:
                many ? FormMetadata.metaSelectionTypeMany : 'single'
          });
      var changes = 0;
      await _environment.pumpWidget(
          tester,
          MaterialApp(builder: DependencyMaterialBridge.builder,
              home: Scaffold(
                  body: SingleChildScrollView(
                      child: ProductTypeEditor(
                          form: FormEditorDraft(
                              occasionId: 1, relatedFields: [field]),
                          ptField: field,
                          refresh: () => changes++)))));
      final selector = many
          ? find.descendant(
              of: find
                  .ancestor(
                      of: find.byType(TicketProductEditorRow),
                      matching: find.byType(Container))
                  .first,
              matching: find.byType(Checkbox))
          : find.byType(Radio<String>);
      expect(selector, findsOneWidget);
      if (!many)
        expect(tester.widget<Radio<String>>(selector).onChanged, isNotNull);
      await tester.tap(selector);
      await tester.pump();
      expect(changes, 1);
      expect(
          many
              ? DefaultValueHelper.readList(field.definition.data).single
              : DefaultValueHelper.readString(field.definition.data),
          '10');
      if (many) {
        expect(tester.widget<Checkbox>(selector).value, isTrue);
      } else {
        expect(tester.widget<Radio<String>>(selector).groupValue, '10');
      }
      await tester.tap(selector);
      await tester.pump();
      expect(changes, 2);
      expect(DefaultValueHelper.read(field.definition.data), isNull);
      expect(
          tester
              .widget<Container>(find
                  .ancestor(
                      of: find.byType(TicketProductEditorRow),
                      matching: find.byType(Container))
                  .first)
              .decoration,
          isNull);
      Finder input(String label) => find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.labelText == label);
      final name = find.descendant(
          of: find.byType(TicketProductEditorRow), matching: input('Název'));
      expect(tester.getRect(name).top, tester.getRect(input('Cena')).top);
      expect(tester.takeException(), isNull);
    });
  }
  testWithWidgetEnvironment(
      () => _environment, 'valid filter follows ticket/application terminology',
      () {
    occasion();
    expect(OrderItemStrings.validTickets, 'Platné přihlášky');
    occasion(tickets: true);
    expect(OrderItemStrings.validTickets, 'Platné vstupenky');
  });
  for (final width in [240.0, 760.0]) {
    for (final brightness in Brightness.values) {
      testWidgetsWithEnvironment(() => _environment,
          'price and surcharge stay grouped and editable at $width/$brightness',
          (tester) async {
        occasion();
        var product =
            ProductModel(title: 'Bez slevy', price: 4500, currencyCode: 'CZK')
                .withMetaSurchargeAmount(150)
                .withMetaSurchargeCurrency('EUR');
        await _environment.pumpWidget(
            tester,
            MaterialApp(builder: DependencyMaterialBridge.builder,
                theme: ThemeData(brightness: brightness),
                home: Scaffold(
                    body: SingleChildScrollView(
                        child: SizedBox(
                            width: width,
                            child: TicketProductEditorRow(
                                readProduct: () => product,
                                replaceProduct: (value) => product = value,
                                onDelete: () {},
                                availableCurrencies: ['CZK', 'EUR']))))));
        Finder field(String label) => find.byWidgetPredicate(
            (w) => w is TextField && w.decoration?.labelText == label);
        final price = field('Cena');
        final surcharge = field('Doplatek');
        expect(price, findsOneWidget);
        expect(surcharge, findsOneWidget);
        if (width > 480) {
          expect(tester.getRect(price).top, tester.getRect(surcharge).top);
          expect(tester.getSize(find.byType(TicketProductEditorRow)).height,
              lessThan(100));
          expect(tester.getRect(price).right,
              lessThan(tester.getRect(surcharge).left));
        } else {
          expect(tester.getRect(surcharge).top,
              greaterThan(tester.getRect(price).bottom));
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
