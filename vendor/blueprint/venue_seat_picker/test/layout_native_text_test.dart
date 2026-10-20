import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_scene_surface.dart';

void main() {
  testWidgets(
    'editing uses cached actual fonts while resizing without prepared text; viewing keeps vectors',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final base = tableLayout(
        shape: 'rect',
        count: 0,
        x: 600,
        y: 400,
        width: 300,
        height: 200,
      );
      final d = base.copyWith(
        nodes: [
          for (final n in base.nodes)
            n.kind == 'table' ? n.copyWith(label: 'Editor table') : n,
        ],
      );
      final table = d.nodes.firstWhere((n) => n.kind == 'table');
      final c = VenueLayoutController(d)..select({table.id});
      addTearDown(c.dispose);
      var fonts = 0;
      Future<TextStyle> font(LayoutNode _) async {
        fonts++;
        return const TextStyle(fontFamily: 'Ahem');
      }

      Future<void> render(bool editing) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: VenueLayoutEditor(
                controller: c,
                showGallery: false,
                interactionEnabled: editing,
                inlineTextStyleBuilder: font,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      LayoutScenePainter painter() => tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((w) => w.painter)
          .whereType<LayoutScenePainter>()
          .firstWhere(
            (p) => (p.scene['items'] as List).any(
              (i) => (i['nodeId'] ?? i['id']) == table.id,
            ),
          );
      await render(true);
      expect(
        (painter().scene['items'] as List).where(
          (i) => i['kind'] == 'nativeText',
        ),
        hasLength(1),
      );
      expect(
        (painter().scene['items'] as List).any(
          (i) => i['kind'] == 'glyphs' && '${i['id']}'.endsWith(':text'),
        ),
        isFalse,
      );
      expect(find.text('Text is not ready yet.'), findsNothing);
      for (final height in [250.0, 300.0, 400.0]) {
        c.resizeObject(table.id, 300, height);
        await tester.pumpAndSettle();
        expect(c.error, isNull);
        expect((painter().scene['issues'] as List), isEmpty);
      }
      expect(fonts, 1);
      expect(c.resources['textLayouts'] ?? {}, isEmpty);
      Offset center() =>
          (tester.getCenter(
                find.byKey(const ValueKey('layout-handle-Resize n')),
              ) +
              tester.getCenter(
                find.byKey(const ValueKey('layout-handle-Resize s')),
              )) /
          2;
      final rotate = find.byKey(const ValueKey('layout-handle-Rotate'));
      expect(tester.getCenter(rotate).dy, lessThan(center().dy));
      c.rotateSelection(90);
      await tester.pumpAndSettle();
      expect(tester.getCenter(rotate).dx, greaterThan(center().dx));
      expect(tester.getCenter(rotate).dy, closeTo(center().dy, 1));
      await render(false);
      expect(
        (painter().scene['items'] as List).any(
          (i) => i['kind'] == 'nativeText',
        ),
        isFalse,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
