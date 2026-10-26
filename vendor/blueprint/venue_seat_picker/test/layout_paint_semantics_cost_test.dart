import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_layout_core/venue_layout_core.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_scene_surface.dart';

class _Visits {
  int count = 0;
}

class _SemanticsVisits extends SingleChildRenderObjectWidget {
  const _SemanticsVisits({required this.visits, required super.child});
  final _Visits visits;
  @override
  RenderObject createRenderObject(BuildContext context) => _CountVisits(visits);
}

class _CountVisits extends RenderProxyBox {
  _CountVisits(this.visits);
  final _Visits visits;
  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    visits.count++;
    super.visitChildrenForSemantics(visitor);
  }
}

void main() {
  testWidgets(
    'paint-only layout changes avoid repeated accessible canvas traversals',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final visits = _Visits();
        final document = VenueLayoutDocument(
          nodes: [LayoutNode(id: newLayoutId(), kind: 'seat', x: 100, y: 100)],
        );
        final scene = ValueNotifier(compileScene(document));
        addTearDown(scene.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: Semantics(
              container: true,
              label: 'Accessible layout',
              child: _SemanticsVisits(
                visits: visits,
                child: ValueListenableBuilder<Map<String, dynamic>>(
                  valueListenable: scene,
                  builder: (context, value, _) => CustomPaint(
                    size: const Size(500, 500),
                    painter: LayoutScenePainter(
                      scene: value,
                      resources: const {},
                      selected: const {},
                      scale: 1,
                      offset: Offset.zero,
                      canvasColor: Colors.white,
                      selectionColor: Colors.blue,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final initial = visits.count;
        expect(find.bySemanticsLabel('Accessible layout'), findsOneWidget);
        scene.value = compileScene(
          document.copyWith(nodes: [document.nodes.single.copyWith(x: 150)]),
        );
        await tester.pump();
        expect(
          visits.count - initial,
          lessThanOrEqualTo(1),
          reason:
              'A widget update may visit once; geometry-only painting must not schedule additional semantic subtree traversals',
        );
        expect(find.bySemanticsLabel('Accessible layout'), findsOneWidget);
      } finally {
        semantics.dispose();
      }
    },
  );
}
