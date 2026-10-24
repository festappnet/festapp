import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
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
  late RootSupabaseFixture backend;
  late WidgetEnvironmentFixture environment;
  setUpAll(() async {
    backend = await RootSupabaseFixture.open(
        (_) => throw StateError('Pan must stay offline'));
    environment = WidgetEnvironmentFixture(
        locale: const Locale('cs'),
        translations:
            jsonDecode(File('assets/translations/cs.json').readAsStringSync()));
  });
  tearDownAll(() => backend.dispose());
  testWidgetsWithEnvironment(() => environment,
      'reservation host pans both axes from dark margin after selecting a seat',
      (tester) async {
    tester.view.physicalSize = const Size(390, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final previous = RightsService.occasionLinkModelNotifier.value;
    RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
        capabilities: {'occasions.write': true, 'orders.write': true});
    addTearDown(() => RightsService.occasionLinkModelNotifier.value = previous);
    final id = newLayoutId();
    final document = VenueLayoutDocument.empty().copyWith(canvas: {
      'x': 0,
      'y': 0,
      'width': 800,
      'height': 1000,
      'fill': '#FFFFFFFF'
    }, nodes: [
      LayoutNode(
          id: id,
          kind: 'seat',
          x: 100,
          y: 100,
          width: 20,
          height: 20,
          label: 'A1')
    ]);
    final source = BlueprintModel(
        layoutSnapshot: BlueprintLayoutSnapshot(
            blueprintId: 1,
            occasionId: 1,
            title: 'Ples',
            revision: 1,
            document: document,
            seatBindings: {
              id: BlueprintSeatBinding(nodeId: id, spotId: 1, title: 'A1')
            }),
        layoutResources: blueprintPreparedResourcesFixture(document));
    var interceptGestures = false;
    late StateSetter updateHost;
    await environment.pumpWidget(
        tester,
        MaterialApp(
            theme: ThemeConfig.theme(brightness: Brightness.dark),
            locale: const Locale('cs'),
            supportedLocales: VenueLayoutLocalizations.supportedLocales,
            localizationsDelegates:
                VenueLayoutLocalizations.localizationsDelegates,
            home: StatefulBuilder(builder: (context, update) {
              updateHost = update;
              return RawGestureDetector(
                  gestures: interceptGestures
                      ? {
                          EagerGestureRecognizer:
                              GestureRecognizerFactoryWithHandlers<
                                      EagerGestureRecognizer>(
                                  () => EagerGestureRecognizer(), (_) {})
                        }
                      : {},
                  child: BlueprintLayoutHost(
                      source: source, reload: () async => source));
            })));
    await tester.pumpAndSettle();
    await tester.tapAt(layoutPoint(tester, const Offset(110, 110)));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<VenueLayoutEditor>(find.byType(VenueLayoutEditor))
            .viewSelection,
        {id});
    updateHost(() => interceptGestures = true);
    await tester.pumpAndSettle();
    final TransformationController camera = layoutPainter(tester).camera;
    for (final delta in [const Offset(-70, 0), const Offset(0, 70)]) {
      camera.value = Matrix4.diagonal3Values(3, 3, 1)
        ..setTranslationRaw(120, -180, 0);
      await tester.pump();
      final viewport = tester.getRect(layoutCanvas());
      final start = viewport.topLeft + Offset(60, viewport.height / 2);
      final before = camera.value.clone();
      final gesture = await tester.startGesture(start);
      for (var i = 0; i < 10; i++) {
        await gesture.moveBy(delta / 10);
        await tester.pump(const Duration(milliseconds: 20));
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(camera.value, isNot(before));
      expect(
          tester
              .widget<VenueLayoutEditor>(find.byType(VenueLayoutEditor))
              .viewSelection,
          {id});
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
