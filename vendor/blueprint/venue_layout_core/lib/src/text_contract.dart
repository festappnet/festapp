import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'canonical_contract.dart';
import 'model.dart';

class LayoutTextDependencyFailure implements Exception {
  const LayoutTextDependencyFailure(
    this.reason, {
    this.nodeId,
    this.fontFamilyId,
  });
  final String reason;
  final String? nodeId, fontFamilyId;
  @override
  String toString() => '$reason: ${nodeId ?? fontFamilyId ?? ''}';
}

class LayoutTextRequest {
  LayoutTextRequest(Map<String, dynamic> value) : descriptor = frozenMap(value);
  final Map<String, dynamic> descriptor;
  Map<String, dynamic> toJson() => descriptor;
  Map<String, dynamic> get resourceDescriptor => {
    'layoutResourceProtocol': canonicalTextResourceProtocol,
    'policy': canonicalLayoutTextPolicy,
    'request': descriptor,
  };
  String get id =>
      'layout-text:${sha256.convert(utf8.encode(canonicalContractJson(resourceDescriptor)))}';
}

String resolvedLayoutFontFace(
  Map<String, dynamic> label,
  Map<String, dynamic> families, {
  String? nodeId,
}) {
  final id = label['fontFamilyId'],
      weight = label['weight'],
      italic = label['italic'];
  final family = families[id];
  if (family is! Map)
    throw LayoutTextDependencyFailure(
      'font_family_unavailable',
      nodeId: nodeId,
      fontFamilyId: id as String?,
    );
  final face =
      (family['faces']
          as Map?)?['$weight:${italic == true ? 'italic' : 'normal'}'];
  if (face is! String || face.isEmpty)
    throw LayoutTextDependencyFailure(
      'font_face_unavailable',
      nodeId: nodeId,
      fontFamilyId: id as String?,
    );
  return face;
}

LayoutTextRequest nodeTextRequest(
  VenueLayoutDocument document,
  LayoutNode node,
  Map<String, dynamic> families, {
  String? text,
}) {
  final label = resolveNodeAppearance(document, node).label;
  return LayoutTextRequest({
    'text':
        text ??
        (node.kind == 'text' ? '${node.properties['text'] ?? ''}' : node.label),
    'role': node.kind == 'text' ? 'text' : 'label',
    'fontFamilyId': label['fontFamilyId'],
    'fontFaceId': resolvedLayoutFontFace(label, families, nodeId: node.id),
    'size': label['size'],
    'language': label['language'],
    'direction': label['direction'],
    'lineHeight': label['lineHeight'],
    'align': label['align'],
    'box': {
      'x': -quantize(node.width) / 2,
      'y': -quantize(node.height) / 2,
      'width': quantize(node.width),
      'height': quantize(node.height),
    },
    'fit': node.kind == 'text' ? 'wrap' : 'shrink',
  });
}

/// The only authored-text role collector, including isolated preset defaults.
/// Derived numeric notation is a separate bounded symbol dependency below.
Map<String, LayoutTextRequest> collectTextRequests(
  VenueLayoutDocument document,
  Map<String, dynamic> families, {
  bool includePresets = false,
}) {
  if (document.schemaVersion != 2)
    throw const FormatException('canonical_document_required');
  final requests = <String, LayoutTextRequest>{};
  void collect(VenueLayoutDocument doc, String namespace) {
    for (final node in doc.nodes) {
      final hidden =
          node.kind == 'seat' ||
          node.kind == 'group' ||
          node.kind == 'image' ||
          node.kind == 'vector' ||
          (node.kind == 'furniture' &&
              node.properties['furniture'] == 'couch') ||
          (node.kind == 'table' && node.properties['furniture'] == 'bar');
      if (hidden) continue;
      final text = node.kind == 'text'
          ? '${node.properties['text'] ?? ''}'
          : node.label;
      if (text.isNotEmpty)
        requests['$namespace${node.id}'] = nodeTextRequest(
          doc,
          node,
          families,
          text: text,
        );
    }
    if (includePresets)
      for (final preset in doc.presets)
        collect(
          VenueLayoutDocument.fromJson(
            Map<String, dynamic>.from(preset['document'] as Map),
          ),
          '$namespace${preset['id']}/',
        );
  }

  collect(document, '');
  return Map.unmodifiable(requests);
}

