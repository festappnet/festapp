import 'text_contract.dart';
import 'dart:math';
import 'model.dart';
import 'material_families.dart';
import 'scene_floor.dart';
import 'geometry.dart';
import 'node_outline.dart';
export 'node_outline.dart' show ScenePath, nodePath, nodeOutlineContours;

// Center object labels by their visible outlines rather than font ascent and
// line-box whitespace. Prepared resources stay immutable and authored text keeps
// its original baseline. Evaluate curve extrema, not off-curve control points.
List<dynamic> _centerLabelInk(List path) {
  var low = double.infinity, high = double.negativeInfinity;
  var y = 0.0, startY = 0.0;
  void include(double value) {
    low = min(low, value);
    high = max(high, value);
  }

  for (final raw in path) {
    final c = raw as List;
    if (c[0] == 'M') {
      y = startY = (c[2] as num).toDouble();
    } else if (c[0] == 'L') {
      include(y);
      y = (c[2] as num).toDouble();
      include(y);
    } else if (c[0] == 'Q') {
      final a = y, b = (c[2] as num).toDouble(), end = (c[4] as num).toDouble();
      include(a);
      include(end);
      final denominator = a - 2 * b + end;
      if (denominator.abs() > 1e-12) {
        final t = (a - b) / denominator;
        if (t > 0 && t < 1)
          include((1 - t) * (1 - t) * a + 2 * (1 - t) * t * b + t * t * end);
      }
      y = end;
    } else if (c[0] == 'C') {
      final a = y,
          b = (c[2] as num).toDouble(),
          d = (c[4] as num).toDouble(),
          end = (c[6] as num).toDouble();
      include(a);
      include(end);
      final qa = -a + 3 * b - 3 * d + end, qb = 2 * (a - 2 * b + d), qc = b - a;
      final roots = <double>[];
      if (qa.abs() < 1e-12) {
        if (qb.abs() > 1e-12) roots.add(-qc / qb);
      } else {
        final discriminant = qb * qb - 4 * qa * qc;
        if (discriminant >= 0) {
          roots.addAll([
            (-qb + sqrt(discriminant)) / (2 * qa),
            (-qb - sqrt(discriminant)) / (2 * qa),
          ]);
        }
      }
      for (final t in roots) {
        if (t > 0 && t < 1) {
          final u = 1 - t;
          include(
            u * u * u * a +
                3 * u * u * t * b +
                3 * u * t * t * d +
                t * t * t * end,
          );
        }
      }
      y = end;
    } else if (c[0] == 'Z') {
      include(y);
      include(startY);
      y = startY;
    }
  }
  if (!low.isFinite) return path;
  final center = (low + high) / 2;
  return [
    for (final raw in path)
      [
        (raw as List)[0],
        for (var i = 1; i < raw.length; i += 2) ...[
          raw[i],
          (raw[i + 1] as num) - center,
        ],
      ],
  ];
}

// Offset each contour towards the filled surface. Unlike scaling a bounding
// box, this keeps the rim inside concave branches and outside authored holes.
ScenePath _polygonMaterialPath(LayoutNode n, {required bool wood}) {
  final rings = [
    (n.properties['points'] as List)
        .map((p) => (p as List).map((v) => (v as num).toDouble()).toList())
        .toList(),
    for (final ring in n.properties['holes'] as List? ?? const [])
      (ring as List)
          .map((p) => (p as List).map((v) => (v as num).toDouble()).toList())
          .toList(),
  ];
  bool filled(List<double> p) =>
      pointInPolygon(rings.first, p[0], p[1]) &&
      !rings.skip(1).any((r) => pointInPolygon(r, p[0], p[1]));
  final path = <List<dynamic>>[];
  final inset = polygonRingArea(rings.first) < 0 ? -5.0 : 5.0;
  for (final ring in rings) {
    final offset = <List<double>>[];
    for (var i = 0; i < ring.length; i++) {
      final a = ring[(i + ring.length - 1) % ring.length],
          b = ring[i],
          c = ring[(i + 1) % ring.length];
      final ux = b[0] - a[0],
          uy = b[1] - a[1],
          vx = c[0] - b[0],
          vy = c[1] - b[1];
      final ul = sqrt(ux * ux + uy * uy), vl = sqrt(vx * vx + vy * vy);
      if (ul < .001 || vl < .001) continue;
      final px = b[0] - uy / ul * inset, py = b[1] + ux / ul * inset;
      final qx = b[0] - vy / vl * inset, qy = b[1] + vx / vl * inset;
      final cross = ux * vy - uy * vx;
      final t = cross.abs() < .001
          ? 0.0
          : ((qx - px) * vy - (qy - py) * vx) / cross;
      offset.add([px + t * ux, py + t * uy]);
    }
    if (offset.length < 3 || polygonSelfIntersects(offset)) continue;
    bool safeSegment(List<double> a, List<double> b) =>
        !rings.any((r) => polygonRingsTouch([a, b], r)) &&
        filled(a) &&
        filled(b) &&
        filled([(a[0] + b[0]) / 2, (a[1] + b[1]) / 2]);
    final safe = [
      for (var i = 0; i < offset.length; i++)
        safeSegment(offset[i], offset[(i + 1) % offset.length]),
    ];
    if (safe.every((v) => v)) {
      final radius = (n.properties['cornerRadius'] as num? ?? 6).toDouble();
      final outer =
          polygonRingArea(ring).sign == polygonRingArea(rings.first).sign;
      path.addAll(
        polygonContourPath(
          offset,
          cornerRadius: max(0, radius + (outer ? -inset.abs() : inset.abs())),
        ),
      );
    } else {
      // A narrow recess can collapse an inset; retain only safe edge details.
      for (var i = 0; i < offset.length; i++) {
        if (safe[i])
          path.addAll([
            ['M', ...offset[i]],
            ['L', ...offset[(i + 1) % offset.length]],
          ]);
      }
    }
  }
  if (wood) {
    // Clip plank joints to filled scan intervals, including every hole.
    for (
      var x = -n.width / 2 + 100;
      x < n.width / 2 && path.length < 4096;
      x += 100
    ) {
      final ys = <double>[];
      for (final r in rings) {
        for (var i = 0; i < r.length; i++) {
          final a = r[i], b = r[(i + 1) % r.length];
          if ((a[0] <= x && b[0] > x) || (b[0] <= x && a[0] > x)) {
            ys.add(a[1] + (x - a[0]) / (b[0] - a[0]) * (b[1] - a[1]));
          }
        }
      }
      ys.sort();
      for (var i = 0; i + 1 < ys.length; i += 2) {
        if (ys[i + 1] - ys[i] > inset.abs() * 4)
          path.addAll([
            ['M', x, ys[i] + inset.abs() * 2],
            ['L', x, ys[i + 1] - inset.abs() * 2],
          ]);
      }
    }
  }
  return path;
}

