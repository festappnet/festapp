import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';

void main() {
  testWidgets(
    'public readonly viewer focuses exact nodes and reports hits without changing geometry',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final document = VenueLayoutDocument.empty().copyWith(
        nodes: [
          LayoutNode.fromJson({
            'id': '00000000-0000-4000-8000-000000000001',
            'kind': 'seat',
            'width': 40,
            'height': 40,
            'transform': {'x': 250, 'y': 250, 'rotation': 0},
          }),
          LayoutNode.fromJson({
            'id': '00000000-0000-4000-8000-000000000002',
            'kind': 'seat',
            'width': 40,
            'height': 40,
            'transform': {'x': 750, 'y': 750, 'rotation': 0},
          }),
        ],
        canvas: {
          'x': 0,
          'y': 0,
          'width': 1000,
          'height': 1000,
          'fill': '#ffffffff',
        },
      );
      final before = document.toJson();
      String? hit;
      Future<void> show(int revision, String focus) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: VenueLayoutViewer(
                document: document,
                highlightedNodeIds: document.nodes.map((n) => n.id).toSet(),
                activeNodeIds: {focus},
                focusNodeIds: {focus},
                focusRevision: revision,
                onNodeTap: (id) => hit = id,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tapAt(tester.getCenter(find.byType(VenueLayoutViewer)));
        await tester.pumpAndSettle();
      }

      await show(1, document.nodes.first.id);
      expect(hit, document.nodes.first.id);
      await show(2, document.nodes.last.id);
      expect(hit, document.nodes.last.id);
      expect(document.toJson(), before);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'embedded map passes ordinary wheel scrolling to its page and reserves modifier zoom',
    (tester) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              controller: scroll,
              child: Column(
                children: [
                  const SizedBox(height: 40),
                  SizedBox(
                    height: 300,
                    child: VenueLayoutViewer(
                      document: VenueLayoutDocument.empty(),
                      wheelZoomRequiresModifier: true,
                    ),
                  ),
                  const SizedBox(height: 1400),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final position = tester.getCenter(find.byType(VenueLayoutViewer));
      tester.binding.handlePointerEvent(
        PointerScrollEvent(
          position: position,
          scrollDelta: const Offset(0, 120),
        ),
      );
      await tester.pumpAndSettle();
      expect(scroll.offset, greaterThan(0));
      scroll.jumpTo(0);
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      tester.binding.handlePointerEvent(
        PointerScrollEvent(
          position: position,
          scrollDelta: const Offset(0, -120),
        ),
      );
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(scroll.offset, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
