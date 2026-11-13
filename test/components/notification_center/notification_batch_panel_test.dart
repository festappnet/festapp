import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fstapp/components/notification_center/notification_center_controller.dart';
import 'package:fstapp/components/notification_center/notification_center_panel.dart';
import 'package:fstapp/components/notification_center/notification_item_presenter.dart';
import 'package:fstapp/theme_config.dart';
import 'package:fstapp/widgets/dependency_material_bridge.dart';

class _Translations extends AssetLoader {
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      jsonDecode(File('assets/translations/cs.json').readAsStringSync())
          as Map<String, dynamic>;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    final font = FontLoader(ThemeConfig.fontFamily);
    for (final file in [
      'fonts/Futura PT Book.ttf',
      'fonts/Futura PT Medium.ttf',
    ]) {
      font.addFont(
        Future.value(ByteData.sublistView(File(file).readAsBytesSync())),
      );
    }
    await font.load();
  });
  testWidgets(
    'email controls use the existing settings panel and save the selected scope',
    (tester) async {
      tester.view.physicalSize = const Size(390, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final saves = <Map<String, dynamic>>[];
      var revision = 0;
      var selected = <String, dynamic>{
        'email_problem': {'enabled': true},
        'payment_problem': {'enabled': false},
      };
      final controller = NotificationCenterController(
        read: (name, params) async {
          if (name == 'save_notification_center_email_settings') {
            saves.add(Map<String, dynamic>.from(params));
            selected = {
              for (final entry in (params['p_kinds'] as Map).entries)
                entry.key.toString(): {'enabled': entry.value},
            };
            return ++revision;
          }
          return {
            'items': [
              {'id': 12, 'title': 'Ples hasičů', 'muted': false},
            ],
            'email': {
              'revision': revision,
              'windowSeconds': 300,
              'stopped': false,
              'locale': 'cs',
              'catalog': {
                'order_created': 'orders',
                'bank_problem': 'problems',
                'provider_problem': 'problems',
                'email_problem': 'problems',
                'payment_problem': 'problems',
              },
              'requiredKinds': ['bank_problem', 'provider_problem'],
              'kinds': selected,
            },
          };
        },
      );
      addTearDown(controller.dispose);
      controller.organization = 7;
      controller.user = 'current-user';
      const imageKey = ValueKey('email-settings-light');
      await tester.pumpWidget(
        EasyLocalization(
          supportedLocales: const [Locale('cs')],
          startLocale: const Locale('cs'),
          path: 'assets/translations',
          assetLoader: _Translations(),
          child: Builder(
            builder: (context) => RepaintBoundary(
              key: imageKey,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                builder: DependencyMaterialBridge.builder,
                theme: ThemeConfig.theme(brightness: Brightness.light),
                locale: context.locale,
                supportedLocales: context.supportedLocales,
                localizationsDelegates: [
                  ...context.localizationDelegates,
                  ...GlobalMaterialLocalizations.delegates,
                ],
                home: Scaffold(
                  body: NotificationCenterPanel(
                    controller: controller,
                    onDetail: (_) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.tune));
      await tester.pumpAndSettle();
      final assignment = NotificationItem.fromJson({
        'id': 'payment-assignment',
        'kind': 'order_payment_received',
        'occurredAt': DateTime.now().toIso8601String(),
        'data': {'reassigned': true},
      });
      expect(
        NotificationItemPresenter(assignment).title,
        'Přiřazení přijaté platby',
      );
      final changes = NotificationItem.fromJson({
        'id': 'payment-group',
        'kind': 'order_payment_received',
        'occurredAt': DateTime.now().toIso8601String(),
        'data': {'activityCount': 2},
      });
      expect(
        NotificationItemPresenter(changes, locale: 'cs').title,
        'Změny plateb: 2',
      );
      expect(find.text('Volitelné e-mailové souhrny'), findsOneWidget);
      expect(
        find.text(
          'Jednou za 5 minut jeden souhrn. Přepínač platí pro Váš účet napříč portály.',
        ),
        findsOneWidget,
      );
      expect(find.text('Vždy zapnuto'), findsNWidgets(2));
      expect(find.text('Problémy platebních bran'), findsOneWidget);
      final gateway = NotificationItem.fromJson({
        'id': 'gateway-incident',
        'kind': 'provider_problem',
        'occurredAt': DateTime.now().toIso8601String(),
        'data': {
          'unitId': 10,
          'title': 'Stripe',
          'reason': 'provider_restricted',
        },
      });
      expect(NotificationItemPresenter(gateway).isError, true);
      expect(NotificationItemPresenter(gateway).hasDetail, true);
      expect(
        NotificationItemPresenter(gateway).title,
        'Problém platební brány',
      );
      expect(find.text('Bankovní problémy'), findsOneWidget);
      final categories = tester
          .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
          .toList();
      expect(categories.map((tile) => tile.value), contains(null));
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Objednávky'));
      await tester.pumpAndSettle();
      expect(saves.single['p_kinds'], {
        'order_created': true,
        'email_problem': true,
        'payment_problem': false,
      });
      expect(saves.single.containsKey('recipient'), false);
      expect(saves.single.containsKey('p_occasion'), false);
      expect(find.byType(DropdownButton<int>), findsNothing);
      expect(tester.takeException(), isNull);
      const capturePath = String.fromEnvironment('NOTIFICATION_CAPTURE_DIR');
      if (capturePath.isNotEmpty) {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(imageKey),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          File('$capturePath/email-settings-light.png')
              .writeAsBytesSync(data!.buffer.asUint8List());
          image.dispose();
        });
      }
    },
  );
  for (final width in [390.0, 1000.0]) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'real batch panel keeps history and prioritizes unread at $width ${brightness.name}',
        (tester) async {
          tester.view.physicalSize = Size(width, 1000);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final controller = NotificationCenterController(
            read: (_, _) async => true,
          );
          addTearDown(controller.dispose);
          controller.snapshot = 42;
          NotificationItem row(String id, bool read, int count) =>
              NotificationItem.fromJson({
                'id': id,
                'isRead': read,
                'isSeen': true,
                'sequence': 40,
                'occasionId': 1,
                'occasionTitle': 'Ples AKH 2026',
                'occasionLink': 'fixture',
                'kind': 'order_created',
                'occurredAt': DateTime.now().toUtc().toIso8601String(),
                'data': {
                  'activityCount': count,
                  'placeCount': count + 2,
                  'relatedOrders': true,
                  'previewContacts': [
                    {'name': 'Filip', 'surname': 'Konzal'},
                    {'name': 'Jana', 'surname': 'Nováková'},
                    {'name': 'Štěpánka', 'surname': 'Juránková'},
                  ].take(count).toList(),
                },
              });
          controller.items = [row('read', true, 20), row('unread', false, 2)];
          NotificationItem? followed;
          const imageKey = ValueKey('batch-preview-image');
          await tester.pumpWidget(
            EasyLocalization(
              supportedLocales: const [Locale('cs')],
              startLocale: const Locale('cs'),
              path: 'assets/translations',
              assetLoader: _Translations(),
              child: Builder(
                builder: (context) => RepaintBoundary(
                  key: imageKey,
                  child: MaterialApp(
                    debugShowCheckedModeBanner: false,
                    builder: DependencyMaterialBridge.builder,
                    theme: ThemeConfig.theme(brightness: brightness),
                    locale: context.locale,
                    supportedLocales: context.supportedLocales,
                    localizationsDelegates: [
                      ...context.localizationDelegates,
                      ...GlobalMaterialLocalizations.delegates,
                    ],
                    home: Scaffold(
                      body: NotificationCenterPanel(
                        controller: controller,
                        onDetail: (item) => followed = item,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final unread = find.byKey(const ValueKey('notification-item-unread'));
          final read = find.byKey(const ValueKey('notification-item-read'));
          expect(
            tester.getTopLeft(unread).dy,
            lessThan(tester.getTopLeft(read).dy),
          );
          expect(find.text('Nepřečtené'), findsOneWidget);
          expect(find.text('Přečtené'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.tap(unread);
          expect(followed?.id, 'unread');
          // The panel retains its viewport and offset while polling and visiting
          // settings, including in a narrow centered dialog.
          controller.items = List.generate(
            30,
            (i) => row('history-$i', true, 1),
          );
          controller.notifyListeners();
          await tester.pumpAndSettle();
          final feed = find.byKey(const PageStorageKey('notification-feed'));
          await tester.drag(feed, const Offset(0, -350));
          await tester.pumpAndSettle();
          final scroll = tester.widget<ListView>(feed).controller!;
          final offset = scroll.offset;
          final bounds = tester.getRect(feed);
          expect(offset, greaterThan(100));
          controller.loading = true;
          controller.notifyListeners();
          await tester.pump();
          expect(scroll.offset, offset);
          expect(tester.getRect(feed), bounds);
          controller.loading = false;
          controller.notifyListeners();
          await tester.tap(find.byIcon(Icons.tune));
          await tester.pumpAndSettle();
          await tester.tap(find.byIcon(Icons.arrow_back));
          await tester.pumpAndSettle();
          expect(tester.widget<ListView>(feed).controller!.offset, offset);
          expect(tester.getRect(feed), bounds);

          const capturePath = String.fromEnvironment(
            'NOTIFICATION_CAPTURE_DIR',
          );
          if (capturePath.isNotEmpty && brightness == Brightness.light) {
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(imageKey),
            );
            await tester.runAsync(() async {
              final image = await boundary.toImage(pixelRatio: 1);
              final data = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              File('$capturePath/panel-${width.toInt()}-${brightness.name}.png')
                  .writeAsBytesSync(data!.buffer.asUint8List());
              image.dispose();
            });
          }
        },
      );
    }
  }
}
