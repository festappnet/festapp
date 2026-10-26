import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import 'package:venue_layout_core/venue_layout_core.dart';

void main() {
  test('whole-text identity survives canonical serialization of fractional table dimensions',(){
    final resources=Map<String,dynamic>.from(jsonDecode(File('../../assets/layout_fonts/fixtures.json').readAsStringSync()));
    final families=Map<String,dynamic>.from(resources['fontFamilies']);
    final source=VenueLayoutDocument(nodes:[LayoutNode(id:newLayoutId(),kind:'table',surface:const {'type':'rect'},width:296.5333330000003,height:99.73333300000002,label:'29',style:const {'label':{'size':70,'weight':700}})]);
    final read=VenueLayoutDocument.fromJson(jsonDecode(jsonEncode(source.toJson())));
    final before=collectTextRequests(source,families).values.single,after=collectTextRequests(read,families).values.single;
    expect(before.id,after.id);expect(before.resourceDescriptor,after.resourceDescriptor);
  });

  test(
    'historical input cannot reach a runtime renderer or glyph fallback',
    () {
      final legacy = VenueLayoutDocument(
        schemaVersion: 1,
        nodes: [
          LayoutNode(
            id: '10000000-0000-4000-8000-000000000001',
            kind: 'text',
            properties: {'text': 'AV', 'bold': true, 'italic': true},
          ),
        ],
      );
      final resources = {
        'fonts': {
          'fixture:sans': {
            'unitsPerEm': 1000,
            'glyphs': {
              'A': {
                'advance': 500,
                'path': [
                  ['M', 0, 0],
                  ['L', 1, 1],
                ],
              },
            },
          },
        },
      };
      for (final scene in [
        compileScene(legacy, resources: resources),
        compileSceneNodes(legacy, {
          legacy.nodes.single.id,
        }, resources: resources),
      ]) {
        expect(scene['items'], isEmpty);
        expect(scene['issues'], [
          {'reason': 'canonical_document_required', 'path': 'schemaVersion'},
        ]);
      }
    },
  );

  test(
    'text transitions switch prepared outlines discretely while retaining geometric motion',
    () {
      final a = {
            'protocol': 1,
            'items': [
              {
                'id': 'text',
                'kind': 'glyphs',
                'matrix': [1, 0, 0, 1, 0, 0],
                'path': [
                  ['M', 0, 0],
                  ['L', 10, 10],
                ],
                'fill': '#000000FF',
              },
            ],
          },
          b = {
            'protocol': 1,
            'items': [
              {
                'id': 'text',
                'kind': 'glyphs',
                'matrix': [1, 0, 0, 1, 20, 0],
                'path': [
                  ['M', 0, 0],
                  ['L', 20, 20],
                ],
                'fill': '#000000FF',
              },
            ],
          };
      final midway = interpolateScene(a, b, 0.5),
          item = (midway['items'] as List).single;
      expect(item['path'], (b['items'] as List).single['path']);
      expect(item['matrix'][4], greaterThan(0));
      expect(item['matrix'][4], lessThan(20));
    },
  );

  test(
    'canonical numeric codec matches independently shared JSON and hash corpus',
    () {
      final fixtures =
          jsonDecode(
                File('../../doc/layout-resource-codec.json').readAsStringSync(),
              )
              as List;
      for (final f in fixtures) {
        final encoded = canonicalContractJson(f['value']);
        expect(encoded, f['canonical']);
        expect(sha256.convert(utf8.encode(encoded)).toString(), f['sha256']);
      }
    },
  );
  test(
    'prepared whole text is painted verbatim; missing and stale layouts never fall back',
    () {
      final family = {
        'faces': {'400:normal': 'font:face'},
        'family': 'Test',
        'version': 1,
      };
      final hash = sha256
              .convert(utf8.encode(canonicalContractJson(family)))
              .toString(),
          id =
              'font-family:${sha256.convert(utf8.encode(canonicalContractJson(family)))}';
      final families = {
        id: {...family, 'id': id, 'hash': hash},
      };
      final node = LayoutNode(
        id: '10000000-0000-4000-8000-000000000001',
        kind: 'text',
        width: 200,
        height: 100,
        properties: {'text': 'AV fi العربية'},
      );
      final doc = VenueLayoutDocument(
        schemaVersion: 2,
        styles: {
          'label': {'fontFamilyId': id},
        },
        nodes: [node],
      );
      final request = nodeTextRequest(doc, node, families);
      final path = [
        ['M', -80, -20],
        ['C', -10, -40, 40, 35, 60, 20],
        ['Z'],
      ];
      final resources = {
        'protocol': 2,
        'fontFamilies': families,
        'textLayouts': {
          request.id: {
            'id': request.id,
            'descriptor': request.resourceDescriptor,
            'path': path,
            'clip': request.descriptor['box'],
          },
        },
      };
      expect(validateLayoutResources(resources), isEmpty);
      final scene = compileScene(doc, resources: resources),
          item = (scene['items'] as List).singleWhere(
            (i) => i['kind'] == 'glyphs',
          );
      expect(item['path'], path);
      expect(item['localClip'], request.descriptor['box']);
      expect(item['strokeWidth'], 0);
      final absent = compileScene(
        doc,
        resources: {'protocol': 2, 'fontFamilies': families, 'textLayouts': {}},
      );
      expect(
        (absent['items'] as List).where((i) => i['kind'] == 'glyphs'),
        isEmpty,
      );
      expect(
        (absent['issues'] as List).any(
          (i) => i['reason'] == 'text_layout_unavailable',
        ),
        isTrue,
      );
      final stale = doc.copyWith(
        nodes: [
          node.copyWith(properties: {'text': 'changed'}),
        ],
      );
      expect(
        (compileScene(stale, resources: resources)['items'] as List).where(
          (i) => i['kind'] == 'glyphs',
        ),
        isEmpty,
      );
    },
  );
  test(
    'invalid surface records report issues rather than crashing geometry projection',
    () {
      final doc = VenueLayoutDocument(
        schemaVersion: 2,
        nodes: [
          LayoutNode(
            id: '10000000-0000-4000-8000-000000000001',
            kind: 'table',
            surface: {'type': 'grid', 'moduleSize': 'bad', 'outer': false},
          ),
        ],
      );
      expect(validateDocument(doc), isNotEmpty);
    },
  );
  test(
    'vector scene preserves balanced paint operations and culls as one object',
    () {
      final graphic = importSvgGraphic(
        '<svg xmlns="http://www.w3.org/2000/svg" width="100" height="80"><g opacity="0.5"><path d="M0 0L100 80L0 80Z" fill="red"/></g></svg>',
      ).graphic;
      final doc = VenueLayoutDocument(
        schemaVersion: 2,
        nodes: [
          LayoutNode(
            id: '10000000-0000-4000-8000-000000000001',
            kind: 'vector',
            x: 500,
            y: 500,
            width: 200,
            height: 160,
            graphic: {'type': 'vector', ...graphic.toJson()},
          ),
        ],
      );
      expect(validateDocument(doc), isEmpty);
      final scene = compileScene(doc), items = scene['items'] as List;
      expect(items.where((i) => i['kind'] == 'vectorPath'), hasLength(1));
      expect(
        items.where((i) => i['kind'] == 'vectorRestore').length,
        items
            .where(
              (i) => i['kind'] == 'vectorClip' || i['kind'] == 'vectorLayer',
            )
            .length,
      );
      expect(
        cullScene(scene, {
          'x': 0,
          'y': 0,
          'width': 100,
          'height': 100,
        }).where((i) => i['nodeId'] != null),
        isEmpty,
      );
      expect(
        cullScene(scene, {
          'x': 450,
          'y': 450,
          'width': 100,
          'height': 100,
        }).where((i) => i['nodeId'] != null).length,
        items.where((i) => i['nodeId'] != null).length,
      );
    },
  );
}
