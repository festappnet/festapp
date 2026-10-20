import '../../packages/venue_layout_core/test/support/style.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';

void main() {
  test(
    'selection returns stable immutable snapshots through editing and history',
    () {
      final a = LayoutNode(id: newLayoutId(), kind: 'seat', x: 200, y: 200),
          b = LayoutNode(id: newLayoutId(), kind: 'seat', x: 260, y: 200);
      final d = VenueLayoutDocument(nodes: [a, b]),
          c = VenueLayoutController(VenueLayoutDocument(nodes: [a, b]));
      final empty = c.selection;
      expect(identical(c.selection, c.selection), isTrue);
      c.select({a.id});
      final first = c.selection;
      expect(empty, isEmpty);
      expect(() => first.add(b.id), throwsUnsupportedError);
      c.select({a.id});
      expect(c.selection, same(first));
      c.beginGesture();
      expect(c.preview(transformNodes(c.document, {a.id}, dx: 10)), isTrue);
      expect(c.selection, same(first));
      c.cancelGesture();
      expect(c.selection, same(first));
      c.select({b.id});
      final second = c.selection;
      expect(first, {a.id});
      expect(second, {b.id});
      expect(c.apply(d.copyWith(nodes: [a])), isTrue);
      expect(c.selection, isEmpty);
      expect(second, {b.id});
      c.undo();
      expect(c.selection, {b.id});
      expect(() => c.selection.clear(), throwsUnsupportedError);
      c.dispose();
    },
  );
  test(
    'quantized no-op retains snapshot and baseline while real edits share undo',
    () {
      final n = LayoutNode(id: newLayoutId(), kind: 'seat', x: 200, y: 200);
      final doc = VenueLayoutDocument(nodes: [n]);
      final c = VenueLayoutController(doc);
      expect(
        c.apply(doc.copyWith(nodes: [n.copyWith(x: n.x + .0001)])),
        isTrue,
      );
      expect(c.document, same(doc));
      expect(c.canUndo, isFalse);
      expect(c.dirty, isFalse);
      expect(c.apply(transformNodes(doc, {n.id}, dx: 10)), isTrue);
      expect(c.dirty, isTrue);
      c.undo();
      expect(c.dirty, isFalse);
      final themed = withKindStyle(c.document, 'seat', {'seatStyle': 'wood'});
      expect(c.apply(themed), isTrue);
      expect(c.dirty, isTrue);
      c.markSaved();
      expect(c.dirty, isFalse);
      expect(
        c.apply(
          withKindStyle(c.document, 'seat', {'seatStyle': 'upholstered'}),
        ),
        isTrue,
      );
      expect(c.dirty, isTrue);
      c.undo();
      expect(c.dirty, isFalse);
      c.dispose();
    },
  );
}
