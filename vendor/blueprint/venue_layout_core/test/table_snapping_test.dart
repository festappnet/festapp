import 'package:test/test.dart';
import 'package:venue_layout_core/venue_layout_core.dart';

void main() {
  test('table magnets follow body centers after asymmetric chair reflow', () {
    final a = LayoutNode(
      surface: const {'type': 'rect'},
      id: newLayoutId(),
      kind: 'table',
      x: 200,
      y: 200,
      width: 100,
      height: 80,
    );
    final b = LayoutNode(
      surface: const {'type': 'rect'},
      id: newLayoutId(),
      kind: 'table',
      x: 500,
      y: 200,
      width: 100,
      height: 80,
    );
    final doc = VenueLayoutDocument(
      nodes: [
        a,
        b,
        LayoutNode(
          id: newLayoutId(),
          kind: 'seat',
          parentId: a.id,
          x: 100,
          width: 20,
          height: 20,
        ),
        LayoutNode(
          id: newLayoutId(),
          kind: 'seat',
          parentId: b.id,
          x: -90,
          width: 20,
          height: 20,
        ),
      ],
    );
    final snap = snapTranslation(doc, {a.id}, 294, 3);
    expect(snap.dx, 300);
    expect(snap.dy, 0);
    expect(snap.guides.any((g) => g['axis'] == 'x' && g['value'] == 450), true);
  });
}
