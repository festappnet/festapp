import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:fstapp/components/blueprint/blueprint_focus_target.dart';
import 'package:fstapp/components/blueprint/views/blueprint_plan_editor.dart';
import 'package:fstapp/components/blueprint/views/blueprint_editor_tab.dart';
import 'package:fstapp/widgets/dependency_material_bridge.dart';

import '../../support/fixtures/widget_environment_fixture.dart';
import '../../support/fixtures/layout_canvas_fixture.dart';

VenueLayoutDocument document() => VenueLayoutDocument.empty().copyWith(
  canvas: {'x': 0, 'y': 0, 'width': 3000, 'height': 2000, 'fill': '#FFFFFFFF'},
  nodes: [
    LayoutNode(
      id: '00000000-0000-4000-8000-000000000001',
      kind: 'seat',
      x: 1000,
      y: 800,
      width: 30,
      height: 30,
    ),
    LayoutNode(
      id: '00000000-0000-4000-8000-000000000002',
      kind: 'seat',
      x: 2400,
      y: 1500,
      width: 30,
      height: 30,
    ),
  ],
);

void main() {
  WidgetEnvironmentFixture.register();
  late WidgetEnvironmentFixture environment;
  setUpAll(() {
    environment = WidgetEnvironmentFixture(
      locale: const Locale('en'),
      translations: jsonDecode(
        File('assets/translations/en.json').readAsStringSync(),
      ) as Map<String, dynamic>,
    );
  });

  test('only the visible occasion Blueprint route consumes focus; re-entry is a new intent', () {
    final state = BlueprintRouteFocusState();
    final focused = Uri.parse(
      '/occasion-a/reservations/blueprint?blueprintId=81&blueprintNodeId=seat-a',
    );
    bool observe(Uri uri, {bool visible = true}) =>
        state.observe(uri, occasionLink: 'occasion-a', visible: visible);

    expect(observe(focused), isTrue);
    expect(state.target?.blueprintId, 81);
    expect(state.target?.nodeId, 'seat-a');
    expect(observe(focused), isFalse);
    expect(
      observe(
        focused.replace(
          queryParameters: {...focused.queryParameters, 'unrelated': 'value'},
        ),
      ),
      isFalse,
    );

    // Retained tabs must ignore another section's query, even within an occasion.
    expect(
      observe(
        Uri.parse(
          '/occasion-a/reservations/orders?blueprintId=99&blueprintNodeId=foreign',
        ),
      ),
      isTrue,
    );
    expect(state.active, isFalse);
    expect(state.target, isNull);
    expect(observe(focused), isTrue);
    expect(state.target?.nodeId, 'seat-a');

    // Another occasion cannot load or focus this retained instance.
    expect(
      observe(
        Uri.parse(
          '/occasion-b/reservations/blueprint?blueprintId=99&blueprintNodeId=foreign',
        ),
      ),
      isTrue,
    );
    expect(state.active, isFalse);
    expect(state.target, isNull);
    expect(observe(focused, visible: false), isFalse);
    expect(state.target, isNull);
    expect(observe(focused), isTrue);
    expect(
      observe(
        focused.replace(
          queryParameters: {'blueprintId': '81', 'blueprintNodeId': 'seat-b'},
        ),
      ),
      isTrue,
    );
    expect(state.target?.nodeId, 'seat-b');
  });

  test('invalid explicit plan stays distinguishable from ordinary overview navigation', () {
    final state = BlueprintRouteFocusState();
    bool observe(String path) => state.observe(
      Uri.parse(path),
      occasionLink: 'occasion-a',
      visible: true,
    );
    expect(
      observe('/occasion-a/reservations/blueprint?blueprintId=invalid'),
      isTrue,
    );
    expect(state.active, isTrue);
    expect(state.invalidPlan, isTrue);
    expect(state.target, isNull);
    expect(observe('/occasion-a/reservations/blueprint'), isTrue);
    expect(state.invalidPlan, isFalse);
    expect(state.target, isNull);
    expect(observe('/occasion-a/reservations/blueprint'), isFalse);
  });

  test('navigation binds a saved node to its explicit plan only', () {
    final doc = document();
    final target = BlueprintFocusTarget.fromQuery({
      'blueprintId': '81',
      'blueprintNodeId': doc.nodes.first.id,
    })!;
    expect(target.nodeFor(81, doc), doc.nodes.first.id);
    expect(target.nodeFor(82, doc), isNull);
    expect(target.nodeFor(81, doc.copyWith(nodes: [])), isNull);
    expect(
      BlueprintFocusTarget.fromQuery({
        'blueprintId': '-1',
        'blueprintNodeId': doc.nodes.first.id,
      }),
      isNull,
    );
    expect(
      BlueprintFocusTarget.fromQuery({'blueprintNodeId': doc.nodes.first.id}),
      isNull,
    );
    expect(
      BlueprintFocusTarget.fromQuery({'blueprintId': '81'})!.nodeFor(81, doc),
      isNull,
    );
  });

  testWidgetsWithEnvironment(
    () => environment,
    'explicit focus moves the real editor camera without changing selection or saved geometry; rebuilds do not refocus',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final doc = document();
      final before = doc.toJson();
      final controller = VenueLayoutController(doc)..readOnly = true;
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
      });
      String? target;
      var revision = 0;
      late StateSetter update;
      await environment.pumpWidget(
        tester,
        MaterialApp(
          builder: DependencyMaterialBridge.builder,
          supportedLocales: VenueLayoutLocalizations.supportedLocales,
          localizationsDelegates: [
            ...VenueLayoutLocalizations.localizationsDelegates,
            ...GlobalMaterialLocalizations.delegates,
          ],
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return BlueprintPlanEditor(
                  controller: controller,
                  interactionEnabled: false,
                  showGallery: false,
                  openGalleryOnStart: false,
                  focusNodeId: target,
                  focusRevision: revision,
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final overview = List<double>.from(
        layoutPainter(tester).camera.value.storage,
      );
      update(() {
        target = doc.nodes.first.id;
        revision++;
      });
      await tester.pumpAndSettle();
      final focused = List<double>.from(
        layoutPainter(tester).camera.value.storage,
      );
      expect(focused, isNot(overview));
      expect(
        (layoutPoint(tester, const Offset(1015, 815)) -
                tester.getCenter(layoutCanvas()))
            .distance,
        lessThan(120),
      );
      expect(controller.selection, isEmpty);
      expect(controller.document.toJson(), before);
      expect(
        tester
            .widget<VenueLayoutEditor>(find.byType(VenueLayoutEditor))
            .highlightedNodeIds,
        {doc.nodes.first.id},
      );

      await tester.drag(layoutCanvas(), const Offset(55, 35));
      await tester.pumpAndSettle();
      final panned = List<double>.from(
        layoutPainter(tester).camera.value.storage,
      );
      update(() {});
      await tester.pumpAndSettle();
      expect(
        List<double>.from(layoutPainter(tester).camera.value.storage),
        panned,
      );
      controller.select({doc.nodes.last.id});
      await tester.pumpAndSettle();
      expect(
        List<double>.from(layoutPainter(tester).camera.value.storage),
        panned,
      );

      update(() {
        target = doc.nodes.last.id;
        revision++;
      });
      await tester.pumpAndSettle();
      expect(
        (layoutPoint(tester, const Offset(2415, 1515)) -
                tester.getCenter(layoutCanvas()))
            .distance,
        lessThan(120),
      );
      final second = List<double>.from(
        layoutPainter(tester).camera.value.storage,
      );
      update(() {
        target = 'missing-node';
        revision++;
      });
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<VenueLayoutEditor>(find.byType(VenueLayoutEditor))
            .highlightedNodeIds,
        isEmpty,
      );
      expect(
        List<double>.from(layoutPainter(tester).camera.value.storage),
        second,
      );
      expect(controller.document.toJson(), before);
      expect(tester.takeException(), isNull);
    },
  );
}