ScenePath _qpath(ScenePath p) =>
    p.map((c) => [c[0], ...c.skip(1).map((v) => quantize(v as num))]).toList();
final _sceneGeometryCache = Expando<_SceneGeometry>();

class _SceneGeometry {
  final List<Map<String, dynamic>> issues;
  late final Map<String, List<double>> matrices;
  final List<LayoutNode> ordered;
  late final Map<String, int> paintRanks;
  final Map<String, LayoutNode> nodes;
  final furnitureCapacity = <String, int>{};
  _SceneGeometry(VenueLayoutDocument d)
    : issues = validateDocument(d).map((i) => i.toJson()).toList(),
      ordered = orderedNodes(d),
      nodes = {for (final n in d.nodes) n.id: n} {
    matrices = issues.isEmpty ? worldMatrices(d) : {};
    paintRanks = {for (var i = 0; i < ordered.length; i++) ordered[i].id: i};
    if (issues.isEmpty) {
      for (final unit in d.selectionUnits) {
        final members = unit['nodeIds'] as List;
        if (members.isEmpty) continue;
        final parentId = nodes[members.first]?.parentId;
        if (parentId == null || nodes[parentId]?.kind != 'furniture') continue;
        if (members.every((id) => nodes[id]?.parentId == parentId)) {
          furnitureCapacity.putIfAbsent(parentId, () => members.length);
        }
      }
    }
  }
}

/// Visible background bounds use the same crop and transform as rendering.
List<List<double>> backgroundHull(VenueLayoutDocument document) {
  if (document.background == null) return const [];
  final scene = compileSceneNodes(document, const {}, includeCanvas: true);
  final items = (scene['items'] as List).where(
    (item) => item['id'] == 'background',
  );
  if (items.isEmpty) return const [];
  final item = items.first as Map;
  final rect = item['destinationRect'] as Map;
  final matrix = List<double>.from(item['matrix'] as List);
  final x = (rect['x'] as num).toDouble(), y = (rect['y'] as num).toDouble();
  final right = x + (rect['width'] as num),
      bottom = y + (rect['height'] as num);
  return [
    for (final p in [
      [x, y],
      [right, y],
      [right, bottom],
      [x, bottom],
    ])
      transformPoint(matrix, p[0], p[1]),
  ];
}

