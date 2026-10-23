import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/eshop/models/ticket_batch_document_part.dart';
import 'package:fstapp/components/eshop/views/ticket_batch_print_downloads.dart';

void main() {
  testWidgets(
      '200-ticket batch offers one packed PDF or a ZIP in a compact mobile menu',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    String? selected;
    final parts = List.generate(
        200,
        (n) => TicketBatchDocumentPart(
            id: 'part-$n',
            key: 'single-${n + 1}',
            kind: 'single',
            state: 'ready',
            pages: 1));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Column(children: [
      TicketBatchPrintDownloads(
          parts: parts,
          label: 'Download',
          a4Label: 'Print PDF - multiple tickets per A4',
          zipLabel: 'ZIP - individual PDFs',
          onSelected: (id) => selected = id),
      const Expanded(child: Center(child: Text('Ticket selection'))),
    ]))));
    expect(tester.getSize(find.byType(TicketBatchPrintDownloads)).height,
        lessThan(60));
    expect(find.text('Ticket selection').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Download'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Print PDF - multiple tickets per A4'));
    await tester.pumpAndSettle();
    expect(selected, 'a4');
    await tester.tap(find.text('Download'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ZIP - individual PDFs'));
    await tester.pumpAndSettle();
    expect(selected, 'zip');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: TicketBatchPrintDownloads(
                parts: const [
          TicketBatchDocumentPart(
              id: 'pending', key: 'single-1', kind: 'single', state: 'pending')
        ],
                label: 'Download',
                a4Label: 'A4',
                zipLabel: 'ZIP',
                onSelected: (_) {}))));
    expect(find.text('Download'), findsNothing);
  });
}
