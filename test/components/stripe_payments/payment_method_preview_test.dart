import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/forms/models/form_editor_draft.dart';
import 'package:fstapp/components/forms/models/holder_models/form_holder.dart';
import 'package:fstapp/components/forms/models/holder_models/ticket_holder.dart';
import 'package:fstapp/components/forms/views/order_preview_screen.dart';
import '../../support/fixtures/widget_environment_fixture.dart';

const connection = '12345678-1234-4234-8234-123456789abc';
Map<String, dynamic> options() => {
      'configured': {'bank': true, 'stripe': true},
      'available': ['stripe', 'bank'],
      'supportedSurfaces': ['web'],
      'recipient': {'connectionId': connection, 'name': 'Organizer'},
      'reservationSeconds': 1860
    };
void main() {
  WidgetEnvironmentFixture.register();
  late Map<String, dynamic> catalog;
  setUpAll(() {
    catalog =
        jsonDecode(File('assets/translations/cs.json').readAsStringSync());
  });
  WidgetEnvironmentFixture env() => WidgetEnvironmentFixture(
      locale: const Locale('cs'), translations: catalog);
  FormHolder holder() => FormHolder(fields: [
        TicketHolder(id: 1, fieldType: 'ticket', maxTickets: 1, fields: [])
      ], isCardDesign: true)
        ..controller =
            (FormHolderController(globalKey: GlobalKey<FormBuilderState>())
              ..currencyCode = 'CZK');
  testWidgets(
      'A05/A07 preview submits the displayed amount, currency and recipient snapshot',
      (tester) async {
    final h = holder(), raw = options();
    int sent = 0;
    await env().pumpWidget(
        tester,
        MaterialApp(
            home: Scaffold(
                body: OrderPreviewScreen(
                    formHolder: h,
                    totalPrice: 123.45,
                    payments: raw,
                    onSendPressed: () => sent++))));
    await tester.pumpAndSettle();
    expect(find.textContaining('123,45'), findsWidgets);
    raw['recipient']['connectionId'] = 'changed';
    h.controller!.currencyCode = 'EUR';
    await tester
        .ensureVisible(find.text(catalog['PaymentMethods']['orderAndPay']));
    await tester.tap(find.text(catalog['PaymentMethods']['orderAndPay']));
    expect(sent, 1);
    expect(h.paymentMethod, 'stripe');
    expect(h.paymentAmountMinor, 12345);
    expect(h.paymentCurrency, 'CZK');
    expect(h.paymentConnectionId, connection);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'bank-only order submits without displaying a redundant payment choice',
      (tester) async {
    final h = holder();
    int sent = 0;
    await env().pumpWidget(
        tester,
        MaterialApp(
            home: Scaffold(
                body: OrderPreviewScreen(
                    formHolder: h,
                    totalPrice: 100,
                    onSendPressed: () => sent++))));
    await tester.pumpAndSettle();
    expect(find.text(catalog['PaymentMethods']['title']), findsNothing);
    expect(find.text(catalog['PaymentMethods']['bank']), findsNothing);
    final submit = find.byType(FilledButton);
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    expect(sent, 1);
    expect(h.paymentMethod, 'bank');
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'A06 unavailable paid order cannot submit and free order has no payment choice',
      (tester) async {
    final h = holder();
    int sent = 0;
    final fixture = env();
    await fixture.pumpWidget(
        tester,
        MaterialApp(
            home: Scaffold(
                body: OrderPreviewScreen(
                    formHolder: h,
                    totalPrice: 123.45,
                    payments: {...options(), 'available': []},
                    onSendPressed: () => sent++))));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    expect(sent, 0);
    await fixture.pumpWidget(
        tester,
        MaterialApp(
            home: Scaffold(
                body: OrderPreviewScreen(
                    key: const ValueKey('free'),
                    formHolder: h,
                    totalPrice: 0,
                    payments: options(),
                    onSendPressed: () => sent++))));
    await tester.pumpAndSettle();
    expect(find.byType(RadioListTile<String>), findsNothing);
    await tester
        .ensureVisible(find.text(catalog['PaymentMethods']['finishFree']));
    await tester.tap(find.text(catalog['PaymentMethods']['finishFree']));
    expect(sent, 1);
    expect(h.paymentMethod, isNull);
  });
  test(
      'A06 editor save retains chosen configuration and excludes server availability',
      () {
    final draft = FormEditorDraft.fromJson({
      'id': 1,
      'data': {
        'payments': {'bankEnabled': false, 'stripeConnectionId': connection}
      },
      'payments': options()
    });
    final saved = draft.toEditedJson();
    expect(saved.containsKey('payments'), isFalse);
    expect(saved['data']['payments']['stripeConnectionId'], connection);
  });
}