Map<String, dynamic> compileSceneNodes(
  VenueLayoutDocument document,
  Set<String> nodeIds, {
  bool includeCanvas = false,
  Map<String, dynamic> resources = const {},
  Map<String, dynamic> presentation = const {},
}) => _compileScene(
  document,
  resources: resources,
  presentation: presentation,
  nodeIds: nodeIds,
  includeCanvas: includeCanvas,
);
Map<String, dynamic> compileScene(
  VenueLayoutDocument document, {
  Map<String, dynamic> resources = const {},
  Map<String, dynamic> presentation = const {},
}) => _compileScene(document, resources: resources, presentation: presentation);
Map<String, dynamic> _compileScene(
  VenueLayoutDocument document, {
  Map<String, dynamic> resources = const {},
  Map<String, dynamic> presentation = const {},
  Set<String>? nodeIds,
  bool includeCanvas = false,
}) {
  if (document.schemaVersion != 2) {
    return {
      'protocol': 1,
      'canvas': document.canvas,
      'items': <Map<String, dynamic>>[],
      'issues': [
        {'reason': 'canonical_document_required', 'path': 'schemaVersion'},
      ],
    };
  }
  final cached = _sceneGeometryCache[document] ??= _SceneGeometry(document);
  final issues = cached.issues.toList(), items = <Map<String, dynamic>>[];
  if (issues.isNotEmpty)
    return {
      'protocol': 1,
      'canvas': document.canvas,
      'items': items,
      'issues': issues,
    };
  final matrices = cached.matrices;
  if (nodeIds == null || includeCanvas) {
    final floor = floorSceneItem(document);
    if (floor != null) items.add(floor);
  }
  if ((nodeIds == null || includeCanvas) && document.background != null) {
    final b = document.background!;
    final rot = (b['rotation'] as num? ?? 0) * pi / 180,
        s = (b['scale'] as num? ?? 1).toDouble();
    final width = (b['width'] as num? ?? document.canvas['width'] as num)
            .toDouble(),
        height = (b['height'] as num? ?? document.canvas['height'] as num)
            .toDouble(),
        crop =
            b['crop'] as Map? ??
            const {'x': 0, 'y': 0, 'width': 1, 'height': 1};
    final sourceRect = <String, double>{
      'x': quantize((crop['x'] as num) * width),
      'y': quantize((crop['y'] as num) * height),
      'width': quantize((crop['width'] as num) * width),
      'height': quantize((crop['height'] as num) * height),
    };
    final destinationRect = <String, double>{
      'x': quantize(-width / 2 + sourceRect['x']!),
      'y': quantize(-height / 2 + sourceRect['y']!),
      'width': sourceRect['width']!,
      'height': sourceRect['height']!,
    };
    items.add({
      'id': 'background',
      'paintOrder': [-1, 0],
      'kind': 'image',
      'assetRef': b['assetRef'],
      'matrix': [
        cos(rot) * s,
        sin(rot) * s,
        -sin(rot) * s,
        cos(rot) * s,
        b['x'] ?? 0,
        b['y'] ?? 0,
      ].map((v) => quantize(v as num)).toList(),
      'width': b['width'] ?? document.canvas['width'],
      'height': b['height'] ?? document.canvas['height'],
      'crop': crop,
      'sourceRect': sourceRect,
      'destinationRect': destinationRect,
      'opacity': b['opacity'] ?? 1,
      'clip': document.canvas,
    });
  }
  final nodesToPaint = nodeIds == null
      ? cached.ordered
      : (nodeIds.map((id) => cached.nodes[id]).whereType<LayoutNode>().toList()
          ..sort(
            (a, b) =>
                cached.paintRanks[a.id]!.compareTo(cached.paintRanks[b.id]!),
          ));
  for (final n in nodesToPaint) {
    if (n.kind == 'group') continue;
    final firstItem = items.length;
    final props = effectiveNodeProperties(document, n),
        state = presentation[n.id] as Map? ?? {},
        status = state['status'] ?? 'available',
        selected = state['selected'] == true,
        pending = state['pending'] == true;
    final fill =
        state['fill'] ??
        (selected
            ? layoutSelectedSeatFill
            : status == 'occupied'
            ? '#94A3B8FF'
            : n.kind == 'seat'
            ? layoutDefaultSeatFill
            : n.kind == 'table'
            ? '#E2E8F0FF'
            : n.kind == 'capacityArea'
            ? '#DBEAFEFF'
            : '#F1F5F9FF');
    final isCouch = n.kind == 'furniture' && props['furniture'] == 'couch';
    final parent = cached.nodes[n.parentId];
    final isCushion =
        n.kind == 'seat' &&
        parent?.kind == 'furniture' &&
        parent?.properties['furniture'] == 'couch';
    final matrix = matrices[n.id]!.map(quantize).toList();
    if (n.kind == 'vector' || n.kind == 'image') {
      final graphic = n.graphic!;
      final bounds = boundsOfPoints(worldHull(n, matrices[n.id]!));
      void media(Map<String, dynamic> value) => items.add({
        'id': '${n.id}:graphic:${items.length - firstItem}',
        'nodeId': n.id,
        'matrix': matrix,
        'cullingBounds': bounds,
        ...value,
        'paintOrder': [cached.paintRanks[n.id]!, items.length - firstItem],
      });
      if (n.kind == 'vector') {
        final w = (graphic['width'] as num).toDouble(),
            h = (graphic['height'] as num).toDouble();
        final local = <double>[
          n.width / w,
          0,
          0,
          n.height / h,
          -n.width / 2,
          -n.height / 2,
        ];
        final transform = multiplyMatrix(
          matrices[n.id]!,
          local,
        ).map(quantize).toList();
        media({
          'kind': 'vectorClip',
          'matrix': transform,
          'path': [
            ['M', 0, 0],
            ['L', w, 0],
            ['L', w, h],
            ['L', 0, h],
            ['Z'],
          ],
          'fillRule': 'nonzero',
        });
        media({
          'kind': 'vectorLayer',
          'opacity': resolveNodeAppearance(document, n).values['opacity'] ?? 1,
        });
        for (final raw in graphic['commands'] as List) {
          final command = Map<String, dynamic>.from(raw as Map),
              op = command.remove('op');
          media({
            'kind': switch (op) {
              'path' => 'vectorPath',
              'clip' => 'vectorClip',
              'layer' => 'vectorLayer',
              _ => 'vectorRestore',
            },
            'matrix': transform,
            ...command,
          });
        }
        media({'kind': 'vectorRestore'});
        media({'kind': 'vectorRestore'});
      } else {
        final asset = (resources['assets'] as Map?)?[graphic['assetRef']];
        if (asset is! Map ||
            asset['hash'] != graphic['hash'] ||
            asset['width'] is! num ||
            asset['height'] is! num) {
          issues.add({'reason': 'asset_unavailable', 'nodeId': n.id});
          continue;
        }
        final crop = graphic['crop'] as Map,
            w = asset['width'] as num,
            h = asset['height'] as num;
        media({
          'kind': 'image',
          'assetRef': graphic['assetRef'],
          'width': w,
          'height': h,
          'opacity': resolveNodeAppearance(document, n).values['opacity'] ?? 1,
          'sourceRect': {
            'x': crop['x'] * w,
            'y': crop['y'] * h,
            'width': crop['width'] * w,
            'height': crop['height'] * h,
          },
          'destinationRect': {
            'x': -n.width / 2,
            'y': -n.height / 2,
            'width': n.width,
            'height': n.height,
          },
        });
      }
      continue;
    }
    if (n.kind != 'text') {
      final pattern = props['strokePattern'] as Map?;
      final strokeType = pattern?['type'];
      final authoredDash = pattern?['lengths'];
      final dash =
          (authoredDash as List?)?.map((v) => (v as num).toDouble()).toList() ??
          (strokeType == 'dashed'
              ? <double>[8, 5]
              : strokeType == 'dotted'
              ? <double>[2, 4]
              : <double>[]);
      final styledNode = identical(props, n.properties)
          ? n
          : n.copyWith(properties: props);
      final hitPath = _qpath(nodePath(styledNode, parent: parent));
      final path = selected && n.kind == 'seat'
          ? props['points'] == null
                ? _qpath(
                    nodePath(
                      styledNode.copyWith(
                        width: n.width * layoutSelectedSeatScale,
                        height: n.height * layoutSelectedSeatScale,
                      ),
                      parent: parent,
                    ),
                  )
                : [
                    for (final command in hitPath)
                      [
                        command.first,
                        ...command
                            .skip(1)
                            .map(
                              (v) => quantize(
                                (v as num) * layoutSelectedSeatScale,
                              ),
                            ),
                      ],
                  ]
          : hitPath;
      items.add({
        'id': n.id,
        'kind': n.kind,
        'matrix': matrix,
        'path': path,
        'fill': const ['line', 'polyline', 'arrow'].contains(props['shape'])
            ? '#00000000'
            : state['fill'] ??
                  (selected || status == 'occupied'
                      ? fill
                      : props['fill'] ?? (isCushion ? '#F8FAFCFF' : fill)),
        'stroke': dash.isEmpty ? props['stroke'] ?? '#475569FF' : '#00000000',
        'strokeWidth': dash.isEmpty ? props['strokeWidth'] ?? 1 : 0,
        'opacity': props['opacity'] ?? 1,
        'hitPath': hitPath,
        'label': state['accessibilityLabel'] ?? n.label,
        'status': status,
        'selected': selected,
        'pending': pending,
      });
      if (dash.isNotEmpty)
        items.add({
          'id': '${n.id}:stroke',
          'nodeId': n.id,
          'kind': 'stroke',
          'renderBand': renderBand(n),
          'matrix': matrix,
          'path': dashedPath(path, dash),
          'fill': '#00000000',
          'stroke': props['stroke'] ?? '#475569FF',
          'strokeWidth': props['strokeWidth'] ?? 1,
          'opacity': props['opacity'] ?? 1,
        });
    }
    final seatStyle = chairStyle(n.copyWith(properties: props));
    final objectStyle =
        layoutMaterialFamilies[props['material']]?['construction'] ??
        props['material'] ??
        'simple';
    final materialState =
        selected ||
        status == 'occupied' ||
        pending ||
        state.containsKey('fill');
    final bodyFill =
        state['fill'] ??
        (selected || status == 'occupied' ? fill : props['fill'] ?? fill);
    if (n.kind == 'seat' &&
        !isCushion &&
        !const ['plain', 'round'].contains(seatStyle) &&
        !const [
          'polygon',
          'polyline',
          'line',
          'arrow',
        ].contains(props['shape'])) {
      final styledNode = n.copyWith(properties: props);
      final ScenePath accent;
      if (seatStyle == 'wood') {
        accent = contoursPath(
          isStoolNode(n, parent: parent)
              ? woodStoolFrame(styledNode)
              : woodChairFrame(styledNode, parent: parent),
        );
      } else if (const [
            'upholstered',
            'roundUpholstered',
          ].contains(seatStyle) &&
          !isStoolNode(n, parent: parent)) {
        accent = upholsteredChairBackrest(styledNode, parent: parent);
      } else if (seatStyle == 'banquet') {
        accent = banquetChairInlay(styledNode, parent: parent);
      } else {
        final inset = n.copyWith(
          width: n.width * .64,
          height: n.height * .60,
          properties: {
            'shape': seatStyle == 'transit' ? 'roundedRect' : 'ellipse',
            'cornerRadius': 4,
          },
        );
        accent = nodePath(inset);
      }
      items.add({
        'id': '${n.id}:seat-style',
        'nodeId': n.id,
        'kind': 'decoration',
        'renderBand': renderBand(n),
        'matrix': matrix,
        'path': _qpath(accent),
        'fill': seatStyle == 'wood'
            ? (materialState ? bodyFill : '#B88755FF')
            : '#00000000',
        'stroke': materialState
            ? '#FFFFFF80'
            : seatStyle == 'wood'
            ? '#6F4B2FFF'
            : props['stroke'] ?? '#47556980',
        'strokeWidth': min(
          (props['strokeWidth'] as num? ?? 1).toDouble(),
          min(n.width, n.height) * .035,
        ),
        'opacity': props['opacity'] ?? 1,
      });
    }
    if (n.kind == 'table' && objectStyle != 'simple') {
      final curved = const [
        'circle',
        'round',
        'ellipse',
        'oval',
      ].contains(props['shape']);
      final inset = n.copyWith(
        width: n.width * (curved ? 0.84 : 0.90),
        height: n.height * .84,
        properties: {
          ...props,
          'cornerRadius': max(0, (props['cornerRadius'] as num? ?? 6) - 3),
        },
      );
      final polygon = props['shape'] == 'polygon';
      final rim = polygon
          ? _polygonMaterialPath(
              n.copyWith(properties: props),
              wood: objectStyle == 'wood',
            )
          : nodePath(inset);
      if (objectStyle == 'wood' && !polygon) {
        if (curved) {
          // A restrained round construction mark above the centered label.
          final radius = min(n.width, n.height) * .045;
          final markCenter = props['orientation'] == 'object'
              ? <double>[0, -min(n.width, n.height) * .28]
              : transformPoint(
                  inverseMatrix(matrix),
                  matrix[4],
                  matrix[5] - min(n.width, n.height) * .28,
                );
          final mark = n.copyWith(
            width: radius * 2,
            height: radius * 2,
            properties: {'shape': 'circle'},
          );
          rim.addAll(
            nodePath(mark).map(
              (command) => [
                command.first,
                for (var i = 1; i < command.length; i++)
                  (command[i] as num) +
                      (i.isEven ? markCenter[1] : markCenter[0]),
              ],
            ),
          );
        } else {
          for (final x in [-n.width * .18, n.width * .18]) {
            rim.addAll([
              ['M', x, -n.height * .31],
              ['L', x, n.height * .31],
            ]);
          }
        }
      }
      items.add({
        'id': '${n.id}:table-style',
        'nodeId': n.id,
        'kind': 'decoration',
        'renderBand': renderBand(n),
        'matrix': matrix,
        'path': _qpath(rim),
        'fill': '#00000000',
        'stroke': materialState
            ? '#FFFFFF80'
            : objectStyle == 'wood'
            ? '#8B623FFF'
            : props['stroke'] ?? '#64748B80',
        'strokeWidth': min((props['strokeWidth'] as num? ?? 1).toDouble(), 2),
        'opacity': props['opacity'] ?? 1,
      });
    }
    if (isBarNode(n) && props['shape'] != 'polygon') {
      final side = props['guestSide'],
          horizontal = side == 'top' || side == 'bottom';
      final along = (horizontal ? n.width : n.height) * .43;
      final across =
          (horizontal ? n.height : n.width) *
          .34 *
          (side == 'top' || side == 'left' ? -1 : 1);
      final rail = <List<dynamic>>[
        ['M', horizontal ? -along : across, horizontal ? across : -along],
        ['L', horizontal ? along : across, horizontal ? across : along],
      ];
      items.add({
        'id': '${n.id}:bar-front',
        'nodeId': n.id,
        'kind': 'decoration',
        'renderBand': renderBand(n),
        'matrix': matrix,
        'path': _qpath(rail),
        'fill': '#00000000',
        'stroke': materialState
            ? '#FFFFFF80'
            : objectStyle == 'wood'
            ? '#6F4B2FFF'
            : props['stroke'] ?? '#475569FF',
        'strokeWidth': min(
          (props['strokeWidth'] as num? ?? 1).toDouble() + 1,
          3,
        ),
        'opacity': props['opacity'] ?? 1,
      });
    }
    if (isCouch) {
      // Upholstery parts use ordinary paths so every scene consumer paints the
      // same sofa. All retain ownership of the furniture's selection unit.
      final arm = objectStyle == 'lounge'
          ? min(n.width * .12, 18.0)
          : objectStyle == 'wood'
          ? min(n.width * .05, 8.0)
          : min(n.width * .08, 10.0);
      final back = objectStyle == 'lounge'
          ? min(n.height * .30, 30.0)
          : objectStyle == 'wood'
          ? min(n.height * .13, 13.0)
          : min(n.height * .23, 22.0);
      final upholstery = objectStyle == 'wood' && !materialState
          ? '#B88755FF'
          : bodyFill;
      void part(String name, double x, double y, double width, double height) {
        final shape = n.copyWith(
          width: width,
          height: height,
          properties: {
            'shape': 'roundedRect',
            'cornerRadius': objectStyle == 'wood'
                ? 1
                : objectStyle == 'lounge'
                ? min(width, height) / 2
                : props['cornerRadius'] ?? min(5, min(width, height) / 3),
          },
        );
        items.add({
          'id': '${n.id}:$name',
          'nodeId': n.id,
          'kind': 'decoration',
          'matrix': multiplyMatrix(matrix, [
            1,
            0,
            0,
            1,
            x,
            y,
          ]).map(quantize).toList(),
          'path': _qpath(nodePath(shape)),
          'fill': upholstery,
          'stroke': props['stroke'] ?? '#64748BFF',
          'strokeWidth': props['strokeWidth'] ?? 1,
          'opacity': props['opacity'] ?? 1,
        });
      }

      part(
        'backrest',
        0,
        -n.height / 2 + back / 2 + 2,
        max(1, n.width - arm * 2),
        back,
      );
      part(
        'left-arm',
        -n.width / 2 + arm / 2 + 2,
        0,
        arm,
        max(1, n.height - 4),
      );
      part(
        'right-arm',
        n.width / 2 - arm / 2 - 2,
        0,
        arm,
        max(1, n.height - 4),
      );
    }
    final text = n.kind == 'seat' || isCouch || isBarNode(n)
        ? ''
        : n.kind == 'text'
        ? '${props['text'] ?? ''}'
        : '${state['label'] ?? n.label}';
    if (text.isNotEmpty) {
      final prepared = preparedNodeText(
        document,
        n,
        resources,
        issues,
        text: text,
      );
      if (prepared != null) {
        final label = resolveNodeAppearance(document, n).label;
        items.add({
          'id': '${n.id}:text',
          'nodeId': n.id,
          'kind': 'glyphs',
          'minZoom': 0,
          'matrix': labelRenderMatrix(n, label, matrix),
          'path': n.kind == 'text'
              ? prepared['path']
              : _centerLabelInk(prepared['path'] as List),
          'localClip': prepared['clip'],
          'fill': label['color'],
          'stroke': '#00000000',
          'strokeWidth': 0,
          'label': text,
          'textResourceId': prepared['id'],
        });
      }
    }
    if (selected ||
        pending ||
        (status == 'occupied' && state['stateMarker'] != 'none')) {
      final markerWidth =
          n.width *
          (selected && n.kind == 'seat' ? layoutSelectedSeatScale : 1);
      final markerHeight =
          n.height *
          (selected && n.kind == 'seat' ? layoutSelectedSeatScale : 1);
      final unit = min(markerWidth, markerHeight) * .7 / 24;
      final statePath = selected
          ? <List<dynamic>>[
              ['M', -7 * unit, 0],
              ['L', -3 * unit, 4 * unit],
              ['L', 7 * unit, -6 * unit],
            ]
          : status == 'occupied'
          ? <List<dynamic>>[
              ['M', -9 * unit, -9 * unit],
              ['L', 9 * unit, 9 * unit],
              ['M', 9 * unit, -9 * unit],
              ['L', -9 * unit, 9 * unit],
            ]
          : <List<dynamic>>[
              ['M', -4 * unit, 0],
              ['L', 4 * unit, 0],
              ['M', 0, -4 * unit],
              ['L', 0, 4 * unit],
            ];
      items.add({
        'id': '${n.id}:state',
        'nodeId': n.id,
        'kind': 'state',
        'matrix': selected && n.kind == 'seat'
            ? [1, 0, 0, 1, matrix[4], matrix[5]]
            : matrix,
        'path': _qpath(statePath),
        'fill': '#00000000',
        'stroke': selected ? '#FFFFFFFF' : '#444444FF',
        'strokeWidth': quantize(unit * (selected ? 3 : 1.5)),
      });
    }
    if (n.kind == 'seat' && state['highlighted'] == true) {
      final w = n.width / 2 + 3, h = n.height / 2 + 3;
      items.add({
        'id': '${n.id}:highlight',
        'nodeId': n.id,
        'kind': 'state',
        'matrix': matrix,
        'path': [
          ['M', -w, -h],
          ['L', w, -h],
          ['L', w, h],
          ['L', -w, h],
          ['Z'],
        ],
        'fill': '#00000000',
        'stroke': '#2563EBFF',
        'strokeWidth': 3,
        'screenStrokeWidth': 2.5,
      });
    }
    final capacity = state['capacity'] ?? cached.furnitureCapacity[n.id];
    if (!isCouch && capacity is num && capacity > 1) {
      final outlineBounds = boundsOfPoints(worldHull(n, matrices[n.id]!));
      items.add({
        'id': '${n.id}:badge',
        'nodeId': n.id,
        'kind': 'glyphs',
        'minZoom': layoutLimits['glyphMinLogicalPixels']! / 16,
        'matrix': <double>[
          1,
          0,
          0,
          1,
          quantize(outlineBounds['x']! + outlineBounds['width']! / 2),
          quantize(outlineBounds['y']! + outlineBounds['height']! + 16),
        ],
        'path': canonicalNumberPath(
          document,
          capacity,
          resources,
          issues,
          n.id,
        ),
        'fill': '#222222FF',
        'label': '$capacity places',
      });
    }
    for (var i = firstItem; i < items.length; i++) {
      items[i]['paintOrder'] = [cached.paintRanks[n.id]!, i - firstItem];
    }
  }
  for (final item in items) {
    item['bounds'] = item['cullingBounds'] ?? sceneItemBounds(item);
  }
  return {
    'protocol': 1,
    'canvas': document.canvas,
    'items': items,
    'issues': issues,
  };
}

