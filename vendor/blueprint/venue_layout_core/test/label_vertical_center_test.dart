import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:venue_layout_core/venue_layout_core.dart';

void main() {
  final fixture = Map<String, dynamic>.from(
    jsonDecode(
      File(
        'vendor/blueprint/venue_seat_picker/assets/layout_fonts/fixtures.json',
      ).readAsStringSync(),
    ),
  );
  for (final curve in ['Q', 'C']) {
    test('$curve label centering uses visible curve extrema', () {
      final node = LayoutNode(
        id: newLayoutId(),
        kind: 'table',
        width: 200,
        height: 200,
        label: '9',
        surface: const {'type': 'rect'},
      );
      final document = VenueLayoutDocument(nodes: [node]);
      final request = nodeTextRequest(
        document,
        node,
        Map<String, dynamic>.from(fixture['fontFamilies']),
      );
      final path = [
        ['M', 0, 0],
        curve == 'Q' ? ['Q', 10, 100, 20, 0] : ['C', 5, 100, 15, 100, 20, 0],
        ['Z'],
      ];
      final scene = compileScene(
        document,
        resources: {
          ...fixture,
          'textLayouts': {
            request.id: {
              'id': request.id,
              'descriptor': request.resourceDescriptor,
              'clip': request.descriptor['box'],
              'path': path,
            },
          },
        },
      );
      final item = (scene['items'] as List).singleWhere(
        (i) => i['kind'] == 'glyphs',
      );
      expect(
        item['path'][0][2],
        curve == 'Q' ? -25 : -37.5,
        reason: 'control points extend beyond visible ink',
      );
    });
  }
  for (final rotation in [0.0, 90.0, 270.0]) {
    test('table label ink is vertically centered at rotation $rotation', () {
      final node = LayoutNode(
        id: newLayoutId(),
        kind: 'table',
        x: 400,
        y: 400,
        width: 200,
        height: 40,
        rotation: rotation,
        label: '9',
        surface: const {'type': 'rect'},
      );
      final document = VenueLayoutDocument(nodes: [node]);
      final request = nodeTextRequest(
        document,
        node,
        Map<String, dynamic>.from(fixture['fontFamilies']),
      );
      // A valid prepared outline whose ascent/line box leaves the ink low.
      final prepared = {
        'id': request.id,
        'descriptor': request.resourceDescriptor,
        'clip': request.descriptor['box'],
        'path': [
          ['M', -5, 5],
          ['L', 5, 5],
          ['L', 5, 15],
          ['L', -5, 15],
          ['Z'],
        ],
      };
      final resources = {
        ...fixture,
        'textLayouts': {request.id: prepared},
      };
      final original = jsonEncode(resources);
      final scene = compileScene(document, resources: resources);
      final item =
          (scene['items'] as List).singleWhere(
                (i) => i['id'] == '${node.id}:text',
              )
              as Map<String, dynamic>;
      final bounds = sceneItemBounds(item);
      expect(bounds['x']! + bounds['width']! / 2, closeTo(400, .001));
      expect(bounds['y']! + bounds['height']! / 2, closeTo(400, .001));
      expect(
        jsonEncode(resources),
        original,
        reason: 'immutable prepared geometry is not rewritten',
      );
      final text = LayoutNode(
        id: node.id,
        kind: 'text',
        x: node.x,
        y: node.y,
        width: node.width,
        height: node.height,
        rotation: node.rotation,
        properties: {'text': '9'},
      );
      final textDoc = document.copyWith(nodes: [text]);
      final textRequest = nodeTextRequest(
        textDoc,
        text,
        Map<String, dynamic>.from(fixture['fontFamilies']),
      );
      final textScene = compileScene(
        textDoc,
        resources: {
          ...fixture,
          'textLayouts': {
            textRequest.id: {
              ...prepared,
              'id': textRequest.id,
              'descriptor': textRequest.resourceDescriptor,
            },
          },
        },
      );
      expect(textScene['issues'], isEmpty);
      final textItem = (textScene['items'] as List).singleWhere(
        (i) => i['kind'] == 'glyphs',
      );
      expect(
        textItem['path'],
        prepared['path'],
        reason: 'authored text keeps its baseline',
      );
    });
  }
}
