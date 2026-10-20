import 'dart:math' as math;
import 'package:uuid/uuid.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'blueprint_layout_contract.dart';
import 'blueprint_model.dart';
import 'blueprint_seat_state.dart';
import '../fonts/ticket_font_catalog.dart';

class BlueprintLegacyConversion {
  BlueprintLegacyConversion(this.snapshot, Map<String, dynamic> receipt)
      : receipt = frozenMap(receipt);
  final BlueprintLayoutSnapshot snapshot;
  final Map<String, dynamic> receipt;
}

Map<String, List<double>> _legacyInputMatrices(List<LayoutNode> input) {
  final nodes = {for (final node in input) node.id: node},
      result = <String, List<double>>{}, active = <String>{};
  List<double> resolve(LayoutNode node) {
    if (result.containsKey(node.id)) return result[node.id]!;
    if (!active.add(node.id)) throw const FormatException('legacy_parent_cycle');
    final parent = nodes[node.parentId];
    final local = localMatrix(node);
    final matrix = parent == null ? local : multiplyMatrix(resolve(parent), local);
    active.remove(node.id);
    return result[node.id] = matrix;
  }
  for (final node in input) resolve(node);
  return result;
}

/// Explicit, read-only migration preparation. Callers must review its output and
/// submit it through the normal aggregate command; runtime readers never use it.
BlueprintLegacyConversion convertLegacyBlueprint(BlueprintModel source,
    {required Map<String, Map<String, dynamic>> fontFamilies,
    Map<String, dynamic>? nativePlan, String? reviewedSourceSha256}) {
  if (source.id == null || source.occasion == null) {
    throw StateError('legacy_blueprint_identity_missing');
  }
  final basic = layoutAppearancePresets['Original']!;
  const uuid = Uuid();
  String identity(String key) => uuid.v5(Uuid.NAMESPACE_URL,
      'festapp:occasion:${source.occasion}:blueprint:${source.id}:$key');
  final groups = {
    for (final g in source.groups ?? [])
      if (g.id != null) g.id!: identity('group:${g.id}')
  };
  final nodes = <LayoutNode>[
    for (final g in source.groups ?? [])
      if (g.id != null)
        LayoutNode(
            id: groups[g.id]!,
            kind: 'group',
            label: g.title ?? '',
            width: 1,
            height: 1),
  ];
  final seats = <String, BlueprintSeatBinding>{};
  final defaults = <String, int>{};
  for (final g in source.groups ?? []) {
    if (g.id == null) continue;
    // A mixed/empty legacy group has no inferred default. The next inserted
    // chair therefore requires an explicit choice rather than a guessed price.
    final products = (source.objects ?? [])
        .where((s) => s.groupId == g.id && s.type == 'spot')
        .map((s) => s.spotProduct ?? s.product?.id)
        .toSet();
    if (products.length == 1 && products.single != null)
      defaults[groups[g.id]!] = products.single!;
  }
  for (final object in source.objects ?? []) {
    final isSeat = object.type == 'spot';
    if (object.x == null || object.y == null) {
      throw StateError('legacy_object_coordinates_missing');
    }
    if (isSeat && object.id == null)
      throw StateError('legacy_spot_identity_missing');
    final id = identity(isSeat
        ? 'spot:${object.id}'
        : 'object:${object.x}:${object.y}:${object.type}');
    nodes.add(LayoutNode(
        id: id,
        kind: isSeat ? 'seat' : 'shape',
        parentId: isSeat ? groups[object.groupId] : null,
        label: object.title ?? '',
        x: object.x! * 48.0 + 24,
        y: object.y! * 48.0 + 24,
        width: 48 * 31 / 40,
        height: 48 * 31 / 40,
        properties: {'shape': 'roundedRect'}));
    if (isSeat)
      seats[id] = BlueprintSeatBinding(
          nodeId: id,
          spotId: object.id,
          productId: object.spotProduct ?? object.product?.id,
          title: object.title ?? '',
          groupNodeId: groups[object.groupId],
          blocked: object.seatState == BlueprintSeatState.blocked);
  }
  final hasArtwork = source.backgroundSvg?.isNotEmpty == true;
  if (hasArtwork && nativePlan == null) {
    throw StateError('legacy_artwork_requires_reviewed_native_geometry');
  }
  if (nativePlan != null && (!hasArtwork || nativePlan['complete'] != true ||
      (nativePlan['issues'] as List? ?? const ['unreviewed']).isNotEmpty ||
      reviewedSourceSha256 == null || nativePlan['sourceSha256'] != reviewedSourceSha256)) {
    throw StateError('legacy_native_geometry_review_invalid');
  }
  final attachments = <Map<String, dynamic>>[];
  final tableStyle = <String, dynamic>{...({...basic.object}..remove('label')), 'color': (basic.object['label'] as Map)['color'], 'cornerRadius': 8};
  if (nativePlan != null) {
    final rawNodes = (nativePlan['nodes'] as List).cast<Map>();
    final fills = <String, int>{}, colors = <String, int>{};
    for (final raw in rawNodes.where((node) => node['kind'] == 'table')) {
      final props = {...Map<String, dynamic>.from(raw['properties'] as Map? ?? const {}), ...raw};
      final fill = (props['fill'] ?? basic.object['fill']) as String;
      final color = (props['color'] ?? (basic.object['label'] as Map)['color']) as String;
      fills[fill] = (fills[fill] ?? 0) + 1; colors[color] = (colors[color] ?? 0) + 1;
    }
    // Keep the reviewed hall palette in the document style, not per-table
    // overrides. This includes the original purple and white hall exceptions.
    if (fills.isNotEmpty) tableStyle['fill'] = (fills.entries.toList()..sort((a,b) => b.value.compareTo(a.value))).first.key;
    if (colors.isNotEmpty) tableStyle['color'] = (colors.entries.toList()..sort((a,b) => b.value.compareTo(a.value))).first.key;
    final nativeIds = <String, String>{};
    for (final raw in rawNodes) {
      final key = raw['id'] as String;
      if (nativeIds.containsKey(key) || raw['kind'] == 'seat') {
        throw StateError('legacy_native_geometry_identity_invalid');
      }
      nativeIds[key] = identity('native:$key');
    }
    final nativeNodes = <LayoutNode>[];
    for (final raw in rawNodes) {
      final parent = raw['parentId'] as String?;
      if (parent != null && !nativeIds.containsKey(parent)) {
        throw StateError('legacy_native_geometry_parent_missing');
      }
      final rawWire = Map<String, dynamic>.from(raw)..remove('properties');
      final wire = <String, dynamic>{
        ...Map<String, dynamic>.from(raw['properties'] as Map? ?? const {}),
        ...rawWire,
        'id': nativeIds[raw['id']]!,
        if (parent != null) 'parentId': nativeIds[parent]!,
      };
      if (wire['kind'] == 'table') {
        // Native Basic V1 is the shared V2 preset. Furniture geometry and text
        // survive; the reviewed hall palette is owned by the document style.
        wire.remove('appearanceOverrides');
        wire.remove('objectStyle');
        // A table's authored name is semantic content, not an appearance override.
        for (final key in basic.object.keys) {
          if (key != 'label') wire.remove(key);
        }
        wire['lineHeight'] = 1;
      }
      if (wire['kind'] == 'text') {
        // The chosen native font may be wider than an imported SVG font. Keep
        // each explicit source line intact without changing its anchor point.
        final text = (wire['text'] ?? wire['label'] ?? '').toString();
        final size = (wire['size'] as num? ?? 24).toDouble();
        final longest = text.split('\n').fold<int>(0, (n, line) => math.max(n, line.runes.length));
        final oldWidth = (wire['width'] as num).toDouble();
        final width = math.max(oldWidth, longest * size);
        final anchor = wire['align'] ?? 'center';
        final shift = anchor == 'left' ? (width - oldWidth) / 2 : anchor == 'right' ? -(width - oldWidth) / 2 : 0.0;
        final t = Map<String, dynamic>.from(wire['transform'] as Map);
        final angle = (t['rotation'] as num? ?? 0) * math.pi / 180;
        t['x'] = (t['x'] as num) + math.cos(angle) * shift;
        t['y'] = (t['y'] as num) + math.sin(angle) * shift;
        wire['width'] = width; wire['transform'] = t;
      }
      if (wire['pathPattern'] == 'zigzag') {
        // The source starts at a tooth, not a half-tooth baseline. Retain its
        // exact native editable polyline vertices, including both end points.
        wire.remove('pathPattern');
        wire.remove('zigzagTeeth');
        wire.remove('zigzagAmplitude');
      }
      nativeNodes.add(LayoutNode.fromJson(wire));
    }
    final nativeMatrices = _legacyInputMatrices(nativeNodes);
    final tables = <String, LayoutNode>{};
    final tableIds = <String>{};
    for (final entry in (nativePlan['tableGroups'] as Map).entries) {
      final group = int.tryParse(entry.key.toString());
      final tableId = nativeIds[entry.value];
      if (group == null || groups[group] == null || tableId == null || !tableIds.add(tableId)) {
        throw StateError('legacy_native_table_group_invalid');
      }
      final table = nativeNodes.firstWhere((node) => node.id == tableId);
      if (table.kind != 'table') throw StateError('legacy_native_table_required');
      final matrix = nativeMatrices[table.id]!;
      tables[groups[group]!] = table.copyWith(parentId: groups[group],
        x: matrix[4], y: matrix[5], rotation: math.atan2(matrix[1], matrix[0]) * 180 / math.pi);
    }
    nodes.addAll(nativeNodes.map((node) => tables.values.where((t) => t.id == node.id).firstOrNull ?? node));
    final geometry = _legacyInputMatrices(nodes);
    for (var i = 0; i < nodes.length; i++) {
      final seat = nodes[i];
      final table = tables[seat.parentId];
      if (seat.kind != 'seat' || table == null) continue;
      final matrix = geometry[table.id]!;
      final point = transformPoint(inverseMatrix(matrix), seat.x, seat.y);
      final rotation = -math.atan2(matrix[1], matrix[0]) * 180 / math.pi;
      nodes[i] = seat.copyWith(parentId: table.id, x: point[0], y: point[1], rotation: rotation);
      final side = point[0].abs() / (table.width / 2) > point[1].abs() / (table.height / 2);
      final edge = side ? (point[0] < 0 ? 'left' : 'right') : (point[1] < 0 ? 'top' : 'bottom');
      attachments.add({
        'id': identity('attachment:${seat.id}'), 'seatId': seat.id, 'targetId': table.id,
        'kind': 'edge', 'edge': edge, 'manual': true,
        'x': point[0], 'y': point[1], 'rotation': rotation,
        'gap': ((side ? point[0].abs() - table.width / 2 : point[1].abs() - table.height / 2) - seat.width / 2).clamp(0, 1000000),
        't': ((side ? point[1] / table.height : point[0] / table.width) + .5).clamp(0, 1),
      });
    }
  }
  final imported = importLegacyLayout({
    'schemaVersion': 1, 'symbolSetVersion': 1,
    'nodes': [for (final node in nodes) node.toJson()],
    'attachments': attachments,
    'defaultTextStyle': {'fontId': TicketFontCatalog.defaultLayoutFontId, 'size': 24, 'color': '#222222FF'},
    'appearance': {'table': tableStyle, 'seat': basic.seats ?? basic.object},
    'canvas': {'x': 0, 'y': 0,
      'width': (source.configuration?.width ?? 50) * 48,
      'height': (source.configuration?.height ?? 35) * 48,
      'fill': basic.canvasFill ?? '#FFFFFFFF'},
    'sections': [], 'selectionUnits': [], 'presets': [], 'generators': [],
    'background': null,
  }, fontFamilies: fontFamilies, sourceRevision: 0);
  if (!imported.isReady) throw StateError('legacy_conversion_invalid:${imported.receipt['issues']}');
  var document = imported.document!;
  final labelProfile = nativePlan?['tableLabelStyle'] as Map?;
  if (labelProfile != null) {
    // Explicitly reviewed typography applies to the table kind, so later
    // styling continues through the same canonical inheritance as new tables.
    for (final entry in labelProfile.entries) {
      final key = entry.key as String;
      document = setKindStyleLeaf(document, 'table', ['label', key], value: entry.value);
      for (final table in document.nodes.where((node) => node.kind == 'table').toList()) {
        document = setNodeStyleLeaf(document, table.id, ['label', key], unset: true);
      }
    }
  }
  final snapshot = BlueprintLayoutSnapshot(
      blueprintId: source.id,
      occasionId: source.occasion!,
      organizationId: source.organization,
      title: source.title ?? '',
      revision: 0,
      document: document,
      seatBindings: seats,
      groupProducts: defaults);
  return BlueprintLegacyConversion(snapshot, {
    'sourceBlueprintId': source.id,
    'sourceOccasionId': source.occasion,
    'reviewedSourceSha256': reviewedSourceSha256,
    'documentImport': imported.receipt,
  });
}
