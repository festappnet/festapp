import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_scene_surface.dart';

void main() {
  for (final kind in ['Text', 'Seat']) {
    testWidgets('Ctrl+Z immediately removes dragged $kind while selected', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final c = VenueLayoutController(VenueLayoutDocument.empty());
      addTearDown(c.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VenueLayoutEditor(controller: c, showGallery: false),
          ),
        ),
      );
      final search = find
          .byWidgetPredicate(
            (w) => w is TextField && w.decoration?.labelText == 'Find object',
          )
          .first;
      await tester.enterText(search, kind);
      await tester.pump();
      final tile = find.byWidgetPredicate(
        (w) => w is Draggable<String> && w.data == kind,
      );
      final canvas = find.byWidgetPredicate(
        (w) => w is LayoutSceneSurface && w.onDrop != null,
      );
      await tester.dragFrom(
        tester.getCenter(tile),
        tester.getCenter(canvas) - tester.getCenter(tile),
      );
      await tester.pumpAndSettle();
      expect(c.document.nodes, hasLength(1));
      expect(c.selection, isNotEmpty);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(c.document.nodes, isEmpty);
      expect(find.byKey(const ValueKey('layout-inline-label')), findsNothing);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(c.document.nodes, hasLength(1));
    });
  }
  testWidgets(
    'Escape closes the actual template gallery before canvas consumes it',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final caller = FocusNode();
      addTearDown(caller.dispose);
      final c = VenueLayoutController(rowLayout(rows: 1, seatsPerRow: 2));
      addTearDown(c.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: VenueLayoutEditor(controller: c, toolbarTrailing: TextButton(focusNode: caller, onPressed: () {}, child: const Text('Caller')))),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('palette-templates')));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
      caller.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
    },
  );
}