/// Declared families remain editable even before their first visible label.
/// Preset declarations belong only to the explicit admin dependency closure.
Set<String> collectDeclaredLayoutFontFamilies(
  VenueLayoutDocument document, {
  bool includePresets = false,
}) {
  final ids = <String>{};
  void style(Map value) {
    final id = (value['label'] as Map?)?['fontFamilyId'];
    if (id is String) ids.add(id);
  }

  void collect(VenueLayoutDocument doc) {
    style(doc.styles);
    for (final value in (doc.styles['kinds'] as Map? ?? {}).values)
      if (value is Map) style(value);
    for (final node in doc.nodes) {
      style(node.style);
      for (final value in node.childStyles.values)
        if (value is Map) style(value);
    }
    if (includePresets)
      for (final preset in doc.presets)
        collect(
          VenueLayoutDocument.fromJson(
            Map<String, dynamic>.from(preset['document'] as Map),
          ),
        );
  }

  collect(document);
  return Set.unmodifiable(ids);
}

/// No Cartesian product of counts. Every actual numeric role needs just ×/0-9
/// outlines at the resolved document face, not a network request for each value.
Set<String> _numericFontFaces(
  VenueLayoutDocument document,
  Map<String, dynamic> families,
) {
  final nodes = {for (final n in document.nodes) n.id: n};
  final parents = <String, int>{};
  for (final unit in document.selectionUnits) {
    final ids = (unit['nodeIds'] as List).cast<String>();
    if (ids.isEmpty) continue;
    final parent = nodes[ids.first]?.parentId;
    if (parent != null &&
        nodes[parent]?.kind == 'furniture' &&
        ids.every((id) => nodes[id]?.parentId == parent))
      parents.putIfAbsent(parent, () => ids.length);
  }
  if (!document.nodes.any(
    (n) =>
        n.kind == 'capacityArea' ||
        (n.kind == 'furniture' &&
            n.properties['furniture'] != 'couch' &&
            (parents[n.id] ?? 0) > 1),
  ))
    return const {};
  final virtual = LayoutNode(
    id: '00000000-0000-4000-8000-000000000000',
    kind: 'text',
  );
  final defaultDocument = document.copyWith(
    styles: {'label': document.styles['label'] ?? {}},
  );
  return {
    resolvedLayoutFontFace(
      resolveNodeAppearance(defaultDocument, virtual).label,
      families,
    ),
  };
}

bool _path(Object? value) =>
    value is List &&
    value.length <= 200000 &&
    value.every(
      (c) =>
          c is List &&
          c.isNotEmpty &&
          canonicalPathArities[c.first] != null &&
          c.length == canonicalPathArities[c.first]! + 1 &&
          c.skip(1).every((n) => n is num && n.isFinite && n.abs() <= 1e9),
    );
bool _box(Object? value) =>
    value is Map &&
    value.keys.toSet().difference({'x', 'y', 'width', 'height'}).isEmpty &&
    [
      'x',
      'y',
      'width',
      'height',
    ].every((k) => value[k] is num && (value[k] as num).isFinite) &&
    value['width'] > 0 &&
    value['height'] > 0;

