import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:fstapp/theme_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/forms/widgets_view/card_payment_status.dart';
import 'package:fstapp/components/forms/views/order_finish_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../support/fixtures/widget_environment_fixture.dart';

Map<String, dynamic> payment(String state) => {
      'method': 'stripe',
      'status': state,
      'amount': '1234.50',
      'received': state == 'paid' ? '1234.50' : '0',
      'returned': '0',
      'currency': 'CZK',
      'admissionState': 'pending',
      'allowedActions': ['refresh', 'pay'],
    };
void main() {
  WidgetEnvironmentFixture.register();
  late Map<String, dynamic> translations;
  setUpAll(() async {
    final fonts = FontLoader('Futura')
      ..addFont(rootBundle.load('fonts/Futura PT Book.ttf'))
      ..addFont(rootBundle.load('fonts/Futura PT Medium.ttf'))
      ..addFont(rootBundle.load('fonts/Gill Sans Bold.otf'));
    await fonts.load();
    translations =
        jsonDecode(File('assets/translations/cs.json').readAsStringSync())
            as Map<String, dynamic>;
  });
  WidgetEnvironmentFixture env() => WidgetEnvironmentFixture(
      locale: const Locale('cs'), translations: translations);
  testWidgets(
      'A08 read projection cannot render a payment action without its separate owner',
      (tester) async {
    final fixture = env();
    await fixture.pumpWidget(
        tester,
        MaterialApp(
            home: Scaffold(
                body: CardPaymentStatus(
                    payment: payment('open'), onRefresh: () {}))));
    await tester.pumpAndSettle();
    expect(find.text('Pokračovat k platbě'), findsNothing);
    expect(find.textContaining('soukromý platební odkaz'), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
    expect(find.textContaining('1\u00a0234,50'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'A15/A17/A18 paid delivery failure and refunded states never invite another payment',
      (tester) async {
    final fixture = env();
    for (final state in [
      'paid',
      'refunded',
      'partially_refunded',
      'disputed',
      'action_required',
      'pending',
      'expired'
    ]) {
      await fixture.pumpWidget(
          tester,
          MaterialApp(
              home: Scaffold(
                  body: CardPaymentStatus(
                      payment: {...payment(state), 'deliveryState': 'failed'},
                      onPay: () => fail('cannot pay')))));
      await tester.pumpAndSettle();
      expect(find.byType(FilledButton), findsNothing);
      if (state == 'paid') {
        expect(find.text('Zaplaceno.'), findsOneWidget);
        expect(
            find.textContaining('email se nepodařilo odeslat'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    }
  });
  testWidgets(
      'A24 mobile dark theme at large text keeps amount and long translated copy visible',
      (tester) async {
    tester.view.physicalSize = const Size(320, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fixture = env();
    await fixture.pumpWidget(
        tester,
        MaterialApp(
            theme: ThemeConfig.theme(brightness: Brightness.dark),
            home: RepaintBoundary(
                key: const ValueKey('card-payment-capture'),
                child: MediaQuery(
                    data:
                        const MediaQueryData(textScaler: TextScaler.linear(2)),
                    child: Scaffold(
                        body: SingleChildScrollView(
                            child: CardPaymentStatus(payment: {
                      ...payment('paid'),
                      'deliveryState': 'suppressed'
                    }, onRefresh: () {})))))));
    await tester.pumpAndSettle();
    expect(find.textContaining('email se nepodařilo odeslat'), findsOneWidget);
    expect(tester.takeException(), isNull);
    const directory = String.fromEnvironment('FESTAPP_STRIPE_SCREENSHOT_DIR');
    if (directory.isNotEmpty) {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('card-payment-capture')));
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        try {
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File('$directory/flutter-mobile-dark-large-text.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(data!.buffer.asUint8List());
        } finally {
          image.dispose();
        }
      });
    }
  });
  testWidgets(
      'A15 actual result screen does not celebrate an unconfirmed card payment',
      (tester) async {
    final fixture = env();
    await fixture.pumpWidget(
        tester,
        MaterialApp(
            home: Scaffold(
                body: FinishOrderScreen(
          orderFutureFunction: () async => FunctionResponse(status: 200, data: {
            'code': 200,
            'payment': payment('pending'),
            'ticketOrder': {
              'order': {'order_symbol': 'FIXTURE'}
            }
          }),
        ))));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('Ověřujeme výsledek platby.'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
