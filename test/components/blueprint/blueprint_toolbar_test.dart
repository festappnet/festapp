import 'package:fstapp/widgets/dependency_material_bridge.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/blueprint/blueprint_layout_contract.dart';
import 'package:fstapp/components/blueprint/blueprint_model.dart';
import 'package:fstapp/components/blueprint/views/blueprint_layout_host.dart';
import 'package:fstapp/components/occasion/occasion_link_model.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/theme_config.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';

import '../../support/fixtures/blueprint_font_registry_fixture.dart';
import '../../support/fixtures/layout_canvas_fixture.dart';
import '../../support/fixtures/root_supabase_fixture.dart';
import '../../support/fixtures/widget_environment_fixture.dart';

void main() {
  WidgetEnvironmentFixture.register();
  late WidgetEnvironmentFixture environment;
  late RootSupabaseFixture backend;
  setUpAll(() async {
    backend = await RootSupabaseFixture.open(
      (_) => throw StateError('Toolbar must stay offline'),
    );
    environment = WidgetEnvironmentFixture(
      locale: const Locale('cs'),
      translations: jsonDecode(
        File('assets/translations/cs.json').readAsStringSync(),
      ) as Map<String, dynamic>,
    );
    final font = FontLoader('Futura')
      ..addFont(rootBundle.load('fonts/Futura PT Book.ttf'))
      ..addFont(rootBundle.load('fonts/Futura PT Medium.ttf'));
    await font.load();
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
  });
  tearDownAll(() => backend.dispose());

  for (final brightness in Brightness.values) {
    for (final width in [320.0, 390.0, 1280.0, 1440.0]) {
      testWidgetsWithEnvironment(
        () => environment,
        'toolbar modes stay reachable at $width ${brightness.name}',
        (tester) async {
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final previous = RightsService.occasionLinkModelNotifier.value;
          RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
            capabilities: {'occasions.write': true, 'orders.write': true},
          );
          addTearDown(
            () => RightsService.occasionLinkModelNotifier.value = previous,
          );
          final document = tableLayout(shape: 'rect', count: 8);
          final source = BlueprintModel(
            layoutSnapshot: BlueprintLayoutSnapshot(
              blueprintId: 1,
              occasionId: 1,
              title: 'Ples',
              revision: 1,
              document: document,
              seatBindings: {},
            ),
            layoutResources: blueprintPreparedResourcesFixture(document),
          );
          final boundaryKey = GlobalKey();
          await environment.pumpWidget(
            tester,
            MaterialApp(
              locale: const Locale('cs'),
              supportedLocales: VenueLayoutLocalizations.supportedLocales,
              localizationsDelegates:
                  [...VenueLayoutLocalizations.localizationsDelegates, ...GlobalMaterialLocalizations.delegates],
              theme: ThemeConfig.theme(brightness: brightness),
              builder: DependencyMaterialBridge.wrapBuilder((context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(width == 320 ? 1.6 : 1)),
                child: child!,
              )),
              home: RepaintBoundary(
                key: boundaryKey,
                child: BlueprintLayoutHost(
                  source: source,
                  reload: () async => source,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          Future<void> capture(String mode) async {
            const output = String.fromEnvironment('BLUEPRINT_TOOLBAR_CAPTURE');
            if (output.isEmpty) return;
            await tester.runAsync(() async {
              final boundary =
                  boundaryKey.currentContext!.findRenderObject()
                      as RenderRepaintBoundary;
              final image = await boundary.toImage();
              final data = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final file = File(
                '$output/${brightness.name}-${width.toInt()}-$mode.png',
              );
              await file.parent.create(recursive: true);
              await file.writeAsBytes(data!.buffer.asUint8List());
              image.dispose();
            });
          }

          final toolbar = find.byKey(const ValueKey('layout-editor-toolbar'));
          final mobile = width < 700;
          void checkLayout() {
            expect(tester.takeException(), isNull);
            expect(
              tester.getSize(toolbar).height,
              lessThanOrEqualTo(112),
            );
            expect(tester.getSize(layoutCanvas()).height, greaterThan(540));
          }

          checkLayout();
          expect(
            find.byKey(const ValueKey('blueprint-start-order')).hitTestable(),
            findsOneWidget,
          );
          await capture('reservations');
          if (mobile) {
            await tester.tap(
              find.byKey(const ValueKey('blueprint-more-actions')),
            );
            await tester.pumpAndSettle();
            expect(
              find.byKey(const ValueKey('blueprint-start-swap')).hitTestable(),
              findsOneWidget,
            );
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
            await tester.pumpAndSettle();
            await tester.tap(
              find.byKey(const ValueKey('blueprint-screen-mode')),
            );
            await tester.pumpAndSettle();
          }
          await tester.tap(find.byKey(const ValueKey('blueprint-edit-mode')));
          await tester.pumpAndSettle();
          expect(
            tester
                .widget<VenueLayoutEditor>(find.byType(VenueLayoutEditor))
                .interactionEnabled,
            isTrue,
          );
          checkLayout();
          if (!mobile) {
            final grid = find.widgetWithText(FilterChip, 'Mřížka');
            expect(grid, findsOneWidget);
            final wasSelected = tester.widget<FilterChip>(grid).selected;
            await tester.tap(grid);
            await tester.pumpAndSettle();
            expect(tester.widget<FilterChip>(grid).selected, !wasSelected);
          }
          await capture('edit');
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }
}
