import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:venue_layout_core/venue_layout_core.dart';

void main() {
  test('authored plan labels remain visible at whole-plan fit', () {
    final resources =
        jsonDecode(
              File(
                '../../assets/layout_fonts/fixtures.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final nodes = [
      LayoutNode(
        id: newLayoutId(),
        kind: 'text',
        x: 200,
        y: 200,
        width: 400,
        height: 60,
        properties: {'text': 'Stage'},
        style: {
          'label': {'size': 24},
        },
      ),
      LayoutNode(
        surface: const {'type': 'rect'},
        id: newLayoutId(),
        kind: 'table',
        x: 600,
        y: 400,
        width: 190,
        height: 110,
        label: '21',
      ),
    ];
    final scene = compileScene(
      VenueLayoutDocument(nodes: nodes),
      resources: resources,
    );
    final visible = cullScene(scene, {
      'x': 0,
      'y': 0,
      'width': 2400,
      'height': 1800,
    }, zoom: .2);
    expect(
      visible
          .where((item) => item['kind'] == 'glyphs')
          .map((item) => item['label']),
      containsAll(['Stage', '21']),
    );
  });
  test(
    'canonical labels follow the object and an explicit screen orientation stays upright',
    () {
      final resources =
          jsonDecode(
                File(
                  '../../assets/layout_fonts/fixtures.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final node = LayoutNode(
        surface: const {'type': 'rect'},
        id: newLayoutId(),
        kind: 'table',
        x: 300,
        y: 400,
        width: 700,
        height: 100,
        rotation: 270,
        label: 'Stůl 16',
        properties: {},
        style: {
          'label': {'size': 60},
        },
      );
      final plain = VenueLayoutDocument(nodes: [node]);
      final doc = plain.copyWith(
        nodes: [
          node.copyWith(
            properties: {...node.properties},
            style: {
              'label': {...node.style['label'] as Map, 'orientation': 'screen'},
            },
          ),
        ],
      );
      expect(validateDocument(doc), isEmpty);
      expect(VenueLayoutDocument.fromJson(doc.toJson()).toJson(), doc.toJson());
      Map label(VenueLayoutDocument d) =>
          (compileScene(d, resources: resources)['items'] as List).firstWhere(
                (item) => item['id'] == '${node.id}:text',
              )
              as Map;
      expect(label(plain)['matrix'], worldMatrix(plain, node));
      expect(label(doc)['matrix'], [1, 0, 0, 1, 300, 400]);
      expect(
        compileSceneNodes(doc, {node.id}, resources: resources)['items'],
        (compileScene(doc, resources: resources)['items'] as List)
            .where((i) => i['id'] == node.id || i['nodeId'] == node.id)
            .toList(),
      );
      final bad = doc.copyWith(
        nodes: [
          node.copyWith(
            properties: {...node.properties},
            style: {
              'label': {'orientation': 'random'},
            },
          ),
        ],
      );
      expect(
        validateDocument(bad).any((i) => i.reason == 'invalid_value'),
        isTrue,
      );
    },
  );
}
