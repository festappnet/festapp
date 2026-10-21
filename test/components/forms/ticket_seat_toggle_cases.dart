import '../../support/fixtures/widget_environment_fixture.dart';
import 'package:festapp_core/forms.dart';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:festapp_core/eshop.dart';
import 'package:fstapp/components/features/feature.dart';
import 'package:fstapp/components/features/feature_constants.dart';
import 'package:fstapp/components/forms/form_strings.dart';
import 'package:fstapp/components/forms/models/form_field_draft.dart';
import 'package:fstapp/components/forms/models/form_editor_draft.dart';
import 'package:fstapp/components/forms/widgets_editor/ticket_editor_widgets.dart';
import 'package:fstapp/components/occasion/occasion_link_model.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';
import 'package:fstapp/data_services/rights_service.dart';

late WidgetEnvironmentFixture _environment;

void main() {
  WidgetEnvironmentFixture.register();
  setUpAll(() {
    _environment = WidgetEnvironmentFixture(
        locale: const Locale('cs'),
        translations:
            jsonDecode(File('assets/translations/cs.json').readAsStringSync())
                as Map<String, dynamic>);
  });

  for (final blueprintEnabled in [false, true]) {
    testWidgetsWithEnvironment(() => _environment,
        'order limit is editable without ticket feature; blueprint: $blueprintEnabled',
        (tester) async {
      RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
          occasion: OccasionModel(
              isOpen: true,
              isHidden: false,
              isPromoted: false,
              features: [
            SimpleFeature(
                code: FeatureConstants.blueprint, isEnabled: blueprintEnabled),
          ]));
      addTearDown(() => RightsService.occasionLinkModelNotifier.value = null);
      final ticket = FormFieldDraft(type: FormMetadata.fieldTypeTicket);
      final form = FormEditorDraft(occasionId: 59, relatedFields: [ticket]);
      await _environment.pumpWidget(
          tester,
          MaterialApp(
              home: Scaffold(
            body: SingleChildScrollView(
                child: Builder(
                    builder: (context) => TicketEditorWidgets.buildTicketEditor(
                        context, form, ticket, [], () {}))),
          )));
      final limit = find.widgetWithText(
          TextFormField, FormStrings.labelMaxTicketsPerOrder);
      expect(limit, findsOneWidget);
      await tester.enterText(limit, '4');
      expect(ticket.definition.data?[FormMetadata.maxTickets], 4);
      await _environment.pumpWidget(
          tester,
          MaterialApp(
              home: Scaffold(
            body: Builder(
                builder: (context) =>
                    TicketEditorWidgets.buildTicketEditorReadOnly(
                        context, form, ticket)),
          )));
      expect(find.text(FormStrings.labelMaxTicketsPerOrder), findsOneWidget);
      expect(find.text('4'), findsOneWidget);
    });
  }

  for (final depositEnabled in [false, true]) {
    testWidgetsWithEnvironment(() => _environment,
        'deposit description menu requires enabled deposit feature: $depositEnabled',
        (tester) async {
      RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
          occasion: OccasionModel(
              isOpen: true,
              isHidden: false,
              isPromoted: false,
              features: [
            SimpleFeature(code: FeatureConstants.ticket, isEnabled: true),
            SimpleFeature(
                code: FeatureConstants.deposit, isEnabled: depositEnabled),
          ]));
      addTearDown(() => RightsService.occasionLinkModelNotifier.value = null);
      final ticket = FormFieldDraft(type: FormMetadata.fieldTypeTicket);
      final form = FormEditorDraft(occasionId: 59, relatedFields: [ticket]);
      await _environment.pumpWidget(
          tester,
          MaterialApp(
              home: Scaffold(
                  body: SingleChildScrollView(
                      child: Builder(
                          builder: (context) =>
                              TicketEditorWidgets.buildTicketEditor(
                                  context, form, ticket, [], () {}))))));
      final menu = find.byType(PopupMenuButton<String>);
      expect(menu, depositEnabled ? findsOneWidget : findsNothing);
      if (depositEnabled) {
        await tester.tap(menu);
        await tester.pumpAndSettle();
        expect(find.text(FormStrings.showDepositDescription), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }

  for (final hasExistingSpotField in [false, true]) {
    testWidgetsWithEnvironment(() => _environment,
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
      final ticket = FormFieldDraft(type: FormMetadata.fieldTypeTicket);
      final seatGroup = FormFieldDraft(
          type: FormMetadata.fieldTypeProductType,
          isTicketField: true,
          isRequired: true,
          productType: seats);
      final form = FormEditorDraft(occasionId: 59, relatedFields: [
        ticket,
        FormFieldDraft(
            type: FormMetadata.fieldTypeSpot,
            isTicketField: true,
            isHidden: false),
        FormFieldDraft(
            type: FormMetadata.fieldTypeProductType,
            isTicketField: true,
            productType: meals),
        if (hasExistingSpotField) seatGroup,
      ]);
      await _environment.pumpWidget(tester, MaterialApp(home: Scaffold(body:
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
            .where((field) => field.definition.productType?.id == seats.id)
            .toList();
        expect(groups, hasLength(1));
        if (hasExistingSpotField) {
          expect(groups.single, same(seatGroup));
          expect(groups.single.definition.isRequired, isTrue);
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