const layoutMotionTokens = {
  'insertMs': 160,
  'reflowMs': 200,
  'cameraMs': 240,
  'rejectMs': 160,
};
VenueLayoutDocument interpolateLayout(
  VenueLayoutDocument from,
  VenueLayoutDocument to,
  double t, {
  bool reducedMotion = false,
}) {
  final f = reducedMotion ? 1.0 : 1 - pow(1 - t.clamp(0, 1), 3).toDouble(),
      old = {for (final n in from.nodes) n.id: n};
  double lerp(double a, double b) => quantize(a + (b - a) * f);
  return to.copyWith(
    nodes: to.nodes.map((n) {
      final a = old[n.id];
      if (a == null) return n;
      final angle = ((n.rotation - a.rotation + 540) % 360) - 180;
      return n.copyWith(
        x: lerp(a.x, n.x),
        y: lerp(a.y, n.y),
        width: lerp(a.width, n.width),
        height: lerp(a.height, n.height),
        rotation: lerp(a.rotation, a.rotation + angle),
      );
    }).toList(),
  );
}

Map<String, double> sceneItemBounds(Map<String, dynamic> item) {
  final m = (item['matrix'] as List).map((v) => (v as num).toDouble()).toList(),
      points = <List<double>>[];
  if (item['kind'] == 'image') {
    final rect = item['destinationRect'] as Map<String, dynamic>,
        x = (rect['x'] as num).toDouble(),
        y = (rect['y'] as num).toDouble(),
        w = (rect['width'] as num).toDouble(),
        h = (rect['height'] as num).toDouble();
    for (final p in [
      [x, y],
      [x + w, y],
      [x + w, y + h],
      [x, y + h],
    ]) {
      points.add(transformPoint(m, p[0], p[1]));
    }
  } else {
    for (final raw in item['path'] as List? ?? []) {
      final c = raw as List;
      for (var i = 1; i + 1 < c.length; i += 2) {
        points.add(
          transformPoint(
            m,
            (c[i] as num).toDouble(),
            (c[i + 1] as num).toDouble(),
          ),
        );
      }
    }
  }
  final b = boundsOfPoints(points),
      stroke = (item['strokeWidth'] as num? ?? 0).toDouble() / 2;
  return {
    'x': quantize(b['x']! - stroke),
    'y': quantize(b['y']! - stroke),
    'width': quantize(b['width']! + stroke * 2),
    'height': quantize(b['height']! + stroke * 2),
  };
}

