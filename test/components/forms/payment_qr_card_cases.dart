import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/forms/widgets_view/payment_qr_card.dart';

void main() {
  testWidgets('EUR QR card renders the RF payment reference', (tester) async {
    tester.view.physicalSize = const Size(900, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PaymentQrCard(
              payload: 'BCD\n002\n1\nSCT\n\nFestapp\nDE71110220330123456789'
                  '\nEUR12.30\n\nRF18539007547034\n\n',
              format: 'EPC_SCT',
              bankAccount: 'DE71 1102 2033 0123 4567 89',
              iban: 'DE71110220330123456789',
              paymentReference: 'RF18 5390 0754 7034',
              referenceKind: 'RF',
              amountFormatted: '12.30 EUR',
            ),
          ),
        ),
      ),
    );

    expect(
      find.textContaining('PublicOrder.paymentReference', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('RF18 5390 0754 7034', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('PublicOrder.variableSymbol', findRichText: true),
      findsNothing,
    );
  });
}
