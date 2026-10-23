import 'minimal_appearance.dart' show layoutDefaultSeatFill;
import 'text_contract.dart' show validateCanonicalTextResources;
import 'dart:convert';
import 'dart:math';
import 'canonical_contract.dart';
import 'material_families.dart' show layoutMaterialFamilies;
import 'graphic_import.dart'
    show LayoutVectorGraphic, GraphicImportFailure, validOriginalSvgSource;

const layoutProtocol = 1;
const layoutLimits = <String, num>{
  'maxNodes': layoutMaxNodes,
  'maxSeats': layoutMaxSeats,
  'maxDepth': layoutMaxDepth,
  'maxBytes': layoutMaxBytes,
  'geometryAbsMax': 1000000000,
  'glyphMinLogicalPixels': 6,
  'canvasMin': 64,
  'canvasMax': 1000000,
  'textMaxCodePoints': 4096,
  'fontSizeMin': 1,
  'fontSizeMax': 4096,
  'lineHeightMin': 0.8,
  'lineHeightMax': 3,
  'verticesMin': 2,
  'polygonVerticesMin': 3,
  'verticesMax': 512,
  'presetsMax': 100,
  'presetNodesMax': 2000,
  'cropMin': 0,
  'cropMax': 1,
  'opacityMin': 0,
  'opacityMax': 1,
  'historyCommandsMax': 100,
  'historyBytesMax': 32 * 1024 * 1024,
  'fitCandidatesMax': 100000,
  'fitBatchMicroseconds': 8000,
  'coordinateQuantum': 1024,
};
const layoutMaxNodes = 25000;
const layoutMaxSeats = canonicalAssemblyMaxSeats;
const layoutMaxDepth = 16;
const layoutMaxBytes = 8 * 1024 * 1024;
double quantize(num value) =>
    (value * layoutLimits['coordinateQuantum']!).round() /
    layoutLimits['coordinateQuantum']!;
final _random = Random.secure();
String newLayoutId() {
  final b = List<int>.generate(16, (_) => _random.nextInt(256));
  b[6] = (b[6] & 15) | 64;
  b[8] = (b[8] & 63) | 128;
  final s = b.map((n) => n.toRadixString(16).padLeft(2, '0')).join();
  return '${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}-${s.substring(16, 20)}-${s.substring(20)}';
}

dynamic freeze(dynamic value) {
  final active = Set<Object>.identity();
  var entries = 0;
  dynamic copy(dynamic v, int depth) {
    if (depth > 64 || ++entries > 1000000) {
      throw const FormatException('JSON nesting or value count limit exceeded');
    }
    if (v == null || v is String || v is bool || v is num) return v;
    if (v is! Map && v is! List) {
      throw const FormatException('Only JSON values are supported');
    }
    if (!active.add(v as Object)) {
      throw const FormatException('Cyclic JSON value');
    }
    dynamic result;
    if (v is Map) {
      if (v.keys.any((k) => k is! String)) {
        throw const FormatException('JSON keys must be strings');
      }
      result = Map<String, dynamic>.unmodifiable(
        v.map((k, x) => MapEntry(k as String, copy(x, depth + 1))),
      );
    } else {
      result = List<dynamic>.unmodifiable(
        (v as List).map((x) => copy(x, depth + 1)),
      );
    }
    active.remove(v);
    return result;
  }

  return copy(value, 0);
}

Map<String, dynamic> frozenMap(Map<String, dynamic> v) =>
    freeze(v) as Map<String, dynamic>;

class InvalidLayoutDocument implements Exception {
  final List<LayoutIssue> issues;
  final Map<String, dynamic> original;
  InvalidLayoutDocument(List<LayoutIssue> issues, Map<String, dynamic> original)
    : issues = List.unmodifiable(issues),
      original = frozenMap(original);
  @override
  String toString() =>
      'Invalid layout: ${issues.map((i) => i.toString()).join('; ')}';
}

class UnsupportedLayoutSchema implements Exception {
  final Map<String, dynamic> original;
  UnsupportedLayoutSchema(this.original);
  @override
  String toString() => 'Unsupported layout schema ${original['schemaVersion']}';
}

class LayoutIssue {
  final String reason, path;
  final String? nodeId;
  const LayoutIssue(this.reason, this.path, [this.nodeId]);
  Map<String, dynamic> toJson() => {
    'reason': reason,
    'path': path,
    if (nodeId != null) 'nodeId': nodeId,
  };
  @override
  String toString() => '$path: $reason';
}

class LayoutNode {
  final String id, kind, label;
  final String? parentId;
  final double x, y, rotation, width, height;
  final int z;
  final bool locked;
  final Map<String, dynamic> properties;
  final Map<String, dynamic> style, childStyles, seating;
  final Map<String, dynamic>? surface, assembly, graphic, originalSource;
  LayoutNode({
    required this.id,
    required this.kind,
    this.parentId,
    this.x = 0,
    this.y = 0,
    this.rotation = 0,
    this.width = 40,
    this.height = 40,
    this.z = 0,
    this.locked = false,
    this.label = '',
    Map<String, dynamic> properties = const {},
    Map<String, dynamic> style = const {},
    Map<String, dynamic> childStyles = const {},
    Map<String, dynamic> seating = const {},
    Map<String, dynamic>? surface,
    Map<String, dynamic>? assembly,
    Map<String, dynamic>? graphic,
    Map<String, dynamic>? originalSource,
  }) : properties = frozenMap(properties),
       style = frozenMap(style),
       childStyles = frozenMap(childStyles),
       seating = frozenMap(seating),
       surface = surface == null ? null : frozenMap(surface),
       assembly = assembly == null ? null : frozenMap(assembly),
       graphic = graphic == null ? null : frozenMap(graphic),
       originalSource = originalSource == null
           ? null
           : frozenMap(originalSource);
  factory LayoutNode.fromJson(Map<String, dynamic> j) {
    final decodeIssues = _nodeDecodeIssues(j);
    if (decodeIssues.isNotEmpty) throw InvalidLayoutDocument(decodeIssues, j);
    final t = j['transform'] as Map;
    final props = Map<String, dynamic>.from(j)
      ..removeWhere(
        (k, v) =>
            const [
              'style',
              'childStyles',
              'seating',
              'surface',
              'graphic',
              'originalSource',
              'id',
              'kind',
              'parentId',
              'transform',
              'x',
              'y',
              'rotation',
              'width',
              'height',
              'z',
              'locked',
              'label',
              'x',
              'y',
              'rotation',
            ].contains(k) ||
            (k == 'assembly' && v is Map),
      );
    return LayoutNode(
      id: j['id'] as String,
      kind: j['kind'] as String,
      parentId: j['parentId'] as String?,
      x: (t['x'] as num? ?? 0).toDouble(),
      y: (t['y'] as num? ?? 0).toDouble(),
      rotation: (t['rotation'] as num? ?? 0).toDouble(),
      width: (j['width'] as num? ?? 40).toDouble(),
      height: (j['height'] as num? ?? 40).toDouble(),
      z: j['z'] as int? ?? 0,
      locked: j['locked'] as bool? ?? false,
      label: j['label'] as String? ?? '',
      properties: props,
      style: Map<String, dynamic>.from(j['style'] as Map? ?? {}),
      childStyles: Map<String, dynamic>.from(j['childStyles'] as Map? ?? {}),
      seating: Map<String, dynamic>.from(j['seating'] as Map? ?? {}),
      surface: j['surface'] == null
          ? null
          : Map<String, dynamic>.from(j['surface'] as Map),
      assembly: j['assembly'] is Map
          ? Map<String, dynamic>.from(j['assembly'] as Map)
          : null,
      graphic: j['graphic'] == null
          ? null
          : Map<String, dynamic>.from(j['graphic'] as Map),
      originalSource: j['originalSource'] == null
          ? null
          : Map<String, dynamic>.from(j['originalSource'] as Map),
    );
  }
  LayoutNode copyWith({
    String? kind,
    String? parentId,
    bool clearParent = false,
    double? x,
    double? y,
    double? rotation,
    double? width,
    double? height,
    String? label,
    bool? locked,
    Map<String, dynamic>? properties,
    Map<String, dynamic>? style,
    Map<String, dynamic>? childStyles,
    Map<String, dynamic>? seating,
    Map<String, dynamic>? surface,
    Map<String, dynamic>? assembly,
    Map<String, dynamic>? graphic,
    Map<String, dynamic>? originalSource,
    bool clearSurface = false,
    bool clearAssembly = false,
    bool clearGraphic = false,
    bool clearOriginalSource = false,
    int? z,
  }) => LayoutNode(
    id: id,
    kind: kind ?? this.kind,
    parentId: clearParent ? null : parentId ?? this.parentId,
    x: x ?? this.x,
    y: y ?? this.y,
    rotation: rotation ?? this.rotation,
    width: width ?? this.width,
    height: height ?? this.height,
    z: z ?? this.z,
    locked: locked ?? this.locked,
    label: label ?? this.label,
    properties: properties ?? this.properties,
    style: style ?? this.style,
    childStyles: childStyles ?? this.childStyles,
    seating: seating ?? this.seating,
    surface: clearSurface ? null : surface ?? this.surface,
    assembly: clearAssembly ? null : assembly ?? this.assembly,
    graphic: clearGraphic ? null : graphic ?? this.graphic,
    originalSource: clearOriginalSource
        ? null
        : originalSource ?? this.originalSource,
  );
  Map<String, dynamic> toJson() => {
    ...properties,
    if (style.isNotEmpty) 'style': style,
    if (childStyles.isNotEmpty) 'childStyles': childStyles,
    if (seating.isNotEmpty) 'seating': seating,
    if (surface != null) 'surface': surface,
    if (assembly != null) 'assembly': assembly,
    if (graphic != null) 'graphic': graphic,
    if (originalSource != null) 'originalSource': originalSource,
    'id': id,
    'kind': kind,
    if (parentId != null) 'parentId': parentId,
    'transform': {
      'x': quantize(x),
      'y': quantize(y),
      'rotation': quantize(rotation),
    },
    'width': quantize(width),
    'height': quantize(height),
    if (z != 0) 'z': z,
    if (locked) 'locked': true,
    if (label.isNotEmpty) 'label': label,
  };
}

