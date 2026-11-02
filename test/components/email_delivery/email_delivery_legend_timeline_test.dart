import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/email_delivery/email_delivery_history.dart';
import 'package:fstapp/components/email_delivery/email_delivery_model.dart';
import 'package:fstapp/components/email_delivery/email_delivery_status_help.dart';
import 'package:fstapp/components/eshop/order_detail_strings.dart';
import 'package:fstapp/theme_config.dart';
import 'package:fstapp/widgets/dependency_material_bridge.dart';

import '../../support/fixtures/widget_environment_fixture.dart';

void main() {
  WidgetEnvironmentFixture.register();
  setUpAll(() async {
    if (Platform.environment['FESTAPP_EMAIL_CAPTURE_DIR'] == null) return;
    await (FontLoader('Futura')
          ..addFont(rootBundle.load('fonts/Futura PT Book.ttf'))
          ..addFont(rootBundle.load('fonts/Futura PT Medium.ttf')))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  Map<String, dynamic> row(
    int id,
    String state, {
    String kind = 'order_reminder',
    String? error,
    bool submitted = false,
  }) => {
    'id': id,
    'message_id': 'message-$id',
    'order_id': 42,
    'message_kind': kind,
    'state': state,
    'last_error': error,
    if (submitted) 'accepted_at': '2026-10-11T13:56:00Z',
    'recipient': 'host@example.invalid',
    'created_at': '2026-10-11T12:43:00Z',
  };

  Future<void> open(
    WidgetTester tester,
    Widget child, {
    bool dark = false,
  }) async {
    await tester.binding.setSurfaceSize(const Size(420, 800));
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
        key: const ValueKey('email-capture'),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: const Locale('cs'),
          supportedLocales: const [Locale('cs')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          themeMode: dark ? ThemeMode.dark : ThemeMode.light,
          theme: ThemeConfig.theme(brightness: Brightness.light),
          darkTheme: ThemeConfig.theme(brightness: Brightness.dark),
          builder: DependencyMaterialBridge.builder,
          home: Scaffold(body: child),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> capture(WidgetTester tester, String name) async {
    final directory = Platform.environment['FESTAPP_EMAIL_CAPTURE_DIR'];
    if (directory == null) return;
    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('email-capture')),
      );
      final picture = await boundary.toImage(pixelRatio: 1);
      final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
      Directory(directory).createSync(recursive: true);
      File('$directory/$name.png')
          .writeAsBytesSync(bytes!.buffer.asUint8List());
      picture.dispose();
    });
  }

  testWidgets(
    'order timeline omits only unsent superseded reminder schedules and retains audit rows',
    (tester) async {
      final rows = [
        row(7, 'cancelled', error: 'reminder_superseded'),
        row(6, 'accepted', submitted: true),
        row(5, 'cancelled', error: 'reminder_superseded'),
        row(4, 'open', kind: 'order_confirmation', submitted: true),
        row(3, 'dead'),
        row(2, 'cancelled', kind: 'order_tickets'),
        row(1, 'cancelled', error: 'reminder_superseded', submitted: true),
      ];
      Future<dynamic> read(String name, Map<String, dynamic> args) async {
        expect(name, 'get_email_delivery_page');
        expect(args['p_order'], 42);
        return rows;
      }

      final audit = await EmailDeliveryModel.loadHistory(read, {'p_order': 42});
      expect(audit.length, 7);
      expect(audit.where((m) => m.isSupersededReminderPlan).length, 2);
      await open(
        tester,
        SingleChildScrollView(
          child: EmailDeliveryTimeline(occasionId: 71, orderId: 42, read: read),
        ),
      );
      expect(find.byType(ExpansionTile), findsNWidgets(5));
      expect(find.text('Připomínka platby'), findsNWidgets(3));
      expect(find.textContaining('Zrušeno'), findsNWidgets(2));
      expect(
        find.textContaining('Zprávu se nepodařilo odeslat'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await capture(tester, 'timeline');
    },
  );

  testWidgets(
    'superseded schedule remains reachable through an explicit message target',
    (tester) async {
      await open(
        tester,
        EmailDeliveryTimeline(
          occasionId: 71,
          orderId: 42,
          messageId: 'message-1',
          read: (name, args) async {
            if (name == 'get_email_delivery_page')
              return [row(1, 'cancelled', error: 'reminder_superseded')];
            expect(name, 'get_email_delivery_detail');
            return {
              'message': {'tracking_policy': 'disabled'},
              'attempts': [],
              'events': [],
            };
          },
        ),
      );
      expect(find.byType(ExpansionTile), findsOneWidget);
      expect(find.textContaining('Zrušeno'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final dark in [false, true]) {
    testWidgets('visual tooltip uses actual grid icons dark=$dark', (
      tester,
    ) async {
      await open(
        tester,
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                EmailDeliveryStatusHelp(
                  label: OrderDetailStrings.text('vyznam_stavu_a_diagnostiky'),
                  message: OrderDetailStrings.text('email_status_help'),
                  note: OrderDetailStrings.text(
                    'doruceni_postovnimu_serveru_neoveruje_totoznost_ani_precteni_otevreni_a_kliknuti_mohou_vzniknout_automaticky',
                  ),
                ),
                Expanded(
                  child: Text(
                    OrderDetailStrings.text('vyznam_stavu_a_diagnostiky'),
                  ),
                ),
              ],
            ),
          ),
        ),
        dark: dark,
      );
      await tester.tap(find.byIcon(Icons.info_outline));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('email-delivered-check')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('email-opened-checks')), findsOneWidget);
      expect(find.byIcon(Icons.forward_to_inbox), findsOneWidget);
      expect(find.byIcon(Icons.mark_email_unread_outlined), findsNWidgets(2));
      expect(find.textContaining('Zaznamenáno otevření'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await capture(tester, 'legend-${dark ? 'dark' : 'light'}');
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