bool sceneItemVisible(
  Map<String, dynamic> item,
  Map<String, double> viewport, {
  double zoom = 1,
}) {
  if (zoom < (item['minZoom'] as num? ?? 0)) return false;
  final b =
      item['cullingBounds'] as Map? ??
      item['bounds'] as Map? ??
      sceneItemBounds(item);
  return b['x'] + b['width'] >= viewport['x']! &&
      b['y'] + b['height'] >= viewport['y']! &&
      b['x'] <= viewport['x']! + viewport['width']! &&
      b['y'] <= viewport['y']! + viewport['height']!;
}

List<Map<String, dynamic>> cullScene(
  Map<String, dynamic> scene,
  Map<String, double> viewport, {
  double zoom = 1,
}) => (scene['items'] as List)
    .cast<Map<String, dynamic>>()
    .where((item) => sceneItemVisible(item, viewport, zoom: zoom))
    .toList();

double layoutEaseOut(double t) => 1 - pow(1 - t.clamp(0, 1), 3).toDouble();
final _sceneTweens = Expando<Expando<_SceneTween>>();
bool _sameList(List a, List b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] is List && b[i] is List) {
      if (!_sameList(a[i] as List, b[i] as List)) return false;
    } else if (a[i] != b[i])
      return false;
  }
  return true;
}

