import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';

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
    Size size = const Size(400, 700),
    double textScale = 1.4,
  }) async {
    final previous = TimeHelper.currentTime;
    TimeHelper.currentTime = DateTime.utc(2026, 11, 2, 10);
    addTearDown(() {
      TimeHelper.currentTime = previous;
    });
    await tester.binding.setSurfaceSize(size);
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
            backgroundColor: ThemeConfig.theme(
              brightness: dark ? Brightness.dark : Brightness.light,
            ).colorScheme.surface,
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: MediaQuery(
                  data: MediaQueryData(
                    textScaler: TextScaler.linear(textScale),
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

  Future<void> capture(WidgetTester tester, String name) async {
    final directory = Platform.environment['FESTAPP_PAYMENT_CAPTURE_DIR'];
    if (directory != null)
      await tester.runAsync(() async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('payment-capture')),
        );
        final picture = await boundary.toImage(pixelRatio: 1);
        final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
        Directory(directory).createSync(recursive: true);
        File('$directory/$name.png')
            .writeAsBytesSync(bytes!.buffer.asUint8List());
        picture.dispose();
      });
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
      await capture(tester, 'payment-${dark ? 'dark' : 'light'}');
    });
  }
  for (final narrow in [false, true]) {
    testWidgets('compact payment rows wrap long bank details narrow=$narrow', (
      tester,
    ) async {
      await open(
        tester,
        {
          ...bank,
          'creditorName': 'Spolek přátel kulturních a společenských akcí',
          'iban': 'DE89370400440532013000',
          'referenceKind': 'RF',
          'reference': 'RF18539007547034',
        },
        {'status': 'unpaid', 'dueNow': 300, 'dueAt': '2026-11-05T10:00:00Z'},
        size: narrow ? const Size(320, 900) : const Size(760, 700),
        textScale: narrow ? 1.6 : 1,
      );
      expect(find.text('DE89370400440532013000'), findsOneWidget);
      expect(find.text('RF18539007547034'), findsOneWidget);
      expect(find.textContaining('za 3 dny'), findsOneWidget);
      final reference = tester.getRect(find.text('RF18539007547034'));
      expect(reference.right, lessThanOrEqualTo(narrow ? 300 : 740));
      expect(tester.takeException(), isNull);
      await capture(tester, narrow ? 'payment-long-narrow' : 'payment-wide');
    });
  }

  testWidgets('paid order retains destination without an amount-to-pay row', (
    tester,
  ) async {
    await open(tester, bank, {'status': 'fully_paid', 'dueNow': 0});
    await capture(tester, 'payment-paid');
    expect(find.text('3629'), findsOneWidget);
    expect(find.textContaining(RegExp(r'^0,00\s*Kč$')), findsNothing);
    expect(find.text('Částka k úhradě:'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('bank details form one selectable region including labels', (
    tester,
  ) async {
    await open(tester, bank, {'status': 'partially_paid', 'dueNow': 300});
    final section = find.byType(OrderCustomerPaymentDetails);
    expect(
      find.descendant(of: section, matching: find.byType(SelectionArea)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: section, matching: find.byType(SelectableText)),
      findsNothing,
    );
  });
  testWidgets(
    'all payment labels and values copy through the shared selection',
    (tester) async {
      String? copied;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData')
              copied = (call.arguments as Map)['text'] as String?;
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      await open(
        tester,
        bank,
        {'status': 'partially_paid', 'dueNow': 300},
        size: const Size(760, 700),
        textScale: 1,
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer();
      await mouse.down(
        tester.getTopLeft(find.text('Platební údaje')) + const Offset(2, 8),
      );
      await mouse.moveTo(tester.getBottomRight(find.text('3629')));
      await mouse.up();
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(copied, contains('Platební údaje'));
      expect(copied, contains('Číslo účtu:'));
      expect(copied, contains('19-2000145399/0800'));
      expect(copied, contains('CZ6508000000192000145399'));
      expect(copied, contains('Variabilní symbol:'));
      expect(copied, contains('3629'));
      await mouse.removePointer();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
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
