import 'dart:convert';
import 'dart:io';
import '../../support/fixtures/widget_environment_fixture.dart';
import 'package:fstapp/components/blueprint/blueprint_configuration.dart';
import 'package:fstapp/components/blueprint/blueprint_model.dart';
import 'package:fstapp/components/blueprint/views/blueprint_editor_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/blueprint/views/blueprint_mobile_scroll_view.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';

void main() {
  WidgetEnvironmentFixture.register();
  late WidgetEnvironmentFixture environment;
  setUpAll(() {
    environment = WidgetEnvironmentFixture(
      locale: const Locale('cs'),
      translations:
          jsonDecode(File('assets/translations/cs.json').readAsStringSync())
              as Map<String, dynamic>,
    );
  });
  testWidgetsWithEnvironment(() => environment,
      'mobile editor keeps controls reachable and zooms without losing its camera',
      (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await environment.pumpWidget(
        tester,
        MaterialApp(
            home: BlueprintTab.prototype(
          prototypeBlueprint: BlueprintModel(
            configuration: BlueprintConfiguration(width: 20, height: 2),
            groups: [],
            objects: [],
            products: [],
          ),
          onPrototypeSave: (_) {},
        )));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull,
        reason: 'All controls must fit a narrow phone');
    final viewer = tester.widget<VenueSeatViewer>(
        find.byWidgetPredicate((w) => w is VenueSeatViewer).first);
    final controller = viewer.controller;
    final initialScale =
        controller.transformationController.value.getMaxScaleOnAxis();
    await tester.tap(find.byTooltip('Přiblížit'));
    await tester.pumpAndSettle();
    expect(controller.transformationController.value.getMaxScaleOnAxis(),
        greaterThan(initialScale));
    controller.transformationController.value = Matrix4.diagonal3Values(2, 2, 1)
      ..setTranslationRaw(-100, 0, 0);
    await tester.pump();
    final viewport = tester.getRect(find.byType(InteractiveViewer));
    final start = viewport.topLeft + Offset(viewport.width / 2, 20);
    expect(controller.transformationController.toScene(start - viewport.topLeft).dy,
        lessThan(0), reason: 'Touch starts in blank space above the actual plan');
    final beforePan = controller.transformationController.value.getTranslation().x;
    await tester.dragFrom(start, const Offset(-80, 0));
    await tester.pumpAndSettle();
    expect(controller.transformationController.value.getTranslation().x,
        lessThan(beforePan - 40));
    expect(controller.rows, 2);
    expect(controller.columns, 20);
    expect(controller.seats, isEmpty);
    final zoomed = Matrix4.copy(controller.transformationController.value);
    await tester.tap(find.byKey(const ValueKey('blueprint-tools')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('blueprint-plan')));
    await tester.pumpAndSettle();
    expect(controller.transformationController.value, zoomed);
    await tester.tap(find.byTooltip('Celý plánek'));
    await tester.pumpAndSettle();
    expect(controller.transformationController.value.getMaxScaleOnAxis(),
        closeTo(initialScale, .001));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('mobile plan pans horizontally without moving the side panels',
      (tester) async {
    tester.view.physicalSize = const Size(390, 650);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = VenueSeatController<VenueSeat, Object>(
      adapter: venueSeatAdapter,
    )..loadPlan(rows: 20, columns: 20, seats: const []);
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BlueprintMobileScrollView(
          screenWidth: 390,
          leftPanel: const Text('Legend'),
          rightPanel: const Text('Groups'),
          mainContent: VenueSeatViewer(controller: controller),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    controller.transformationController.value = Matrix4.diagonal3Values(2, 2, 1)
      ..setTranslationRaw(-400, -400, 0);
    await tester.pump();
    final initialX =
        controller.transformationController.value.getTranslation().x;
    await tester.drag(
        find.byType(VenueSeatViewer<VenueSeat, Object>), const Offset(-100, 0));
    await tester.pumpAndSettle();
    expect(controller.transformationController.value.getTranslation().x,
        lessThan(initialX - 50));

    final afterLeft =
        controller.transformationController.value.getTranslation().x;
    await tester.drag(
        find.byType(VenueSeatViewer<VenueSeat, Object>), const Offset(100, 0));
    await tester.pumpAndSettle();
    expect(controller.transformationController.value.getTranslation().x,
        greaterThan(afterLeft + 50));

    final initialScale =
        controller.transformationController.value.getMaxScaleOnAxis();
    final center = tester.getCenter(find.byType(InteractiveViewer));
    final first =
        await tester.startGesture(center - const Offset(40, 0), pointer: 1);
    final second =
        await tester.startGesture(center + const Offset(40, 0), pointer: 2);
    await first.moveBy(const Offset(-30, 0));
    await second.moveBy(const Offset(30, 0));
    await tester.pump();
    await first.moveBy(const Offset(-30, 0));
    await second.moveBy(const Offset(30, 0));
    await first.up();
    await second.up();
    await tester.pumpAndSettle();
    expect(controller.transformationController.value.getMaxScaleOnAxis(),
        greaterThan(initialScale));

    final camera = Matrix4.copy(controller.transformationController.value);
    await tester.tap(find.byKey(const ValueKey('blueprint-groups')));
    await tester.pumpAndSettle();
    expect(find.text('Groups').hitTestable(), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('blueprint-plan')));
    await tester.pumpAndSettle();
    expect(controller.transformationController.value, camera);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
