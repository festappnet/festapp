import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/ticket_layout/google_wallet_appearance.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/features/ticket_feature.dart';
import 'package:fstapp/components/ticket_layout/views/ticket_wallet_selector.dart';
import 'package:fstapp/components/ticket_layout/views/ticket_email_preview.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:fstapp/components/ticket_layout/ticket_delivery_strings.dart';

void main() {
  test('PDF email still reserves its ticket block for an available Wallet offer exactly once', () {
    expect(
      TicketEmailPreview.ticketBody('Text', TicketDeliveryMode.pdfAttachment),
      'Text',
    );
    final body = TicketEmailPreview.ticketBody(
      'Text {{tickets}} {{tickets}}',
      TicketDeliveryMode.pdfAttachment,
      walletEnabled: true,
    );
    expect('FESTAPP_TICKET_PREVIEW_BLOCK'.allMatches(body).length, 1);
  });
  testWidgets(
    'Wallet email preview shows localized real badges with no QR or active action',
    (tester) async {
      await tester.runAsync(() => TicketDeliveryStrings.walletCopy('en'));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: TicketEmailPreview.walletSample(count: 3, language: 'en'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Tickets on your phone'), findsOneWidget);
      expect(find.text('Ticket 2 of 3'), findsOneWidget);
      expect(find.byType(QrImageView), findsNothing);
      expect(find.byType(Image), findsNWidgets(3));
      expect(find.byType(TextButton), findsNothing);
      for (final image in tester.widgetList<Image>(find.byType(Image))) {
        expect(image.height, 48);
        expect(
          (image.image as AssetImage).assetName,
          'assets/brand/google-wallet/en.png',
        );
      }
    },
  );
  test('Native Wallet appearance shares the backend contract and preserves overrides', () {
    final cases = jsonDecode(
      File('packages/festapp_contracts/ticket-wallet-appearance-cases.json')
          .readAsStringSync(),
    ) as List;
    for (final sample in cases) {
      expect(
        GoogleWalletAppearance.fromTicket(
          Map<String, dynamic>.from(sample['feature']),
          Map<String, dynamic>.from(sample['data']),
        ).toJson(),
        sample['expected'],
        reason: sample['name'],
      );
    }
    final feature = TicketFeature.fromJson({
      'code': 'ticket',
      'wallet_appearance': {'background_color': '#216acf', 'logo': null},
    });
    expect(
      TicketFeature.fromJson(feature.toJson()).walletAppearance,
      feature.walletAppearance,
    );
  });
  test('Wallet preference survives model edits, modes and round trip', () {
    final feature = TicketFeature.fromJson({
      'code': 'ticket',
      'is_enabled': true,
    });
    expect(feature.walletEnabled, true);
    feature.walletEnabled = false;
    for (final mode in TicketDeliveryMode.values) {
      feature.deliveryMode = mode;
      expect(TicketFeature.fromJson(feature.toJson()).walletEnabled, false);
    }
    expect(
      () =>
          TicketFeature.fromJson({'code': 'ticket', 'wallet_enabled': 'false'}),
      throwsA(isA<TypeError>()),
    );
  });
  testWidgets(
    'Wallet row toggles independently and disabled retains preference',
    (tester) async {
      bool value = false;
      Widget view(bool enabled) => MaterialApp(
        home: Scaffold(
          body: TicketWalletSelector(
            value: value,
            enabled: enabled,
            onChanged: (next) => value = next,
          ),
        ),
      );
      await tester.pumpWidget(view(true));
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      expect(value, true);
      await tester.pumpWidget(view(false));
      expect(
        tester
            .widget<CheckboxListTile>(find.byType(CheckboxListTile))
            .onChanged,
        isNull,
      );
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        true,
      );
    },
  );
}
