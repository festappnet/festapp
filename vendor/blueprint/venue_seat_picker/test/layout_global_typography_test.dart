import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';

void main() {
  test(
    'shared typography follows the cascade while locked nodes remain immutable and history restores declarations',
    () {
      final table = LayoutNode(
        id: newLayoutId(),
        kind: 'table',
        surface: const {'type': 'rect'},
        label: 'A',
      );
      final local = LayoutNode(
        kind: 'table',
        surface: const {'type': 'rect'},
        label: 'B',
        id: newLayoutId(),
        x: 400,
        style: const {
          'label': {'size': 40.64},
        },
      );
      final locked = LayoutNode(
        kind: 'table',
        surface: const {'type': 'rect'},
        label: 'C',
        id: newLayoutId(),
        x: 800,
        locked: true,
      );
      final original = VenueLayoutDocument(nodes: [table, local, locked]);
      final controller = VenueLayoutController(original);
      addTearDown(controller.dispose);
      var changed = setKindStyleLeaf(original, 'table', [
        'label',
        'size',
      ], value: 36);
      changed = setKindStyleLeaf(changed, 'table', [
        'label',
        'weight',
      ], value: 700);
      expect(controller.apply(changed), isTrue, reason: controller.error);
      expect(
        resolveNodeAppearance(controller.document, table).label['size'],
        36,
      );
      expect(
        resolveNodeAppearance(controller.document, local).label['size'],
        40.64,
      );
      expect(
        resolveNodeAppearance(controller.document, locked).label['size'],
        36,
      );
      expect(controller.document.nodes.last.toJson(), locked.toJson());
      final malicious = setNodeStyleLeaf(controller.document, locked.id, [
        'label',
        'size',
      ], value: 99);
      expect(controller.apply(malicious), isFalse);
      final reset = setKindStyleLeaf(controller.document, 'table', [
        'label',
        'size',
      ], unset: true);
      expect(controller.apply(reset), isTrue);
      expect(
        resolveNodeAppearance(controller.document, table).label['size'],
        24,
      );
      controller.undo();
      expect(
        resolveNodeAppearance(controller.document, table).label['size'],
        36,
      );
      controller.undo();
      expect(controller.document.toJson(), original.toJson());
      controller.redo();
      expect(
        controller.document.styles['kinds']['table']['label']['weight'],
        700,
      );
    },
  );
}
