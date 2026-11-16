import 'dart:async';
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
import 'package:fstapp/app_config.dart';
import 'package:fstapp/components/ticket_layout/views/ticket_wallet_card_preview.dart';

import '../../support/fixtures/widget_environment_fixture.dart';

void main() {
  WidgetEnvironmentFixture.register();
  setUpAll(() async {
    OccasionTimeContext.initializeTimeZones();
    await (FontLoader('WalletPreviewSans')..addFont(
          rootBundle.load(
            'supabase/functions/_shared/ticket-assets/roboto.ttf',
          ),
        ))
        .load();
    await (FontLoader(
      'Futura',
    )..addFont(rootBundle.load('fonts/Futura PT Book.ttf'))).load();
  });
  for (final platform in TicketWalletPlatform.values) {
    testWidgets('${platform.name} preview matches the issued native template', (
      tester,
    ) async {
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
          locale: const Locale('cs'),
          supportedLocales: const [Locale('cs')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: ThemeData(brightness: Brightness.light, fontFamily: 'Futura'),
          home: Scaffold(
            body: Center(
              child: RepaintBoundary(
                key: key,
                child: TicketWalletCardPreview(
                  platform: platform,
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
      final cardStyle = tester
          .widget<DefaultTextStyle>(
            find
                .descendant(
                  of: find.byType(TicketWalletCardPreview),
                  matching: find.byType(DefaultTextStyle),
                )
                .first,
          )
          .style;
      expect(cardStyle.fontFamily, 'WalletPreviewSans');
      expect(find.text(AppConfig.appName), findsOneWidget);
      final qrTop = tester.getTopLeft(find.byType(QrImageView)).dy;
      if (platform == TicketWalletPlatform.google) {
        expect(find.text('Kulturní dům'), findsNothing);
        expect(tester.getTopLeft(find.text('DATUM')).dy, greaterThan(qrTop));
        expect(find.text('ČAS'), findsOneWidget);
        expect(find.text('19:00'), findsOneWidget);
        expect(find.textContaining('7:00 PM'), findsNothing);
      } else {
        expect(
          tester.getTopLeft(find.text('Kulturní dům')).dy,
          lessThan(qrTop),
        );
        expect(find.text('Datum / Date'), findsOneWidget);
        expect(find.textContaining('19:00'), findsOneWidget);
      }
      expect(
        tester.getSize(find.byType(TicketWalletCardPreview)).height,
        lessThan(tester.getSize(find.byType(Scaffold)).height),
      );
      expect(tester.takeException(), isNull);
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
          File('$path/wallet-preview-${platform.name}-cs.png')
              .writeAsBytesSync(bytes.buffer.asUint8List());
        } finally {
          image.dispose();
        }
      }
    });
  }
  testWidgets(
    'artwork uses a Google image and an Apple cropped primary strip',
    (tester) async {
      final environment = WidgetEnvironmentFixture(
        locale: const Locale('cs'),
        translations: jsonDecode(
          File('assets/translations/cs.json').readAsStringSync(),
        ) as Map<String, dynamic>,
      );
      final bytes = File('test/fixtures/ticket_layout/background.png')
          .readAsBytesSync();
      debugNetworkImageHttpClientProvider = () => _ArtworkClient(bytes);
      addTearDown(() {
        debugNetworkImageHttpClientProvider = null;
        PaintingBinding.instance.imageCache.clear();
      });
      for (final platform in TicketWalletPlatform.values) {
        await environment.pumpWidget(
          tester,
          MaterialApp(
            locale: const Locale('cs'),
            supportedLocales: const [Locale('cs')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: Scaffold(
              body: SingleChildScrollView(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: 344,
                    child: TicketWalletCardPreview(
                      platform: platform,
                      previewLabel: 'Náhled',
                      sampleCodeLabel: 'UKÁZKA',
                      appearance: const GoogleWalletAppearance(
                        heroImage: 'https://img.festapp.net/images/sample.png',
                        logoOverridden: true,
                      ),
                      occasion: const {
                        'title': 'Slavnostní večer',
                        'start_time': '2026-11-13T18:00:00Z',
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.runAsync(
          () => precacheImage(
            const NetworkImage('https://img.festapp.net/images/sample.png'),
            tester.element(find.byType(TicketWalletCardPreview)),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
        expect(tester.getSize(find.byType(TicketWalletCardPreview)).width, 344);
        final image = tester.widget<Image>(find.byType(Image));
        final titleY = tester.getTopLeft(find.text('Slavnostní večer')).dy;
        final imageY = tester.getTopLeft(find.byType(Image)).dy;
        if (platform == TicketWalletPlatform.google) {
          expect(image.fit, BoxFit.fitWidth);
          expect(imageY, greaterThan(titleY));
          final body = find.descendant(
            of: find.byType(TicketWalletCardPreview),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Container && widget.decoration is BoxDecoration,
            ),
          );
          expect(imageY, greaterThanOrEqualTo(tester.getBottomLeft(body).dy));
          expect(
            find.byKey(const ValueKey('apple-wallet-strip')),
            findsNothing,
          );
        } else {
          expect(image.fit, BoxFit.cover);
          final strip = tester.widget<AspectRatio>(
            find.byKey(const ValueKey('apple-wallet-strip')),
          );
          expect(strip.aspectRatio, 375 / 98);
          expect(titleY, greaterThanOrEqualTo(imageY));
          expect(
            tester.getBottomLeft(find.byType(Image)).dy,
            lessThan(tester.getTopLeft(find.byType(QrImageView)).dy),
          );
        }
        if (platform == TicketWalletPlatform.apple) {
          const longTitle =
              'Slavnostní skautský ples s bohatým programem a živou hudbou';
          await environment.pumpWidget(
            tester,
            MaterialApp(
              home: Scaffold(
                body: Center(
                  child: SizedBox(
                    width: 280,
                    child: MediaQuery(
                      data: const MediaQueryData(
                        textScaler: TextScaler.linear(1.6),
                      ),
                      child: TicketWalletCardPreview(
                        platform: platform,
                        previewLabel: 'Náhled',
                        sampleCodeLabel: 'UKÁZKA',
                        appearance: const GoogleWalletAppearance(
                          heroImage:
                              'https://img.festapp.net/images/sample.png',
                        ),
                        occasion: const {'title': longTitle},
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final stripRect = tester.getRect(
            find.byKey(const ValueKey('apple-wallet-strip')),
          );
          final titleRect = tester.getRect(find.text(longTitle));
          expect(titleRect.top, greaterThanOrEqualTo(stripRect.top));
          expect(titleRect.bottom, lessThanOrEqualTo(stripRect.bottom));
          expect(
            tester.widget<RawImage>(find.byType(RawImage)).image,
            isNotNull,
          );
        }
        expect(tester.takeException(), isNull);
      }
    },
  );
}

// A real decoded fixture through NetworkImage, without external network access.
class _ArtworkClient extends Fake implements HttpClient {
  _ArtworkClient(this.bytes);
  final List<int> bytes;
  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _ArtworkRequest(bytes);
}

class _ArtworkRequest extends Fake implements HttpClientRequest {
  _ArtworkRequest(this.bytes);
  final List<int> bytes;
  @override
  Future<HttpClientResponse> close() async => _ArtworkResponse(bytes);
}

class _ArtworkResponse extends Stream<List<int>> implements HttpClientResponse {
  _ArtworkResponse(this.bytes);
  final List<int> bytes;
  @override
  int get statusCode => HttpStatus.ok;
  @override
  int get contentLength => bytes.length;
  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.value(bytes).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
