import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:venue_layout_core/venue_layout_core.dart';

const families = <String, Map<String, dynamic>>{
  'family:sans': {
    'id': 'family:sans',
    'faces': {
      '400:normal': 'fixture:sans',
      '700:normal': 'fixture:bold',
      '400:italic': 'fixture:italic',
      '700:italic': 'fixture:bold-italic',
    },
  },
};

class HistoricalInput {
  HistoricalInput({
    this.nodes = const [],
    Map<String, dynamic> defaultTextStyle = const {
      'fontId': 'fixture:sans',
      'size': 24,
      'color': '#222222FF',
    },
    Map<String, dynamic> appearance = const {},
  }) : raw = {
         'schemaVersion': 1,
         'symbolSetVersion': 1,
         'canvas': {
           'x': 0,
           'y': 0,
           'width': 2400,
           'height': 1600,
           'fill': '#FFFFFFFF',
         },
         'defaultTextStyle': defaultTextStyle,
         'appearance': appearance,
         'nodes': nodes.map((n) => n.toJson()).toList(),
       };
  HistoricalInput.fromJson(this.raw)
    : nodes = (raw['nodes'] as List)
          .map((v) => LayoutNode.fromJson(Map<String, dynamic>.from(v)))
          .toList();
  final Map<String, dynamic> raw;
  final List<LayoutNode> nodes;
  Map<String, dynamic> toJson() => raw;
  Map<String, List<double>> get materializedMatrices {
    final byId = {for (final n in nodes) n.id: n},
        result = <String, List<double>>{};
    List<double> matrix(LayoutNode n) => result.putIfAbsent(
      n.id,
      () => n.parentId == null
          ? localMatrix(n)
          : multiplyMatrix(matrix(byId[n.parentId]!), localMatrix(n)),
    );
    for (final n in nodes) {
      matrix(n);
    }
    return result;
  }
}

