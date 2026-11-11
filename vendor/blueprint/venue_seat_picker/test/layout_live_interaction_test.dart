import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_number_slider_control.dart';

void main() {
  test(
    'translated assemblies use current obstacles without stale moving footprints',
    () {
      final table = tableLayout(
        shape: 'rect',
        count: 0,
        x: 400,
        y: 400,
        width: 100,
        height: 100,
      );
      final root = table.nodes.firstWhere((n) => n.kind == 'table');
      final obstacle = LayoutNode(
        id: newLayoutId(),
        kind: 'furniture',
        x: 600,
        y: 400,
        width: 100,
        height: 100,
      );
      final document = table.copyWith(nodes: [...table.nodes, obstacle]);
      expect(
        translateLayoutWithinCanvas(document, {root.id}, dx: 200),
        same(document),
      );
      final together = translateLayoutWithinCanvas(document, {
        root.id,
        obstacle.id,
      }, dx: 200);
      expect(together.nodes.firstWhere((n) => n.id == root.id).x, 600);
      expect(together.nodes.firstWhere((n) => n.id == obstacle.id).x, 800);
      final overlapping = document.copyWith(
        nodes: [root, obstacle.copyWith(x: 400)],
      );
      expect(
        translateLayoutWithinCanvas(overlapping, {
          root.id,
          obstacle.id,
        }, dx: 200),
        same(overlapping),
      );
    },
  );

  testWidgets('cached inspector slider follows accepted preview each frame', (
    tester,
  ) async {
    final document = tableLayout(
      shape: 'round',
      x: 500,
      y: 500,
      width: 180,
      seating: const TableSeating(gap: 8),
    );
    final table = document.nodes.firstWhere((n) => n.kind == 'table');
    final c = VenueLayoutController(document);
    addTearDown(c.dispose);
    var previews = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LayoutNumberSliderControl(
            controller: c,
            node: table,
            label: 'Chair gap',
            value: 8,
            min: 0,
            max: 1000000,
            rangeMax: 64,
            updateDocument: (baseline, value) {
              previews++;
              return configureTableSeating(
                baseline,
                table.id,
                TableSeating.fromDocument(baseline, table).copyWith(gap: value),
              );
            },
          ),
        ),
      ),
    );
    Slider slider() => tester.widget<Slider>(find.byType(Slider));
    slider().onChangeStart!(8);
    for (var i = 1; i <= 40; i++) {
      slider().onChanged!(8 + i / 10);
    }
    await tester.pump();
    expect(
      slider().value,
      12,
      reason: 'The cached inspector must update its own thumb during drag',
    );
    expect(previews, 1, reason: 'Only the latest pointer sample is paintable');
    expect(c.gestureActive, isTrue);
    slider().onChanged!(13);
    slider().onChangeEnd!(13);
    await tester.pump();
    expect(
      c.document.nodes.firstWhere((n) => n.id == table.id).seating['gap'],
      13,
    );
    expect(c.canUndo, isTrue);
    c.undo();
    expect(c.document, same(document));
    expect(c.canUndo, isFalse);
  });

  test('scout hall controller drag CPU baseline', () {
    final source = VenueLayoutTemplates.create('scout-ball-182');
    final fragment = tableLayout(shape: 'round', x: 1600, y: 1600, width: 180);
    final table = fragment.nodes.firstWhere((n) => n.kind == 'table');
    final baseline = source.copyWith(
      nodes: [...source.nodes, ...fragment.nodes],
      attachments: [...source.attachments, ...fragment.attachments],
    );
    final c = VenueLayoutController(baseline);
    addTearDown(c.dispose);
    c.beginGesture();
    final operation = <int>[], accept = <int>[];
    for (var i = 1; i <= 30; i++) {
      final timer = Stopwatch()..start();
      final next = translateLayoutWithinCanvas(
        baseline,
        {table.id},
        dx: i.toDouble(),
        dy: 0,
      );
      final translation = timer.elapsedMicroseconds;
      timer.reset();
      expect(c.preview(next), isTrue);
      if (i > 10) {
        operation.add(translation);
        accept.add(timer.elapsedMicroseconds);
      }
    }
    operation.sort();
    accept.sort();
    debugPrint(
      'SCOUT_DRAG nodes=${baseline.nodes.length} translationMedianUs=${operation[10]} acceptMedianUs=${accept[10]}',
    );
  });
}