class _SceneTween {
  final List<Map<String, dynamic>> target;
  final Map<int, Map<String, dynamic>> before = {};
  _SceneTween(Map<String, dynamic> from, Map<String, dynamic> to)
    : target = (to['items'] as List).cast<Map<String, dynamic>>() {
    final old = {
      for (final raw in from['items'] as List) (raw as Map)['id']: raw,
    };
    for (var i = 0; i < target.length; i++) {
      final b = target[i], a = old[b['id']] as Map<String, dynamic>?;
      if (a != null &&
          (!_sameList(a['matrix'] as List, b['matrix'] as List) ||
              !_sameList(a['path'] as List? ?? [], b['path'] as List? ?? []) ||
              a['opacity'] != b['opacity']))
        before[i] = a;
    }
  }
}

Map<String, dynamic> interpolateScene(
  Map<String, dynamic> from,
  Map<String, dynamic> to,
  double t, {
  bool reducedMotion = false,
}) {
  if (reducedMotion || t >= 1) return to;
  if (t <= 0) return from;
  final easing = layoutEaseOut(t),
      byTarget = _sceneTweens[from] ??= Expando<_SceneTween>(),
      transition = byTarget[to] ??= _SceneTween(from, to),
      items = transition.target.toList();
  double lerp(num a, num b) => quantize(a + (b - a) * easing);
  for (final entry in transition.before.entries) {
    final a = entry.value,
        b = items[entry.key],
        am = (a['matrix'] as List).cast<num>(),
        bm = (b['matrix'] as List).cast<num>(),
        aa = atan2(am[1], am[0]),
        ba = atan2(bm[1], bm[0]),
        delta = (ba - aa + 3 * pi) % (2 * pi) - pi,
        angle = aa + delta * easing,
        scale = lerp(
          sqrt(am[0] * am[0] + am[1] * am[1]),
          sqrt(bm[0] * bm[0] + bm[1] * bm[1]),
        );
    final item = <String, dynamic>{
      ...b,
      'matrix': [
        quantize(cos(angle) * scale),
        quantize(sin(angle) * scale),
        quantize(-sin(angle) * scale),
        quantize(cos(angle) * scale),
        lerp(am[4], bm[4]),
        lerp(am[5], bm[5]),
      ],
      'opacity': lerp(a['opacity'] as num? ?? 1, b['opacity'] as num? ?? 1),
    };
    final ap = a['path'] as List?, bp = b['path'] as List?;
    if (b['kind'] != 'glyphs' &&
        ap != null &&
        bp != null &&
        ap.length == bp.length &&
        List.generate(
          ap.length,
          (i) =>
              (ap[i] as List).length == (bp[i] as List).length &&
              ap[i][0] == bp[i][0],
        ).every((same) => same)) {
      item['path'] = [
        for (var i = 0; i < ap.length; i++)
          [
            bp[i][0],
            for (var j = 1; j < (bp[i] as List).length; j++)
              lerp(ap[i][j] as num, bp[i][j] as num),
          ],
      ];
    }
    item['bounds'] = item['cullingBounds'] ?? sceneItemBounds(item);
    items[entry.key] = item;
  }
  return {...to, 'items': items};
}

