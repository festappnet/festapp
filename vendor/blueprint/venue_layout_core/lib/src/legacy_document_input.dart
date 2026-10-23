part of 'legacy_document_import.dart';

/// Historical input DTO. It cannot be passed to an editor, renderer or save API.
/// All inference stays here; only the validated document 2 leaves the importer.
class _LegacyLayoutInput {
  _LegacyLayoutInput._(
    this.nodes,
    this.canvas,
    this.defaultTextStyle,
    this.appearance,
    this.sections,
    this.selectionUnits,
    this.attachments,
    this.presets,
    this.generators,
    this.background,
  );
  factory _LegacyLayoutInput.fromJson(Map<String, dynamic> source) {
    const keys = {
      'schemaVersion',
      'symbolSetVersion',
      'canvas',
      'defaultTextStyle',
      'appearance',
      'nodes',
      'sections',
      'selectionUnits',
      'attachments',
      'presets',
      'generators',
      'background',
    };
    if (source.keys.any((key) => !keys.contains(key)) ||
        source['schemaVersion'] != 1 ||
        source['symbolSetVersion'] != 1 ||
        source['canvas'] is! Map ||
        source['nodes'] is! List ||
        utf8.encode(jsonEncode(source)).length > layoutMaxBytes) {
      throw const FormatException('invalid_legacy_layout_input');
    }
    Map<String, dynamic> map(String key) {
      final value = source[key];
      if (value == null) return const {};
      if (value is! Map) throw FormatException('invalid_legacy_$key');
      return frozenMap(Map<String, dynamic>.from(value));
    }

    List<Map<String, dynamic>> records(String key) {
      final value = source[key];
      if (value == null) return const [];
      if (value is! List || value.any((item) => item is! Map)) {
        throw FormatException('invalid_legacy_$key');
      }
      return List.unmodifiable(
        value.map((item) => frozenMap(Map<String, dynamic>.from(item))),
      );
    }

    final nodes = [
      for (final node in records('nodes')) LayoutNode.fromJson(node),
    ];
    if (nodes.length > layoutMaxNodes ||
        nodes.map((node) => node.id).toSet().length != nodes.length) {
      throw const FormatException('invalid_legacy_nodes');
    }
    return _LegacyLayoutInput._(
      List.unmodifiable(nodes),
      map('canvas'),
      source.containsKey('defaultTextStyle')
          ? map('defaultTextStyle')
          : const {'fontId': 'fixture:sans', 'size': 24, 'color': '#222222FF'},
      map('appearance'),
      records('sections'),
      records('selectionUnits'),
      records('attachments'),
      records('presets'),
      records('generators'),
      source['background'] == null ? null : map('background'),
    );
  }
  final List<LayoutNode> nodes;
  final Map<String, dynamic> canvas, defaultTextStyle, appearance;
  final List<Map<String, dynamic>> sections,
      selectionUnits,
      attachments,
      presets,
      generators;
  final Map<String, dynamic>? background;
  _LegacyLayoutInput copyWith({required List<LayoutNode> nodes}) =>
      _LegacyLayoutInput._(
        List.unmodifiable(nodes),
        canvas,
        defaultTextStyle,
        appearance,
        sections,
        selectionUnits,
        attachments,
        presets,
        generators,
        background,
      );
}