/// A row root owns a typed assembly spec; legacy spelling exists only until
/// the explicit input cutover is complete.
bool isRowAssemblyNode(LayoutNode? node) =>
    node != null && node.kind == 'group' && node.assembly?['kind'] == 'rows';

class VenueLayoutDocument {
  final List<LayoutNode> nodes;
  final Map<String, dynamic> canvas;
  final List<Map<String, dynamic>> sections,
      selectionUnits,
      attachments,
      presets;
  final Map<String, dynamic>? background;
  final int symbolSetVersion, schemaVersion;
  final Map<String, dynamic> styles, seatingDefaults, textPolicy;
  VenueLayoutDocument({
    this.schemaVersion = 2,
    Map<String, dynamic> styles = const {},
    Map<String, dynamic> seatingDefaults = const {},
    Map<String, dynamic> textPolicy = const {
      'language': 'und',
      'direction': 'auto',
    },
    List<LayoutNode> nodes = const [],
    Map<String, dynamic> canvas = const {
      'x': 0,
      'y': 0,
      'width': 2400,
      'height': 1600,
      'fill': '#FFFFFFFF',
    },
    List<Map<String, dynamic>> sections = const [],
    List<Map<String, dynamic>> selectionUnits = const [],
    List<Map<String, dynamic>> attachments = const [],
    List<Map<String, dynamic>> presets = const [],
    Map<String, dynamic>? background,
    this.symbolSetVersion = 1,
  }) : nodes = List.unmodifiable(nodes),
       canvas = frozenMap(canvas),
       styles = frozenMap(styles),
       seatingDefaults = frozenMap(seatingDefaults),
       textPolicy = frozenMap(textPolicy),
       sections = _maps(sections),
       selectionUnits = _maps(selectionUnits),
       attachments = _maps(attachments),
       presets = _maps(presets),
       background = background == null ? null : frozenMap(background);
  static List<Map<String, dynamic>> _maps(List<Map<String, dynamic>> l) =>
      List.unmodifiable(l.map(frozenMap));
  factory VenueLayoutDocument.empty() => VenueLayoutDocument();
  factory VenueLayoutDocument.fromJson(Map<String, dynamic> j) {
    if (j['schemaVersion'] != 2) throw UnsupportedLayoutSchema(frozenMap(j));
    final decodeIssues = _documentDecodeIssues(j);
    if (decodeIssues.isNotEmpty) throw InvalidLayoutDocument(decodeIssues, j);
    List<Map<String, dynamic>> maps(String k) => (j[k] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final decoded = VenueLayoutDocument(
      schemaVersion: j['schemaVersion'] as int,
      styles: Map<String, dynamic>.from(j['styles'] as Map? ?? {}),
      seatingDefaults: Map<String, dynamic>.from(
        j['seatingDefaults'] as Map? ?? {},
      ),
      textPolicy: Map<String, dynamic>.from(
        j['textPolicy'] as Map? ??
            const {'language': 'und', 'direction': 'auto'},
      ),
      nodes: (j['nodes'] as List? ?? [])
          .map((e) => LayoutNode.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      canvas: Map<String, dynamic>.from(j['canvas'] as Map),
      sections: maps('sections'),
      selectionUnits: maps('selectionUnits'),
      attachments: maps('attachments'),
      presets: maps('presets'),
      background: j['background'] == null
          ? null
          : Map<String, dynamic>.from(j['background']),
      symbolSetVersion: j['symbolSetVersion'] as int? ?? 1,
    );
    final issues = validateDocument(decoded);
    if (issues.isNotEmpty) throw InvalidLayoutDocument(issues, j);
    return decoded;
  }
  VenueLayoutDocument copyWith({
    List<LayoutNode>? nodes,
    Map<String, dynamic>? canvas,
    int? schemaVersion,
    Map<String, dynamic>? styles,
    Map<String, dynamic>? seatingDefaults,
    Map<String, dynamic>? textPolicy,
    List<Map<String, dynamic>>? sections,
    List<Map<String, dynamic>>? selectionUnits,
    List<Map<String, dynamic>>? attachments,
    List<Map<String, dynamic>>? presets,
    Map<String, dynamic>? background,
    bool clearBackground = false,
  }) => VenueLayoutDocument(
    schemaVersion: schemaVersion ?? this.schemaVersion,
    styles: styles ?? this.styles,
    seatingDefaults: seatingDefaults ?? this.seatingDefaults,
    textPolicy: textPolicy ?? this.textPolicy,
    nodes: nodes ?? this.nodes,
    canvas: canvas ?? this.canvas,
    sections: sections ?? this.sections,
    selectionUnits: selectionUnits ?? this.selectionUnits,
    attachments: attachments ?? this.attachments,
    presets: presets ?? this.presets,
    background: clearBackground ? null : background ?? this.background,
    symbolSetVersion: symbolSetVersion,
  );
  Map<String, dynamic> toJson() {
    final issues = validateDocument(this);
    if (issues.isNotEmpty) {
      throw InvalidLayoutDocument(issues, {
        'schemaVersion': schemaVersion,
        'nodes': nodes.map((n) => {'id': n.id, 'kind': n.kind}).toList(),
      });
    }
    return _toJsonUnchecked();
  }

  Map<String, dynamic> _toJsonUnchecked({bool includeNodes = true}) =>
      _canonicalMap({
        'schemaVersion': schemaVersion,
        'symbolSetVersion': symbolSetVersion,
        'canvas': canvas,

        ...{
          'styles': styles,
          'seatingDefaults': seatingDefaults,
          'textPolicy': textPolicy,
        },
        'nodes':
            ((includeNodes ? nodes.toList() : <LayoutNode>[])
                  ..sort((a, b) => a.id.compareTo(b.id)))
                .map((n) => n.toJson())
                .toList(),
        'sections': _sortedRecords(sections),
        'selectionUnits': _sortedRecords(
          selectionUnits
              .map(
                (u) => {
                  ...u,
                  if (u['nodeIds'] is List)
                    'nodeIds': (List<dynamic>.from(u['nodeIds'])
                      ..sort((a, b) => a.toString().compareTo(b.toString()))),
                },
              )
              .toList(),
        ),
        'attachments': _sortedRecords(attachments, key: 'seatId'),

        'background': background,
        'presets': _sortedRecords(
          presets
              .map(
                (p) => {
                  ...p,
                  'document': VenueLayoutDocument.fromJson(
                    Map<String, dynamic>.from(p['document']),
                  ).toJson(),
                },
              )
              .toList(),
        ),
      });
}

final _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
);
final layoutColorPattern = RegExp(r'^#[0-9a-fA-F]{8}$');
// Layout nodes are deeply immutable. Weak keys avoid retaining old drafts;
// canvas-only snapshots can reuse the exact encoded byte count of each node.
final _encodedNodeBytes = Expando<int>();
int _documentPayloadBytes(VenueLayoutDocument document) {
  final envelope = document._toJsonUnchecked(includeNodes: false);
  var bytes = utf8.encode(jsonEncode(envelope)).length;
  for (final node in document.nodes) {
    bytes += _encodedNodeBytes[node] ??= utf8
        .encode(jsonEncode(node.toJson()))
        .length;
  }
  // The empty nodes array already contributes its brackets to the envelope.
  return bytes + (document.nodes.isEmpty ? 0 : document.nodes.length - 1);
}

final _validationCache = Expando<List<LayoutIssue>>();
List<LayoutIssue> validateDocument(VenueLayoutDocument d) =>
    _validationCache[d] ??= List<LayoutIssue>.unmodifiable(
      _validateDocumentUncached(d),
    );
List<LayoutIssue> _validateDocumentUncached(VenueLayoutDocument d) {
  if (d.schemaVersion != 2) {
    return [LayoutIssue('unsupported_schema', 'schemaVersion')];
  }
  final out = <LayoutIssue>[];
  void issue(String r, String p, [String? id]) =>
      out.add(LayoutIssue(r, p, id));
  final index = <String, LayoutNode>{};
  if (d.nodes.length > layoutMaxNodes) issue('node_limit', 'nodes');
  if (d.nodes.where((n) => n.kind == 'seat').length > layoutMaxSeats) {
    issue('seat_limit', 'nodes');
  }
  for (final k in ['x', 'y', 'width', 'height']) {
    final v = d.canvas[k];
    if (v is! num ||
        !v.isFinite ||
        (k == 'width' || k == 'height') &&
            (v < layoutLimits['canvasMin']! || v > layoutLimits['canvasMax']!)) {
      issue('invalid_canvas', 'canvas.$k');
    }
  }
  if (!layoutColorPattern.hasMatch('${d.canvas['fill']}')) {
    issue('invalid_color', 'canvas.fill');
  }
  for (final n in d.nodes) {
    if (!_uuid.hasMatch(n.id)) issue('invalid_uuid', 'nodes.id', n.id);
    if (index.containsKey(n.id)) issue('duplicate_id', 'nodes.id', n.id);
    index[n.id] = n;
    if (!const [
      'group',
      'table',
      'seat',
      'furniture',
      'capacityArea',
      'shape',
      'text',
      'image',
      'vector',
    ].contains(n.kind)) {
      issue('unknown_kind', 'nodes.kind', n.id);
    }
    if ([n.x, n.y, n.rotation, n.width, n.height].any((v) => !v.isFinite) ||
        n.width <= 0 ||
        n.height <= 0) {
      issue('invalid_geometry', 'nodes.transform', n.id);
    }
    final p = surfaceGeometryProperties(n);
    if (p.keys.any(
      (k) => const [
        'id',
        'kind',
        'parentId',
        'transform',
        'width',
        'height',
        'z',
        'locked',
        'label',
      ].contains(k),
    )) {
      issue('reserved_property', 'nodes.properties', n.id);
    }
    if (p['shape'] != null &&
        !const [
          'rect',
          'rectangle',
          'roundedRect',
          'ellipse',
          'oval',
          'circle',
          'round',
          'polygon',
          'polyline',
          'line',
          'arrow',
        ].contains(p['shape'])) {
      issue('invalid_shape', 'nodes.shape', n.id);
    }
    if (p['strokeWidth'] != null &&
        (p['strokeWidth'] is! num ||
            !(p['strokeWidth'] as num).isFinite ||
            (p['strokeWidth'] as num) < 0)) {
      issue('invalid_stroke', 'nodes.strokeWidth', n.id);
    }
    if (p['arrowHeadLength'] != null &&
        (p['arrowHeadLength'] is! num ||
            !(p['arrowHeadLength'] as num).isFinite ||
            (p['arrowHeadLength'] as num) <= 0)) {
      issue('invalid_arrow_head_length', 'nodes.arrowHeadLength', n.id);
    }
    if (p['dash'] != null &&
        (p['dash'] is! List ||
            (p['dash'] as List).any((v) => v is! num || !v.isFinite || v <= 0))) {
      issue('invalid_dash', 'nodes.dash', n.id);
    }
    if (p['labelOrientation'] != null &&
        !const ['screen', 'object'].contains(p['labelOrientation'])) {
      issue('invalid_label_orientation', 'nodes.labelOrientation', n.id);
    }
    if (p['align'] != null &&
        !const ['left', 'center', 'right'].contains(p['align'])) {
      issue('invalid_alignment', 'nodes.align', n.id);
    }

    for (final k in ['fill', 'stroke', 'color']) {
      if (p[k] != null && !layoutColorPattern.hasMatch('${p[k]}')) {
        issue('invalid_color', 'nodes.$k', n.id);
      }
    }
    if (p['opacity'] != null &&
        (p['opacity'] is! num ||
            (p['opacity'] as num) < 0 ||
            (p['opacity'] as num) > 1)) {
      issue('invalid_opacity', 'nodes.opacity', n.id);
    }
    if (n.kind == 'text') {
      if ('${p['text'] ?? ''}'.runes.length >
          layoutLimits['textMaxCodePoints']!) {
        issue('text_limit', 'nodes.text', n.id);
      }
      final size = resolveNodeAppearance(d, n).label['size'],
          lh = resolveNodeAppearance(d, n).label['lineHeight'];
      if (size is! num || !size.isFinite || size < 1 || size > 4096) {
        issue('font_size', 'nodes.size', n.id);
      }
      if (lh is! num || !lh.isFinite || lh < 0.8 || lh > 3) {
        issue('line_height', 'nodes.lineHeight', n.id);
      }
    }
    if (p.containsKey('pathPattern') ||
        p.containsKey('zigzagTeeth') ||
        p.containsKey('zigzagAmplitude')) {
      final teeth = p['zigzagTeeth'],
          amplitude = p['zigzagAmplitude'],
          vertices = p['points'];
      if (p['pathPattern'] != 'zigzag' ||
          n.kind != 'shape' ||
          p['shape'] != 'polyline' ||
          teeth is! int ||
          teeth < 1 ||
          2 * teeth + 2 > layoutLimits['verticesMax']! ||
          amplitude is! num ||
          !amplitude.isFinite ||
          amplitude <= 0 ||
          amplitude > layoutLimits['geometryAbsMax']! ||
          vertices is! List ||
          vertices.length != 2 * teeth + 2) {
        issue('invalid_zigzag', 'nodes.pathPattern', n.id);
      } else if (vertices.every(
        (v) =>
            v is List &&
            v.length == 2 &&
            v.every((c) => c is num && c.isFinite),
      )) {
        final a = vertices.first as List, b = vertices.last as List;
        final dx = (b[0] as num) - (a[0] as num),
            dy = (b[1] as num) - (a[1] as num);
        final length = sqrt(dx * dx + dy * dy);
        var regular = length >= 0.001;
        if (regular) {
          for (var i = 0; i < 2 * teeth; i++) {
            final t = (i + 0.5) / (2 * teeth),
                offset = i.isEven ? amplitude : -amplitude,
                point = vertices[i + 1] as List;
            if (((point[0] as num) - (a[0] + dx * t - dy / length * offset))
                        .abs() >
                    0.002 ||
                ((point[1] as num) - (a[1] + dy * t + dx / length * offset))
                        .abs() >
                    0.002) {
              regular = false;
              break;
            }
          }
        }
        if (!regular) issue('invalid_zigzag_geometry', 'nodes.points', n.id);
      }
    }
    final points = p['points'];
    if (points != null) {
      if (points is! List ||
          points.length > layoutLimits['verticesMax']! ||
          points.length < (p['shape'] == 'polygon' ? 3 : 2)) {
        issue('invalid_vertices', 'nodes.points', n.id);
      } else if (points.any(
        (v) =>
            v is! List ||
            v.length != 2 ||
            v.any((x) => x is! num || !x.isFinite),
      ))
        issue('invalid_vertices', 'nodes.points', n.id);
      else if (p['shape'] == 'polygon' && polygonSelfIntersects(points))
        issue('self_intersection', 'nodes.points', n.id);
    }
  }
  for (final n in d.nodes) {
    var p = n;
    final seen = <String>{n.id};
    var depth = 1;
    while (p.parentId != null) {
      final parent = index[p.parentId];
      if (parent == null) {
        issue('missing_parent', 'nodes.parentId', n.id);
        break;
      }
      if (!seen.add(parent.id)) {
        issue('parent_cycle', 'nodes.parentId', n.id);
        break;
      }
      if (++depth > layoutMaxDepth) {
        issue('depth_limit', 'nodes.parentId', n.id);
        break;
      }
      p = parent;
    }
  }
  final members = <String>{};
  final unitIds = <String>{};
  for (final u in d.selectionUnits) {
    if (!_uuid.hasMatch('${u['id']}') || !unitIds.add('${u['id']}')) {
      issue('invalid_unit_id', 'selectionUnits');
    }
    final ids = u['nodeIds'];
    if (ids is! List || ids.isEmpty) {
      issue('empty_unit', 'selectionUnits');
      continue;
    }
    for (final id in ids) {
      if (index[id]?.kind != 'seat') {
        issue('invalid_member', 'selectionUnits', id.toString());
      }
      if (!members.add(id.toString())) {
        issue('duplicate_membership', 'selectionUnits', id.toString());
      }
    }
  }
  for (final a in d.attachments) {
    if (index[a['seatId']]?.kind != 'seat' ||
        index[a['targetId']] == null ||
        index[a['seatId']]?.parentId != a['targetId']) {
      issue('invalid_attachment', 'attachments');
    }
  }
  for (final s in d.sections) {
    if (index[s['rootId']]?.kind != 'group') {
      issue('invalid_section_root', 'sections');
    }
  }
  if (d.presets.length > layoutLimits['presetsMax']!) {
    issue('preset_limit', 'presets');
  }
  for (final p in d.presets) {
    final nodes = (p['document'] as Map?)?['nodes'] ?? p['nodes'];
    if (nodes is List && nodes.length > layoutLimits['presetNodesMax']!) {
      issue('preset_node_limit', 'presets');
    }
  }
  if (d.background case final Map<String, dynamic> b) {
    final opacity = b['opacity'] ?? 1;
    if (opacity is! num || !opacity.isFinite || opacity < 0 || opacity > 1) {
      issue('invalid_opacity', 'background.opacity');
    }
    final c = b['crop'];
    if (c is Map) {
      final x = c['x'] ?? 0,
          y = c['y'] ?? 0,
          w = c['width'] ?? 1,
          h = c['height'] ?? 1;
      if ([x, y, w, h].any((v) => v is! num || !v.isFinite) ||
          x < 0 ||
          y < 0 ||
          w <= 0 ||
          h <= 0 ||
          x + w > 1 ||
          y + h > 1) {
        issue('invalid_crop', 'background.crop');
      }
    }
  }
  _validateExtras(d, index, out);
  try {
    if (out.every(
          (i) => !const [
            'nonfinite_number',
            'invalid_geometry',
            'non_json_value',
          ].contains(i.reason),
        ) &&
        _documentPayloadBytes(d) > layoutMaxBytes) {
      issue('payload_limit', 'document');
    }
  } catch (_) {
    issue('non_json_value', 'document');
  }
  return out;
}

bool polygonSelfIntersects(List points) {
  double cross(List a, List b, List c) =>
      ((b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0]))
          .toDouble();
  for (var i = 0; i < points.length; i++) {
    final a = points[i] as List, b = points[(i + 1) % points.length] as List;
    for (var j = i + 1; j < points.length; j++) {
      if (j == i + 1 || i == 0 && j == points.length - 1) continue;
      final c = points[j] as List, e = points[(j + 1) % points.length] as List;
      if (cross(a, b, c) * cross(a, b, e) <= 0 &&
          cross(c, e, a) * cross(c, e, b) <= 0) {
        final overlap =
            max(min(a[0], b[0]), min(c[0], e[0])) <=
                min(max(a[0], b[0]), max(c[0], e[0])) &&
            max(min(a[1], b[1]), min(c[1], e[1])) <=
                min(max(a[1], b[1]), max(c[1], e[1]));
        if (overlap) return true;
      }
    }
  }
  return false;
}

