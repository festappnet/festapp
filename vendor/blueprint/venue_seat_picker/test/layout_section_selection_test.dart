import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_scene_surface.dart';

void main() {
  testWidgets('ordinary object groups still select as a group', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final root = newLayoutId();
    final table = LayoutNode(
      id: newLayoutId(),
      kind: 'table',
      parentId: root,
      x: 300,
      y: 300,
      width: 200,
      height: 100,
      surface: const {'type': 'rect'},
    );
    final c = VenueLayoutController(
      VenueLayoutDocument(
        nodes: [
          LayoutNode(id: root, kind: 'group'),
          table,
        ],
      ),
    );
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VenueLayoutEditor(controller: c, showGallery: false),
        ),
      ),
    );
    final surface = tester.widget<LayoutSceneSurface>(
      find.byWidgetPredicate(
        (w) => w is LayoutSceneSurface && w.onSelectDown != null,
      ),
    );
    surface.onSelectDown!(Offset(table.x, table.y));
    await tester.pump();
    expect(c.selection, {root});
  });

  testWidgets(
    'clicking a table inside a hall section selects the table itself',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final doc = VenueLayoutTemplates.create('scout-ball-182');
      final c = VenueLayoutController(doc);
      addTearDown(c.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VenueLayoutEditor(controller: c, showGallery: false),
          ),
        ),
      );
      final table = doc.nodes.firstWhere(
        (n) => n.kind == 'table' && n.label == '1',
      );
      final surface = tester.widget<LayoutSceneSurface>(
        find.byWidgetPredicate(
          (w) => w is LayoutSceneSurface && w.onSelectDown != null,
        ),
      );
      expect(hitTest(doc, table.x, table.y), table.id);
      surface.onSelectDown!(Offset(table.x, table.y));
      await tester.pump();
      expect(c.selection, {table.id});
      expect(find.text('Table'), findsWidgets);
      final second = doc.nodes.firstWhere(
        (n) => n.kind == 'table' && n.label == '2',
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      surface.onSelectDown!(Offset(second.x, second.y));
      await tester.pump();
      expect(c.selection, {table.id, second.id});
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      final seat = doc.nodes.firstWhere(
        (n) => n.kind == 'seat' && n.parentId == table.id,
      );
      final m = worldMatrix(doc, seat);
      surface.onSelectDown!(Offset(m[4], m[5]));
      await tester.pump();
      expect(c.selection, {seat.id});
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(c.selection, isEmpty);
    },
  );
}
