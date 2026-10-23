import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_scene_surface.dart';

void main() {
  testWidgets(
    'view shortcuts require selected double click or canvas triple click',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final table = LayoutNode(
        id: newLayoutId(),
        kind: 'table',
        x: 100,
        y: 100,
        width: 100,
        height: 80,
        surface: const {'type': 'rect'},
      );
      final c = VenueLayoutController(
        VenueLayoutDocument.empty().copyWith(nodes: [table]),
      );
      addTearDown(c.dispose);
      var selected = <String>{};
      final requests = <Set<String>>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (_, setState) => VenueLayoutEditor(
                controller: c,
                interactionEnabled: false,
                viewSelection: selected,
                viewSelectableIds: {table.id},
                onViewSelectionChanged: (ids) => setState(() => selected = ids),
                onEditRequested: requests.add,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> tap(Offset p) async {
        tester
            .widget<LayoutSceneSurface>(find.byType(LayoutSceneSurface))
            .onTap!(p);
        await tester.pump();
      }

      const object = Offset(100, 100), blank = Offset(800, 600);
      await tap(object);
      await tap(object);
      expect(
        requests,
        isEmpty,
        reason: 'A new selection requires a triple click',
      );
      await tap(blank); // Reset the click sequence at a different position.
      selected = {table.id};
      await tester.pumpWidget(const SizedBox());
      // Remount with a preselected object, as after selecting a sidebar row.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VenueLayoutEditor(
              controller: c,
              interactionEnabled: false,
              viewSelection: selected,
              viewSelectableIds: {table.id},
              onEditRequested: requests.add,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tap(object);
      expect(requests, isEmpty);
      await tap(object);
      expect(requests.single, {table.id});
      requests.clear();
      await tap(blank);
      await tap(blank);
      expect(requests, isEmpty);
      await tap(blank);
      expect(requests.single, {table.id});
      expect(
        c.canUndo,
        isFalse,
        reason: 'Mode shortcuts never mutate geometry',
      );
    },
  );
}