/// Resource validation runs at the provider boundary, never during a frame.
List<LayoutIssue> validateCanonicalTextResources(
  Map<String, dynamic> resources,
) {
  final issues = <LayoutIssue>[];
  void issue(String reason, String path) =>
      issues.add(LayoutIssue(reason, path));
  if (resources['protocol'] != 2)
    issue('unsupported_resource_protocol', 'resources.protocol');
  for (final key in resources.keys)
    if (!{
      'protocol',
      'fontFamilies',
      'fontFaces',
      'textLayouts',
      'numberSymbols',
      'assets',
      'images',
    }.contains(key))
      issue('unknown_resource_field', 'resources.$key');
  final families = resources['fontFamilies'];
  if (families is! Map) {
    issue('invalid_font_families', 'resources.fontFamilies');
  } else {
    for (final entry in families.entries) {
      final family = entry.value, path = 'resources.fontFamilies.${entry.key}';
      if (family is! Map ||
          family.keys.any(
            (k) => !{'id', 'hash', 'faces', 'family', 'version'}.contains(k),
          ) ||
          family['id'] != entry.key ||
          family['faces'] is! Map ||
          family['version'] != 1 ||
          family['family'] is! String ||
          (family['family'] as String).isEmpty) {
        issue('invalid_font_family', path);
        continue;
      }
      final payload = {
        for (final key in ['faces', 'family', 'version']) key: family[key],
      };
      final digest = sha256
          .convert(utf8.encode(canonicalContractJson(payload)))
          .toString();
      if (entry.key != 'font-family:$digest' || family['hash'] != digest)
        issue('font_family_hash_mismatch', path);
      for (final face in (family['faces'] as Map).entries)
        if (!RegExp(r'^(400|700):(normal|italic)$').hasMatch('${face.key}') ||
            face.value is! String)
          issue('invalid_font_face', path);
    }
  }
  final texts = resources['textLayouts'];
  if (texts is! Map) {
    issue('invalid_text_layouts', 'resources.textLayouts');
  } else {
    if (texts.length > 20000)
      issue('text_layout_limit', 'resources.textLayouts');
    for (final entry in texts.entries) {
      final value = entry.value, path = 'resources.textLayouts.${entry.key}';
      if (value is! Map ||
          value['id'] != entry.key ||
          value['descriptor'] is! Map) {
        issue('invalid_text_layout', path);
        continue;
      }
      final descriptor = value['descriptor'] as Map;
      if (descriptor['request'] is! Map) {
        issue('invalid_text_request', path);
        continue;
      }
      if (descriptor.keys.toSet().difference({
            'layoutResourceProtocol',
            'policy',
            'request',
          }).isNotEmpty ||
          descriptor['layoutResourceProtocol'] != 2 ||
          canonicalContractJson(descriptor['policy']) !=
              canonicalContractJson(canonicalLayoutTextPolicy))
        issue('text_policy_mismatch', path);
      if (entry.key !=
          'layout-text:${sha256.convert(utf8.encode(canonicalContractJson(descriptor)))}')
        issue('text_layout_hash_mismatch', path);
      if (!_path(value['path']) ||
          !_box(value['clip']) ||
          canonicalContractJson(value['clip']) !=
              canonicalContractJson((descriptor['request'] as Map?)?['box']))
        issue('invalid_text_path', path);
    }
  }
  final assets = resources['assets'];
  if (assets != null && assets is! Map) {
    issue('invalid_assets', 'resources.assets');
  } else if (assets is Map) {
    for (final entry in assets.entries) {
      final asset = entry.value, path = 'resources.assets.${entry.key}';
      if (asset is! Map ||
          asset.keys.any(
            (k) => !{
              'hash',
              'url',
              'width',
              'height',
              'mimeType',
              'byteLength',
            }.contains(k),
          ) ||
          asset['hash'] is! String ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(asset['hash']) ||
          entry.key != 'image:${asset['hash']}' ||
          asset['url'] is! String ||
          !{
            'image/png',
            'image/jpeg',
            'image/webp',
          }.contains(asset['mimeType'])) {
        issue('invalid_asset_manifest', path);
        continue;
      }
      for (final key in ['width', 'height', 'byteLength']) {
        final v = asset[key];
        if (v is! int || v < 1 || v > (key == 'byteLength' ? 819200 : 3000))
          issue('invalid_asset_manifest', '$path.$key');
      }
    }
  }
  final numbers = resources['numberSymbols'];
  if (numbers != null && numbers is! Map) {
    issue('invalid_number_symbols', 'resources.numberSymbols');
  } else if (numbers is Map) {
    for (final entry in numbers.entries) {
      final value = entry.value, path = 'resources.numberSymbols.${entry.key}';
      if (value is! Map ||
          value['fontFaceId'] != entry.key ||
          value['unitsPerEm'] is! num ||
          !(value['unitsPerEm'] as num).isFinite ||
          value['unitsPerEm'] <= 0 ||
          value['tokens'] is! Map) {
        issue('invalid_number_symbols', path);
        continue;
      }
      final descriptor = {
        'layoutResourceProtocol': 2,
        'policy': canonicalLayoutTextPolicy,
        'role': 'number',
        'fontFaceId': entry.key,
      };
      if (canonicalContractJson(value['descriptor']) !=
              canonicalContractJson(descriptor) ||
          value['id'] !=
              'layout-number:${sha256.convert(utf8.encode(canonicalContractJson(descriptor)))}')
        issue('numeric_policy_mismatch', path);
      final tokens = value['tokens'] as Map;
      if (tokens.length != 11) issue('invalid_numeric_alphabet', path);
      for (final token in tokens.entries) {
        final v = token.value;
        if (!'×0123456789'.split('').contains(token.key) ||
            v is! Map ||
            !_path(v['path']) ||
            v['advance'] is! num ||
            !(v['advance'] as num).isFinite ||
            v['advance'] <= 0)
          issue('invalid_numeric_symbol', path);
      }
    }
  }
  return issues;
}

