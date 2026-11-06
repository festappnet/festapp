import 'package:fstapp/widgets/dependency_material_bridge.dart';
import 'dart:convert';
import 'dart:io';
import 'package:fstapp/components/blueprint/views/blueprint_plan_editor.dart';
import '../../support/fixtures/widget_environment_fixture.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import '../../support/fixtures/layout_canvas_fixture.dart';

void main() {
  WidgetEnvironmentFixture.register();
  late WidgetEnvironmentFixture environment;
  setUpAll(() {
    environment = WidgetEnvironmentFixture(
        locale: const Locale('cs'),
        translations:
            jsonDecode(File('assets/translations/cs.json').readAsStringSync())
                as Map<String, dynamic>);
  });
  testWidgetsWithEnvironment(() => environment,
      'Festapp plan host pans blank margins and resolves near taps without changing its draft',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final node = LayoutNode(
        id: newLayoutId(),
        kind: 'table',
        x: 400,
        y: 100,
        width: 80,
        height: 60,
        surface: const {'type': 'rect'});
    final document = VenueLayoutDocument.empty().copyWith(canvas: {
      'x': 0,
      'y': 0,
      'width': 800,
      'height': 200,
      'fill': '#FFFFFFFF'
    }, nodes: [
      node
    ]);
    final controller = VenueLayoutController(document);
    addTearDown(controller.dispose);
    await environment.pumpWidget(
        tester,
        MaterialApp(builder: DependencyMaterialBridge.builder,
            locale: const Locale('cs'),
            supportedLocales: VenueLayoutLocalizations.supportedLocales,
            localizationsDelegates:
                [...VenueLayoutLocalizations.localizationsDelegates, ...GlobalMaterialLocalizations.delegates],
            home: Scaffold(
                body: BlueprintPlanEditor(
                    controller: controller, showGallery: false))));
    await tester.pumpAndSettle();
    final TransformationController camera = layoutPainter(tester).camera;
    final viewport = tester.getRect(layoutCanvas());
    camera.value = Matrix4.diagonal3Values(2, 2, 1)
      ..setTranslationRaw(-250, -200, 0);
    await tester.pump();
    final start = viewport.topLeft + const Offset(120, 25);
    final scene = camera.toScene(start - viewport.topLeft);
    final Offset offset = layoutPainter(tester).offset;
    expect(scene.dy, lessThan(offset.dy),
        reason: 'The gesture starts above the transformed plan');
    controller.select({node.id});
    await tester.pump();
    final before = camera.value.clone();
    await tester.dragFrom(start, const Offset(-70, 0));
    await tester.pumpAndSettle();
    expect(camera.value, isNot(before));
    expect(controller.selection, {node.id});
    controller.select({});
    await tester.pump();
    final double zoom = layoutPainter(tester).scale * camera.value.entry(0, 0);
    await tester.tapAt(layoutPoint(
        tester, Offset(node.x + node.width / 2 + 7 / zoom, node.y)));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(controller.selection, {node.id});
    expect(controller.document, same(document));
    expect(controller.canUndo, false);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('mobile reservations retain one-finger pan after pinch zoom',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 650));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = VenueLayoutController(VenueLayoutDocument.empty());
    final originalDocument = controller.document;
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(builder: DependencyMaterialBridge.builder,
      home: Scaffold(
        body: VenueLayoutEditor(
          controller: controller,
          interactionEnabled: false,
          showGallery: false,
          viewSelection: const {},
          onViewSelectionChanged: (_) {},
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final surface = layoutCanvas();
    final center = tester.getCenter(surface);
    final TransformationController camera = layoutPainter(tester).camera;
    final initialZoom = camera.value.entry(0, 0);
    final first =
        await tester.startGesture(center - const Offset(35, 0), pointer: 1);
    final second =
        await tester.startGesture(center + const Offset(35, 0), pointer: 2);
    for (var i = 0; i < 4; i++) {
      await first.moveBy(const Offset(-15, 0));
      await second.moveBy(const Offset(15, 0));
      await tester.pump();
    }
    await first.up();
    await second.up();
    await tester.pumpAndSettle();
    expect(camera.value.entry(0, 0), greaterThan(initialZoom));
    final zoom = camera.value.entry(0, 0);
    final before = camera.value.entry(0, 3);
    await tester.dragFrom(center, const Offset(-60, 0));
    await tester.pumpAndSettle();
    final afterLeft = camera.value.entry(0, 3);
    expect(afterLeft, lessThan(before - 20));
    await tester.dragFrom(center, const Offset(60, 0));
    await tester.pumpAndSettle();
    expect(camera.value.entry(0, 3), greaterThan(afterLeft + 20));
    expect(camera.value.entry(0, 0), closeTo(zoom, .000001));
    expect(controller.document, same(originalDocument));
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgetsWithEnvironment(() => environment,
      'mobile reservation pans from dark space outside the plan',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 650));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final document = VenueLayoutDocument.empty().copyWith(canvas: {
      'x': 0,
      'y': 0,
      'width': 800,
      'height': 1000,
      'fill': '#FFFFFFFF'
    });
    final controller = VenueLayoutController(document);
    addTearDown(controller.dispose);
    var selectionChanges = 0;
    await environment.pumpWidget(
        tester,
        MaterialApp(builder: DependencyMaterialBridge.builder,
            home: Scaffold(
                body: BlueprintPlanEditor(
                    controller: controller,
                    interactionEnabled: false,
                    showGallery: false,
                    viewSelection: const {},
                    onViewSelectionChanged: (_) => selectionChanges++))));
    await tester.pumpAndSettle();
    final viewport = tester.getRect(layoutCanvas());
    final TransformationController camera = layoutPainter(tester).camera;
    camera.value = Matrix4.diagonal3Values(1.5, 1.5, 1)
      ..setTranslationRaw(180, -180, 0);
    await tester.pump();
    final start = viewport.topLeft + Offset(30, viewport.height / 2);
    final scene = camera.toScene(start - viewport.topLeft);
    final Offset offset = layoutPainter(tester).offset;
    expect(scene.dx, lessThan(offset.dx),
        reason:
            'The drag begins outside the plan, in the dark viewport margin');
    final before = camera.value.entry(0, 3);
    await tester.dragFrom(start, const Offset(-70, 0));
    await tester.pumpAndSettle();
    expect(camera.value.entry(0, 3), lessThan(before - 20));
    expect(camera.value.entry(0, 0), closeTo(1.5, 0.000001));
    expect(controller.document, same(document));
    expect(selectionChanges, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
