import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_scene_surface.dart';

void main() {
  testWidgets(
    'geometry previews update canvas without rebuilding inspector until commit',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final node = LayoutNode(
        id: newLayoutId(),
        kind: 'table',
        x: 300,
        y: 300,
        width: 180,
        height: 100,
        surface: const {'type': 'rect'},
      );
      final c = VenueLayoutController(
        VenueLayoutDocument.empty().copyWith(nodes: [node]),
      );
      addTearDown(c.dispose);
      c.select({node.id});
      var inspectorBuilds = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VenueLayoutEditor(
              controller: c,
              showGallery: false,
              inspectorBuilder: (_, node) {
                inspectorBuilds++;
                return Text('Position ${node.x}');
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final before = inspectorBuilds;
      expect(before, greaterThan(0));
      c.beginGesture();
      for (var i = 1; i <= 5; i++) {
        c.previewMove(
          VenueLayoutDocument.empty().copyWith(nodes: [node]),
          {node.id},
          dx: i * 10,
          dy: 0,
        );
        await tester.pump();
        final surface = tester.widget<LayoutSceneSurface>(
          find.byWidgetPredicate(
            (w) => w is LayoutSceneSurface && w.onTap != null,
          ),
        );
        expect(surface.document.nodes.single.x, 300 + i * 10);
      }
      expect(
        inspectorBuilds,
        before,
        reason: 'Pointer previews must retain the unrelated inspector subtree',
      );
      c.commitGesture();
      await tester.pumpAndSettle();
      expect(inspectorBuilds, greaterThan(before));
      expect(find.text('Position 350.0'), findsOneWidget);
      c.undo();
      await tester.pumpAndSettle();
      expect(find.text('Position 300.0'), findsOneWidget);
    },
  );
}