/// Materialize stroke dashes once in the shared scene, including curved paths.
/// Curves use pinned subdivisions (cubic 32, quadratic 16); adapters draw paths.
ScenePath dashedPath(ScenePath path, List<double> pattern) {
  if (pattern.isEmpty || pattern.any((v) => !v.isFinite || v <= 0))
    throw ArgumentError('Dash lengths must be positive');
  final lengths = pattern.length.isOdd ? [...pattern, ...pattern] : pattern,
      out = <List<dynamic>>[];
  var x = 0.0,
      y = 0.0,
      startX = 0.0,
      startY = 0.0,
      index = 0,
      remaining = lengths.first;
  void line(double tx, double ty) {
    final dx = tx - x, dy = ty - y, distance = sqrt(dx * dx + dy * dy);
    if (distance < 1e-12) {
      x = tx;
      y = ty;
      return;
    }
    var consumed = 0.0;
    while (consumed < distance - 1e-10) {
      final step = min(remaining, distance - consumed);
      if (index.isEven) {
        out.add([
          'M',
          quantize(x + dx * consumed / distance),
          quantize(y + dy * consumed / distance),
        ]);
        out.add([
          'L',
          quantize(x + dx * (consumed + step) / distance),
          quantize(y + dy * (consumed + step) / distance),
        ]);
      }
      consumed += step;
      remaining -= step;
      if (remaining < 1e-10) {
        index = (index + 1) % lengths.length;
        remaining = lengths[index];
      }
    }
    x = tx;
    y = ty;
  }

  for (final c in path) {
    switch (c.first) {
      case 'M':
        x = (c[1] as num).toDouble();
        y = (c[2] as num).toDouble();
        startX = x;
        startY = y;
        index = 0;
        remaining = lengths.first;
      case 'L':
        line((c[1] as num).toDouble(), (c[2] as num).toDouble());
      case 'C':
        final ox = x, oy = y;
        for (var i = 1; i <= 32; i++) {
          final t = i / 32, u = 1 - t;
          line(
            u * u * u * ox +
                3 * u * u * t * (c[1] as num) +
                3 * u * t * t * (c[3] as num) +
                t * t * t * (c[5] as num),
            u * u * u * oy +
                3 * u * u * t * (c[2] as num) +
                3 * u * t * t * (c[4] as num) +
                t * t * t * (c[6] as num),
          );
        }
      case 'Q':
        final ox = x, oy = y;
        for (var i = 1; i <= 16; i++) {
          final t = i / 16, u = 1 - t;
          line(
            u * u * ox + 2 * u * t * (c[1] as num) + t * t * (c[3] as num),
            u * u * oy + 2 * u * t * (c[2] as num) + t * t * (c[4] as num),
          );
        }
      case 'Z':
        line(startX, startY);
    }
  }
  return out;
}
