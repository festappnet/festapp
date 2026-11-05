import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/canonical_appearance_panel.dart';

void main() {
  for (final kind in ['shape', 'capacityArea', 'table', 'seat', 'furniture']) {
    testWidgets('$kind shows only applicable construction controls', (
      tester,
    ) async {
      final node = LayoutNode(
        id: newLayoutId(),
        kind: kind,
        properties: kind == 'shape'
            ? {'shape': 'rect'}
            : kind == 'furniture'
            ? {'furniture': 'couch'}
            : {},
      );
      final doc = kind == 'table'
          ? tableLayout(shape: 'rect', count: 4)
          : VenueLayoutDocument(nodes: [node]);
      final target = doc.nodes.firstWhere((n) => n.kind == kind);
      final controller = VenueLayoutController(doc);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CanonicalAppearancePanel(
                controller: controller,
                nodeId: target.id,
              ),
            ),
          ),
        ),
      );
      expect(
        find.text('Material'),
        ['table', 'seat', 'furniture'].contains(kind)
            ? findsOneWidget
            : findsNothing,
      );
      expect(find.text('Fill color'), findsOneWidget);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showCanonicalAppearanceDialog(
                  context,
                  controller,
                  nodeId: target.id,
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(
        find.text('Style family'),
        ['table', 'seat', 'furniture'].contains(kind)
            ? findsOneWidget
            : findsNothing,
      );
      expect(find.text('Color palette'), findsOneWidget);
    });
  }
  for (final type in ['line', 'text', 'image', 'vector', 'group']) {
    testWidgets('$type uses the same controls in panel and quick dialog', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1000, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final node = LayoutNode(
        id: newLayoutId(),
        kind: type == 'line' ? 'shape' : type,
        properties: type == 'line'
            ? {'shape': 'line'}
            : type == 'text'
            ? {'text': 'Entrance'}
            : {},
        graphic: type == 'image'
            ? {
                'type': 'bitmap',
                'assetRef': 'image:fixture',
                'hash': 'a' * 64,
                'crop': {'x': 0, 'y': 0, 'width': 1, 'height': 1},
              }
            : type == 'vector'
            ? {
                'type': 'vector',
                ...importSvgGraphic(
                  '<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20"><rect width="20" height="20" fill="#123456"/></svg>',
                ).graphic.toJson(),
              }
            : null,
      );
      final controller = VenueLayoutController(
        VenueLayoutDocument(nodes: [node]),
      );
      addTearDown(controller.dispose);
      final before = controller.document.toJson();
      Future<void> checkControls() async {
        expect(find.text('Material'), findsNothing);
        expect(find.text('Fill color'), findsNothing);
        expect(
          find.text('Text'),
          type == 'text' || type == 'line' ? findsOneWidget : findsNothing,
        );
        await tester.ensureVisible(find.text('Advanced appearance'));
        await tester.tap(find.text('Advanced appearance'));
        await tester.pumpAndSettle();
        expect(find.text('Corner radius'), findsNothing);
        expect(
          find.text('Outline color'),
          type == 'line' ? findsOneWidget : findsNothing,
        );
        expect(
          find.text('Opacity'),
          type == 'group' ? findsNothing : findsOneWidget,
        );
      }

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CanonicalAppearancePanel(
                controller: controller,
                nodeId: node.id,
              ),
            ),
          ),
        ),
      );
      await checkControls();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showCanonicalAppearanceDialog(
                  context,
                  controller,
                  nodeId: node.id,
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(
        find.text('Style family'),
        type == 'group' ? findsOneWidget : findsNothing,
      );
      expect(find.text('Color palette'), findsOneWidget);
      await tester.ensureVisible(find.text('Detailed settings'));
      await tester.tap(find.text('Detailed settings'));
      await tester.pumpAndSettle();
      await checkControls();
      expect(controller.document.toJson(), before);
    });
  }

  testWidgets(
    'table switches to child seat controls without changing declarations',
    (tester) async {
      final controller = VenueLayoutController(
        tableLayout(shape: 'rect', count: 4),
      );
      addTearDown(controller.dispose);
      final before = controller.document.toJson();
      final table = controller.document.nodes.firstWhere(
        (n) => n.kind == 'table',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CanonicalAppearancePanel(
                controller: controller,
                nodeId: table.id,
              ),
            ),
          ),
        ),
      );
      expect(find.text('Material'), findsOneWidget);
      expect(find.text('Chair style'), findsNothing);
      expect(find.text('Text'), findsOneWidget);
      await tester.tap(find.text('Chairs'));
      await tester.pumpAndSettle();
      expect(find.text('Material'), findsOneWidget);
      expect(find.text('Chair style'), findsOneWidget);
      expect(find.text('Text'), findsNothing);
      expect(find.text('Fill color'), findsOneWidget);
      await tester.tap(find.text('Table'));
      await tester.pumpAndSettle();
      expect(find.text('Chair style'), findsNothing);
      expect(find.text('Text'), findsOneWidget);
      expect(controller.document.toJson(), before);
    },
  );

  testWidgets(
    'global presets stay aggregate while kind controls follow selected target',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller = VenueLayoutController(
        tableLayout(shape: 'rect', count: 4),
      );
      addTearDown(controller.dispose);
      final before = controller.document.toJson();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showCanonicalAppearanceDialog(
                  context,
                  controller,
                  global: true,
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Style family'), findsOneWidget);
      await tester.ensureVisible(find.text('Detailed settings'));
      await tester.tap(find.text('Detailed settings'));
      await tester.pumpAndSettle();
      expect(find.text('Text'), findsOneWidget);
      expect(find.text('Material'), findsNothing);
      expect(find.text('Fill color'), findsNothing);
      Future<void> select(String kind) async {
        final dropdown = find.byKey(const ValueKey('canonical-style-target'));
        await tester.ensureVisible(dropdown);
        await tester.tap(dropdown);
        await tester.pumpAndSettle();
        await tester.tap(find.text(kind).last);
        await tester.pumpAndSettle();
      }

      await select('seat');
      expect(find.text('Material'), findsOneWidget);
      expect(find.text('Chair style'), findsOneWidget);
      expect(find.text('Text'), findsNothing);
      await select('image');
      expect(find.text('Material'), findsNothing);
      expect(find.text('Fill color'), findsNothing);
      expect(find.text('Text'), findsNothing);
      await select('shape');
      expect(find.text('Material'), findsNothing);
      expect(find.text('Fill color'), findsOneWidget);
      expect(find.text('Text'), findsOneWidget);
      expect(find.text('Style family'), findsOneWidget);
      expect(controller.document.toJson(), before);
    },
  );
}
