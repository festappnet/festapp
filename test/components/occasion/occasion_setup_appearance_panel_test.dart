import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:fstapp/widgets/dependency_material_bridge.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/occasion/setup/occasion_setup_appearance_panel.dart';
import 'package:fstapp/components/_shared/appearance_palettes.dart';
import 'package:fstapp/components/_shared/appearance_color_strings.dart';

import '../../support/fixtures/widget_environment_fixture.dart';

void main() {
  WidgetEnvironmentFixture.register();
  late WidgetEnvironmentFixture environment;
  setUpAll(() async {
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    await (FontLoader('PalettePreview')..addFont(
          Future.value(
            ByteData.sublistView(
              File('supabase/functions/_shared/ticket-assets/font.ttf')
                  .readAsBytesSync(),
            ),
          ),
        ))
        .load();
    environment = WidgetEnvironmentFixture(
      locale: const Locale('cs'),
      translations: jsonDecode(
        File('assets/translations/cs.json').readAsStringSync(),
      ),
    );
  });
  for (final width in [320.0, 390.0, 800.0]) {
    for (final scale in [1.0, 2.0]) {
      for (final brightness in [Brightness.light, Brightness.dark]) {
        testWidgetsWithEnvironment(
          () => environment,
          'shared setup chooser $width $scale $brightness',
          (tester) async {
            tester.view.physicalSize = Size(width, 1100);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final capture = GlobalKey();
            var primary = 0xff263238;
            var secondary = 0xffeceff1;
            var gradient = false;
            var font = 'Roboto';
            late StateSetter update;
            await environment.pumpWidget(
              tester,
              MaterialApp(
                builder: DependencyMaterialBridge.builder,
                theme: ThemeData(
                  brightness: brightness,
                  fontFamily: 'PalettePreview',
                ),
                home: RepaintBoundary(
                  key: capture,
                  child: Scaffold(
                    body: MediaQuery(
                      data: MediaQueryData(
                        textScaler: TextScaler.linear(scale),
                      ),
                      child: StatefulBuilder(
                        builder: (context, setState) {
                          update = setState;
                          return SingleChildScrollView(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: OccasionSetupAppearancePanel(
                                onPresetSelected: (id) => setState(() {
                                  final palette = AppearancePalettes.byId(id);
                                  primary = palette.primary;
                                  secondary = palette.secondary;
                                }),
                                fontFamily: font,
                                fontFamilies: const ['Roboto', 'Roboto Slab'],
                                onFontChanged: (value) =>
                                    setState(() => font = value),
                                primaryColor: Color(primary),
                                secondaryColor: Color(secondary),
                                gradient: gradient,
                                onPrimaryChanged: (color) =>
                                    setState(() => primary = color.toARGB32()),
                                onSecondaryChanged: (color) => setState(
                                  () => secondary = color.toARGB32(),
                                ),
                                onGradientChanged: (value) =>
                                    setState(() => gradient = value),
                                formPreview: const Text(
                                  'Skutečný náhled formuláře',
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final name = AppearancePalettes.byId('form-night').label;
            expect(
              find.text(AppearanceColorStrings.palette(name)),
              findsOneWidget,
            );
            expect(
              find.byKey(const ValueKey('appearance-style-form-night')),
              findsOneWidget,
            );
            expect(find.text('Náš příběh akce'), findsNothing);
            final dropdown = find.byType(DropdownButtonFormField<String>);
            await tester.tap(dropdown);
            await tester.pumpAndSettle();
            await tester.tap(find.text('Roboto Slab').last);
            await tester.pumpAndSettle();
            expect(font, 'Roboto Slab');
            expect(
              find.text(AppearanceColorStrings.palette(name)),
              findsOneWidget,
            );
            final gala = find.byKey(const ValueKey('appearance-style-gala'));
            await tester.ensureVisible(gala);
            await tester.tap(gala);
            await tester.pumpAndSettle();
            expect(font, 'Roboto Slab');
            expect(gradient, false);
            expect(
              find.text(
                AppearanceColorStrings.palette(
                  AppearancePalettes.byId('gala').label,
                ),
              ),
              findsOneWidget,
            );
            update(() {
              primary = 0xff263238;
              secondary = 0xff123456;
              gradient = true;
            });
            await tester.pumpAndSettle();
            expect(find.text(AppearanceColorStrings.custom), findsOneWidget);
            update(() {
              secondary = 0xffeceff1;
            });
            await tester.pumpAndSettle();
            expect(
              find.text(AppearanceColorStrings.palette(name)),
              findsOneWidget,
            );
            if (const bool.fromEnvironment('CAPTURE_PALETTE_UI')) {
              await tester.ensureVisible(
                find.byKey(const ValueKey('appearance-style-status')),
              );
              await tester.pumpAndSettle();
              await tester.runAsync(() async {
                final image =
                    await (capture.currentContext!.findRenderObject()!
                            as RenderRepaintBoundary)
                        .toImage(pixelRatio: 1);
                final bytes = await image.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                final dir = Directory('/tmp/festapp-unified-appearance');
                await dir.create(recursive: true);
                await File(
                  '${dir.path}/wizard-$width-${scale}x-${brightness.name}.png',
                ).writeAsBytes(bytes!.buffer.asUint8List());
                image.dispose();
              });
            }
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
}
