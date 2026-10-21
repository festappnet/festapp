import 'dart:convert';
import 'dart:io';
import 'package:venue_layout_core/venue_layout_core.dart';

void main(List<String> args) {
  if (args.isNotEmpty && args.first == '--text-quality') {
    exportTextQuality(Directory(args[1]));
    return;
  }

  final output = Directory(args.isEmpty ? '/tmp/venue-layout-qa' : args.first)
    ..createSync(recursive: true);
  final root = File.fromUri(Platform.script).parent.parent.parent.parent;
  final resources = Map<String, dynamic>.from(
    jsonDecode(
      File('${root.path}/assets/layout_fonts/fixtures.json').readAsStringSync(),
    ),
  );
  final canonical =
      jsonDecode(
            File(
              '${root.path}/web/test/fixtures/canonical_rendering.json',
            ).readAsStringSync(),
          )
          as Map;
  for (final key in ['fontFamilies', 'textLayouts', 'numberSymbols'])
    resources[key] = {
      ...resources[key] as Map? ?? {},
      ...canonical['resources'][key] as Map? ?? {},
    };
  const hash =
      '623f3779d56f23b2f7498643cec8cb1a7976abd7b0df640903b92616a501fbb9';
  const raster =
      'iVBORw0KGgoAAAANSUhEUgAAAGQAAABQCAYAAADvCdDvAAAA40lEQVR4nO3RMRGAMADAwMph7syMYpSgBAdFBrneD28gGWvOtYPjPrcw/g5piCFphsQYEmNIjCExhsQYEmNIjCExhsQYEmNIjCExhsQYEmNIjCExhsQYEmNIjCExhsQYEmNIjCExhsQYEmNIjCExhsQYEmNIjCExhsQYEmNIjCExhsSMeb1rB+s5tmBIjCExhsQYEmNIjCExhsQYEmNIjCExhsQYEmNIjCExhsQYEmNIjCExhsQYEmNIjCExhsQYEmNIjCExhsQYEmNIjCExhsQYEmNIjCExhsQYEmNIjCExhsR8IRXr9VHGlAsAAAAASUVORK5CYII=';
  resources['assets'] = {
    'image:$hash': {
      'url': 'data:image/png;base64,$raster',
      'mimeType': 'image/png',
      'hash': hash,
      'width': 100,
      'height': 80,
      'byteLength': base64Decode(raster).length,
    },
  };
  const group = '10000000-0000-4000-8000-000000000001',
      seat = '10000000-0000-4000-8000-000000000002',
      text = '20000000-0000-4000-8000-000000000001';
  final d =
      VenueLayoutDocument.fromJson(
        Map<String, dynamic>.from(canonical['document']),
      ).copyWith(
        nodes: [
          ...VenueLayoutDocument.fromJson(
            Map<String, dynamic>.from(canonical['document']),
          ).nodes,
          LayoutNode(id: group, kind: 'group', x: 300, y: 250, rotation: 37),
          LayoutNode(
            id: seat,
            kind: 'seat',
            parentId: group,
            x: 90,
            y: 10,
            rotation: 22,
            label: '12',
          ),
        ],
      );
  final presentation = <String, dynamic>{
        seat: {'selected': true, 'pending': true},
      },
      m = worldMatrix(d, d.nodes.firstWhere((n) => n.id == seat)),
      target = transformNodes(d, {group, text}, dx: 120, rotation: 50);
  final motion = [
    for (final t in [0.0, 1 / 3, 2 / 3, 1.0])
      {
        't': t,
        'document': interpolateLayout(d, target, t).toJson(),
        'scene': compileScene(
          interpolateLayout(d, target, t),
          resources: resources,
          presentation: presentation,
        ),
      },
  ];
  final corpus = <Map<String, dynamic>>[];
  for (final count in [500, 5000, 20000]) {
    var layout = rowLayout(
      rows: (count / 50).ceil(),
      seatsPerRow: 50,
      x: 100,
      y: 100,
    );
    layout = fitCanvas(layout, padding: 40);
    // Semantic deterministic fixture IDs, independent of production UUID allocation.
    final ids = {
      for (var i = 0; i < layout.nodes.length; i++)
        layout.nodes[i].id:
            '20000000-0000-4000-8000-${i.toRadixString(16).padLeft(12, '0')}',
    };
    final json = layout.toJson();
    dynamic remap(dynamic v) => v is String
        ? ids[v] ?? v
        : v is List
        ? v.map(remap).toList()
        : v is Map
        ? v.map((k, v) => MapEntry(k, remap(v)))
        : v;
    layout = VenueLayoutDocument.fromJson(
      Map<String, dynamic>.from(remap(json)),
    );
    final documentJson = jsonEncode(layout.toJson()),
        watch = Stopwatch()..start(),
        scene = compileScene(layout, resources: resources);
    watch.stop();
    final sceneJson = jsonEncode(scene);
    File(
      '${output.path}/corpus-$count.document.json',
    ).writeAsStringSync(documentJson);
    File(
      '${output.path}/corpus-$count.scene.json',
    ).writeAsStringSync(sceneJson);
    corpus.add({
      'count': count,
      'documentFile': 'corpus-$count.document.json',
      'sceneFile': 'corpus-$count.scene.json',
      'sceneMs': watch.elapsedMicroseconds / 1000,
      'bytes': utf8.encode(documentJson).length,
      'sceneBytes': utf8.encode(sceneJson).length,
      'sceneItems': (scene['items'] as List).length,
      'issues': scene['issues'],
    });
  }
  final cropDocument = VenueLayoutDocument(
    canvas: {'x': 0, 'y': 0, 'width': 400, 'height': 300, 'fill': '#FFFFFFFF'},
    background: {
      'assetRef': 'image:$hash',
      'hash':
          '623f3779d56f23b2f7498643cec8cb1a7976abd7b0df640903b92616a501fbb9',
      'width': 100,
      'height': 80,
      'x': 200,
      'y': 150,
      'scale': 2,
      'rotation': 0,
      'crop': {'x': .1, 'y': .2, 'width': .6, 'height': .4},
    },
  );
  final report = {
    'protocol': 1,
    'resources': resources,
    'fixtures': [
      {
        'name': 'crop-preserves-registration',
        'document': cropDocument.toJson(),
        'toDocument': cropDocument.toJson(),
        'presentation': <String, dynamic>{},
        'scene': compileScene(cropDocument, resources: resources),
        'hits': <Map<String, dynamic>>[],
        'motion': [
          for (final t in [0.0, 1 / 3, 2 / 3, 1.0])
            {
              't': t,
              'document': cropDocument.toJson(),
              'scene': compileScene(cropDocument, resources: resources),
            },
        ],
      },
      {
        'name': 'rotated-czech-glyphs',
        'document': d.toJson(),
        'toDocument': target.toJson(),
        'presentation': presentation,
        'scene': compileScene(
          d,
          resources: resources,
          presentation: presentation,
        ),
        'hits': [
          {'x': m[4], 'y': m[5], 'id': seat},
          {'x': -100, 'y': -100, 'id': null},
        ],
        'motion': motion,
      },
    ],
    'corpus': corpus,
  };
  File('${output.path}/report.json').writeAsStringSync(jsonEncode(report));
  File(
    '${output.path}/fixture.report.json',
  ).writeAsStringSync(jsonEncode(report));
  stdout.writeln('QA fixtures exported to ${output.path}/report.json');
}

