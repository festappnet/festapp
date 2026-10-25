import 'package:fstapp/widgets/dependency_material_bridge.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/occasion/setup/occasion_setup_appearance.dart';
import 'package:fstapp/components/occasion/setup/occasion_setup_appearance_panel.dart';
import 'package:fstapp/components/occasion/setup/occasion_setup_ticket_gallery.dart';
import 'package:fstapp/components/ticket_layout/ticket_layout_service.dart';
import 'package:fstapp/components/ticket_layout/ticket_preview_assets.dart';
import 'package:fstapp/components/ticket_layout/views/ticket_layout_canvas.dart';
import 'package:fstapp/theme_config.dart';
import 'package:fstapp/components/fonts/ticket_font_ids.dart';
import 'package:fstapp/components/ticket_layout/models/ticket_layout.dart';
import 'package:fstapp/components/ticket_layout/ticket_text.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import '../../support/fixtures/widget_environment_fixture.dart';

void main() {
  WidgetEnvironmentFixture.register();
  setUpAll(() async {
    await (FontLoader('Futura')
          ..addFont(rootBundle.load('fonts/Futura PT Book.ttf')))
        .load();
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
  });
  final environment = WidgetEnvironmentFixture(
      locale: const Locale('cs'),
      translations:
          jsonDecode(File('assets/translations/cs.json').readAsStringSync())
              as Map<String, dynamic>);

  Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
    const path = String.fromEnvironment('UI_SCREENSHOT_DIR');
    if (path.isEmpty) return;
    final boundary =
        key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = (await tester.runAsync(() => boundary.toImage()))!;
    final bytes = (await tester
        .runAsync(() => image.toByteData(format: ui.ImageByteFormat.png)))!;
    Directory(path).createSync(recursive: true);
    File('$path/$name.png').writeAsBytesSync(bytes.buffer.asUint8List());
    image.dispose();
  }

  testWidgets(
      'thumbnail recoloring is bounded and cache handles survive disposal',
      (tester) async {
    await tester.runAsync(() async {
      final url = OccasionSetupAppearance.ticketBackground(
          'concert_stub', OccasionSetupAppearance.presets[1])!;
      final assets = TicketPreviewAssets();
      final timer = Stopwatch()..start();
      final thumbnail = (await assets.image(url, maxWidth: 640))!;
      expect(thumbnail.width, lessThanOrEqualTo(640));
      final elapsed = timer.elapsedMilliseconds;
      final clone = (await assets.image(url, maxWidth: 640))!;
      thumbnail.dispose();
      expect(await clone.toByteData(), isNotNull);
      clone.dispose();
      final full = (await assets.image(url))!;
      expect(full.width, greaterThan(640));
      // ignore: avoid_print
      print(
          'Recolored thumbnail: ${elapsed}ms, 640px; full artwork: ${full.width}x${full.height}');
      full.dispose();
    });
  });

  testWidgets(
      'gallery retains prepared painters across parent rebuild and scroll',
      (tester) async {
    final fixture = jsonDecode(
            File('test/fixtures/ticket_layout/resolve.json').readAsStringSync())
        as Map;
    final template = TicketTemplate.fromJson(fixture['template']);
    final metrics = TicketFontMetrics.fromJson(fixture['metrics']);
    final resources = TicketLayoutResources(
        template: template,
        preset: template,
        presets: {'first': template},
        metrics: metrics,
        fonts: legacyTicketFontIds.map((name, id) => MapEntry(
            id, TicketFontResource(id, name, 400, metrics, 'TestFont'))),
        scenarios: (fixture['scenarios'] as Map).map((k, v) =>
            MapEntry(k as String, (v as Map).cast<String, String?>())),
        qrSize: fixture['qrMatrix']['size'],
        qrModules: (fixture['qrMatrix']['data'] as List).cast<int>());
    final rebuild = ValueNotifier(0);
    await environment.pumpWidget(
        tester,
        MaterialApp(builder: DependencyMaterialBridge.builder,
            home: Scaffold(
          body: ValueListenableBuilder<int>(
            valueListenable: rebuild,
            builder: (context, value, _) => SingleChildScrollView(
                child: OccasionSetupTicketGallery(
              loadResources: () async => resources,
              appearance: Map.of(OccasionSetupAppearance.presets.first),
              onSelected: (_) {},
            )),
          ),
        )));
    await tester.pumpAndSettle();
    final painters = find
        .byType(CustomPaint)
        .evaluate()
        .map((e) => (e.widget as CustomPaint).painter)
        .whereType<TicketLayoutPainter>()
        .toList();
    expect(painters, isNotEmpty);
    final controllers = painters.map((p) => p.controller).toList();
    rebuild.value++;
    await tester.pumpAndSettle();
    final updated = find
        .byType(CustomPaint)
        .evaluate()
        .map((e) => (e.widget as CustomPaint).painter)
        .whereType<TicketLayoutPainter>()
        .toList();
    expect(updated.map((p) => p.controller), orderedEquals(controllers));
    await tester.drag(
        find.byType(SingleChildScrollView), const Offset(0, -220));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    rebuild.dispose();
  });

  for (final size in [const Size(1200, 1100), const Size(375, 900)]) {
    testWidgets(
        'appearance choices and template picker render at ${size.width}',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fonts = <String, TicketFontResource>{};
      await tester.runAsync(() async {
        final bundled =
            (await TicketPreviewAssets.shared.manifest)['fonts'] as Map;
        for (final entry in OccasionSetupAppearance.fonts.entries) {
          if (bundled.containsKey(entry.value)) {
            fonts[entry.key] = await TicketLayoutService().font(0, entry.value);
          }
        }
      });
      final key = GlobalKey();
      await environment.pumpWidget(
        tester,
        RepaintBoundary(
            key: key,
            child: MaterialApp(builder: DependencyMaterialBridge.builder,
                debugShowCheckedModeBanner: false,
                locale: const Locale('cs'),
                supportedLocales: VenueLayoutLocalizations.supportedLocales,
                localizationsDelegates:
                    [...VenueLayoutLocalizations.localizationsDelegates, ...GlobalMaterialLocalizations.delegates],
                theme: ThemeConfig.theme(brightness: Brightness.dark),
                home: Scaffold(
                    body: SingleChildScrollView(
                        child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: OccasionSetupAppearancePanel(
                    presets: [
                      for (final p in OccasionSetupAppearance.presets)
                        OccasionSetupAppearancePreset(
                            id: p['id'],
                            label: p['label'],
                            primaryColor: Color(
                                int.parse('FF${p['primary']}', radix: 16)),
                            secondaryColor: Color(
                                int.parse('FF${p['secondary']}', radix: 16)),
                            gradient: p['gradient'],
                            fontFamily: p['fontFamily'])
                    ],
                    selectedPresetId: 'gala',
                    onPresetSelected: (_) {},
                    fontFamily: 'Roboto',
                    fontFamilies: OccasionSetupAppearance.fonts.keys.toList(),
                    onFontChanged: (_) {},
                    fontStyle: (family, base) => base.copyWith(
                        fontFamily: fonts[family]?.loaderName ??
                            fonts['Roboto']!.loaderName),
                    primaryColor: Colors.blue,
                    secondaryColor: Colors.amber,
                    gradient: true,
                    onPrimaryChanged: (_) {},
                    onSecondaryChanged: (_) {},
                    onGradientChanged: (_) {},
                    formPreview: Builder(
                        builder: (context) => TextButton(
                            onPressed: () =>
                                showVenueLayoutTemplateGallery(context),
                            child: const Text('Open templates'))),
                  ),
                ))))),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('appearance-preset-cream')),
          findsOneWidget);
      expect(tester.takeException(), isNull);
      await capture(tester, key, 'appearance-${size.width.toInt()}');
      await tester.ensureVisible(find.text('Open templates'));
      await tester.tap(find.text('Open templates'));
      await tester.pumpAndSettle();
      expect(
          find.byKey(const ValueKey('layout-template-blank')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await capture(tester, key, 'templates-${size.width.toInt()}');
      await tester.tap(find.byKey(const ValueKey('layout-template-blank')));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
    });
  }
}
