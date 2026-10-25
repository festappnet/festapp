import 'package:fstapp/widgets/dependency_material_bridge.dart';
import 'dart:convert';
import 'dart:io';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/eshop/views/ticket_batch_detail_header.dart';
import 'package:fstapp/components/eshop/views/ticket_batch_print_downloads.dart';
import 'package:fstapp/components/eshop/models/ticket_batch_document_part.dart';
import 'package:fstapp/theme_config.dart';
import '../../support/fixtures/widget_environment_fixture.dart';

void main() {
  WidgetEnvironmentFixture.register();
  setUpAll(() async {
    await (FontLoader('Futura')
          ..addFont(rootBundle.load('fonts/Futura PT Book.ttf'))
          ..addFont(rootBundle.load('fonts/Futura PT Medium.ttf')))
        .load();
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
  });
  for (final width in [1280.0, 760.0, 360.0]) {
    for (final dark in [true, false]) {
      testWidgets('batch actions preserve table space at $width, dark=$dark',
          (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final environment = WidgetEnvironmentFixture(
            locale: const Locale('cs'),
            translations: jsonDecode(
                File('assets/translations/cs.json').readAsStringSync()));
        await environment.pumpWidget(
            tester,
            MaterialApp(builder: DependencyMaterialBridge.builder,
                theme: ThemeConfig.theme(
                    brightness: dark ? Brightness.dark : Brightness.light),
                home: Scaffold(
                    body: Column(children: [
                  ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 540),
                      child: SingleChildScrollView(
                          child: TicketBatchDetailHeader(
                        batch: const {
                          'title': 'Vstupenky na místě',
                          'currency': 'CZK',
                          'counts': {
                            'available': 10,
                            'soldActive': 0,
                            'voidedUnsold': 1,
                            'cancelledAfterSale': 2
                          },
                          'stockValue': 5000,
                          'receivedAmount': 0
                        },
                        selectedCount: 0,
                        onBack: () {},
                        printActions: [
                          OutlinedButton.icon(
                              onPressed: () {},
                              icon: const Icon(Icons.print_outlined),
                              label: const Text('Připravit / obnovit tisk')),
                          TicketBatchPrintDownloads(
                              parts: const [
                                TicketBatchDocumentPart(
                                    id: 'one',
                                    key: 'single-1',
                                    kind: 'single',
                                    state: 'ready')
                              ],
                              label: 'Stáhnout',
                              a4Label: 'PDF',
                              zipLabel: 'ZIP',
                              onSelected: (_) {}),
                        ],
                        selectionActions: const [
                          ElevatedButton(
                              onPressed: null, child: Text('Zapsat prodej')),
                          TextButton(
                              onPressed: null,
                              child: Text('Zneplatnit neprodané'))
                        ],
                        lookup: const TextField(
                            decoration: InputDecoration(
                                isDense: true,
                                border: OutlineInputBorder(),
                                labelText: 'Symbol / načtený QR',
                                prefixIcon: Icon(Icons.qr_code_scanner),
                                suffixIcon: Icon(Icons.search))),
                      ))),
                  const Expanded(
                      child: ColoredBox(
                          color: Colors.transparent,
                          child: Center(child: Text('Tickets table')))),
                ]))));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Vybráno: 0'), findsOneWidget);
        expect(find.text('Zneplatněno: 3', findRichText: true), findsOneWidget);
        expect(tester.getSize(find.byType(TextField)).width,
            lessThanOrEqualTo(328));
        expect(find.text('Tickets table').hitTestable(), findsOneWidget);
      });
    }
  }
}
