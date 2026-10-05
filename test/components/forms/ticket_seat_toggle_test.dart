import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/src/localization.dart';
import 'package:easy_localization/src/translations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/eshop/models/product_model.dart';
import 'package:fstapp/components/eshop/models/product_type_model.dart';
import 'package:fstapp/components/features/feature.dart';
import 'package:fstapp/components/features/feature_constants.dart';
import 'package:fstapp/components/forms/form_strings.dart';
import 'package:fstapp/components/forms/models/form_field_model.dart';
import 'package:fstapp/components/forms/models/form_model.dart';
import 'package:fstapp/components/forms/widgets_editor/ticket_editor_widgets.dart';
import 'package:fstapp/components/forms/widgets_view/form_helper.dart';
import 'package:fstapp/components/occasion/occasion_link_model.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';
import 'package:fstapp/data_services/rights_service.dart';

void main() {
  setUpAll(() {
    Localization.load(const Locale('cs'),
        translations: Translations(
            jsonDecode(File('assets/translations/cs.json').readAsStringSync())
                as Map<String, dynamic>));
  });

  for (final hasExistingSpotField in [false, true]) {
    testWidgets(
        'disabling blueprint shows seats alongside meals; existing field: $hasExistingSpotField',
        (tester) async {
      tester.view.physicalSize = const Size(1600, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
          occasion: OccasionModel(
              isOpen: true,
              isHidden: false,
              isPromoted: false,
              features: [
            SimpleFeature(code: FeatureConstants.blueprint, isEnabled: true),
          ]));
      addTearDown(() => RightsService.occasionLinkModelNotifier.value = null);
      final seats = ProductTypeModel(
          id: 10,
          title: 'Seats',
          type: ProductModel.spotType,
          products: [
            ProductModel(id: 100, title: 'Seat ticket', price: 200),
          ]);
      final meals = ProductTypeModel(id: 20, title: 'Meals', products: [
        ProductModel(id: 200, title: 'Dinner', price: 100),
      ]);
      final ticket = FormFieldModel(type: FormHelper.fieldTypeTicket);
      final seatGroup = FormFieldModel(
          type: FormHelper.fieldTypeProductType,
          isTicketField: true,
          isRequired: true,
          productType: seats);
      final form = FormModel(occasionId: 59, relatedFields: [
        ticket,
        FormFieldModel(
            type: FormHelper.fieldTypeSpot,
            isTicketField: true,
            isHidden: false),
        FormFieldModel(
            type: FormHelper.fieldTypeProductType,
            isTicketField: true,
            productType: meals),
        if (hasExistingSpotField) seatGroup,
      ]);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body:
          SingleChildScrollView(
              child: StatefulBuilder(builder: (context, setState) {
        return TicketEditorWidgets.buildTicketEditor(
            context, form, ticket, [seats, meals], () => setState(() {}));
      })))));
      final seatToggle = find.descendant(
          of: find.widgetWithText(Card, FormStrings.seatSelection),
          matching: find.byType(Switch));
      final seatProduct = find.widgetWithText(TextField, 'Seat ticket');
      final mealProduct = find.widgetWithText(TextField, 'Dinner');
      expect(seatProduct, findsNothing);
      expect(mealProduct, findsOneWidget);
      for (var i = 0; i < 2; i++) {
        await tester.tap(seatToggle);
        await tester.pumpAndSettle();
        expect(seatProduct, findsOneWidget);
        expect(mealProduct, findsOneWidget);
        final groups = form.relatedFields
            .where((field) => field.productType?.id == seats.id)
            .toList();
        expect(groups, hasLength(1));
        if (hasExistingSpotField) {
          expect(groups.single, same(seatGroup));
          expect(groups.single.isRequired, isTrue);
        }
        await tester.tap(seatToggle);
        await tester.pumpAndSettle();
        expect(seatProduct, findsNothing);
        expect(mealProduct, findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
