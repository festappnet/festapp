import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/eshop/models/order_model.dart';
import 'package:fstapp/components/eshop/models/ticket_model.dart';
import 'package:fstapp/components/scan/scan_page.dart';
import 'package:fstapp/components/scan/scan_result_display.dart';
import '../../support/fixtures/widget_environment_fixture.dart';
import '../../support/fixtures/localization_log_fixture.dart';

void main() {
  WidgetEnvironmentFixture.register();
  setUp(() {
    final logs = LocalizationLogFixture.install(expectedMissingCatalog: true);
    addTearDown(logs.dispose);
  });

  test('scanner label supports anonymous sales and optional customer contact',
      () {
    final ticket = TicketModel.fromJson({
      'ticket_symbol': 'QR-1',
      'batch': {'title': 'drahe'},
    });
    expect(ticket.scanLabel, 'drahe · QR-1');
    ticket.relatedOrder = OrderModel(data: {'email': 'buyer@example.org'});
    expect(ticket.scanLabel, 'drahe · buyer@example.org · QR-1');
    ticket.batch = null;
    expect(ticket.scanLabel, 'buyer@example.org · QR-1');
    ticket.relatedOrder = null;
    expect(ticket.scanLabel, 'QR-1');
  });

  testWidgets('anonymous ticket renders its identity without an order',
      (tester) async {
    final environment = WidgetEnvironmentFixture(
      locale: const Locale('cs'),
      translations:
          jsonDecode(File('assets/translations/cs.json').readAsStringSync())
              as Map<String, dynamic>,
    );
    await environment.pumpWidget(
        tester,
        MaterialApp(
            home: Scaffold(
          body: SingleChildScrollView(
              child: ScanResultDisplay(
            scannedObject: TicketModel(
                ticketSymbol: 'QR-1', state: 'sent', batch: {'title': 'drahe'}),
            scanState: ScanState.valid,
            features: const [],
            fieldMappings: const {},
            showHelpText: false,
            backgroundColor: Colors.green,
            onConfirm: () {},
            onResetPassword: () {},
            onDismissHelp: () {},
          )),
        )));
    await tester.pumpAndSettle();
    expect(find.textContaining('drahe · QR-1'), findsOneWidget);
    expect(find.textContaining('Dávka:'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
