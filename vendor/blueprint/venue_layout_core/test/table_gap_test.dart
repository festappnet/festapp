import 'package:test/test.dart';
import 'package:venue_layout_core/venue_layout_core.dart';

void main() {
  test(
    'global chair profile resizes physical seats and persists defaults without masking locks',
    () {
      final original = tableLayout(
        shape: 'rect',
        x: 700,
        y: 700,
        width: 400,
        height: 300,
        count: 4,
      );
      final changed = configurePlanTableSeating(
        original,
        width: 52,
        height: 48,
        spacing: 18,
        edgePadding: 20,
      );
      expect(
        documentSeating(changed).record,
        const TableSeating(
          width: 52,
          height: 48,
          spacing: 18,
          edgePadding: 20,
        ).record,
      );
      expect(
        changed.nodes
            .where((n) => n.kind == 'seat')
            .every((n) => n.width == 52 && n.height == 48),
        true,
      );
      expect(changed.nodes.map((n) => n.id), original.nodes.map((n) => n.id));
      expect(validateDocument(changed), isEmpty);
      final restored = VenueLayoutDocument.fromJson(changed.toJson());
      expect(documentSeating(restored).record, documentSeating(changed).record);
      final locked = original.copyWith(
        nodes: [
          for (final n in original.nodes)
            n.kind == 'table' ? n.copyWith(locked: true) : n,
        ],
      );
      final untouched = configurePlanTableSeating(
        locked,
        width: 52,
        height: 48,
        spacing: 18,
      );
      expect(untouched.nodes, locked.nodes);
      expect(
        effectiveNodeProperties(untouched, untouched.nodes.first)['seatWidth'],
        locked.nodes.first.properties['seatWidth'],
      );
      final empty = configurePlanTableSeating(
        VenueLayoutDocument.empty(),
        width: 52,
        height: 48,
        spacing: 18,
      );
      expect(documentSeating(empty).width, 52);
      expect(documentSeating(empty).height, 48);
      expect(documentSeating(empty).spacing, 18);
      expect(
        () => configurePlanTableSeating(empty, width: 0),
        throwsArgumentError,
      );
      expect(
        () => configurePlanTableSeating(empty, height: double.nan),
        throwsArgumentError,
      );
      expect(
        () => configurePlanTableSeating(empty, spacing: -1),
        throwsArgumentError,
      );
    },
  );
  test(
    'global gap keeps dimensions, identities, manual poses and style across table shapes',
    () {
      for (final shape in ['rect', 'circle', 'polygon']) {
        var source = tableLayout(
          shape: 'rect',
          x: 700,
          y: 700,
          width: 400,
          height: 300,
          count: 6,
          seating: const TableSeating(width: 60, height: 60, gap: 12),
        );
        if (shape == 'polygon') {
          source = setTableSurfaceKind(source, source.nodes.first.id, 'grid');
        } else if (shape == 'circle') {
          source = tableLayout(
            shape: 'circle',
            x: 700,
            y: 700,
            width: 300,
            height: 300,
            count: 6,
            seating: const TableSeating(width: 60, height: 60, gap: 12),
          );
        }
        source = withLayoutMaterialFamily(source, 'lounge');
        final manual = source.nodes.firstWhere((node) => node.kind == 'seat');
        source = source.copyWith(
          nodes: [
            for (final node in source.nodes)
              node.id == manual.id
                  ? node.copyWith(
                      properties: {...node.properties},
                      x: -450,
                      y: -400,
                      rotation: 37,
                    )
                  : node,
          ],
        );
        source = source.copyWith(
          attachments: [
            for (final a in source.attachments)
              a['seatId'] == manual.id
                  ? {
                      ...a,
                      'placement': {'mode': 'free'},
                      'rotationMode': 'manual',
                    }
                  : a,
          ],
        );
        final before = source.nodes.firstWhere((node) => node.id == manual.id);
        final configured = configurePlanTableGap(source, 30);
        expect(validateDocument(configured), isEmpty);
        expect(
          configured.nodes.map((node) => node.id).toSet(),
          source.nodes.map((node) => node.id).toSet(),
        );
        expect(
          configured.nodes.firstWhere((node) => node.id == manual.id).toJson(),
          before.toJson(),
        );
        expect(
          configured.nodes
              .where((node) => node.kind == 'seat')
              .every((node) => node.width == 60 && node.height == 60),
          true,
        );
        expect(
          TableSeating.fromDocument(configured, configured.nodes.first).gap,
          30,
        );
        expect(configured.styles['seat'], source.styles['seat']);
        expect(documentSeating(configured).gap, 30);
        expect(
          documentSeating(withLayoutMaterialFamily(configured, 'wood')).gap,
          30,
        );
        expect(
          VenueLayoutDocument.fromJson(configured.toJson()).toJson(),
          configured.toJson(),
        );
        expect(
          configured.nodes.any(
            (node) =>
                node.kind == 'seat' &&
                node.id != manual.id &&
                (node.x != source.nodes.firstWhere((n) => n.id == node.id).x ||
                    node.y !=
                        source.nodes.firstWhere((n) => n.id == node.id).y),
          ),
          true,
        );
      }
    },
  );
  test(
    'explicit chair rotation remains while automatic position follows the new gap',
    () {
      final source = tableLayout(
        shape: 'rect',
        x: 700,
        y: 700,
        width: 400,
        height: 300,
        count: 4,
      );
      final seat = source.nodes.firstWhere((node) => node.kind == 'seat');
      final rotated = transformNodes(source, {seat.id}, rotation: 37);
      final before = rotated.nodes.firstWhere((node) => node.id == seat.id);
      final configured = configurePlanTableGap(rotated, 30);
      final after = configured.nodes.firstWhere((node) => node.id == seat.id);
      expect(after.rotation, before.rotation);
      expect(seatAttachment(configured, after.id)!['rotationMode'], 'manual');
      expect(after.x != before.x || after.y != before.y, true);
    },
  );
  test(
    'empty plans retain the default; locked assemblies and bars remain unchanged',
    () {
      final empty = configurePlanTableGap(VenueLayoutDocument.empty(), 25);
      expect(documentSeating(empty).gap, 25);
      final source = tableLayout(shape: 'rect', count: 4);
      final locked = source.copyWith(
        nodes: [
          for (final node in source.nodes)
            node.id == source.nodes.first.id
                ? node.copyWith(locked: true)
                : node,
        ],
      );
      final changed = configurePlanTableGap(locked, 25);
      expect(changed.nodes, locked.nodes);
      final bar = barLayout(count: 3);
      expect(configurePlanTableGap(bar, 25).nodes, bar.nodes);
      expect(() => configurePlanTableGap(empty, -1), throwsArgumentError);
      expect(
        () => configurePlanTableGap(empty, double.nan),
        throwsArgumentError,
      );
      expect(() => configurePlanTableGap(empty, 1000001), throwsArgumentError);
      expect(() => configurePlanTableGap(source, 10000), throwsStateError);
      expect(source.styles, isEmpty);
    },
  );
}