Map<String, num> _legacyRowParameters(_LegacyLayoutInput d, String rootId) {
  final root = d.nodes.firstWhere((n) => n.id == rootId);
  if (root.properties['assembly'] != 'rows') {
    throw ArgumentError('Not a row assembly');
  }
  final slots = <(LayoutNode, int, int, int)>[];
  for (final seat in d.nodes.where(
    (n) => n.kind == 'seat' && n.parentId == rootId,
  )) {
    final parts = '${seat.properties['slot']}'.split(':');
    if (parts.length != 3) continue;
    final indices = parts.map(int.tryParse).toList();
    if (indices.any((i) => i == null || i < 0)) continue;
    slots.add((seat, indices[0]!, indices[1]!, indices[2]!));
  }
  slots.sort((a, b) {
    for (final c in [
      a.$2.compareTo(b.$2),
      a.$3.compareTo(b.$3),
      a.$4.compareTo(b.$4),
    ]) {
      if (c != 0) return c;
    }
    return a.$1.id.compareTo(b.$1.id);
  });
  int count(String key, int index) {
    final explicit = root.properties[key];
    if (explicit is num &&
        explicit.isFinite &&
        explicit >= 1 &&
        explicit == explicit.round()) {
      return explicit.toInt();
    }
    return slots.fold(
      1,
      (n, slot) => math.max(n, [slot.$2, slot.$3, slot.$4][index] + 1),
    );
  }

  final rows = count('rows', 0),
      blocks = count('blocks', 1),
      seatsPerRow = count('seatsPerRow', 2),
      automatic = slots
          .where((s) => s.$1.properties['manual'] != true)
          .toList();
  double setting(
    String key,
    double inferred,
    double fallback, {
    bool signed = false,
    bool zero = false,
  }) {
    bool valid(num value) =>
        value.isFinite && (signed || (zero ? value >= 0 : value > 0));
    final explicit = root.properties[key];
    if (explicit is num && valid(explicit)) return explicit.toDouble();
    return valid(inferred) ? inferred : fallback;
  }

  double inferDelta(String kind) {
    final origins = <String, (LayoutNode, int, int, int)>{};
    for (final slot in automatic) {
      final key = switch (kind) {
        'spacing' => '${slot.$2}:${slot.$3}',
        'rowSpacing' => '${slot.$3}:${slot.$4}',
        _ => '${slot.$2}:${slot.$4}',
      };
      final previous = origins[key];
      if (previous == null) {
        origins[key] = slot;
        continue;
      }
      final index = kind == 'spacing'
          ? slot.$4 - previous.$4
          : kind == 'rowSpacing'
          ? slot.$2 - previous.$2
          : slot.$3 - previous.$3;
      if (index != 0) {
        return (kind == 'rowSpacing'
                ? slot.$1.y - previous.$1.y
                : slot.$1.x - previous.$1.x) /
            index;
      }
    }
    return double.nan;
  }

  final spacing = setting('spacing', inferDelta('spacing'), 56),
      rowSpacing = setting('rowSpacing', inferDelta('rowSpacing'), 64),
      half = (seatsPerRow - 1) / 2;
  var inferredArc = double.nan;
  for (final slot in automatic.where((s) => s.$2 == 0)) {
    final square = math.pow(slot.$4 - half, 2);
    if (square > 0) {
      inferredArc = slot.$1.y / square;
      break;
    }
  }
  return {
    'rows': rows,
    'seatsPerRow': seatsPerRow,
    'blocks': blocks,
    'spacing': spacing,
    'rowSpacing': rowSpacing,
    'arc': setting('arc', inferredArc, 0, signed: true),
    'aisle': setting(
      'aisle',
      inferDelta('aisle') - seatsPerRow * spacing,
      80,
      zero: true,
    ),
  };
}

