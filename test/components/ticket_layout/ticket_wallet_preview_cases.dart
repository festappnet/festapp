import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:festapp_core/time.dart';
import 'package:fstapp/components/ticket_layout/google_wallet_appearance.dart';
import 'package:fstapp/components/ticket_layout/views/ticket_wallet_card_preview.dart';

import '../../support/fixtures/widget_environment_fixture.dart';

void main() {
  WidgetEnvironmentFixture.register();
  setUpAll(() async {
    OccasionTimeContext.initializeTimeZones();
    await (FontLoader(
      'Futura',
    )..addFont(rootBundle.load('fonts/Futura PT Book.ttf'))).load();
  });
  testWidgets(
    'native Wallet preview inherits color and keeps a clean invalid sample QR',
    (tester) async {
      final environment = WidgetEnvironmentFixture(
        locale: const Locale('cs'),
        translations: jsonDecode(
          File('assets/translations/cs.json').readAsStringSync(),
        ) as Map<String, dynamic>,
      );
      final key = GlobalKey();
      await environment.pumpWidget(
        tester,
        MaterialApp(
          theme: ThemeData(brightness: Brightness.light, fontFamily: 'Futura'),
          home: Scaffold(
            body: Center(
              child: RepaintBoundary(
                key: key,
                child: TicketWalletCardPreview(
                  previewLabel: 'Orientační náhled Google Wallet',
                  sampleCodeLabel: 'UKÁZKA - NEPLATÍ PRO VSTUP',
                  appearance: const GoogleWalletAppearance(
                    backgroundColor: '#e8f0fe',
                  ),
                  occasion: const {
                    'title': 'Slavnostní večer',
                    'start_time': '2026-11-13T18:00:00Z',
                    'data': {'place_name': 'Kulturní dům'},
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Slavnostní večer'), findsOneWidget);
      final qr = tester.widget<QrImageView>(find.byType(QrImageView));
      expect(qr.backgroundColor, Colors.white);
      const path = String.fromEnvironment('UI_SCREENSHOT_DIR');
      if (path.isNotEmpty) {
        final boundary =
            key.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final image = (await tester.runAsync(() => boundary.toImage()))!;
        try {
          final bytes = (await tester.runAsync(
            () => image.toByteData(format: ui.ImageByteFormat.png),
          ))!;
          Directory(path).createSync(recursive: true);
          File('$path/wallet-preview-cs.png')
              .writeAsBytesSync(bytes.buffer.asUint8List());
        } finally {
          image.dispose();
        }
      }
    },
  );
}