/// Exact prepared geometry only. A missing resource cannot fall back to runes,
/// a native font or client-dependent measurement.
/// Whole-text paths use the same label transform in canonical and pending views.
List<double> labelRenderMatrix(
  LayoutNode node,
  Map<String, dynamic> label,
  List<double> matrix,
) => node.kind == 'text' || label['orientation'] == 'object'
    ? matrix
    : <double>[1, 0, 0, 1, matrix[4], matrix[5]];

Map<String, dynamic>? preparedNodeText(
  VenueLayoutDocument document,
  LayoutNode node,
  Map<String, dynamic> resources,
  List<Map<String, dynamic>> issues, {
  required String text,
}) {
  try {
    final request = nodeTextRequest(
      document,
      node,
      Map<String, dynamic>.from(resources['fontFamilies'] as Map? ?? {}),
      text: text,
    );
    final value = (resources['textLayouts'] as Map?)?[request.id];
    if (value is! Map ||
        canonicalContractJson(value['descriptor']) !=
            canonicalContractJson(request.resourceDescriptor) ||
        !_path(value['path']) ||
        canonicalContractJson(value['clip']) !=
            canonicalContractJson(request.descriptor['box']))
      throw LayoutTextDependencyFailure(
        'text_layout_unavailable',
        nodeId: node.id,
      );
    return Map<String, dynamic>.from(value);
  } on LayoutTextDependencyFailure catch (error) {
    issues.add({'reason': error.reason, 'nodeId': node.id});
    return null;
  }
}

