import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/features/ticket_feature.dart';
import 'package:fstapp/components/images/image_area.dart';
import 'package:fstapp/components/ticket_layout/views/ticket_wallet_appearance_editor.dart';
import 'package:fstapp/services/import_file.dart';
import 'package:image/image.dart' as image;
import 'package:material_ui/material_ui.dart';

import '../support/fixtures/widget_environment_fixture.dart';

void main() {
  WidgetEnvironmentFixture.register();

  testWidgets('Wallet editor accepts PNG and JPEG artwork on web', (
    tester,
  ) async {
    final environment = WidgetEnvironmentFixture(
      locale: const Locale('en'),
      translations: const {
        'TicketDelivery': {
          'walletAppearance': 'Wallet appearance',
          'walletLogoSize': 'Use a square logo of at least 660 × 660 px.',
        },
      },
    );
    const url = 'https://img.festapp.net/images/wallet.png';
    final uploads = <Uint8List>[];
    final changes = <Map<String, dynamic>>[];
    await environment.pumpWidget(
      tester,
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TicketWalletAppearanceEditor(
              feature: TicketFeature(code: 'ticket'),
              occasionId: 1,
              occasion: const {'title': 'Spring gala'},
              onChanged: changes.add,
              uploadImage: (bytes) async {
                uploads.add(bytes);
                return url;
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Wallet appearance'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apple Wallet'));
    await tester.pumpAndSettle();

    final logo = tester.widget<ImageArea>(find.byType(ImageArea).first);
    final square = image.Image(width: 660, height: 660);
    for (final (name, bytes) in [
      ('logo.png', image.encodePng(square)),
      ('logo.jpg', image.encodeJpg(square)),
    ]) {
      expect(
        await logo.onFileSelected(ImportFile.fromData(bytes, name: name)),
        url,
      );
      expect(uploads.last, bytes);
    }

    final rectangle = image.encodePng(image.Image(width: 660, height: 659));
    await expectLater(
      logo.onFileSelected(ImportFile.fromData(rectangle, name: 'logo.png')),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          'Use a square logo of at least 660 × 660 px.',
        ),
      ),
    );
    final artwork = tester.widget<ImageArea>(find.byType(ImageArea).last);
    expect(
      await artwork.onFileSelected(
        ImportFile.fromData(rectangle, name: 'artwork.png'),
      ),
      url,
    );
    expect(changes, [
      {'logo': url},
      {'logo': url},
      {'hero_image': url},
    ]);
    expect(uploads, hasLength(3));
  });
}