Map<String, dynamic> _canonicalMap(Map<String, dynamic> input) {
  dynamic canonical(dynamic v) {
    if (v is Map) {
      final keys = v.keys.cast<String>().toList()..sort();
      return <String, dynamic>{for (final k in keys) k: canonical(v[k])};
    }
    if (v is List) return v.map(canonical).toList();
    return v;
  }

  return canonical(input) as Map<String, dynamic>;
}

List<Map<String, dynamic>> _sortedRecords(
  List<Map<String, dynamic>> records, {
  String key = 'id',
}) => records.map((r) => _canonicalMap(r)).toList()
  ..sort((a, b) {
    final order = (a['order'] as num? ?? 0).compareTo(b['order'] as num? ?? 0);
    return order != 0 ? order : '${a[key]}'.compareTo('${b[key]}');
  });
const _geometryKeys = {
  'shape',
  'arrowHeadLength',
  'cornerRadius',
  'appearanceOverrides',
  'seatStyle',
  'seatWidth',
  'seatHeight',
  'seatGap',
  'seatSpacing',
  'seatEdgePadding',
  'objectStyle',
  'fill',
  'stroke',
  'strokeWidth',
  'strokeStyle',
  'dash',
  'opacity',
  'points',
  'holes',
  'pathPattern',
  'zigzagTeeth',
  'zigzagAmplitude',
  'text',
  'fontId',
  'labelOrientation',
  'fontStyle',
  'size',
  'color',
  'align',
  'lineHeight',
  'bold',
  'italic',
  'symbol',
  'role',
  'obstacle',
  'manual',
  'manualRotation',
  'slot',
  'assembly',
  'rows',
  'seatsPerRow',
  'blocks',
  'aisle',
  'spacing',
  'rowSpacing',
  'arc',
  'left',
  'right',
  'rear',
  'decks',
  'upperRows',
  'upperRear',
  'deck',
  'compartments',
  'seats',
  'capacity',
  'furniture',
  'guestSide',
};
const _nodeKinds = {
  'group',
  'table',
  'seat',
  'furniture',
  'capacityArea',
  'shape',
  'text',
  'image',
  'vector',
};
const _documentKeys = {
  'styles',
  'seatingDefaults',
  'textPolicy',
  'schemaVersion',
  'symbolSetVersion',
  'canvas',
  'nodes',
  'sections',
  'selectionUnits',
  'attachments',
  'background',
  'presets',
};
final _sha256Pattern = RegExp(r'^[0-9a-f]{64}$');
const _privateKeys = {
  'spot',
  'spotid',
  'product',
  'productid',
  'price',
  'unitprice',
  'currency',
  'orderid',
  'ticket',
  'ticketid',
  'secret',
  'secretid',
  'token',
  'accesstoken',
  'refreshtoken',
  'customer',
  'customerid',
  'email',
  'payment',
  'paymentid',
  'reservation',
  'reservationid',
  'hold',
  'holdid',
  'selected',
  'pending',
  'status',
  'camera',
  'viewport',
};
bool _finite(dynamic v) => v is num && v.isFinite;
List<LayoutIssue> _jsonIssues(
  dynamic value, {
  String path = 'document',
  bool business = false,
}) {
  final issues = <LayoutIssue>[], active = Set<Object>.identity();
  var count = 0;
  void walk(dynamic v, String p, int depth) {
    if (depth > 64 || ++count > 1000000) {
      if (issues.length < 100) issues.add(LayoutIssue('json_nesting_limit', p));
      return;
    }
    if (v == null || v is bool || v is String) return;
    if (v is num) {
      if (!v.isFinite) {
        issues.add(LayoutIssue('nonfinite_number', p));
      } else if (v.abs() > 8796093022207)
        issues.add(LayoutIssue('unsafe_number', p));
      return;
    }
    if (v is! Map && v is! List) {
      issues.add(LayoutIssue('non_json_value', p));
      return;
    }
    if (!active.add(v as Object)) {
      issues.add(LayoutIssue('json_cycle', p));
      return;
    }
    if (v is Map) {
      for (final e in v.entries) {
        if (e.key is! String) {
          issues.add(LayoutIssue('non_string_key', p));
          continue;
        }
        final k = e.key as String;
        if (business &&
            _privateKeys.contains(
              k.toLowerCase().replaceAll(RegExp(r'[_-]'), ''),
            )) {
          issues.add(LayoutIssue('host_data_forbidden', '$p.$k'));
        }
        walk(e.value, '$p.$k', depth + 1);
      }
    } else {
      for (var i = 0; i < (v as List).length; i++) {
        walk(v[i], '$p[$i]', depth + 1);
      }
    }
    active.remove(v);
  }

  walk(value, path, 0);
  return issues;
}