Map<String, int> _legacyBusParameters(_LegacyLayoutInput document, String id) {
  final root = document.nodes.firstWhere((n) => n.id == id),
      p = root.properties;
  if (p['decks'] is int) {
    return {
      for (final key in [
        'rows',
        'left',
        'right',
        'rear',
        'decks',
        'upperRows',
        'upperRear',
      ])
        key: p[key] as int,
    };
  }
  final seats = document.nodes
      .where((n) => n.parentId == id && n.kind == 'seat')
      .toList();
  var rows = 0, rear = 0, total = 0;
  final first = <LayoutNode>[];
  for (final seat in seats) {
    final slot = '${seat.properties['slot']}',
        match = RegExp(r'^(\d+):(\d+)$').firstMatch(slot);
    if (match != null) {
      final r = int.parse(match[1]!);
      rows = math.max(rows, r + 1);
      total = math.max(total, int.parse(match[2]!) + 1);
      if (r == 0) first.add(seat);
    } else if (slot.startsWith('rear:'))
      rear++;
  }
  if (first.isEmpty) {
    throw StateError(
      'Legacy bus layout requires explicit row and seat-block parameters.',
    );
  }
  first.sort((a, b) => a.x.compareTo(b.x));
  var left = total, right = 0;
  var largest = 0.0, index = -1;
  for (var i = 1; i < first.length; i++) {
    final gap = first[i].x - first[i - 1].x;
    if (gap > largest) {
      largest = gap;
      index = i;
    }
  }
  if (largest > 80) {
    left = index;
    right = total - left;
  } else if (first.first.x >= 80) {
    left = 0;
    right = total;
  }
  return {
    'rows': rows,
    'left': left,
    'right': right,
    'rear': rear,
    'decks': 1,
    'upperRows': rows + 2,
    'upperRear': rear,
  };
}

Map<String, int> _legacyCompartmentParameters(
  _LegacyLayoutInput document,
  String id,
) {
  final root = document.nodes.firstWhere((n) => n.id == id),
      p = root.properties;
  if (p['compartments'] is int && p['seats'] is int) {
    return {
      'compartments': p['compartments'] as int,
      'seats': p['seats'] as int,
    };
  }
  var compartments = 0, seats = 0;
  for (final node in document.nodes.where(
    (n) => n.parentId == id && n.kind == 'seat',
  )) {
    final match = RegExp(
      r'^(\d+):(\d+)$',
    ).firstMatch('${node.properties['slot']}');
    if (match != null) {
      compartments = math.max(compartments, int.parse(match[1]!) + 1);
      seats = math.max(seats, int.parse(match[2]!) + 1);
    }
  }
  if (compartments == 0 || seats < 2) {
    throw StateError(
      'Legacy carriage requires explicit compartment parameters.',
    );
  }
  return {'compartments': compartments, 'seats': seats};
}

/// Attached chairs face the tabletop. Local +Y is the backrest direction;
/// manual placement changes position, not the attachment's facing constraint.
/// A detached chair retains its authored rotation.
double _legacyTableSeatFacingRotation(LayoutNode seat, LayoutNode? table) {
  if (table?.surface != null) {
    table = table!.copyWith(properties: surfaceGeometryProperties(table));
  }
  if (seat.kind != 'seat' ||
      table?.kind != 'table' ||
      seat.properties['manualRotation'] == true) {
    return seat.rotation;
  }
  var dx = seat.x, dy = seat.y;
  if (!const [
    'circle',
    'round',
    'ellipse',
    'oval',
  ].contains(table!.properties['shape'])) {
    final points = table.properties['points'];
    if (table.properties['shape'] == 'polygon' &&
        points is List &&
        points.length >= 3) {
      var best = double.infinity;
      for (var i = 0; i < points.length; i++) {
        final a = points[i] as List,
            b = points[(i + 1) % points.length] as List;
        final ax = (a[0] as num).toDouble(), ay = (a[1] as num).toDouble();
        final vx = (b[0] as num) - ax, vy = (b[1] as num) - ay;
        final length = vx * vx + vy * vy;
        final t = length == 0
            ? 0.0
            : ((seat.x - ax) * vx + (seat.y - ay) * vy) / length;
        final x = seat.x - ax - vx * t.clamp(0, 1),
            y = seat.y - ay - vy * t.clamp(0, 1);
        final distance = x * x + y * y;
        if (distance < best) {
          best = distance;
          dx = x;
          dy = y;
        }
      }
    } else {
      dx -= seat.x.clamp(-table.width / 2, table.width / 2);
      dy -= seat.y.clamp(-table.height / 2, table.height / 2);
    }
  }
  return dx.abs() + dy.abs() < .000001
      ? seat.rotation
      : quantize(math.atan2(-dx, dy) * 180 / math.pi);
}
