import 'support/style.dart';
import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:venue_layout_core/venue_layout_core.dart';

void main() {
  test(
    'shared JSON equality handles nested immutable values without list reordering',
    () {
      expect(
        sameLayoutValue(
          {
            'b': [
              1,
              {'color': '#123456FF'},
            ],
            'a': true,
          },
          {
            'a': true,
            'b': [
              1.0,
              {'color': '#123456FF'},
            ],
          },
        ),
        isTrue,
      );
      expect(sameLayoutValue([1, 2], [2, 1]), isFalse);
      expect(sameLayoutValue({'a': null}, {}), isFalse);
      expect(sameLayoutValue({'a': 1}, {'a': 2}), isFalse);
    },
  );
  test(
    'node equality preserves canonical quantization and unordered override keys',
    () {
      final node = LayoutNode(
        id: newLayoutId(),
        kind: 'seat',
        x: 200,
        y: 200,
        properties: {
          'appearanceOverrides': ['fill', 'stroke'],
        },
        style: {'fill': '#123456FF', 'stroke': '#334455FF'},
      );
      expect(sameLayoutNode(node, node.copyWith(x: 200.0001)), isTrue);
      expect(sameLayoutNode(node, node.copyWith(x: 200.01)), isFalse);
      expect(
        sameLayoutNode(
          node,
          node.copyWith(
            properties: {
              ...node.properties,
              'appearanceOverrides': ['stroke', 'fill'],
            },
          ),
        ),
        isTrue,
      );
      expect(sameLayoutNode(node, node.copyWith(label: 'changed')), isFalse);
      expect(sameLayoutNode(node, node.copyWith(locked: true)), isFalse);
      expect(
        sameLayoutNode(
          node,
          node.copyWith(
            properties: {...node.properties},
            style: {'fill': '#112233FF'},
          ),
        ),
        isFalse,
      );
    },
  );
  test(
    'document comparison agrees with canonical JSON for common and reordered snapshots',
    () {
      final doc = couchLayout();
      final rounded = doc.copyWith(
        nodes: [for (final n in doc.nodes) n.copyWith(x: n.x + .0001)],
      );
      final reordered = doc.copyWith(
        nodes: doc.nodes.reversed.toList(),
        selectionUnits: [
          {
            ...doc.selectionUnits.single,
            'nodeIds': (doc.selectionUnits.single['nodeIds'] as List).reversed
                .toList(),
          },
        ],
      );
      for (final other in [doc.copyWith(), rounded, reordered]) {
        expect(sameLayoutDocument(doc, other), isTrue);
        expect(jsonEncode(doc.toJson()), jsonEncode(other.toJson()));
      }
      final styles = withKindStyle(doc, 'seat', {'seatStyle': 'wood'});
      expect(sameLayoutDocument(doc, styles), isFalse);
      expect(
        sameLayoutDocument(
          doc,
          transformNodes(doc, {doc.nodes.first.id}, dx: 20),
        ),
        isFalse,
      );
      expect(
        sameLayoutDocument(
          doc,
          doc.copyWith(nodes: doc.nodes.take(1).toList(), selectionUnits: []),
        ),
        isFalse,
      );
    },
  );
  test(
    'furniture unit index preserves badge counts and partial scene parity',
    () {
      final resources = Map<String, dynamic>.from(
        jsonDecode(
          File('../../assets/layout_fonts/fixtures.json').readAsStringSync(),
        ),
      );
      final nodes = <LayoutNode>[], units = <Map<String, dynamic>>[];
      for (var i = 0; i < 3; i++) {
        final furniture = LayoutNode(
          id: newLayoutId(),
          kind: 'furniture',
          x: 200 + i * 200,
          y: 200,
          width: 120,
          height: 100,
        );
        final seats = [
          for (var j = 0; j < 2; j++)
            LayoutNode(
              id: newLayoutId(),
              kind: 'seat',
              parentId: furniture.id,
              x: j * 50 - 25,
            ),
        ];
        nodes.addAll([furniture, ...seats]);
        units.add({
          'id': newLayoutId(),
          'kind': 'atomic',
          'nodeIds': seats.map((n) => n.id).toList(),
        });
      }
      final d = VenueLayoutDocument(nodes: nodes, selectionUnits: units);
      final full = compileScene(d, resources: resources)['items'] as List;
      expect(
        full.where((i) => (i['id'] as String).endsWith(':badge')).length,
        3,
      );
      for (final furniture in nodes.where((n) => n.kind == 'furniture')) {
        expect(
          full.singleWhere((i) => i['id'] == '${furniture.id}:badge')['label'],
          '2 places',
        );
        expect(
          compileSceneNodes(d, {furniture.id}, resources: resources)['items'],
          full
              .where(
                (i) => i['id'] == furniture.id || i['nodeId'] == furniture.id,
              )
              .toList(),
        );
      }
    },
  );
}