List<LayoutIssue> _nodeDecodeIssues(Map<String, dynamic> j) {
  final issues = <LayoutIssue>[];
  void add(String r, String k) =>
      issues.add(LayoutIssue(r, k, j['id'] is String ? j['id'] : null));
  if (j['id'] is! String || !_uuid.hasMatch(j['id'])) add('invalid_uuid', 'id');
  if (j['kind'] is! String || !_nodeKinds.contains(j['kind'])) {
    add('unknown_kind', 'kind');
  }
  if (j.containsKey('parentId') &&
      j['parentId'] != null &&
      (j['parentId'] is! String || !_uuid.hasMatch(j['parentId']))) {
    add('invalid_parent_id', 'parentId');
  }
  final t = j['transform'];
  if (t is! Map) {
    add('missing_transform', 'transform');
  } else {
    for (final k in ['x', 'y', 'rotation']) {
      if (!_finite(t[k])) add('invalid_transform', 'transform.$k');
    }
    if (t.keys.any((k) => !const ['x', 'y', 'rotation'].contains(k))) {
      add('unknown_transform_field', 'transform');
    }
  }
  for (final k in ['width', 'height']) {
    if (!_finite(j[k]) || j[k] <= 0) add('invalid_dimension', k);
  }
  if (j.containsKey('z') && j['z'] is! int) add('invalid_z', 'z');
  if (j.containsKey('locked') && j['locked'] is! bool) {
    add('invalid_locked', 'locked');
  }
  for (final key in [
    'style',
    'childStyles',
    'seating',
    'surface',
    'graphic',
    'originalSource',
  ]) {
    if (j.containsKey(key) && j[key] is! Map) {
      add('invalid_canonical_record', key);
    }
  }
  if (j.containsKey('label') && j['label'] is! String) {
    add('invalid_label', 'label');
  }
  if (j.keys.any((k) => const ['x', 'y', 'rotation'].contains(k))) {
    add('flat_transform_forbidden', 'transform');
  }
  return issues;
}

List<LayoutIssue> _documentDecodeIssues(Map<String, dynamic> j) {
  final issues = _jsonIssues(j, business: true);
  void add(String r, String p) => issues.add(LayoutIssue(r, p));
  if (j.keys.any((k) => !_documentKeys.contains(k))) {
    add('unknown_document_field', 'document');
  }
  if (j['symbolSetVersion'] != 1) {
    add('unsupported_symbols', 'symbolSetVersion');
  }
  if (j['canvas'] is! Map) add('missing_canvas', 'canvas');
  if (j.containsKey('defaultTextStyle') ||
      j.containsKey('appearance') ||
      j.containsKey('generators')) {
    add('legacy_style_forbidden', 'document');
  }
  for (final key in ['styles', 'seatingDefaults', 'textPolicy']) {
    if (j[key] is! Map) add('missing_canonical_record', key);
  }
  if (j['nodes'] is! List) {
    add('missing_nodes', 'nodes');
  } else {
    for (var i = 0; i < (j['nodes'] as List).length; i++) {
      final node = j['nodes'][i];
      if (node is! Map) {
        add('invalid_node', 'nodes[$i]');
      } else {
        if (j['schemaVersion'] == 2 &&
            node.containsKey('assembly') &&
            node['assembly'] is! Map) {
          add('invalid_assembly', 'nodes[$i].assembly');
        }
        issues.addAll(
          _nodeDecodeIssues(
            Map<String, dynamic>.from(node),
          ).map((e) => LayoutIssue(e.reason, 'nodes[$i].${e.path}', e.nodeId)),
        );
      }
    }
  }
  for (final k in ['sections', 'selectionUnits', 'attachments', 'presets']) {
    if (j.containsKey(k) &&
        (j[k] is! List || (j[k] as List).any((v) => v is! Map))) {
      add('invalid_collection', k);
    }
  }
  if (j['background'] != null && j['background'] is! Map) {
    add('invalid_background', 'background');
  }
  if (issues.isEmpty && utf8.encode(jsonEncode(j)).length > layoutMaxBytes) {
    add('payload_limit', 'document');
  }
  return issues;
}

