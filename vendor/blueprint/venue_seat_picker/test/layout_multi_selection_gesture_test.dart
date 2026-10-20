import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_scene_surface.dart';

void main() {
  testWidgets(
    'Shift toggles objects; dragging selected row child moves the whole set; Shift marquee adds roots',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final tableDoc = tableLayout(shape: 'rect', x: 300, y: 300);
      final rows = rowLayout(rows: 2, seatsPerRow: 4, arc: 3, x: 800, y: 300);
      final original = tableDoc.copyWith(
        nodes: [...tableDoc.nodes, ...rows.nodes],
      );
      final table = original.nodes.firstWhere((n) => n.kind == 'table');
      final row = rows.nodes.firstWhere((n) => n.parentId == null);
      final seat = rows.nodes.firstWhere((n) => n.kind == 'seat');
      final matrix = worldMatrix(original, seat);
      final rowPoint = Offset(matrix[4], matrix[5]);
      final tablePoint = Offset(table.x, table.y);
      final c = VenueLayoutController(original);
      addTearDown(c.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VenueLayoutEditor(controller: c, showGallery: false),
          ),
        ),
      );
      await tester.pumpAndSettle();
      LayoutSceneSurface surface() => tester.widget<LayoutSceneSurface>(
        find.byWidgetPredicate(
          (w) => w is LayoutSceneSurface && w.onViewportScaleChanged != null,
        ),
      );
      void click(Offset p) {
        surface().onSelectDown!(p);
        surface().onTap!(p);
      }

      click(tablePoint);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      click(rowPoint);
      expect(c.selection, {table.id, row.id});
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      surface().onSelectDown!(rowPoint);
      expect(c.selection, {table.id, row.id});
      surface().onDragStart!(rowPoint);
      surface().onDragUpdate!(rowPoint + const Offset(100, 50));
      surface().onDragEnd!();
      expect(c.selection, {table.id, row.id});
      final tableAfter = c.document.nodes.firstWhere((n) => n.id == table.id);
      final rowAfter = c.document.nodes.firstWhere((n) => n.id == row.id);
      expect(tableAfter.x - table.x, greaterThan(80));
      expect(tableAfter.x - table.x, rowAfter.x - row.x);
      expect(tableAfter.y - table.y, rowAfter.y - row.y);
      c.undo();
      expect(c.document.toJson(), original.toJson());
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      click(tablePoint);
      expect(c.selection, {row.id});
      const start = Offset(160, 180), end = Offset(440, 420);
      surface().onSelectDown!(start);
      surface().onDragStart!(start);
      surface().onDragUpdate!(end);
      surface().onDragEnd!();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(c.selection, {table.id, row.id});
      // A plain click, without dragging, focuses one member and does not edit it.
      click(tablePoint);
      expect(c.selection, {table.id});
      await tester.pump();
      expect(
        find
            .byType(EditableText)
            .evaluate()
            .where((e) => (e.widget as EditableText).focusNode.hasFocus),
        isEmpty,
      );
    },
  );
}