void main() {
  test(
    'legacy text ignores shape fill and preserves its actual label color',
    () {
      final node = LayoutNode(
        id: newLayoutId(),
        kind: 'text',
        properties: {'text': 'A', 'fill': '#FF0000FF', 'color': '#000000FF'},
      );
      final result = importLegacyLayout(
        HistoricalInput(nodes: [node]).toJson(),
        fontFamilies: families,
        sourceRevision: 1,
      );
      expect(result.isReady, isTrue);
      expect(result.document!.nodes.single.style.keys, contains('label'));
      expect(result.document!.nodes.single.style, isNot(contains('fill')));
      expect(
        resolveNodeAppearance(
          result.document!,
          result.document!.nodes.single,
        ).label['color'],
        '#000000FF',
      );
      expect(
        jsonEncode(result.receipt),
        contains('legacy_unused_text_visual_removed'),
      );
    },
  );

  test(
    'legacy screen-oriented centered labels keep their effective defaults during import',
    () {
      final node = LayoutNode(
            id: newLayoutId(),
            kind: 'table',
            x: 400,
            y: 300,
            width: 200,
            height: 100,
            rotation: 37,
            label: 'Table',
            properties: {'align': 'left'},
          ),
          source = HistoricalInput(
            defaultTextStyle: {
              'fontId': 'fixture:sans',
              'size': 24,
              'color': '#222222FF',
              'align': 'left',
            },
            nodes: [node],
          );
      final result = importLegacyLayout(
        source.toJson(),
        fontFamilies: families,
        sourceRevision: 1,
      );
      expect(result.isReady, isTrue);
      final document = result.document!,
          table = document.nodes.single,
          label = resolveNodeAppearance(document, table).label;
      expect(label['orientation'], 'screen');
      expect(label['align'], 'center');
      expect(labelRenderMatrix(table, label, worldMatrix(document, table)), [
        1,
        0,
        0,
        1,
        400,
        300,
      ]);
      expect(result.receipt['source'], source.toJson());
    },
  );

  test(
    'legacy transport parameters and physical profiles materialize without changing any rendered pose',
    () {
      final source = HistoricalInput.fromJson(
            Map<String, dynamic>.from(
              jsonDecode(
                    File(
                      'test/fixtures/legacy-bus-materialized.json',
                    ).readAsStringSync(),
                  )
                  as Map,
            ),
          ),
          result = importLegacyLayout(
            source.toJson(),
            fontFamilies: families,
            sourceRevision: 1,
          );
      expect(result.isReady, isTrue);
      final converted = result.document!;
      expect(validateDocument(converted), isEmpty);
      expect(worldMatrices(converted), source.materializedMatrices);
      final root = converted.nodes.firstWhere((node) => node.kind == 'group');
      expect(root.seating['width'], 40);
      expect(root.assembly!['rows'], 2);
      final changed = updateBusLayout(converted, root.id, rows: 3);
      expect(validateDocument(changed), isEmpty);
      expect(
        changed.nodes.map((node) => node.id).toSet(),
        containsAll(converted.nodes.map((node) => node.id)),
      );
    },
  );
  test(
    'empty legacy couch remains materialized furniture with a recorded decision',
    () {
      final root = LayoutNode(
            id: newLayoutId(),
            kind: 'furniture',
            properties: {'furniture': 'couch'},
          ),
          source = HistoricalInput(nodes: [root]);
      final result = importLegacyLayout(
        source.toJson(),
        fontFamilies: families,
        sourceRevision: 1,
      );
      expect(result.isReady, isTrue);
      expect(result.document!.nodes.single.id, root.id);
      expect(result.document!.nodes.single.assembly, isNull);
      expect(
        (result.receipt['decisions'] as List).any(
          (decision) =>
              decision['reason'] ==
              'empty_couch_kept_as_materialized_furniture',
        ),
        isTrue,
      );
    },
  );

  test(
    'legacy inferred chair facing becomes a stored pose without changing its rendered geometry',
    () {
      final table = LayoutNode(
        id: newLayoutId(),
        kind: 'table',
        x: 400,
        y: 300,
        width: 200,
        height: 100,
        rotation: 23,
      );
      final seat = LayoutNode(
        id: newLayoutId(),
        kind: 'seat',
        parentId: table.id,
        x: 0,
        y: -100,
        rotation: 0,
      );
      final legacy = HistoricalInput(nodes: [table, seat]);
      final before = multiplyMatrix(
            localMatrix(table),
            localMatrix(seat.copyWith(rotation: 180)),
          ),
          result = importLegacyLayout(
            legacy.toJson(),
            fontFamilies: families,
            sourceRevision: 1,
          );
      expect(result.isReady, isTrue);
      final imported = result.document!,
          chair = imported.nodes.firstWhere((node) => node.id == seat.id);
      expect(chair.rotation, isNot(seat.rotation));
      expect(worldMatrix(imported, chair), before.map(quantize).toList());
      expect(
        (result.receipt['decisions'] as List).any(
          (decision) =>
              decision['reason'] == 'legacy_effective_rotation_materialized',
        ),
        isTrue,
      );
    },
  );

  test(
    'explicit legacy import preserves IDs and geometry but removes shadow style and aliases',
    () {
      final id = newLayoutId();
      final source = HistoricalInput(
        appearance: const {
          'table': {'size': 36},
        },
        nodes: [
          LayoutNode(
            id: id,
            kind: 'table',
            width: 200,
            height: 100,
            label: 'Table',
            properties: const {'size': 40, 'fill': '#ff0000ff'},
          ),
        ],
      ).toJson();
      final result = importLegacyLayout(
        source,
        fontFamilies: families,
        sourceRevision: 7,
      );
      expect(result.document, isNotNull);
      final d = result.document!, node = d.nodes.single;
      expect(d.schemaVersion, 2);
      expect(node.id, id);
      expect(node.width, 200);
      expect(node.properties.containsKey('size'), isFalse);
      expect(node.style['label'], isNull);
      expect(resolveNodeAppearance(d, node).label['size'], 36);
      final reset = d.copyWith(styles: {...d.styles, 'kinds': {}});
      expect(resolveNodeAppearance(reset, node).label['size'], 24);
      expect(
        acceptLegacyLayoutImport(result, source, currentRevision: 7),
        same(d),
      );
      expect(
        () => acceptLegacyLayoutImport(result, source, currentRevision: 8),
        throwsStateError,
      );
      expect(
        () => acceptLegacyLayoutImport(result, {
          ...source,
          'canvas': {...source['canvas'] as Map, 'width': 2000},
        }, currentRevision: 7),
        throwsStateError,
      );
      expect(result.receipt['sourceRevision'], 7);
      expect(result.receipt['source'], source);
      expect(result.isReady, isTrue);
      expect(result.receipt['status'], 'ready');
    },
  );
  test(
    'actual faces replace faux flags automatically with a recorded decision',
    () {
      final source = HistoricalInput(
        nodes: [
          LayoutNode(
            id: newLayoutId(),
            kind: 'text',
            properties: const {'text': 'AV', 'bold': true, 'italic': true},
          ),
        ],
      ).toJson();
      final result = importLegacyLayout(
        source,
        fontFamilies: families,
        sourceRevision: 1,
      );
      expect(result.document, isNotNull);
      expect(result.document!.nodes.single.style['label'], {
        'weight': 700,
        'italic': true,
      });
      expect(
        (result.receipt['decisions'] as List).any(
          (i) => i['reason'] == 'faux_typography_replaced',
        ),
        isTrue,
      );
    },
  );
  test(
    'offgrid surfaces get an exact module automatically without modifying source',
    () {
      final source = HistoricalInput(
        nodes: [
          LayoutNode(
            id: newLayoutId(),
            kind: 'table',
            width: 150,
            height: 100,
            properties: const {
              'shape': 'polygon',
              'points': [
                [-75, -50],
                [75, -50],
                [75, 50],
                [-75, 50],
              ],
            },
          ),
        ],
      ).toJson();
      final before = canonicalContractJson(source),
          result = importLegacyLayout(
            source,
            fontFamilies: families,
            sourceRevision: 1,
          );
      expect(result.document, isNotNull);
      expect(result.document!.nodes.single.surface!['moduleSize'], 50);
      expect(result.receipt['status'], 'ready');
      expect(canonicalContractJson(source), before);
      expect(
        importLegacyLayout(
          HistoricalInput().toJson(),
          fontFamilies: {},
          sourceRevision: 1,
        ).document,
        isNull,
      );
    },
  );
}