void _validateExtras(
  VenueLayoutDocument d,
  Map<String, LayoutNode> nodes,
  List<LayoutIssue> out,
) {
  void issue(String r, String p, [String? id]) =>
      out.add(LayoutIssue(r, p, id));
  void fields(Map<String, dynamic> values, Set<String> allowed, String path) {
    for (final key in values.keys) {
      if (!allowed.contains(key)) issue('unknown_field', '$path.$key');
    }
  }

  {
    _validateCanonicalDocument(d, nodes, out);
  }
  fields(d.canvas, const {
    'x',
    'y',
    'width',
    'height',
    'fill',
    'floorStyle',
  }, 'canvas');
  if (d.canvas.containsKey('floorStyle') &&
      !layoutFloorStyles.contains(d.canvas['floorStyle'])) {
    issue('invalid_floor_style', 'canvas.floorStyle');
  }
  if (d.background != null) {
    fields(d.background!, const {
      'assetRef',
      'hash',
      'x',
      'y',
      'rotation',
      'width',
      'height',
      'scale',
      'opacity',
      'crop',
    }, 'background');
    if (d.background!['crop'] is Map) {
      fields(Map<String, dynamic>.from(d.background!['crop']), const {
        'x',
        'y',
        'width',
        'height',
      }, 'background.crop');
    }
  }
  final allIds = <String>{...nodes.keys};
  void identity(dynamic id, String path) {
    if (id is! String || !_uuid.hasMatch(id)) {
      issue('invalid_uuid', path);
      return;
    }
    if (!allIds.add(id)) issue('duplicate_identity', path, id);
  }

  bool polygon(dynamic points, String path) {
    if (points is! List ||
        points.length < 3 ||
        points.length > layoutLimits['verticesMax']! ||
        points.any(
          (v) => v is! List || v.length != 2 || v.any((x) => !_finite(x)),
        )) {
      issue('invalid_vertices', path);
      return false;
    }
    if (polygonSelfIntersects(points)) {
      issue('self_intersection', path);
      return false;
    }
    var area = 0.0;
    for (var i = 0; i < points.length; i++) {
      final a = points[i] as List, b = points[(i + 1) % points.length] as List;
      area += (a[0] as num) * (b[1] as num) - (a[1] as num) * (b[0] as num);
    }
    if (area.abs() < 1e-9) {
      issue('degenerate_polygon', path);
      return false;
    }
    return true;
  }

  for (final entry in d.canvas.entries) {
    if (const ['x', 'y', 'width', 'height'].contains(entry.key) &&
        _finite(entry.value) &&
        (entry.value as num).abs() > layoutLimits['geometryAbsMax']!) {
      issue('coordinate_range', 'canvas.${entry.key}');
    }
  }
  if (d.symbolSetVersion != 1) issue('unsupported_symbols', 'symbolSetVersion');
  out.addAll(
    _jsonIssues({
      'canvas': d.canvas,
      'sections': d.sections,
      'selectionUnits': d.selectionUnits,
      'attachments': d.attachments,
      'background': d.background,
      'presets': d.presets,
      'nodeProperties': [for (final n in d.nodes) n.properties],
    }, business: true),
  );
  {}
  for (final n in d.nodes) {
    {}
    final p = surfaceGeometryProperties(n);
    if (p.containsKey('deck') &&
        (p['deck'] is! int || p['deck'] < 0 || p['deck'] > 1)) {
      issue('invalid_deck', 'nodes.deck', n.id);
    }
    if (p.containsKey('decks') &&
        (p['decks'] is! int || p['decks'] < 1 || p['decks'] > 2)) {
      issue('invalid_decks', 'nodes.decks', n.id);
    }
    if (p['assembly'] == 'bus' && p.containsKey('decks')) {
      for (final key in [
        'rows',
        'left',
        'right',
        'rear',
        'upperRows',
        'upperRear',
      ]) {
        if (p[key] is! int || p[key] < 0 || p[key] > layoutMaxSeats) {
          issue('invalid_transport_count', 'nodes.$key', n.id);
        }
      }
      if (p['left'] is int &&
          p['right'] is int &&
          (p['left'] > 3 || p['right'] > 3 || p['left'] + p['right'] == 0)) {
        issue('invalid_bus_blocks', 'nodes.left', n.id);
      }
      for (final key in ['rear', 'upperRear']) {
        if (p[key] is int && p[key] > 6) {
          issue('invalid_transport_count', 'nodes.$key', n.id);
        }
      }
    }
    if (p['assembly'] == 'compartments' &&
        (p.containsKey('compartments') || p.containsKey('seats'))) {
      if (p['compartments'] is! int ||
          p['compartments'] < 1 ||
          p['compartments'] > layoutMaxSeats ||
          p['seats'] is! int ||
          p['seats'] < 2 ||
          p['seats'] > 12) {
        issue('invalid_transport_count', 'nodes.compartments', n.id);
      }
    }
    if (p.containsKey('guestSide') &&
        (!isBarNode(n) || !barGuestSides.contains(p['guestSide']))) {
      issue('invalid_bar_guest_side', 'nodes.guestSide', n.id);
    }
    if (p['furniture'] == 'bar' &&
        (n.kind != 'table' ||
            !barGuestSides.contains(p['guestSide']) ||
            !const [
              'rect',
              'rectangle',
              'roundedRect',
              'polygon',
            ].contains(p['shape']))) {
      issue('invalid_bar', 'nodes.furniture', n.id);
    }
    if (p['furniture'] == 'stool' && n.kind != 'seat') {
      issue('invalid_stool', 'nodes.furniture', n.id);
    }
    final barParent = nodes[n.parentId];
    if (n.kind == 'seat' && barParent != null && isBarNode(barParent)) {
      final side = barParent.properties['guestSide'];
      final guest = switch (side) {
        'top' => n.y <= -barParent.height / 2,
        'bottom' => n.y >= barParent.height / 2,
        'left' => n.x <= -barParent.width / 2,
        'right' => n.x >= barParent.width / 2,
        _ => false,
      };
      if (!guest) issue('bar_stool_wrong_side', 'nodes.parentId', n.id);
    }
    if (p.containsKey('objectStyle') &&
        !layoutObjectStyles.contains(p['objectStyle'])) {
      issue('invalid_object_style', 'nodes.objectStyle', n.id);
    }
    if (p.containsKey('seatStyle') &&
        !layoutSeatStyles.contains(p['seatStyle'])) {
      issue('invalid_seat_style', 'nodes.seatStyle', n.id);
    }
    if (p.containsKey('appearanceOverrides')) {
      final overrides = p['appearanceOverrides'];
      if (overrides is! List ||
          overrides.any(
            (key) => key is! String || !layoutAppearanceKeys.contains(key),
          ) ||
          overrides.toSet().length != overrides.length) {
        issue(
          'invalid_appearance_overrides',
          'nodes.appearanceOverrides',
          n.id,
        );
      }
    }
    for (final key in p.keys) {
      if (!_geometryKeys.contains(key)) {
        issue('unknown_geometry_property', 'nodes.$key', n.id);
      }
    }
    if ([
      n.x,
      n.y,
      n.rotation,
      n.width,
      n.height,
    ].any((v) => v.isFinite && v.abs() > layoutLimits['geometryAbsMax']!)) {
      issue('coordinate_range', 'nodes.geometry', n.id);
    }
    if (p['points'] is List &&
        (p['points'] as List).any(
          (p) =>
              p is List &&
              p.any(
                (v) =>
                    _finite(v) &&
                    (v as num).abs() > layoutLimits['geometryAbsMax']!,
              ),
        )) {
      issue('coordinate_range', 'nodes.points', n.id);
    }
    if (p['symbol'] != null &&
        !const [
          'chair',
          'bench',
          'sofa',
          'wheelchair',
          'driver',
        ].contains(p['symbol'])) {
      issue('unknown_symbol', 'nodes.symbol', n.id);
    }
    if (n.parentId != null && !_uuid.hasMatch(n.parentId!)) {
      issue('invalid_parent_id', 'nodes.parentId', n.id);
    }
    if (n.parentId != null &&
        nodes[n.parentId] != null &&
        !const [
          'group',
          'table',
          'furniture',
        ].contains(nodes[n.parentId]!.kind)) {
      issue('invalid_parent_kind', 'nodes.parentId', n.id);
    }
    if (p['text'] != null && p['text'] is! String) {
      issue('invalid_text', 'nodes.text', n.id);
    }
    if (n.kind == 'text' && p['text'] == null) {
      issue('missing_text', 'nodes.text', n.id);
    }
    if (p['fontId'] != null &&
        (p['fontId'] is! String || (p['fontId'] as String).isEmpty)) {
      issue('invalid_font_id', 'nodes.fontId', n.id);
    }
    for (final key in [
      'bold',
      'italic',
      'manual',
      'manualRotation',
      'obstacle',
    ]) {
      if (p[key] != null && p[key] is! bool) {
        issue('invalid_boolean', 'nodes.$key', n.id);
      }
    }
    for (final key in ['size', 'lineHeight']) {
      if (p[key] != null &&
          (!_finite(p[key]) ||
              p[key] <
                  (key == 'size'
                      ? layoutLimits['fontSizeMin']!
                      : layoutLimits['lineHeightMin']!) ||
              p[key] >
                  (key == 'size'
                      ? layoutLimits['fontSizeMax']!
                      : layoutLimits['lineHeightMax']!))) {
        issue(key == 'size' ? 'font_size' : 'line_height', 'nodes.$key', n.id);
      }
    }
    for (final key in [
      'seatWidth',
      'seatHeight',
      'seatGap',
      'seatSpacing',
      'seatEdgePadding',
    ]) {
      if (p[key] != null &&
          (!_finite(p[key]) ||
              p[key] < (key == 'seatWidth' || key == 'seatHeight' ? 1 : 0) ||
              p[key] > 1000000)) {
        issue('invalid_table_seating', 'nodes.$key', n.id);
      }
    }
    if (p['cornerRadius'] != null &&
        (!_finite(p['cornerRadius']) || p['cornerRadius'] < 0)) {
      issue('invalid_radius', 'nodes.cornerRadius', n.id);
    }
    if (p['labelOrientation'] != null &&
        !const ['screen', 'object'].contains(p['labelOrientation'])) {
      issue('invalid_label_orientation', 'nodes.labelOrientation', n.id);
    }
    if (p['fontStyle'] != null &&
        !const ['normal', 'italic'].contains(p['fontStyle'])) {
      issue('invalid_font_style', 'nodes.fontStyle', n.id);
    }
    if (p['capacity'] != null && (p['capacity'] is! int || p['capacity'] < 0)) {
      issue('invalid_capacity', 'nodes.capacity', n.id);
    }
    if (p['strokeStyle'] != null &&
        !const ['solid', 'dashed', 'dotted'].contains(p['strokeStyle'])) {
      issue('invalid_stroke_style', 'nodes.strokeStyle', n.id);
    }
    if (p.containsKey('holes')) {
      final holes = p['holes'];
      if (p['shape'] != 'polygon' || holes is! List || holes.length > 128) {
        issue('invalid_holes', 'nodes.holes', n.id);
      } else {
        var vertices = p['points'] is List ? (p['points'] as List).length : 0;
        final validHoles = <List<List<double>>>[];
        for (final hole in holes) {
          if (polygon(hole, 'nodes.${n.id}.holes')) {
            final ring = (hole as List)
                .map(
                  (p) => (p as List).map((n) => (n as num).toDouble()).toList(),
                )
                .toList();
            vertices += ring.length;
            validHoles.add(ring);
          }
        }
        if (vertices > layoutLimits['verticesMax']!) {
          issue('vertex_limit', 'nodes.holes', n.id);
        } else if (p['points'] is List &&
            polygon(p['points'], 'nodes.${n.id}.points')) {
          final outer = (p['points'] as List)
              .map(
                (p) => (p as List).map((n) => (n as num).toDouble()).toList(),
              )
              .toList();
          for (var i = 0; i < validHoles.length; i++) {
            final h = validHoles[i];
            if (polygonRingArea(h) * polygonRingArea(outer) >= 0 ||
                !h.every((p) => polygonRingContains(outer, p[0], p[1])) ||
                polygonRingsTouch(outer, h)) {
              issue('invalid_hole', 'nodes.holes', n.id);
            }
            for (var j = 0; j < i; j++) {
              final other = validHoles[j];
              if (polygonRingsTouch(h, other) ||
                  polygonRingContains(h, other[0][0], other[0][1]) ||
                  polygonRingContains(other, h[0][0], h[0][1])) {
                issue('overlapping_holes', 'nodes.holes', n.id);
              }
            }
          }
        }
      }
    }
    if (p['shape'] == 'polygon' && p['points'] == null) {
      issue('missing_vertices', 'nodes.points', n.id);
    }
    if (p['shape'] == 'polygon' &&
        p['points'] is List &&
        polygon(p['points'], 'nodes.${n.id}.points')) {}
  }
  for (final u in d.selectionUnits) {
    identity(u['id'], 'selectionUnits.id');
    if (u.keys.any(
      (k) => !const ['id', 'nodeIds', 'kind', 'label'].contains(k),
    )) {
      issue('unknown_selection_unit_field', 'selectionUnits');
    }
    if (u['kind'] != 'atomic') {
      issue('invalid_selection_unit_kind', 'selectionUnits.kind');
    }
  }
  for (final a in d.attachments) {
    {
      if (a['id'] != null) identity(a['id'], 'attachments.id');
      continue;
    }
  }
  final sectionRoots = <String>{};
  for (final s in d.sections) {
    identity(s['id'], 'sections.id');
    if (s['title'] is! String || (s['title'] as String).isEmpty) {
      issue('invalid_section_title', 'sections.title');
    }
    if (!sectionRoots.add('${s['rootId']}')) {
      issue('duplicate_section_root', 'sections.rootId');
    }
    if (s.keys.any(
      (k) => !const [
        'id',
        'title',
        'rootId',
        'levelId',
        'outline',
        'order',
      ].contains(k),
    )) {
      issue('unknown_section_field', 'sections');
    }
    if (s['outline'] != null) polygon(s['outline'], 'sections.outline');
    if (s['order'] != null && s['order'] is! int) {
      issue('invalid_order', 'sections.order');
    }
    if (s['levelId'] != null && s['levelId'] is! String) {
      issue('invalid_level', 'sections.levelId');
    }
  }
  for (final p in d.presets) {
    identity(p['id'], 'presets.id');
    if (p.keys.any(
      (k) => !const [
        'id',
        'title',
        'description',
        'document',
        'version',
      ].contains(k),
    )) {
      issue('unknown_preset_field', 'presets');
    }
    if (p['title'] is! String || (p['title'] as String).isEmpty) {
      issue('invalid_preset_title', 'presets.title');
    }
    final fragment = p['document'];
    if (fragment is! Map<String, dynamic>) {
      issue('invalid_preset_document', 'presets.document');
      continue;
    }
    if (fragment['presets'] is List &&
        (fragment['presets'] as List).isNotEmpty) {
      issue('nested_preset_forbidden', 'presets.document.presets');
      continue;
    }
    try {
      VenueLayoutDocument.fromJson(fragment);
    } on InvalidLayoutDocument catch (e) {
      out.addAll(
        e.issues.map(
          (i) =>
              LayoutIssue(i.reason, 'presets.${p['id']}.${i.path}', i.nodeId),
        ),
      );
    } catch (_) {
      issue('invalid_preset_document', 'presets.document');
    }
  }
  if (d.background case final Map<String, dynamic> b) {
    for (final key in ['x', 'y', 'rotation', 'width', 'height', 'scale']) {
      if (!_finite(b[key]) ||
          const ['width', 'height', 'scale'].contains(key) && b[key] <= 0) {
        issue('invalid_background_transform', 'background.$key');
      }
    }
    final ref = b['assetRef'];
    if (ref is! String ||
        !RegExp(r'^[A-Za-z0-9][A-Za-z0-9:._-]{0,255}$').hasMatch(ref) ||
        ref.contains('..')) {
      issue('invalid_asset_ref', 'background.assetRef');
    }
    final hash =
        b['hash'] ??
        (ref is String && ref.startsWith('image:') ? ref.substring(6) : null);
    if (hash is! String || !_sha256Pattern.hasMatch(hash)) {
      issue('invalid_asset_hash', 'background.hash');
    }
    if (b['crop'] is! Map) {
      issue('invalid_crop', 'background.crop');
    } else {
      for (final k in ['x', 'y', 'width', 'height']) {
        if (!_finite(b['crop'][k])) issue('invalid_crop', 'background.crop.$k');
      }
    }
    for (final k in ['x', 'y', 'rotation', 'width', 'height', 'scale']) {
      if (_finite(b[k]) &&
          (b[k] as num).abs() > layoutLimits['geometryAbsMax']!) {
        issue('coordinate_range', 'background.$k');
      }
    }
  }
}

