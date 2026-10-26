import 'dart:convert';
import 'dart:io';
import 'package:venue_layout_core/venue_layout_core.dart';

void main(List<String> args) {
  if (args.isNotEmpty && args.first == '--legacy-reimport') {
    final fixture = jsonDecode(File(args[1]).readAsStringSync()) as Map,
        catalog = jsonDecode(File(args[2]).readAsStringSync()) as Map;
    final families = {
      for (final entry in (catalog['resources']['fontFamilies'] as Map).entries)
        entry.key as String: Map<String, dynamic>.from(entry.value as Map),
    };
    final result = importLegacyLayout(
      Map<String, dynamic>.from(fixture['receipt']['source'] as Map),
      fontFamilies: families,
      sourceRevision: (fixture['receipt']['sourceRevision'] as int?) ?? 0,
    );
    if (!result.isReady) throw StateError('${result.receipt}');
    File(args[3]).writeAsStringSync(
      jsonEncode({
        'document': result.document!.toJson(),
        'receipt': result.receipt,
      }),
    );
    return;
  }

  if (args.isNotEmpty && args.first == '--couch-authoring') {
    final document = couchLayout(count: 2, x: 650, y: 470);
    File(
      args[1],
    ).writeAsStringSync(jsonEncode({'document': document.toJson()}));
    return;
  }
  if (args.isNotEmpty && args.first == '--svg-import') {
    final imported = importSvgGraphic(File(args[1]).readAsStringSync());
    final node = LayoutNode(
      id: '20000000-0000-4000-8000-000000000091',
      kind: 'vector',
      x: 1180,
      y: 570,
      width: 320,
      height: 160,
      graphic: {'type': 'vector', ...imported.graphic.toJson()},
      originalSource: imported.originalSource,
    );
    File(args[2]).writeAsStringSync(
      jsonEncode({'node': node.toJson(), 'receipt': imported.receipt}),
    );
    return;
  }
  if (args.isNotEmpty && args.first == '--text-requests') {
    final input = jsonDecode(File(args[1]).readAsStringSync()) as Map;
    final doc = VenueLayoutDocument.fromJson(
      Map<String, dynamic>.from(input['document']),
    );
    final families = Map<String, dynamic>.from(input['families']);
    final requests = collectTextRequests(doc, families, includePresets: true);
    final numeric = collectNumericFontFaces(doc, families);
    File(args[2]).writeAsStringSync(
      jsonEncode({
        'requests': [for (final r in requests.values) r.toJson()],
        'numericFaces': [
          for (final id in numeric)
            {
              'fontFaceId': id,
              'fontFamilyId': families.entries
                  .firstWhere(
                    (f) => (f.value['faces'] as Map).containsValue(id),
                  )
                  .key,
            },
        ],
      }),
    );
    return;
  }

  if (args.isNotEmpty && args.first == '--sql-corpus') {
    final corpus = jsonDecode(File(args[1]).readAsStringSync()) as Map;
    final scenes = <String, dynamic>{};
    for (final entry in corpus.entries) {
      final document = VenueLayoutDocument.fromJson(
        Map<String, dynamic>.from(entry.value['document'] as Map),
      );
      final resources = Map<String, dynamic>.from(
        entry.value['resources'] as Map,
      );
      final resourceIssues = validateLayoutResources(resources);
      if (resourceIssues.isNotEmpty) throw StateError('$resourceIssues');
      final scene = compileScene(document, resources: resources);
      if ((scene['issues'] as List).isNotEmpty) {
        throw StateError('${entry.key}: ${scene['issues']}');
      }
      scenes[entry.key as String] = {
        'document': document.toJson(),
        'scene': scene,
        'selectionUnits': document.selectionUnits,
      };
    }
    File(args[2]).writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(scenes)}\n',
    );
    return;
  }

  const group = '10000000-0000-4000-8000-000000000001',
      seat = '10000000-0000-4000-8000-000000000002',
      text = '10000000-0000-4000-8000-000000000003';
  final d = VenueLayoutDocument(
    nodes: [
      LayoutNode(
        id: '10000000-0000-4000-8000-000000000004',
        kind: 'shape',
        x: 450,
        y: 340,
        width: 160,
        height: 80,
        rotation: 17,
        properties: {
          'shape': 'ellipse',
          'fill': '#00000000',
          'stroke': '#E11D48FF',
          'strokeWidth': 3,
          'dash': [12, 8],
        },
      ),
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
      LayoutNode(
        id: text,
        kind: 'text',
        x: 200,
        y: 120,
        width: 400,
        height: 100,
        properties: {
          'text': 'Příliš žluťoučký kůň',
          'fontId': 'fixture:serif',
          'bold': true,
          'italic': true,
          'align': 'center',
        },
      ),
    ],
  );
  final resources = Map<String, dynamic>.from(
    jsonDecode(
      File('../../assets/layout_fonts/fixtures.json').readAsStringSync(),
    ),
  );
  final m = worldMatrix(d, d.nodes[2]);
  final output = {
    'document': d.toJson(),
    'resources': resources,
    'presentation': {
      seat: {'selected': true, 'pending': true},
    },
    'hitPoint': [m[4], m[5]],
    'expectedHit': hitTest(d, m[4], m[5]),
    'scene': compileScene(
      d,
      resources: resources,
      presentation: {
        seat: {'selected': true, 'pending': true},
      },
    ),
    'interpolated': interpolateLayout(
      d,
      transformNodes(d, {group}, dx: 120, rotation: 50),
      .4,
    ).toJson(),
  };
  if (args.isEmpty) {
    stdout.write(jsonEncode(output));
  } else {
    File(args.first).writeAsStringSync(jsonEncode(output));
  }
}
