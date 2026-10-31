import 'package:fstapp/components/_shared/appearance_palettes.dart';

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/fonts/form_font_catalog.dart';
import 'package:fstapp/components/forms/form_strings.dart';
import 'package:fstapp/components/_shared/appearance_color_strings.dart';
import 'package:fstapp/components/forms/models/form_editor_draft.dart';
import 'package:fstapp/components/forms/views/form_design_settings.dart';
import 'package:fstapp/components/occasion/setup/occasion_setup_appearance.dart';
import 'package:fstapp/widgets/dependency_material_bridge.dart';

import '../../support/fixtures/widget_environment_fixture.dart';

class _Fonts implements FormFontCatalog {
  @override
  List<String> get families => ['Roboto', 'Roboto Slab'];
  @override
  Future<void> ensureFamily(String family) async {}
  @override
  TextStyle getFont(String family) => TextStyle(fontFamily: family);
  @override
  Future<TextStyle> previewStyle(String family) async => getFont(family);
  @override
  TextTheme getTextTheme(String family, TextTheme base) => base;
}

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

  test('legacy one-color form has no invented secondary or mode override', () {
    final form = FormEditorDraft();
    form.definition = form.definition.withPrimaryColor(0xff216445);
    final before = form.toEditedJson();
    final appearance = OccasionSetupAppearance.read({
      'formDraft': form.definition.toJson(),
    });
    expect(appearance['primary'], '216445');
    expect(appearance['secondary'], '216445');
    expect(appearance['gradient'], false);
    expect(form.definition.backgroundMode, isNull);
    expect(form.definition.secondaryColor, isNull);
    expect(form.toEditedJson(), before);
  });

  testWidgetsWithEnvironment(
    () => environment,
    'form appearance edits use the draft and respect read-only mode',
    (tester) async {
      final form = FormEditorDraft();
      var changes = 0;
      Future<void> mount(bool enabled) async {
        await environment.pumpWidget(
          tester,
          MaterialApp(
            builder: DependencyMaterialBridge.builder,
            home: Scaffold(
              body: FormDesignSettings(
                form: form,
                enabled: enabled,
                onChanged: () => changes++,
                loadFonts: () async => _Fonts(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await mount(true);
      expect(
        tester
            .widget<ChoiceChip>(find.byKey(const ValueKey('form-theme-system')))
            .selected,
        isTrue,
      );
      for (final mode in ['dark', 'light', 'system']) {
        await tester.tap(find.byKey(ValueKey('form-theme-$mode')));
        await tester.pumpAndSettle();
        expect(form.toEditedJson()['settings']['design']['theme_mode'], mode);
      }
      expect(changes, 3);
      await mount(false);
      expect(
        tester
            .widget<ChoiceChip>(find.byKey(const ValueKey('form-theme-dark')))
            .onSelected,
        isNull,
      );
    },
  );
  testWidgetsWithEnvironment(
    () => environment,
    'form editor round-trips one and two colors to the wizard',
    (tester) async {
      final form = FormEditorDraft();
      form.definition = form.definition
          .withPrimaryColor(0xff14284b)
          .withSecondaryColor(0xffa87f28)
          .withFontFamily('Roboto Slab')
          .withBackgroundMode('gradient');
      var changes = 0;
      await environment.pumpWidget(
        tester,
        MaterialApp(
          builder: DependencyMaterialBridge.builder,
          home: Scaffold(
            body: FormDesignSettings(
              form: form,
              onChanged: () => changes++,
              loadFonts: () async => _Fonts(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(form.definition.primaryColor, 0xff14284b);
      expect(form.definition.secondaryColor, 0xffa87f28);
      expect(form.definition.fontFamily, 'Roboto Slab');
      expect(form.definition.backgroundMode, 'gradient');
      expect(
        form.toEditedJson()['settings']['design']['background_mode'],
        'gradient',
      );
      final draft = <String, dynamic>{
        'appearance': {...OccasionSetupAppearance.presets.first},
        'formDraft': form.definition.toJson(),
      };
      final appearance = OccasionSetupAppearance.read(draft);
      expect(appearance['primary'], '14284B');
      expect(appearance['secondary'], 'A87F28');
      expect(appearance['fontFamily'], 'Roboto Slab');
      expect(appearance['gradient'], true);
      final toggle = find.widgetWithText(
        SwitchListTile,
        AppearanceColorStrings.gradient,
      );
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(form.definition.backgroundMode, 'solid');
      expect(
        form.toEditedJson()['settings']['design']['background_mode'],
        'solid',
      );
      expect(form.definition.secondaryColor, 0xffa87f28);
      expect(find.text(AppearanceColorStrings.second), findsNothing);
      Future<void> pick(String id, String hex) async {
        final control = find.byKey(ValueKey('appearance-color-$id'));
        await tester.ensureVisible(control);
        await tester.tap(control);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextField, FormStrings.hexCodeLabel),
          hex,
        );
        await tester.tap(find.text(FormStrings.buttonGotIt));
        await tester.pumpAndSettle();
      }

      await pick('primary', '#216445');
      expect(form.definition.primaryColor, 0xff216445);
      expect(form.definition.secondaryColor, 0xffa87f28);

      draft['formDraft'] = form.definition.toJson();
      final solid = OccasionSetupAppearance.read(draft);
      expect(solid['gradient'], false);
      expect(solid['primary'], '216445');
      expect(solid['secondary'], 'A87F28');
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(form.definition.backgroundMode, 'gradient');
      expect(form.definition.secondaryColor, 0xffa87f28);
      expect(find.text(AppearanceColorStrings.second), findsOneWidget);
      await pick('secondary', '#146475');
      expect(form.definition.secondaryColor, 0xff146475);
      draft['formDraft'] = form.definition.toJson();
      final gradient = OccasionSetupAppearance.read(draft);
      expect(gradient['primary'], '216445');
      expect(gradient['secondary'], '146475');
      expect(gradient['gradient'], true);
      expect(changes, greaterThanOrEqualTo(4));
      expect(tester.takeException(), isNull);
    },
  );
  for (final width in [320.0, 390.0, 800.0]) {
    for (final scale in [1.0, 2.0]) {
      for (final brightness in [Brightness.light, Brightness.dark]) {
        testWidgetsWithEnvironment(
          () => environment,
          'palette state, keyboard and layout at $width / $scale / $brightness',
          (tester) async {
            tester.view.physicalSize = Size(width, 1100);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final capture = GlobalKey();
            final form = FormEditorDraft();
            // A previously selected palette outside the first six is discoverable.
            form.definition = form.definition
                .withPrimaryColor(0xff5d4037)
                .withSecondaryColor(0xff123456)
                .withBackgroundMode('solid');
            Future<void> mount() async {
              await environment.pumpWidget(
                tester,
                MaterialApp(
                  builder: DependencyMaterialBridge.builder,
                  theme: ThemeData(
                    fontFamily: 'PalettePreview',
                    brightness: brightness,
                    primaryColor: const Color(0xff116655),
                  ),
                  home: RepaintBoundary(
                    key: capture,
                    child: Scaffold(
                      body: MediaQuery(
                        data: MediaQueryData(
                          textScaler: TextScaler.linear(scale),
                        ),
                        child: FormDesignSettings(
                          form: form,
                          onChanged: () {},
                          loadFonts: () async => _Fonts(),
                        ),
                      ),
                    ),
                  ),
                ),
              );
              await tester.pumpAndSettle();
            }

            Future<void> screenshot(String state) async {
              if (!const bool.fromEnvironment('CAPTURE_PALETTE_UI') ||
                  width == 320) {
                return;
              }
              await tester.ensureVisible(
                find.byKey(const ValueKey('appearance-style-status')),
              );
              await tester.pumpAndSettle();
              await tester.runAsync(() async {
                final boundary =
                    capture.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary;
                final image = await boundary.toImage(pixelRatio: 1);
                final bytes = await image.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                final dir = Directory('/tmp/festapp-unified-appearance');
                await dir.create(recursive: true);
                await File(
                  '${dir.path}/palette-$state-$width-${scale}x-${brightness.name}.png',
                ).writeAsBytes(bytes!.buffer.asUint8List());
                image.dispose();
              });
            }

            await mount();
            expect(
              find.text(
                AppearanceColorStrings.palette(
                  AppearancePalettes.byId('form-cozy').label,
                ),
              ),
              findsOneWidget,
            );
            final cozy = find.byKey(
              const ValueKey('appearance-style-form-cozy'),
            );
            expect(cozy, findsOneWidget);
            final swatches = tester
                .widgetList<Container>(
                  find.descendant(of: cozy, matching: find.byType(Container)),
                )
                .map((w) => w.decoration)
                .whereType<BoxDecoration>();
            expect(swatches.where((d) => d.gradient != null), isEmpty);
            expect(find.text(FormStrings.customColors), findsNothing);
            // Native palette buttons participate in keyboard traversal.
            var selectedByKeyboard = false;
            for (var i = 0; i < 12 && !selectedByKeyboard; i++) {
              await tester.sendKeyEvent(LogicalKeyboardKey.tab);
              await tester.pump();
              final focus = FocusManager.instance.primaryFocus;
              if (focus?.context
                      ?.findAncestorWidgetOfExactType<ChoiceChip>()
                      ?.key ==
                  const ValueKey('appearance-style-clean')) {
                await tester.sendKeyEvent(LogicalKeyboardKey.enter);
                await tester.pumpAndSettle();
                selectedByKeyboard = true;
              }
            }
            expect(selectedByKeyboard, true);
            expect(
              find.text(
                AppearanceColorStrings.palette(
                  AppearancePalettes.byId('clean').label,
                ),
              ),
              findsOneWidget,
            );
            expect(form.definition.backgroundMode, 'solid');
            final primary = find.byKey(
              const ValueKey('appearance-color-primary'),
            );
            await tester.ensureVisible(primary);
            await tester.tap(primary);
            await tester.pumpAndSettle();
            await tester.enterText(
              find.widgetWithText(TextField, FormStrings.hexCodeLabel),
              '#123456',
            );
            await tester.tap(find.text(FormStrings.buttonGotIt));
            await tester.pumpAndSettle();
            expect(find.text(AppearanceColorStrings.custom), findsOneWidget);
            await screenshot('custom');
            // Returning to a stored palette color restores its name without stored IDs.
            form.definition = form.definition.withPrimaryColor(0xff263238);
            await tester.pumpWidget(const SizedBox.shrink());
            await mount();
            expect(
              find.text(
                AppearanceColorStrings.palette(
                  AppearancePalettes.byId('form-night').label,
                ),
              ),
              findsOneWidget,
            );
            await screenshot('selected');
            form.definition = form.definition.withBackgroundMode('gradient');
            await tester.pumpWidget(const SizedBox.shrink());
            await mount();
            expect(find.text(AppearanceColorStrings.custom), findsOneWidget);
            form.definition = form.definition.withSecondaryColor(0xffeceff1);
            await tester.pumpWidget(const SizedBox.shrink());
            await mount();
            expect(
              find.text(
                AppearanceColorStrings.palette(
                  AppearancePalettes.byId('form-night').label,
                ),
              ),
              findsOneWidget,
            );
            form.definition = form.definition.withBackgroundMode('solid');
            await tester.pumpWidget(const SizedBox.shrink());
            await mount();
            final reset = find.byTooltip(
              '${FormStrings.resetToDefault}: ${AppearanceColorStrings.theme}',
            );
            await tester.ensureVisible(reset);
            await tester.tap(reset);
            await tester.pumpAndSettle();
            expect(form.definition.primaryColor, isNull);
            expect(find.text(AppearanceColorStrings.inherited), findsOneWidget);
            expect(find.text('#116655'), findsOneWidget);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
}