/// Validate canonical prepared resources once at the resource admission seam.
List<LayoutIssue> validateLayoutResources(Map<String, dynamic> resources) {
  final serializable = Map<String, dynamic>.from(resources)..remove('images');
  final issues = _jsonIssues(serializable, path: 'resources');
  if (issues.isNotEmpty || resources.isEmpty) return issues;
  if (resources['protocol'] != canonicalTextResourceProtocol) {
    return [LayoutIssue('unsupported_resource_protocol', 'resources.protocol')];
  }
  return validateCanonicalTextResources(resources);
}

const layoutAppearanceKinds = <String>{
  'table',
  'seat',
  'furniture',
  'shape',
  'capacityArea',
  'text',
};
const layoutSeatStyles = <String>{
  'roundUpholstered',
  'round',
  'plain',
  'wood',
  'upholstered',
  'transit',
  'banquet',
};
const layoutObjectStyles = <String>{
  'round',
  'simple',
  'minimal',
  'wood',
  'lounge',
  'transit',
  'hall',
  'banquet',
};

/// Physical authoring defaults; never override an existing table's geometry.
const layoutSeatingDefaultKeys = <String>{
  'seatWidth',
  'seatHeight',
  'seatGap',
  'seatSpacing',
  'seatEdgePadding',
};

const layoutAppearanceKeys = <String>{
  'fontId',
  'size',
  'bold',
  'italic',
  ...layoutSeatingDefaultKeys,
  'objectStyle',
  'seatStyle',
  'fill',
  'stroke',
  'strokeWidth',
  'cornerRadius',
  'opacity',
  'color',
};

/// Document styles replace factory defaults unless a property is explicitly
/// marked local. Geometry and host presentation state are never merged here.
Map<String, dynamic> effectiveNodeProperties(
  VenueLayoutDocument document,
  LayoutNode node,
) {
  {
    final resolved = resolveNodeAppearance(document, node).values;
    final visual = Map<String, dynamic>.from(resolved)..remove('label');
    return frozenMap({
      ...surfaceGeometryProperties(node),
      ...visual,
      ...Map<String, dynamic>.from(resolved['label'] as Map? ?? {}),
    });
  }

  // Authoring defaults are materialized by configurePlanTableSeating. Local
  // physical profiles remain authoritative, including locked assemblies.

  // Open divider geometry has no surface, regardless of the shared shape fill.
}

/// Structural comparison for validated immutable nodes. Unchanged nodes are an
/// identity check; coordinate comparisons retain canonical serialization's
/// quantization and appearance override order has no semantic significance.
bool sameLayoutNode(LayoutNode a, LayoutNode b) {
  if (identical(a, b)) return true;
  if (a.id != b.id ||
      a.kind != b.kind ||
      a.parentId != b.parentId ||
      a.label != b.label ||
      a.z != b.z ||
      a.locked != b.locked ||
      quantize(a.x) != quantize(b.x) ||
      quantize(a.y) != quantize(b.y) ||
      quantize(a.rotation) != quantize(b.rotation) ||
      quantize(a.width) != quantize(b.width) ||
      quantize(a.height) != quantize(b.height)) {
    return false;
  }
  if (!sameLayoutValue(a.style, b.style) ||
      !sameLayoutValue(a.childStyles, b.childStyles) ||
      !sameLayoutValue(a.seating, b.seating) ||
      !sameLayoutValue(a.surface, b.surface) ||
      !sameLayoutValue(a.assembly, b.assembly) ||
      !sameLayoutValue(a.graphic, b.graphic) ||
      !sameLayoutValue(a.originalSource, b.originalSource)) {
    return false;
  }
  if (identical(a.properties, b.properties)) return true;
  if (a.properties.length != b.properties.length) return false;
  for (final entry in a.properties.entries) {
    if (!b.properties.containsKey(entry.key)) return false;
    final other = b.properties[entry.key];
    if (entry.key == 'appearanceOverrides' &&
        entry.value is List &&
        other is List) {
      final keys = (entry.value as List).toSet();
      if (keys.length != other.length || !keys.containsAll(other)) return false;
    } else if (!sameLayoutValue(entry.value, other))
      return false;
  }
  return true;
}

/// Fast comparison of validated immutable snapshots. Pointer updates usually
/// replace only a few nodes, so no JSON or full property graph is allocated.
/// Rare record/list reorderings retain the canonical serializer as the oracle.
bool sameLayoutDocument(VenueLayoutDocument a, VenueLayoutDocument b) {
  if (identical(a, b)) return true;
  if (a.schemaVersion != b.schemaVersion ||
      !sameLayoutValue(a.styles, b.styles) ||
      !sameLayoutValue(a.seatingDefaults, b.seatingDefaults) ||
      !sameLayoutValue(a.textPolicy, b.textPolicy)) {
    return false;
  }
  if (a.symbolSetVersion != b.symbolSetVersion ||
      a.nodes.length != b.nodes.length) {
    return false;
  }
  for (var i = 0; i < a.nodes.length; i++) {
    if (a.nodes[i].id != b.nodes[i].id) {
      return jsonEncode(a.toJson()) == jsonEncode(b.toJson());
    }
    if (!sameLayoutNode(a.nodes[i], b.nodes[i])) return false;
  }
  if (!sameLayoutValue(a.canvas, b.canvas) ||
      !sameLayoutValue(a.background, b.background)) {
    return false;
  }
  if (sameLayoutValue(a.sections, b.sections) &&
      sameLayoutValue(a.selectionUnits, b.selectionUnits) &&
      sameLayoutValue(a.attachments, b.attachments) &&
      sameLayoutValue(a.presets, b.presets)) {
    return true;
  }
  return jsonEncode(a.toJson()) == jsonEncode(b.toJson());
}

/// Deep JSON-value equality without serialization; maps ignore key order,
/// lists preserve order and equal numeric values compare equally.
bool sameLayoutValue(dynamic a, dynamic b) {
  if (identical(a, b) || a == b) return true;
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || !sameLayoutValue(a[key], b[key])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!sameLayoutValue(a[i], b[i])) return false;
    }
    return true;
  }
  return false;
}

const barGuestSides = <String>{'top', 'right', 'bottom', 'left'};
bool isBarNode(LayoutNode node) =>
    node.kind == 'table' && node.properties['furniture'] == 'bar';
bool isStoolNode(LayoutNode node, {LayoutNode? parent}) =>
    node.kind == 'seat' &&
    (node.properties['furniture'] == 'stool' ||
        parent != null && isBarNode(parent));

const layoutFloorStyles = <String>{'plain', 'wood', 'tile', 'carpet'};

/// Ring geometry shared by authoring validation and spatial hit testing.
double polygonRingArea(List<List<double>> ring) {
  var area = 0.0;
  for (var i = 0; i < ring.length; i++) {
    final a = ring[i], b = ring[(i + 1) % ring.length];
    area += a[0] * b[1] - b[0] * a[1];
  }
  return area / 2;
}

