import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_inspector.dart';

class _MeasuredController extends VenueLayoutController {
  _MeasuredController(super.document);
  int selectionReads = 0, selectionEntries = 0;
  @override
  Set<String> get selection {
    final value = super.selection;
    selectionReads++;
    selectionEntries += value.length;
    return value;
  }

  void pulse() => notifyListeners();
}

void main() {
  testWidgets(
    'layers build on demand and keep expansion across selection changes',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final nodes = List.generate(
        240,
        (i) => LayoutNode(
          id: newLayoutId(),
          kind: 'seat',
          label: 'Seat $i',
          x: (i % 20) * 40 + 20,
          y: (i ~/ 20) * 40 + 20,
          width: 24,
          height: 24,
        ),
      );
      final c = VenueLayoutController(
        VenueLayoutDocument.empty().copyWith(nodes: nodes),
      );
      addTearDown(c.dispose);
      c.select({nodes.first.id});
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AnimatedBuilder(
              animation: c,
              builder: (_, _) => LayoutInspector(
                controller: c,
                cornerPivot: false,
                onPivotChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      final rows = find.byWidgetPredicate(
        (widget) => widget is ListTile && widget.dense == true,
      );
      final search = find.widgetWithText(TextField, 'Find object');
      expect(rows, findsNothing);
      expect(search, findsNothing);
      c.select({nodes[1].id});
      await tester.pumpAndSettle();
      expect(rows, findsNothing);

      await tester.ensureVisible(find.text('Layers'));
      await tester.tap(find.text('Layers'));
      await tester.pumpAndSettle();
      expect(rows, findsNWidgets(200));
      c.select({nodes[2].id});
      await tester.pumpAndSettle();
      expect(rows, findsNWidgets(200));
      await tester.ensureVisible(search);
      await tester.enterText(search, 'Seat 239');
      await tester.pump();
      expect(rows, findsOneWidget);
      expect(find.widgetWithText(ListTile, 'Seat 239'), findsOneWidget);

      await tester.ensureVisible(find.text('Layers'));
      await tester.tap(find.text('Layers'));
      await tester.pumpAndSettle();
      expect(rows, findsNothing);
      c.select({nodes[3].id});
      await tester.pumpAndSettle();
      expect(rows, findsNothing);
      expect(search, findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    '5000-seat inspector keeps selection and layer search on repeated notifications',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final doc = VenueLayoutDocument.empty().copyWith(
        canvas: const {
          'x': 0,
          'y': 0,
          'width': 4800,
          'height': 2400,
          'fill': '#FFFFFFFF',
        },
        nodes: List.generate(
          5000,
          (i) => LayoutNode(
            id: newLayoutId(),
            kind: 'seat',
            x: (i % 100) * 48 + 24,
            y: (i ~/ 100) * 48 + 24,
            width: 24,
            height: 24,
            label: 'Seat $i',
          ),
        ),
      );
      final c = _MeasuredController(doc);
      addTearDown(c.dispose);
      c.select(doc.nodes.take(100).map((n) => n.id).toSet());
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 360,
              child: AnimatedBuilder(
                animation: c,
                builder: (context, _) => LayoutInspector(
                  controller: c,
                  cornerPivot: false,
                  onPivotChanged: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      c.selectionReads = 0;
      c.selectionEntries = 0;
      final micros = <int>[];
      for (var i = 0; i < 8; i++) {
        final watch = Stopwatch()..start();
        c.pulse();
        await tester.pump();
        micros.add(watch.elapsedMicroseconds);
      }
      micros.sort();
      // Debug widget timing is comparative evidence, not a release frame budget.
      debugPrint(
        'INSPECTOR_5000 selected=100 pulses=8 reads=${c.selectionReads} entriesReturned=${c.selectionEntries} pumpMedianUs=${micros[4]} pumpMaxUs=${micros.last}',
      );
      expect(
        find.text('100 objects selected. Individual values vary.'),
        findsOneWidget,
      );
      final previewMicros = <int>[];
      c.beginGesture();
      for (var i = 1; i <= 4; i++) {
        expect(
          c.preview(
            doc.copyWith(
              nodes: [
                doc.nodes.first.copyWith(x: 24.0 + i),
                ...doc.nodes.skip(1),
              ],
            ),
          ),
          isTrue,
        );
        final watch = Stopwatch()..start();
        await tester.pump();
        previewMicros.add(watch.elapsedMicroseconds);
      }
      debugPrint(
        'INSPECTOR_5000 geometryPreviews=4 pumpUs=$previewMicros (controller preview cost excluded)',
      );
      c.cancelGesture();
      await tester.pump();
      await tester.ensureVisible(find.text('Layers'));
      await tester.tap(find.text('Layers'));
      await tester.pumpAndSettle();
      final search = find.widgetWithText(TextField, 'Find object');
      await tester.ensureVisible(search);
      await tester.enterText(search, 'Seat 4999');
      await tester.pump();
      expect(find.widgetWithText(ListTile, 'Seat 4999'), findsOneWidget);
      await tester.tap(find.widgetWithText(ListTile, 'Seat 4999'));
      await tester.pump();
      expect(c.selection, {doc.nodes.last.id});
      c.updateNode(c.document.nodes.last.copyWith(label: 'Renamed last'));
      await tester.pump();
      await tester.ensureVisible(search);
      await tester.enterText(search, 'Renamed last');
      await tester.pump();
      expect(find.widgetWithText(ListTile, 'Renamed last'), findsOneWidget);
      await tester.ensureVisible(find.text('Layers'));
      await tester.tap(find.text('Layers'));
      await tester.pumpAndSettle();
      c.pulse();
      await tester.pump();
      expect(find.widgetWithText(ListTile, 'Renamed last'), findsNothing);
      await tester.tap(find.text('Layers'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ListTile, 'Renamed last'), findsOneWidget);
    },
  );
  testWidgets(
    'layer projection invalidates hierarchy, order and lock metadata',
    (tester) async {
      final group = LayoutNode(
        id: newLayoutId(),
        kind: 'group',
        x: 300,
        y: 300,
        width: 300,
        height: 300,
        label: 'Parent',
        z: 0,
      );
      final child = LayoutNode(
        id: newLayoutId(),
        kind: 'shape',
        parentId: group.id,
        x: 0,
        y: 0,
        width: 40,
        height: 40,
        label: 'Child',
        z: 1,
      );
      final c = VenueLayoutController(
        VenueLayoutDocument.empty().copyWith(nodes: [group, child]),
      );
      addTearDown(c.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AnimatedBuilder(
              animation: c,
              builder: (context, _) => LayoutInspector(
                controller: c,
                cornerPivot: false,
                onPivotChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.ensureVisible(find.text('Layers'));
      await tester.tap(find.text('Layers'));
      await tester.pumpAndSettle();
      ListTile tile(String name) =>
          tester.widget<ListTile>(find.widgetWithText(ListTile, name));
      expect(tile('Child').contentPadding, const EdgeInsets.only(left: 12));
      c.updateNode(
        child.copyWith(clearParent: true, x: 800, y: 300, z: -1, locked: true),
      );
      await tester.pump();
      expect(tile('Child').contentPadding, const EdgeInsets.only(left: 0));
      expect(tile('Child').trailing, isA<Icon>());
      expect(
        tester.getTopLeft(find.widgetWithText(ListTile, 'Child')).dy,
        lessThan(tester.getTopLeft(find.widgetWithText(ListTile, 'Parent')).dy),
      );
    },
  );
}
