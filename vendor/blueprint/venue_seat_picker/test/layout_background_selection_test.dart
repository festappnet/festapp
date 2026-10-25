import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_scene_surface.dart';

void main() {
  testWidgets(
    'background selects beneath objects, transforms and undoes independently',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final seat = LayoutNode(id: newLayoutId(), kind: 'seat', x: 100, y: 100);
      final document = VenueLayoutDocument.empty().copyWith(
        nodes: [seat],
        background: {
          'assetRef': 'test',
          'hash': 'a' * 64,
          'x': 200,
          'y': 200,
          'width': 400,
          'height': 400,
          'scale': 1,
          'rotation': 0,
          'opacity': 1,
          'crop': {'x': 0, 'y': 0, 'width': 1, 'height': 1},
        },
      );
      final controller = VenueLayoutController(document);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: VenueLayoutEditor(controller: controller)),
        ),
      );
      await tester.pumpAndSettle();
      LayoutSceneSurface surface() =>
          tester.widget<LayoutSceneSurface>(find.byType(LayoutSceneSurface));
      surface().onTap!(const Offset(300, 300));
      await tester.pump();
      expect(surface().backgroundSelected, isTrue);
      expect(controller.selection, isEmpty);
      final xField = find.descendant(
        of: find.byKey(const ValueKey('X')),
        matching: find.byType(TextField),
      );
      await tester.ensureVisible(xField);
      await tester.enterText(xField, '240');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(controller.document.background!['x'], 240);
      expect(controller.document.nodes, document.nodes);
      controller.undo();
      await tester.pump();
      expect(controller.document.background, document.background);
      surface().onDragStart!(const Offset(300, 300));
      surface().onDragUpdate!(const Offset(330, 320));
      surface().onDragEnd!();
      await tester.pump();
      expect(controller.document.background!['x'], 230);
      expect(controller.document.background!['y'], 220);
      expect(controller.document.nodes, document.nodes);
      controller.undo();
      await tester.pump();
      expect(controller.document.background, document.background);
      surface().onTap!(const Offset(100, 100));
      await tester.pump();
      expect(controller.selection, {seat.id});
      expect(surface().backgroundSelected, isFalse);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VenueLayoutEditor(
              controller: controller,
              interactionEnabled: false,
            ),
          ),
        ),
      );
      await tester.pump();
      surface().onTap!(const Offset(300, 300));
      await tester.pump();
      expect(surface().backgroundSelected, isFalse);
      expect(controller.document.background, document.background);
      expect(tester.takeException(), isNull);
    },
  );
}
