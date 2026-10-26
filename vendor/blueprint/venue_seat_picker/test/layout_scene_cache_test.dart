import '../packages/venue_layout_core/test/support/style.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:venue_seat_picker/src/layout_editor/layout_scene_cache.dart';

void main() {
  test(
    'pending editor preview retains prepared paths without changing canonical output and clears on ready or empty text',
    () {
      final fixture =
              jsonDecode(
                    File(
                      'web/test/fixtures/canonical_rendering.json',
                    ).readAsStringSync(),
                  )
                  as Map,
          full = VenueLayoutDocument.fromJson(
            Map<String, dynamic>.from(fixture['document'] as Map),
          ),
          resources = Map<String, dynamic>.from(fixture['resources'] as Map);
      final texts = full.nodes.where((node) => node.kind == 'text').toList(),
          first = texts[0],
          second = texts[1],
          original = full.copyWith(
            nodes: [first],
            attachments: [],
            selectionUnits: [],
            sections: [],
            presets: [],
          );
      final cache = LayoutTextPreviewCache(),
          initial = compileScene(original, resources: resources);
      final initialGlyph =
          (initial['items'] as List).firstWhere(
                (item) => item['kind'] == 'glyphs',
              )
              as Map;
      expect(cache.update(initial, original, enabled: true), same(initial));
      final changedNode = first.copyWith(
            properties: second.properties,
            style: second.style,
            x: first.x + 30,
            rotation: 40,
          ),
          changed = original.copyWith(nodes: [changedNode]);
      final missing = Map<String, dynamic>.from(resources['textLayouts'] as Map)
        ..removeWhere(
          (_, value) =>
              value['descriptor']['request']['text'] ==
              second.properties['text'],
        );
      final unavailable = compileScene(
        changed,
        resources: {...resources, 'textLayouts': missing},
      );
      expect(
        (unavailable['items'] as List).where(
          (item) => item['kind'] == 'glyphs',
        ),
        isEmpty,
      );
      final preview = cache.update(unavailable, changed, enabled: true),
          item =
              (preview['items'] as List).firstWhere(
                    (item) => item['kind'] == 'glyphs',
                  )
                  as Map;
      expect(item['path'], initialGlyph['path']);
      expect(item['matrix'], worldMatrix(changed, changedNode));
      expect(item['pendingTextPreview'], isTrue);
      expect(preview['issues'], unavailable['issues']);
      expect(
        (unavailable['items'] as List).where(
          (item) => item['kind'] == 'glyphs',
        ),
        isEmpty,
      );
      final ready = compileScene(changed, resources: resources);
      expect(ready['issues'], isEmpty);
      expect(cache.update(ready, changed, enabled: true), same(ready));
      expect(
        (ready['items'] as List).firstWhere(
          (item) => item['kind'] == 'glyphs',
        )['path'],
        isNot(initialGlyph['path']),
      );
      final empty = changed.copyWith(
            nodes: [
              changedNode.copyWith(properties: {'text': ''}),
            ],
          ),
          emptyScene = compileScene(empty, resources: resources);
      expect(cache.update(emptyScene, empty, enabled: true), same(emptyScene));
      expect(
        (emptyScene['items'] as List).where((item) => item['kind'] == 'glyphs'),
        isEmpty,
      );
      cache.update(initial, original, enabled: true);
      expect(
        cache.update(unavailable, changed, enabled: false),
        same(unavailable),
      );
      expect(
        cache.update(unavailable, changed, enabled: true),
        same(unavailable),
      );
    },
  );

  test(
    'canonical global styles invalidate retained scenes without changing geometry',
    () {
      final table = LayoutNode(
        id: newLayoutId(),
        kind: 'table',
        x: 500,
        y: 400,
        width: 200,
        height: 100,
        surface: {'type': 'rect'},
        locked: true,
      );
      final document = VenueLayoutDocument(schemaVersion: 2, nodes: [table]);
      final cache = LayoutSceneCache();
      final before = cache.update(document);
      final changed = setKindStyleLeaf(document, 'table', [
        'fill',
      ], value: '#FF0000FF');
      final actual = cache.update(changed);
      expect(actual, compileScene(changed));
      expect(actual, isNot(equals(before)));
      expect(changed.nodes.single.toJson(), table.toJson());
      final reset = setKindStyleLeaf(changed, 'table', ['fill'], unset: true);
      expect(cache.update(reset), before);
    },
  );

  test(
    'canvas resizing retains object paths and only rebuilds canvas decoration',
    () {
      final doc = tableLayout(shape: 'roundedRect').copyWith(
        canvas: {
          'x': 0,
          'y': 0,
          'width': 2400,
          'height': 1800,
          'fill': '#FFFFFFFF',
          'floorStyle': 'wood',
        },
      );
      final cache = LayoutSceneCache();
      final first = cache.update(doc);
      final items = {
        for (final item in first['items'] as List) item['id']: item,
      };
      final resized = resizeCanvas(doc, 2800, 2100);
      final next = cache.update(resized);
      expect(next, compileScene(resized));
      for (final item in next['items'] as List) {
        if (item['kind'] != 'floor' && item['id'] != 'background') {
          expect(
            item,
            same(items[item['id']]),
            reason:
                'Dragging a canvas edge must not recompile unchanged table/seat paths',
          );
        }
      }
      expect(
        (next['items'] as List).firstWhere((item) => item['kind'] == 'floor'),
        isNot(same(items['canvas:floor'])),
      );
    },
  );

  VenueLayoutDocument fixture() {
    final table = tableLayout(shape: 'roundedRect');
    return table.copyWith(
      nodes: [
        ...table.nodes,
        LayoutNode(id: newLayoutId(), kind: 'shape', x: 1000),
      ],
      styles: {
        'kinds': {
          'seat': {'seatStyle': 'wood', 'fill': '#FFEEDDFF'},
        },
      },
    );
  }

  test('geometry patches match full scenes and retain unaffected items', () {
    var document = fixture();
    final table = document.nodes.first;
    final stable = document.nodes.last.id;
    final cache = LayoutSceneCache();
    final first = cache.update(document);
    final item = (first['items'] as List).firstWhere(
      (dynamic i) => (i['nodeId'] ?? i['id']) == stable,
    );
    document = document.copyWith(
      nodes: [
        for (final n in document.nodes)
          if (n.id == table.id) n.copyWith(x: n.x + 45, rotation: 35) else n,
      ],
    );
    final moved = cache.update(document);
    expect(moved, compileScene(document));
    expect(
      (moved['items'] as List).firstWhere(
        (dynamic i) => (i['nodeId'] ?? i['id']) == stable,
      ),
      same(item),
    );
    document = reflowTable(document, table.id, 7);
    expect(cache.update(document), compileScene(document));
  });

  test(
    'presentation and geometry share a patch without losing seat decorations',
    () {
      var document = fixture();
      final cache = LayoutSceneCache();
      final seat = document.nodes.firstWhere((n) => n.kind == 'seat');
      cache.update(document);
      final presentation = <String, dynamic>{
        seat.id: {'selected': true},
      };
      document = document.copyWith(
        nodes: [
          for (final n in document.nodes)
            n.id == seat.id ? n.copyWith(rotation: 45) : n,
        ],
      );
      expect(
        cache.update(document, presentation: presentation),
        compileScene(document, presentation: presentation),
      );
      expect(cache.update(document), compileScene(document));
    },
  );

  test(
    'global, structure, layer and resource changes match full compilation',
    () {
      var document = fixture();
      final cache = LayoutSceneCache();
      cache.update(document);
      final variants = <VenueLayoutDocument>[
        withKindStyle(document, 'seat', {'cornerRadius': 12}),
        document.copyWith(canvas: {...document.canvas, 'fill': '#123456FF'}),
        document.copyWith(
          nodes: [for (final n in document.nodes) n.copyWith(z: n.z + 1)],
        ),
        document.copyWith(
          nodes: document.nodes.take(document.nodes.length - 1).toList(),
        ),
        groupNodes(document, {document.nodes.first.id, document.nodes.last.id}),
      ];
      for (final next in variants) {
        document = next;
        expect(cache.update(document), compileScene(document));
      }
      final resources = <String, dynamic>{};
      expect(
        cache.update(document, resources: resources),
        compileScene(document, resources: resources),
      );
    },
  );

  test(
    'invalid snapshots clear all items and recovery restores full scene',
    () {
      final valid = fixture();
      final cache = LayoutSceneCache();
      cache.update(valid);
      final invalid = valid.copyWith(
        nodes: [...valid.nodes, valid.nodes.first],
      );
      expect(cache.update(invalid), compileScene(invalid));
      expect(cache.update(valid), compileScene(valid));
    },
  );

  test(
    'font issues and newly appearing glyph paths preserve full scene order',
    () {
      final base = fixture();
      final cache = LayoutSceneCache();
      cache.update(base);
      final labeled = base.copyWith(
        nodes: [
          base.nodes.first.copyWith(label: 'Missing font'),
          ...base.nodes.skip(1),
        ],
      );
      expect(cache.update(labeled), compileScene(labeled));
      expect(cache.update(base), compileScene(base));
    },
  );
}