/// Derived count notation has a closed alphabet and non-contextual symbol
/// preparation. It never handles authored text or requests every count value.
List<List<dynamic>> canonicalNumberPath(
  VenueLayoutDocument document,
  num count,
  Map<String, dynamic> resources,
  List<Map<String, dynamic>> issues,
  String nodeId,
) {
  try {
    if (!count.isFinite ||
        count < 0 ||
        count != count.truncate() ||
        count > 1000000000)
      throw LayoutTextDependencyFailure('invalid_capacity', nodeId: nodeId);
    final virtual = LayoutNode(id: nodeId, kind: 'text');
    final defaults = document.copyWith(
      styles: {'label': document.styles['label'] ?? {}},
    );
    final faceId = resolvedLayoutFontFace(
      resolveNodeAppearance(defaults, virtual).label,
      Map<String, dynamic>.from(resources['fontFamilies'] as Map? ?? {}),
      nodeId: nodeId,
    );
    final symbols = (resources['numberSymbols'] as Map?)?[faceId];
    if (symbols is! Map ||
        symbols['unitsPerEm'] is! num ||
        symbols['tokens'] is! Map)
      throw LayoutTextDependencyFailure(
        'numeric_symbols_unavailable',
        nodeId: nodeId,
      );
    final tokens = symbols['tokens'] as Map, placed = <List<dynamic>>[];
    var advance = 0.0, minY = double.infinity, maxY = double.negativeInfinity;
    for (final char in '×${count.toInt()}'.split('')) {
      final token = tokens[char];
      if (token is! Map || !_path(token['path']) || token['advance'] is! num)
        throw LayoutTextDependencyFailure(
          'numeric_symbol_unavailable',
          nodeId: nodeId,
        );
      for (final raw in token['path'] as List) {
        final c = raw as List;
        final next = <dynamic>[c.first];
        for (var i = 1; i < c.length; i += 2) {
          final y = (c[i + 1] as num).toDouble();
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
          next.addAll([advance + (c[i] as num), y]);
        }
        placed.add(next);
      }
      advance += (token['advance'] as num).toDouble();
    }
    final scale = (16 / (symbols['unitsPerEm'] as num)).clamp(0, 64 / advance);
    final middle = minY.isFinite ? (minY + maxY) / 2 : 0;
    return [
      for (final c in placed)
        [
          c.first,
          for (var i = 1; i < c.length; i += 2) ...[
            ((c[i] as num) - advance / 2) * scale,
            ((c[i + 1] as num) - middle) * scale,
          ],
        ],
    ];
  } on LayoutTextDependencyFailure catch (error) {
    issues.add({'reason': error.reason, 'nodeId': nodeId});
    return [];
  }
}

Set<String> collectNumericFontFaces(
  VenueLayoutDocument document,
  Map<String, dynamic> families, {
  bool includePresets = false,
}) {
  final faces = {..._numericFontFaces(document, families)};
  if (includePresets)
    for (final preset in document.presets)
      faces.addAll(
        collectNumericFontFaces(
          VenueLayoutDocument.fromJson(
            Map<String, dynamic>.from(preset['document'] as Map),
          ),
          families,
          includePresets: true,
        ),
      );
  return Set.unmodifiable(faces);
}

Map<String, dynamic> layoutNumberDescriptor(String fontFaceId) => {
  'layoutResourceProtocol': 2,
  'policy': canonicalLayoutTextPolicy,
  'role': 'number',
  'fontFaceId': fontFaceId,
};
String layoutNumberResourceId(String fontFaceId) =>
    'layout-number:${sha256.convert(utf8.encode(canonicalContractJson(layoutNumberDescriptor(fontFaceId))))}';
List<String> collectLayoutTextResourceIds(
  VenueLayoutDocument document,
  Map<String, dynamic> resources, {
  bool includePresets = true,
}) {
  final families = Map<String, dynamic>.from(
    resources['fontFamilies'] as Map? ?? {},
  );
  final requests = collectTextRequests(
    document,
    families,
    includePresets: includePresets,
  );
  final ids = <String>{};
  for (final request in requests.values) {
    final prepared = (resources['textLayouts'] as Map?)?[request.id];
    if (prepared is! Map ||
        canonicalContractJson(prepared['descriptor']) !=
            canonicalContractJson(request.resourceDescriptor))
      throw const LayoutTextDependencyFailure('text_layout_unavailable');
    ids.add(request.id);
  }
  for (final face in collectNumericFontFaces(
    document,
    families,
    includePresets: includePresets,
  )) {
    final prepared = (resources['numberSymbols'] as Map?)?[face],
        id = layoutNumberResourceId(face);
    if (prepared is! Map ||
        prepared['id'] != id ||
        canonicalContractJson(prepared['descriptor']) !=
            canonicalContractJson(layoutNumberDescriptor(face)))
      throw const LayoutTextDependencyFailure('numeric_symbols_unavailable');
    ids.add(id);
  }
  return ids.toList()..sort();
}
