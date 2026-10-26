import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_palette_thumbnail.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_scene_surface.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_style.dart';

void main() {
  testWidgets(
    'schematic lines adapt to dark mode without changing authored content',
    (tester) async {
      final doc = VenueLayoutDocument(
        nodes: [
          shapeFromPoints(
            'polyline',
            [
              [0.0, 0.0],
              [100.0, 0.0],
            ],
            style: {'stroke': '#334155FF', 'strokeWidth': 2},
          ),
        ],
      );
      final before = doc.toJson();
      Widget app(Brightness brightness) => MaterialApp(
        theme: ThemeData(brightness: brightness),
        home: Builder(
          builder: (context) => Scaffold(
            body: Container(
              color: layoutWorkspaceColor(context),
              child: LayoutPaletteThumbnail(
                document: doc,
                resources: const {},
                kind: 'Line',
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(app(Brightness.dark));
      await tester.pumpAndSettle();
      LayoutScenePainter painter() => tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((w) => w.painter)
          .whereType<LayoutScenePainter>()
          .single;
      final darkItems = painter().scene['items'] as List;
      expect(darkItems.where((i) => i['stroke'] == '#CBD5E1FF'), isNotEmpty);
      expect(
        darkItems
            .where((i) => i['stroke'] == '#CBD5E1FF')
            .every((i) => (i['strokeWidth'] as num) * painter().scale >= 1.49),
        isTrue,
      );
      expect(
        tester
            .widgetList<Container>(find.byType(Container))
            .any((c) => c.color == const Color(0xFF151B24)),
        isTrue,
      );
      await tester.pumpWidget(app(Brightness.light));
      await tester.pumpAndSettle();
      expect(
        (painter().scene['items'] as List).where(
          (i) => i['stroke'] == '#334155FF',
        ),
        isNotEmpty,
      );
      expect(doc.toJson(), before);
      final seat = LayoutNode(id: newLayoutId(), kind: 'seat');
      expect(
        resolveNodeAppearance(
          VenueLayoutDocument(nodes: [seat]),
          seat,
        ).values['fill'],
        layoutDefaultSeatFill,
      );
    },
  );
}