bool polygonRingContains(List<List<double>> points, double x, double y) {
  var inside = false;
  for (var i = 0, j = points.length - 1; i < points.length; j = i++) {
    final a = points[i], b = points[j];
    if ((a[1] > y) != (b[1] > y) &&
        x < (b[0] - a[0]) * (y - a[1]) / (b[1] - a[1]) + a[0]) {
      inside = !inside;
    }
  }
  return inside;
}

bool polygonRingsTouch(List<List<double>> a, List<List<double>> b) {
  double cross(List<double> a, List<double> b, List<double> c) =>
      (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0]);
  for (var i = 0; i < a.length; i++)
    for (var j = 0; j < b.length; j++) {
      final p = a[i],
          q = a[(i + 1) % a.length],
          r = b[j],
          s = b[(j + 1) % b.length];
      if (max(p[0], q[0]) < min(r[0], s[0]) ||
          max(r[0], s[0]) < min(p[0], q[0]) ||
          max(p[1], q[1]) < min(r[1], s[1]) ||
          max(r[1], s[1]) < min(p[1], q[1])) {
        continue;
      }
      if (cross(p, q, r) * cross(p, q, s) <= 0 &&
          cross(r, s, p) * cross(r, s, q) <= 0) {
        return true;
      }
    }
  return false;
}

void _validateCanonicalDocument(
  VenueLayoutDocument d,
  Map<String, LayoutNode> nodes,
  List<LayoutIssue> out,
) {
  void issue(String reason, String path, [String? id]) =>
      out.add(LayoutIssue(reason, path, id));
  void leaves(
    Object? v,
    Map<String, Map<String, Object>> fields,
    String path, [
    String? id,
  ]) {
    for (final i in validateCanonicalLeaves(v, fields, path)) {
      issue(i.reason, i.path, id);
    }
  }

  if (d.styles.keys.any((k) => k != 'label' && k != 'kinds')) {
    issue('unknown_style_scope', 'styles');
  }
  if (d.styles.containsKey('label')) {
    leaves(d.styles['label'], canonicalLabelFields, 'styles.label');
  }
  final kinds = d.styles['kinds'];
  if (kinds != null) {
    if (kinds is! Map) {
      issue('invalid_kind_styles', 'styles.kinds');
    } else
      for (final e in kinds.entries) {
        if (!canonicalStyleKinds.contains(e.key)) {
          issue('unknown_style_kind', 'styles.kinds.${e.key}');
          continue;
        }
        for (final i in validateCanonicalStyle(
          e.value,
          'styles.kinds.${e.key}',
          kind: e.key as String,
        )) {
          issue(i.reason, i.path);
        }
      }
  }
  leaves(d.seatingDefaults, canonicalSeatingFields, 'seatingDefaults');
  leaves(d.textPolicy, {
    for (final k in ['language', 'direction']) k: canonicalLabelFields[k]!,
  }, 'textPolicy');
  if (!d.textPolicy.containsKey('language') ||
      !d.textPolicy.containsKey('direction')) {
    issue('missing_text_policy', 'textPolicy');
  }
  for (final node in d.nodes) {
    final path = 'nodes.${node.id}';
    for (final i in validateCanonicalStyle(
      node.style,
      '$path.style',
      kind: node.kind,
    )) {
      issue(i.reason, i.path, node.id);
    }
    final legacy = {
      ...legacyStyleDestinations.keys,
      ...legacySeatingDestinations.keys,
      'appearanceOverrides',
      'manual',
      'manualRotation',
      'assembly',
    };
    for (final key in node.properties.keys) {
      if (legacy.contains(key)) {
        issue('legacy_property_forbidden', '$path.$key', node.id);
    }
      }
    for (final key in node.properties.keys) {
      if (!canonicalGeometryPropertyKeys.contains(key) && !legacy.contains(key)) {
        issue('unknown_canonical_geometry_field', '$path.$key', node.id);
    }
      }
    if (node.originalSource != null &&
        (node.kind != 'vector' ||
            !validOriginalSvgSource(node.originalSource!))) {
      issue('invalid_original_source', '$path.originalSource', node.id);
    }
    if (node.kind == 'table') {
      leaves(node.seating, canonicalSeatingFields, '$path.seating', node.id);
      if (node.childStyles.keys.any((k) => k != 'seat')) {
        issue('invalid_child_style_kind', '$path.childStyles', node.id);
      }
      if (node.childStyles.containsKey('seat'))
        for (final i in validateCanonicalStyle(
          node.childStyles['seat'],
          '$path.childStyles.seat',
          kind: 'seat',
        )) {
          issue(i.reason, i.path, node.id);
        }
      _validateCanonicalSurface(node, out);
      if (node.properties.keys.any(
        (k) => const {'shape', 'points', 'holes'}.contains(k),
      )) {
        issue('legacy_surface_forbidden', path, node.id);
      }
    } else {
      final assemblyRoot =
          const {'group', 'furniture'}.contains(node.kind) &&
          const {
            'rows',
            'bus',
            'compartments',
            'couch',
          }.contains(node.assembly?['kind']);
      if (node.childStyles.isNotEmpty ||
          node.surface != null ||
          node.seating.isNotEmpty && !assemblyRoot) {
        issue('table_record_on_other_kind', path, node.id);
      }
      if (assemblyRoot) {
        leaves(node.seating, canonicalSeatingFields, '$path.seating', node.id);
      }
    }
    if (node.assembly != null) {
      for (final problem in validateCanonicalAssembly(
        node.assembly!,
        node.kind,
        '$path.assembly',
      )) {
        issue(problem.reason, problem.path, node.id);
      }
    }
    if (node.kind == 'vector') {
      if (node.graphic?['type'] != 'vector') {
        issue('vector_graphic_required', '$path.graphic', node.id);
      } else {
        try {
          LayoutVectorGraphic.fromJson({...node.graphic!}..remove('type'));
        } on GraphicImportFailure catch (e) {
          issue(e.reason, '$path.graphic', node.id);
        }
      }
    } else if (node.kind == 'image') {
      final g = node.graphic;
      if (g == null ||
          g['type'] != 'bitmap' ||
          g.keys.any(
            (k) => !const {'type', 'assetRef', 'hash', 'crop'}.contains(k),
          ) ||
          g['assetRef'] is! String ||
          (g['assetRef'] as String).isEmpty ||
          g['hash'] is! String ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch('${g['hash']}')) {
        issue('invalid_bitmap_graphic', '$path.graphic', node.id);
      } else {
        final crop = g['crop'];
        if (crop is! Map ||
            crop.keys.toSet().difference({
              'x',
              'y',
              'width',
              'height',
            }).isNotEmpty ||
            [
              'x',
              'y',
              'width',
              'height',
            ].any((k) => crop[k] is! num || !(crop[k] as num).isFinite) ||
            crop['x'] < 0 ||
            crop['y'] < 0 ||
            crop['width'] <= 0 ||
            crop['height'] <= 0 ||
            crop['x'] + crop['width'] > 1 ||
            crop['y'] + crop['height'] > 1) {
          issue('invalid_bitmap_crop', '$path.graphic.crop', node.id);
        }
      }
    } else if (node.graphic != null) {
      issue('graphic_on_other_kind', '$path.graphic', node.id);
    }
  }
  final attached = <String>{};
  for (final a in d.attachments) {
    final seat = nodes[a['seatId']], target = nodes[a['targetId']];
    final assemblyTarget =
        target != null &&
        const {'group', 'furniture'}.contains(target.kind) &&
        const {
          'rows',
          'bus',
          'compartments',
          'couch',
        }.contains(target.assembly?['kind']);
    if (a.keys.any(
          (k) => !const {
            'id',
            'seatId',
            'targetId',
            'placement',
            'rotationMode',
          }.contains(k),
        ) ||
        !attached.add('${a['seatId']}') ||
        seat?.kind != 'seat' ||
        seat?.parentId != target?.id ||
        (target?.kind != 'table' && !assemblyTarget)) {
      issue('invalid_attachment', 'attachments');
    }
    if (!const {'auto', 'manual'}.contains(a['rotationMode'])) {
      issue('invalid_rotation_mode', 'attachments.rotationMode');
    }
    final placement = a['placement'];
    if (placement is! Map) {
      issue('invalid_placement', 'attachments.placement');
      continue;
    }
    final mode = placement['mode'];
    if (mode == 'automatic' || mode == 'free') {
      if (placement.length != 1) {
        issue('invalid_placement', 'attachments.placement');
      }
    } else if (mode == 'sidePinned') {
      if (target?.kind != 'table') {
        issue('invalid_side_pin_target', 'attachments.targetId');
      }
      if (placement['cell'] != null) {
        final cell = placement['cell'];
        if (placement.keys.any(
              (k) => !const {'mode', 'cell', 'face'}.contains(k),
            ) ||
            cell is! List ||
            cell.length != 2 ||
            cell.any((v) => v is! int) ||
            !const {
              'top',
              'right',
              'bottom',
              'left',
            }.contains(placement['face'])) {
          issue('invalid_grid_pin', 'attachments.placement');
        } else if (target == null ||
            !canonicalGridPinOnBoundary(target, cell, placement['face']))
          issue('invalid_grid_pin_boundary', 'attachments.placement');
      } else if (placement.keys.any(
            (k) => !const {'mode', 'side', 't'}.contains(k),
          ) ||
          !const {
            'top',
            'right',
            'bottom',
            'left',
            'perimeter',
          }.contains(placement['side']) ||
          placement['t'] is! num ||
          !(placement['t'] as num).isFinite ||
          placement['t'] < 0 ||
          placement['t'] > 1)
        issue('invalid_side_pin', 'attachments.placement');
      else if (placement['cell'] == null &&
          ((placement['side'] == 'perimeter' &&
                  target?.surface?['type'] != 'circle') ||
              (placement['side'] != 'perimeter' &&
                  target?.surface?['type'] != 'rect')))
        issue('invalid_side_pin_surface', 'attachments.placement');
    } else {
      issue('invalid_placement_mode', 'attachments.placement');
    }
  }
}

