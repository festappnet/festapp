import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_inspector.dart';

void main() {
  testWidgets(
    'layer hover highlights a subtree without selecting or editing it',
    (tester) async {
      final doc = tableLayout(count: 2, shape: 'rect');
      final table = doc.nodes.firstWhere((n) => n.kind == 'table');
      final c = VenueLayoutController(doc);
      addTearDown(c.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SizedBox(
                width: 400,
                child: LayoutInspector(controller: c, cornerPivot: false, onPivotChanged: (_) {}),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Layers'));
      await tester.pumpAndSettle();
      final row = find.byKey(ValueKey('layout-layer-${table.id}'));
      await tester.ensureVisible(row);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(790, 590));
      await mouse.moveTo(tester.getCenter(row));
      await tester.pump();
      expect(c.hoveredIds, contains(table.id));
      expect(c.selection, isEmpty);
      expect(c.canUndo, isFalse);
      expect(c.document.toJson(), doc.toJson());
      await mouse.moveTo(const Offset(790, 0));
      await tester.pump();
      expect(c.hoveredIds, isEmpty);
      await mouse.removePointer();
    },
  );
}
