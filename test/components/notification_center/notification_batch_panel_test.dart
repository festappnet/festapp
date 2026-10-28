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
import 'package:fstapp/theme_config.dart';
import 'package:fstapp/widgets/dependency_material_bridge.dart';

class _Translations extends AssetLoader {
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      jsonDecode(File('assets/translations/cs.json').readAsStringSync()) as Map<String, dynamic>;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    final icons = FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    final font = FontLoader(ThemeConfig.fontFamily);
    for (final file in ['fonts/Futura PT Book.ttf', 'fonts/Futura PT Medium.ttf']) {
      font.addFont(Future.value(ByteData.sublistView(File(file).readAsBytesSync())));
    }
    await font.load();
  });
  for (final width in [390.0, 1000.0]) {
    for (final brightness in Brightness.values) {
      testWidgets('real batch panel keeps history and prioritizes unread at $width ${brightness.name}', (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final controller = NotificationCenterController(read: (_, __) async => true);
        addTearDown(controller.dispose);
        controller.snapshot = 42;
        NotificationItem row(String id, bool read, int count) => NotificationItem.fromJson({
          'id': id, 'isRead': read, 'isSeen': true, 'sequence': 40,
          'occasionId': 1, 'occasionTitle': 'Ples AKH 2026', 'occasionLink': 'fixture',
          'kind': 'order_created', 'occurredAt': DateTime.now().toUtc().toIso8601String(),
          'data': {'activityCount': count, 'placeCount': count + 2, 'relatedOrders': true,
            'previewContacts': [{'name':'Filip','surname':'Konzal'},{'name':'Jana','surname':'Nováková'},{'name':'Štěpánka','surname':'Juránková'}]},
        });
        controller.items = [row('read', true, 20), row('unread', false, 2)];
        NotificationItem? followed;
        const imageKey = ValueKey('batch-preview-image');
        await tester.pumpWidget(EasyLocalization(
          supportedLocales: const [Locale('cs')], startLocale: const Locale('cs'),
          path: 'assets/translations', assetLoader: _Translations(),
          child: Builder(builder: (context) => RepaintBoundary(key: imageKey,
            child: MaterialApp(debugShowCheckedModeBanner: false,
              builder: DependencyMaterialBridge.builder,
              theme: ThemeConfig.theme(brightness: brightness), locale: context.locale,
              supportedLocales: context.supportedLocales,
              localizationsDelegates: [...context.localizationDelegates, ...GlobalMaterialLocalizations.delegates],
              home: Scaffold(body: NotificationCenterPanel(controller: controller, onDetail: (item) => followed = item)),
            ),
          )),
        ));
        await tester.pumpAndSettle();
        final unread = find.byKey(const ValueKey('notification-item-unread'));
        final read = find.byKey(const ValueKey('notification-item-read'));
        expect(tester.getTopLeft(unread).dy, lessThan(tester.getTopLeft(read).dy));
        expect(find.text('Nepřečtené'), findsOneWidget);
        expect(find.text('Přečtené'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(unread);
        expect(followed?.id, 'unread');
        const capturePath = String.fromEnvironment('NOTIFICATION_CAPTURE_DIR');
        if (capturePath.isNotEmpty) {
          final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(imageKey));
          await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 1);
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            File('$capturePath/panel-${width.toInt()}-${brightness.name}.png').writeAsBytesSync(data!.buffer.asUint8List());
            image.dispose();
          });
        }
      });
    }
  }
}