/// Grid coordinates identify filled module cells; holes remain empty.
/// Admission and physical pin placement use this same boundary predicate.
bool canonicalGridCellFilled(LayoutNode node, int x, int y) {
  final surface = node.surface;
  if (surface?['type'] != 'grid') return false;
  try {
    List<List<double>> ring(Object? value) => [
      for (final point in value as List)
        [(point[0] as num).toDouble(), (point[1] as num).toDouble()],
    ];
    return polygonRingContains(ring(surface!['outer']), x + .5, y + .5) &&
        !(surface['holes'] as List).any(
          (hole) => polygonRingContains(ring(hole), x + .5, y + .5),
        );
  } on Object {
    return false;
  }
}

bool canonicalGridPinOnBoundary(LayoutNode node, List cell, String face) {
  if (cell.length != 2 || cell.any((value) => value is! int)) return false;
  final delta = switch (face) {
    'top' => [0, -1],
    'right' => [1, 0],
    'bottom' => [0, 1],
    'left' => [-1, 0],
    _ => null,
  };
  return delta != null &&
      canonicalGridCellFilled(node, cell[0], cell[1]) &&
      !canonicalGridCellFilled(node, cell[0] + delta[0], cell[1] + delta[1]);
}

void _validateCanonicalSurface(LayoutNode node, List<LayoutIssue> out) {
  void issue(String reason) =>
      out.add(LayoutIssue(reason, 'nodes.${node.id}.surface', node.id));
  final s = node.surface;
  if (s == null) {
    issue('surface_required');
    return;
  }
  if (s['type'] == 'rect' || s['type'] == 'circle') {
    if (s.length != 1) issue('unknown_surface_field');
    if (s['type'] == 'circle' && (node.width - node.height).abs() > 1 / 1024) {
      issue('non_circular_surface');
    }
    if (s['type'] == 'circle' && node.properties['furniture'] == 'bar') {
      issue('bar_circle_unsupported');
    }
    return;
  }
  if (s['type'] != 'grid' ||
      s.keys.any(
        (k) => !const {'type', 'moduleSize', 'outer', 'holes'}.contains(k),
      )) {
    issue('invalid_surface');
    return;
  }
  final module = s['moduleSize'], outer = s['outer'], rawHoles = s['holes'];
  if (module is! num ||
      !module.isFinite ||
      module <= 0 ||
      module > 1000000 ||
      outer is! List ||
      rawHoles is! List ||
      rawHoles.length > 128) {
    issue('invalid_grid');
    return;
  }
  final rings = [outer, ...rawHoles];
  var vertices = 0;
  final valid = <List<List<double>>>[];
  for (final raw in rings) {
    if (raw is! List ||
        raw.length < 4 ||
        raw.any(
          (p) =>
              p is! List ||
              p.length != 2 ||
              p.any((v) => v is! int || v.abs() > 16384),
        )) {
      issue('invalid_grid_ring');
      return;
    }
    vertices += raw.length;
    final ring = raw
        .map((p) => [(p[0] as num).toDouble(), (p[1] as num).toDouble()])
        .toList();
    for (var i = 0; i < ring.length; i++) {
      final a = ring[i], b = ring[(i + 1) % ring.length];
      if ((a[0] == b[0]) == (a[1] == b[1])) {
        issue('non_orthogonal_grid');
        return;
      }
    }
    if (polygonSelfIntersects(ring) || polygonRingArea(ring) == 0) {
      issue('invalid_grid_ring');
      return;
    }
    valid.add(ring);
  }
  if (vertices > 512) {
    issue('grid_vertex_limit');
    return;
  }
  final ring = valid.first,
      minX = ring.map((p) => p[0]).reduce(min),
      minY = ring.map((p) => p[1]).reduce(min),
      maxX = ring.map((p) => p[0]).reduce(max),
      maxY = ring.map((p) => p[1]).reduce(max);
  if (minX != 0 ||
      minY != 0 ||
      maxX * maxY > 16384 ||
      (node.width - maxX * module).abs() > 1 / 1024 ||
      (node.height - maxY * module).abs() > 1 / 1024) {
    issue('grid_dimensions');
  }
  for (var i = 1; i < valid.length; i++) {
    final hole = valid[i];
    if (polygonRingArea(ring) * polygonRingArea(hole) >= 0 ||
        !hole.every((p) => polygonRingContains(ring, p[0], p[1])) ||
        polygonRingsTouch(ring, hole)) {
      issue('invalid_grid_hole');
    }
    for (var j = 1; j < i; j++) {
      final prior = valid[j];
      if (polygonRingsTouch(prior, hole) ||
          polygonRingContains(prior, hole[0][0], hole[0][1]) ||
          polygonRingContains(hole, prior[0][0], prior[0][1])) {
        issue('overlapping_grid_holes');
      }
    }
  }
}

class ResolvedNodeAppearance {
  ResolvedNodeAppearance(
    Map<String, dynamic> values,
    Map<String, dynamic> sources,
  ) : values = frozenMap(values),
      sources = frozenMap(sources);
  final Map<String, dynamic> values, sources;
  Map<String, dynamic> get label =>
      Map<String, dynamic>.from(values['label'] as Map? ?? {});
}

/// One sparse cascade, including provenance. Lock never changes inheritance.
ResolvedNodeAppearance resolveNodeAppearance(
  VenueLayoutDocument document,
  LayoutNode node,
) {
  final values = <String, dynamic>{}, sources = <String, dynamic>{};
  void layer(Map raw, String source) {
    final expanded = <String, dynamic>{};
    final family = raw['material'];
    if (family is String) {
      final material = layoutMaterialFamilies[family];
      if (material != null &&
          node.kind != 'text' &&
          node.kind != 'image' &&
          node.kind != 'vector') {
        expanded.addAll({
          'strokeWidth': node.kind == 'seat'
              ? material['seatStrokeWidth'] ?? material['strokeWidth']
              : material['strokeWidth'],
          'cornerRadius': node.kind == 'seat'
              ? material['seatRadius'] ?? material['radius']
              : material['radius'],
          if (node.kind == 'seat') 'seatStyle': material['seatStyle'],
        });
      }
    }
    expanded.addAll(Map<String, dynamic>.from(raw));
    for (final e in expanded.entries) {
      if (e.key == 'label' && e.value is Map) {
        final label = <String, dynamic>{
          ...?values['label'] as Map<String, dynamic>?,
        };
        for (final leaf in (e.value as Map).entries) {
          label[leaf.key as String] = leaf.value;
          sources['label.${leaf.key}'] = source;
        }
        values['label'] = label;
      } else {
        values[e.key] = e.value;
        sources[e.key] = source;
      }
    }
  }

  layer({
    'opacity': 1,
    if (node.kind != 'text' &&
        node.kind != 'image' &&
        node.kind != 'vector') ...{
      'material': 'simple',
      'fill': node.kind == 'seat'
          ? layoutDefaultSeatFill
          : node.kind == 'table'
          ? '#E2E8F0FF'
          : node.kind == 'capacityArea'
          ? '#DBEAFEFF'
          : '#F1F5F9FF',
      'stroke': '#475569FF',
      'strokeWidth': 1,
      'cornerRadius': node.kind == 'seat' ? 5 : 6,
      'strokePattern': {'type': 'solid'},
    },
    'label': {
      ...canonicalLabelDefaults,
      'align': node.kind == 'text' ? 'left' : 'center',
      ...document.textPolicy,
    },
  }, 'core');
  if (document.styles['label'] case final Map label) {
    layer({'label': label}, 'styles.label');
  }
  if ((document.styles['kinds'] as Map?)?[node.kind] case final Map kind) {
    layer(kind, 'styles.kinds.${node.kind}');
  }
  if (node.kind == 'seat' && node.parentId != null) {
    final parent = document.nodes
        .where((n) => n.id == node.parentId && n.kind == 'table')
        .firstOrNull;
    if (parent?.childStyles['seat'] case final Map child) {
      layer(child, 'table:${parent!.id}');
    }
  }
  layer(node.style, 'node:${node.id}');
  return ResolvedNodeAppearance(values, sources);
}

/// Set/Unset modifies one authored leaf. Equal values stay explicit; null is
/// never a reset and siblings retain their declarations.
Map<String, dynamic> patchCanonicalStyle(
  Map<String, dynamic> style,
  List<String> path, {
  Object? value,
  bool unset = false,
}) {
  if (path.isEmpty ||
      path.length > 2 ||
      (path.length == 2 && path.first != 'label') ||
      (!unset && value == null)) {
    throw const FormatException('invalid_style_patch');
  }
  final next = Map<String, dynamic>.from(style);
  if (path.length == 1) {
    if (unset) {
      next.remove(path.single);
    } else {
      next[path.single] = value;
    }
  } else {
    final label = Map<String, dynamic>.from(next['label'] as Map? ?? {});
    if (unset) {
      label.remove(path.last);
    } else {
      label[path.last] = value;
    }
    if (label.isEmpty) {
      next.remove('label');
    } else {
      next['label'] = label;
    }
  }
  return frozenMap(next);
}

/// Rendering/geometry projection only. Grid rings remain the stored authority;
/// materialized width/height and node transforms are not recomputed on load.
Map<String, dynamic> surfaceGeometryProperties(LayoutNode node) {
  final surface = node.surface;
  if (node.kind != 'table' || surface == null) return node.properties;
  final result = <String, dynamic>{...node.properties};
  switch (surface['type']) {
    case 'rect':
      result['shape'] = 'rect';
    case 'circle':
      result['shape'] = 'circle';
    case 'grid':
      bool validRing(Object? raw) =>
          raw is List &&
          raw.every(
            (p) =>
                p is List &&
                p.length == 2 &&
                p.every((v) => v is num && v.isFinite),
          );
      if (surface['moduleSize'] is! num ||
          !(surface['moduleSize'] as num).isFinite ||
          !validRing(surface['outer']) ||
          surface['holes'] is! List ||
          !(surface['holes'] as List).every(validRing)) {
        return node.properties;
      }
      final module = (surface['moduleSize'] as num).toDouble();
      List<List<double>> ring(List raw) => [
        for (final point in raw)
          [
            (point[0] as num) * module - node.width / 2,
            (point[1] as num) * module - node.height / 2,
          ],
      ];
      result.addAll({
        'shape': 'polygon',
        'points': ring(surface['outer'] as List),
        'holes': [
          for (final hole in surface['holes'] as List) ring(hole as List),
        ],
      });
  }
  return frozenMap(result);
}
