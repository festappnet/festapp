import 'dart:math' as math;
import 'package:uuid/uuid.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';

/// Explicit migration of reviewed imported captions to native table names.
/// Commercial groups and seat identities stay intact; unrelated artwork stays.
VenueLayoutDocument normalizeBlueprintTableTitles(
    VenueLayoutDocument document) {
  document = _attachUnambiguousImportedTables(document);
  final nodes = {for (final node in document.nodes) node.id: node};
  final replacements = <String, LayoutNode>{};
  final removed = <String>{};
  String normalized(String value) => value
      .trim()
      .toLowerCase()
      .replaceFirst(RegExp(r'^(stůl|stul|table)\s*'), '')
      .replaceAll(RegExp(r'\s+'), '');
  for (final table in document.nodes.where((node) => node.kind == 'table')) {
    final parent = nodes[table.parentId];
    final name = parent?.kind == 'group' && parent!.label.trim().isNotEmpty
        ? parent.label.trim()
        : table.label.trim();
    if (name.isEmpty) continue;
    final captions = document.nodes
        .where((node) => node.kind == 'text' && node.parentId == table.id)
        .toList();
    if (captions.isNotEmpty) {
      final angle = captions.first.rotation * math.pi / 180;
      captions.sort((a, b) =>
          ((a.x - b.x) * math.cos(angle) + (a.y - b.y) * math.sin(angle))
              .compareTo(0));
    }
    final caption = captions
        .map((node) => '${node.properties['text'] ?? node.label}')
        .join('');
    final matches = captions.isNotEmpty &&
        (normalized(caption) == normalized(name) ||
            captions.every((node) =>
                normalized('${node.properties['text'] ?? node.label}') ==
                normalized(name)) ||
            table.label.isNotEmpty &&
                normalized(caption) == normalized(table.label));
    // Keep unrelated artwork intact instead of painting a second name over it.
    if (captions.isNotEmpty && !matches) continue;
    final rotation = matches ? captions.first.rotation : 0.0;
    final quarterTurns = (rotation / 90).round();
    if ((rotation - quarterTurns * 90).abs() > .01) continue;
    final turn = quarterTurns * 90.0;
    final angle = turn * math.pi / 180;
    if (turn != 0) {
      for (final child in document.nodes.where((n) => n.parentId == table.id)) {
        replacements[child.id] = child.copyWith(
            x: math.cos(angle) * child.x + math.sin(angle) * child.y,
            y: -math.sin(angle) * child.x + math.cos(angle) * child.y,
            rotation: child.rotation - turn);
      }
    }
    replacements[table.id] = table.copyWith(
        label: name,
        rotation: table.rotation + turn,
        width: quarterTurns.isOdd ? table.height : table.width,
        height: quarterTurns.isOdd ? table.width : table.height,
        style: matches
            ? {
                ...table.style,
                'label': {
                  ...resolveNodeAppearance(document, captions.first).label,
                  'align': 'center',
                  'orientation': 'object',
                },
              }
            : table.style);
    if (matches) removed.addAll(captions.map((node) => node.id));
  }
  final normalizedDocument = document.copyWith(nodes: [
    for (final node in document.nodes)
      if (!removed.contains(node.id)) replacements[node.id] ?? node,
  ]);
  // The old migration created an identity-only group around each physical
  // table. Keep that business ID as the native table ID, not a second name.
  final merged = <String, Map<String, dynamic>>{};
  final references = <String, String>{};
  for (final group
      in normalizedDocument.nodes.where((n) => n.kind == 'group')) {
    if (group.width != 1 ||
        group.height != 1 ||
        group.x != 0 ||
        group.y != 0 ||
        group.rotation != 0 ||
        group.style.isNotEmpty ||
        group.properties.isNotEmpty) continue;
    final children =
        normalizedDocument.nodes.where((n) => n.parentId == group.id).toList();
    if (children.length != 1 || children.single.kind != 'table') continue;
    final table = children.single;
    // A caption which could not be reviewed above must not be duplicated.
    if (table.label != group.label.trim()) continue;
    final wire = table.toJson()..['id'] = group.id;
    if (group.parentId == null) {
      wire.remove('parentId');
    } else {
      wire['parentId'] = group.parentId;
    }
    merged[group.id] = wire;
    references[table.id] = group.id;
  }
  dynamic remap(dynamic value) {
    if (value is String) return references[value] ?? value;
    if (value is List) return value.map(remap).toList();
    if (value is Map)
      return {for (final e in value.entries) e.key: remap(e.value)};
    return value;
  }

  final wire = normalizedDocument.toJson();
  wire['nodes'] = [
    for (final node in normalizedDocument.nodes)
      if (!references.containsKey(node.id)) merged[node.id] ?? node.toJson()
  ];
  return VenueLayoutDocument.fromJson(Map<String, dynamic>.from(remap(wire)));
}

// A few imported SVGs painted the same complete caption twice, so the old
// extractor missed the commercial association. Bind only one matching identity
// group whose chairs are all beside that furniture; never infer a price/group.
VenueLayoutDocument _attachUnambiguousImportedTables(
    VenueLayoutDocument document) {
  final updates = <String, LayoutNode>{};
  final attachments = [...document.attachments];
  final claimed = <String>{};
  String normalized(String value) => value
      .trim()
      .toLowerCase()
      .replaceFirst(RegExp(r'^(stůl|stul|table)\s*'), '')
      .replaceAll(RegExp(r'\s+'), '');
  for (final table
      in document.nodes.where((n) => n.kind == 'table' && n.parentId == null)) {
    final captions = document.nodes
        .where((n) => n.kind == 'text' && n.parentId == table.id)
        .toList();
    if (captions.isEmpty) continue;
    final labels = captions
        .map((n) => normalized('${n.properties['text'] ?? n.label}'))
        .toSet();
    if (labels.length != 1 || labels.single.isEmpty) continue;
    final groups = document.nodes
        .where((g) =>
            g.kind == 'group' &&
            g.width == 1 &&
            g.height == 1 &&
            g.x == 0 &&
            g.y == 0 &&
            g.rotation == 0 &&
            normalized(g.label) == labels.single &&
            !claimed.contains(g.id))
        .toList();
    if (groups.length != 1) continue;
    final group = groups.single;
    final children =
        document.nodes.where((n) => n.parentId == group.id).toList();
    if (children.isEmpty || children.any((n) => n.kind != 'seat')) continue;
    final inverse = inverseMatrix(worldMatrix(document, table));
    final positions = {
      for (final seat in children)
        seat.id: transformPoint(inverse, worldMatrix(document, seat)[4],
            worldMatrix(document, seat)[5])
    };
    if (positions.values.any((p) =>
        p[0].abs() > table.width / 2 + 96 ||
        p[1].abs() > table.height / 2 + 96)) continue;
    claimed.add(group.id);
    updates[table.id] = table.copyWith(parentId: group.id);
    for (final seat in children) {
      updates[seat.id] = seat.copyWith(
          parentId: table.id,
          x: positions[seat.id]![0],
          y: positions[seat.id]![1],
          rotation: seat.rotation - table.rotation);
      if (!attachments.any((a) => a['seatId'] == seat.id)) {
        attachments.add({
          'id': const Uuid().v5(Uuid.NAMESPACE_URL,
              'festapp:native-table:${table.id}:seat:${seat.id}'),
          'seatId': seat.id,
          'targetId': table.id,
          'placement': {'mode': 'free'},
          'rotationMode': 'auto'
        });
      }
    }
  }
  return document.copyWith(
      nodes: [for (final n in document.nodes) updates[n.id] ?? n],
      attachments: attachments);
}
