import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/eshop/views/order_customer_payment_details.dart';
import 'package:fstapp/services/time_helper.dart';
import 'package:fstapp/theme_config.dart';
import 'package:fstapp/widgets/dependency_material_bridge.dart';

import '../../support/fixtures/widget_environment_fixture.dart';

void main() {
  WidgetEnvironmentFixture.register();
  setUpAll(() async {
    if (Platform.environment['FESTAPP_PAYMENT_CAPTURE_DIR'] == null) return;
    await (FontLoader('Futura')
          ..addFont(rootBundle.load('fonts/Futura PT Book.ttf'))
          ..addFont(rootBundle.load('fonts/Futura PT Medium.ttf')))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  final bank = {
    'account': '19-2000145399/0800',
    'iban': 'CZ6508000000192000145399',
    'referenceKind': 'VS',
    'reference': '3629',
  };
  Future<void> open(
    WidgetTester tester,
    Map<String, dynamic> details,
    Map<String, dynamic> payment, {
    bool dark = false,
    String currency = 'CZK',
  }) async {
    final previous = TimeHelper.currentTime;
    TimeHelper.currentTime = DateTime.utc(2026, 11, 2, 10);
    addTearDown(() {
      TimeHelper.currentTime = previous;
    });
    await tester.binding.setSurfaceSize(const Size(400, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final environment = WidgetEnvironmentFixture(
      locale: const Locale('cs'),
      translations: jsonDecode(
        File('assets/translations/cs.json').readAsStringSync(),
      ),
    );
    await environment.pumpWidget(
      tester,
      RepaintBoundary(
        key: const ValueKey('payment-capture'),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: const Locale('cs'),
          supportedLocales: const [Locale('cs')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: ThemeConfig.theme(
            brightness: dark ? Brightness.dark : Brightness.light,
          ),
          builder: DependencyMaterialBridge.builder,
          home: Scaffold(
            backgroundColor: ThemeConfig.theme(brightness: dark ? Brightness.dark : Brightness.light).colorScheme.surface,
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: MediaQuery(
                  data: const MediaQueryData(
                    textScaler: TextScaler.linear(1.4),
                  ),
                  child: OrderCustomerPaymentDetails(
                    details: details,
                    payment: payment,
                    currencyCode: currency,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final dark in [false, true]) {
    testWidgets('customer bank instructions fit narrow large text dark=$dark', (
      tester,
    ) async {
      await open(tester, bank, {
        'status': 'partially_paid',
        'dueNow': 300,
        'dueAt': '2026-11-05T10:00:00Z',
      }, dark: dark);
      expect(find.text('19-2000145399/0800'), findsOneWidget);
      expect(find.text('3629'), findsOneWidget);
      expect(find.textContaining('za 3 dny'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final directory = Platform.environment['FESTAPP_PAYMENT_CAPTURE_DIR'];
      if (directory != null)
        await tester.runAsync(() async {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('payment-capture')),
          );
          final picture = await boundary.toImage(pixelRatio: 1);
          final bytes = await picture.toByteData(
            format: ui.ImageByteFormat.png,
          );
          Directory(directory).createSync(recursive: true);
          File('$directory/payment-${dark ? 'dark' : 'light'}.png')
              .writeAsBytesSync(bytes!.buffer.asUint8List());
          picture.dispose();
        });
    });
  }
  testWidgets(
    'paid order retains destination and shows zero due without creating a payment',
    (tester) async {
      await open(tester, bank, {'status': 'fully_paid', 'dueNow': 0});
      expect(find.text('3629'), findsOneWidget);
      expect(find.textContaining(RegExp(r'^0,00\s*Kč$')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('EUR keeps RF reference, not a variable symbol', (tester) async {
    await open(
      tester,
      {...bank, 'referenceKind': 'RF', 'reference': 'RF883629'},
      {'status': 'unpaid', 'dueNow': 10},
      currency: 'EUR',
    );
    expect(find.text('RF883629'), findsOneWidget);
    expect(find.text('Variabilní symbol'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('missing bank projection does not fabricate bank details', (
    tester,
  ) async {
    await open(tester, {}, {'status': 'unknown'});
    expect(find.text('Platební údaje'), findsNothing);
    expect(find.text('Bankovní účet'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