/// Actual CSS text sizes remain 10/12/16/24 at every camera zoom.
/// Source coordinates/sizes compensate for the camera; all four real faces are
/// prepared through the same production owner before either painter runs.
void exportTextQuality(Directory output) {
  output.createSync(recursive: true);
  final root = File.fromUri(Platform.script).parent.parent.parent.parent;
  final registry =
      jsonDecode(
            File(
              '${root.path}/assets/layout_fonts/fixtures.json',
            ).readAsStringSync(),
          )
          as Map;
  final family = Map<String, dynamic>.from(
    (registry['fontFamilies'] as Map)[canonicalLabelDefaults['fontFamilyId']],
  );
  final families = {family['id'] as String: family};
  final requests = <String, Map<String, dynamic>>{};
  final prepared = File('${output.path}/fixtures.json');
  final resources = prepared.existsSync()
      ? Map<String, dynamic>.from(
          jsonDecode(prepared.readAsStringSync()) as Map,
        )
      : null;
  final motion = <Map<String, dynamic>>[];
  for (final zoom in [.5, 1.0, 2.0, 4.0]) {
    final nodes = <LayoutNode>[];
    var row = 0;
    for (final face in [(400, false), (700, false), (400, true), (700, true)]) {
      for (final rotation in [0.0, 30.0, 90.0]) {
        var column = 0;
        for (final size in [10.0, 12.0, 16.0, 24.0]) {
          final index = row * 4 + column++;
          nodes.add(
            LayoutNode(
              id: '40000000-0000-4000-8000-${index.toRadixString(16).padLeft(12, '0')}',
              kind: 'text',
              x: (100 + (column - 1) * 200) / zoom,
              y: (100 + row * 180) / zoom,
              width: 176 / zoom,
              height: 42 / zoom,
              rotation: rotation,
              properties: {'text': 'Áě ffi € × A\u0301'},
              style: {
                'label': {
                  'fontFamilyId': family['id'],
                  'size': size / zoom,
                  'weight': face.$1,
                  'italic': face.$2,
                  'language': 'cs',
                  'direction': 'ltr',
                  'lineHeight': 1.2,
                },
              },
            ),
          );
        }
        row++;
      }
    }
    final doc = VenueLayoutDocument.fromJson(
      VenueLayoutDocument(
        nodes: nodes,
        canvas: {
          'x': 0,
          'y': 0,
          'width': 900 / zoom,
          'height': 2300 / zoom,
          'fill': '#FFFFFFFF',
        },
      ).toJson(),
    );
    final issues = validateDocument(doc);
    if (issues.isNotEmpty) throw StateError('$issues');
    for (final request in collectTextRequests(doc, families).values)
      requests[request.id] = request.toJson();
    final scene = resources == null
        ? null
        : compileScene(doc, resources: resources);
    if (scene != null && (scene['issues'] as List).isNotEmpty)
      throw StateError('${scene['issues']}');
    motion.add({
      't': zoom,
      'zoom': zoom,
      'document': doc.toJson(),
      if (scene != null) 'scene': scene,
    });
  }
  File(
    '${output.path}/quality-requests.json',
  ).writeAsStringSync(jsonEncode(requests.values.toList()));
  if (resources != null)
    File('${output.path}/report.json').writeAsStringSync(
      jsonEncode({
        'protocol': 2,
        'widths': [900],
        'dprs': [1, 2, 3],
        'viewportHeight': 2300,
        'quality': {
          'actualCssSizes': [10, 12, 16, 24],
          'rotations': [0, 30, 90],
          'faces': ['400:normal', '700:normal', '400:italic', '700:italic'],
          'zooms': [.5, 1, 2, 4],
          'text': 'Áě ffi € × A\u0301',
        },
        'resources': resources,
        'fixtures': [
          {
            'name': 'actual-css-text-quality',
            'presentation': {},
            'motion': motion,
          },
        ],
      }),
    );
  print(
    'Text quality: ${requests.length} whole-text requests; ${resources == null ? 'preparation required' : '48 labels x 4 zooms x 3 DPR ready'}',
  );
}
