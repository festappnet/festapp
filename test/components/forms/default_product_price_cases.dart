import 'dart:convert';
import 'dart:io';
import 'package:easy_localization/src/localization.dart';
import 'package:easy_localization/src/translations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/forms/form_session.dart';
import 'package:fstapp/components/forms/models/form_model.dart';
import 'package:fstapp/components/forms/models/form_option_product_model.dart';
import 'package:fstapp/components/forms/models/holder_models/field_holder.dart';
import 'package:fstapp/components/forms/models/holder_models/form_holder.dart';
import 'package:fstapp/components/forms/models/holder_models/ticket_holder.dart';
import 'package:fstapp/components/forms/widgets_view/form_field_builders.dart';

void main() {
  setUpAll(() => Localization.load(const Locale('cs'),
      translations: Translations(
          jsonDecode(File('assets/translations/cs.json').readAsStringSync())
              as Map<String, dynamic>)));
  for (final many in [false, true]) {
    for (final cards in [false, true]) {
      testWidgets(
          'default products enter initial ticket totals: many=$many cards=$cards',
          (tester) async {
        final product = FormOptionProductModel('20', 'Dinner',
            price: 150, currencyCode: 'CZK');
        final lunch = FormOptionProductModel('30', 'Lunch',
            price: 100, currencyCode: 'CZK');
        final field = OptionsFieldProductHolder(
            id: 3,
            fieldType: 'product_type',
            title: 'Products',
            isRequired: false,
            productOptions: [
              FormOptionProductModel('10', 'Other',
                  price: 25, currencyCode: 'CZK'),
              product,
              lunch
            ],
            value: many ? ['20', '30'] : '20',
            selectionType: many
                ? OptionsFieldProductSelectionType.selectMany
                : OptionsFieldProductSelectionType.selectOne);
        final ticket = TicketHolder(
            id: 1, fieldType: 'ticket', maxTickets: 1, fields: [field]);
        final holder = FormHolder(fields: [ticket], isCardDesign: cards);
        final key = GlobalKey<FormBuilderState>();
        final session =
            FormSession(form: FormModel(), formHolder: holder, formKey: key);
        addTearDown(session.dispose);
        holder.controller = FormHolderController(
            globalKey: key, updateTotalPrice: session.recalculateTotals);
        await tester.pumpWidget(MaterialApp(
            home: Scaffold(
                body: FormBuilder(
                    key: key,
                    onChanged: session.recalculateTotals,
                    child: Builder(
                        builder: (context) =>
                            FormFieldBuilders.buildTicketField(
                                context, holder, ticket))))));
        await tester.pumpAndSettle();
        expect(ticket.tickets.length, 1);
        expect(ticket.tickets.single.ticketKey.currentState!.instantValue['3'],
            many ? [product, lunch] : product);
        expect(session.totalPrice, many ? 250 : 150,
            reason: 'Price must appear without user interaction');
        expect(session.totalProducts, many ? 2 : 1);
        expect(session.totalTickets, 1);
        expect(session.currencyCode, 'CZK');
        // Clearing a selected product must update the same initial total.
        ticket.tickets.single.ticketKey.currentState!.fields['3']!
            .didChange(many ? <FormOptionProductModel>[] : null);
        await tester.pumpAndSettle();
        expect(session.totalPrice, 0);
        expect(session.totalProducts, 0);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
