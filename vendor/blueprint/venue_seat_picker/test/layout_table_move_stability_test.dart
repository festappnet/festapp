import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_scene_surface.dart';

String seatAtSide(VenueLayoutDocument d, String side) => d.nodes
    .firstWhere((n) => n.kind == 'seat' && tableSideForSeat(d, n) == side)
    .id;

void main() {
  for (final native in [false, true]) {
    testWidgets(
      'repeated table drags clamp whole assembly without resize or seating changes native=$native',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1440, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        var doc = tableLayout(
          shape: 'roundedRect',
          width: 400,
          height: 100,
          count: 10,
          x: 600,
          y: 400,
        );
        final desk = doc.nodes.firstWhere((n) => n.kind == 'table');
        final wrapper = LayoutNode(
          id: newLayoutId(),
          kind: 'group',
          x: desk.x,
          y: desk.y,
          width: 400,
          height: 100,
          label: 'S10',
        );
        doc = doc.copyWith(
          canvas: {...doc.canvas, 'width': 1400, 'height': 900},
          nodes: [
            wrapper,
            for (final n in doc.nodes)
              n.id == desk.id
                  ? n.copyWith(parentId: wrapper.id, x: 0, y: 0)
                  : native
                  ? n.copyWith(parentId: wrapper.id)
                  : n,
          ],
          attachments: native ? [] : doc.attachments,
        );
        final original = doc;
        final c = VenueLayoutController(doc)..select({wrapper.id});
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
        for (final delta in [
          const Offset(0, -1000),
          const Offset(-1000, 0),
          const Offset(1000, 1000),
          const Offset(-220, -170),
        ]) {
          final center = worldMatrix(
            c.document,
            c.document.nodes.firstWhere((n) => n.id == desk.id),
          );
          final pointer = Offset(center[4], center[5]);
          surface().onDragStart!(pointer);
          surface().onDragUpdate!(pointer + delta);
          await tester.pump();
          surface().onDragEnd!();
          await tester.pump();
          for (final before in original.nodes.where(
            (n) => n.id != wrapper.id,
          )) {
            final after = c.document.nodes.firstWhere((n) => n.id == before.id);
            expect(
              after.toJson(),
              before.toJson(),
              reason: 'body/seat ${before.id} changed during translation',
            );
          }
          expect(c.document.attachments, original.attachments);
          expect(
            c.document.nodes.map((n) => n.id).toSet(),
            original.nodes.map((n) => n.id).toSet(),
          );
        }
        c.moveSelection(-12, 8);
        for (final before in original.nodes.where((n) => n.id != wrapper.id)) {
          expect(
            c.document.nodes.firstWhere((n) => n.id == before.id).toJson(),
            before.toJson(),
          );
        }
        expect(c.document.attachments, original.attachments);
        while (c.canUndo) {
          c.undo();
        }
        expect(c.document, same(original));
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('actual resize handles preserve explicit chair side preference', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var doc = tableLayout(
      shape: 'roundedRect',
      width: 500,
      height: 100,
      count: 10,
      x: 500,
      y: 350,
    );
    final table = doc.nodes.firstWhere((n) => n.kind == 'table');
    final moved = seatAtSide(doc, 'right');
    doc = moveTableSeatToSide(doc, moved, 'top');
    final c = VenueLayoutController(doc)..select({table.id});
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VenueLayoutEditor(controller: c, showGallery: false),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final surface = tester.widget<LayoutSceneSurface>(
      find.byWidgetPredicate(
        (w) => w is LayoutSceneSurface && w.onViewportScaleChanged != null,
      ),
    );
    final east = Offset(table.x + table.width / 2, table.y);
    surface.onHandleStart!('Resize e', east);
    surface.onDragUpdate!(east + const Offset(100, 0));
    surface.onDragEnd!();
    await tester.pump();
    expect(
      c.document.nodes.firstWhere((n) => n.id == table.id).width,
      greaterThan(table.width),
    );
    expect(
      c.document.attachments.firstWhere(
        (a) => a['seatId'] == moved,
      )['placement']['side'],
      'top',
    );
    expect(
      seatPlacementFree(
        c.document,
        c.document.nodes.firstWhere((n) => n.id == moved),
      ),
      false,
    );
    c.undo();
    expect(c.document, same(doc));
    expect(tester.takeException(), isNull);
  });
}
