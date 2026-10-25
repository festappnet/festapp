import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_scene_surface.dart';

void main() {
  testWidgets(
    'host presentation is transient; operation activation never transforms',
    (tester) async {
      final id = newLayoutId();
      final document = VenueLayoutDocument(
        nodes: [LayoutNode(id: id, kind: 'seat', x: 100, y: 100)],
      );
      final controller = VenueLayoutController(document);
      final activated = <String>[];
      var escapes = 0;
      var presentation = <String, dynamic>{
        id: {'status': 'available'},
      };
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, set) {
                update = set;
                return CallbackShortcuts(
                  bindings: {
                    const SingleActivator(LogicalKeyboardKey.escape): () =>
                        escapes++,
                  },
                  child: VenueLayoutEditor(
                    controller: controller,
                    showGallery: false,
                    interactionEnabled: false,
                    seatPresentation: presentation,
                    onNodeActivated: activated.add,
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      LayoutSceneSurface surface() =>
          tester.widget<LayoutSceneSurface>(find.byType(LayoutSceneSurface));
      surface().onTap!(const Offset(100, 100));
      await tester.pump();
      expect(activated, [id]);
      expect(controller.selection, {id});
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      expect(activated, [id, id, id]);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(escapes, 1);
      expect(identical(controller.document, document), isTrue);
      expect(controller.dirty, isFalse);
      update(
        () => presentation = {
          id: {'status': 'occupied', 'label': 'Updated'},
        },
      );
      await tester.pumpAndSettle();
      expect(surface().presentation[id]['status'], 'occupied');
      expect(identical(controller.document, document), isTrue);
      expect(controller.dirty, isFalse);
      expect(controller.canUndo, isFalse);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
}
