import 'dart:math';
import 'geometry.dart';
import 'model.dart';
import 'table_seating.dart';
import 'placement.dart';

/// Configurable schematic, not a manufacturer-specific seating certification.
VenueLayoutDocument busLayout({
  int rows = 10,
  int left = 2,
  int right = 2,
  int rear = 5,
  int decks = 1,
  int? upperRows,
  int? upperRear,
  double x = 160,
  double y = 120,
  String? id,
  TableSeating seating = const TableSeating(),
}) {
  final upper = upperRows ?? rows + 2, upperBack = upperRear ?? rear;
  _busCounts(rows, left, right, rear, decks, upper, upperBack);
  final total =
      rows * (left + right) +
      rear +
      (decks == 2 ? upper * (left + right) + upperBack : 0);
  if (total > layoutMaxSeats) throw RangeError('Transport exceeds seat limit');
  final regular = (left + right) * 52.0 + 112,
      width = max(
        regular,
        max(rear * 52.0 + 48, decks == 2 ? upperBack * 52.0 + 48 : 0.0),
      ),
      height = max(
        156 + rows * 64.0 + (rear > 0 ? 76 : 32),
        decks == 2 ? 112 + upper * 64.0 + (upperBack > 0 ? 76 : 32) : 0.0,
      ),
      root = LayoutNode(
        id: id ?? newLayoutId(),
        kind: 'group',
        x: x,
        y: y,
        width: decks * width + (decks - 1) * 96,
        height: height,
        label: decks == 2 ? 'Double-decker bus' : 'Bus',
        seating: seating.record,
        assembly: {
          'kind': 'bus',
          'rows': rows,
          'left': left,
          'right': right,
          'rear': rear,
          'decks': decks,
          'upperRows': upper,
          'upperRear': upperBack,
        },
        properties: const {},
      );
  final b = _Vehicle(root);
  var number = 1;
  for (var deck = 0; deck < decks; deck++) {
    final offset = deck * (width + 96),
        count = deck == 0 ? rows : upper,
        back = deck == 0 ? rear : upperBack,
        front = deck == 0 ? 156.0 : 112.0,
        blockOffset = (width - regular) / 2,
        aisleLeft = offset + blockOffset + 24 + left * 52,
        aisleRight = aisleLeft + 64;
    String slot(String key) => 'decor:deck:$deck:$key';
    b.box(
      slot('body'),
      offset + width / 2,
      height / 2,
      width,
      height,
      deck: deck,
      radius: 28,
      fill: '#F8FAFCFF',
      strokeWidth: 2,
      z: -20,
    );
    b.box(
      slot('interior'),
      offset + width / 2,
      height / 2,
      width - 16,
      height - 16,
      deck: deck,
      radius: 22,
      fill: '#00000000',
      stroke: '#B3C0CCFF',
      z: -19,
    );
    b.text(
      slot('label'),
      offset + width / 2,
      -24,
      width,
      24,
      decks == 1
          ? 'Bus'
          : deck == 0
          ? 'Lower deck'
          : 'Upper deck',
      deck: deck,
      size: 14,
    );
    b.line(
      slot('windshield'),
      [
        [offset + 28, 18],
        [offset + width - 28, 18],
      ],
      deck: deck,
      stroke: '#7896ACFF',
      strokeWidth: 4,
    );
    b.line(
      slot('aisle-left'),
      [
        [aisleLeft + 7, front - 12],
        [aisleLeft + 7, height - 64],
      ],
      deck: deck,
      stroke: '#BCC7D2FF',
      dash: [6, 6],
    );
    b.line(
      slot('aisle-right'),
      [
        [aisleRight - 7, front - 12],
        [aisleRight - 7, height - 64],
      ],
      deck: deck,
      stroke: '#BCC7D2FF',
      dash: [6, 6],
    );
    if (deck == 0) {
      b.box(
        slot('driver-seat'),
        offset + 54,
        87,
        40,
        42,
        deck: deck,
        radius: 8,
        fill: '#CBD5E1FF',
      );
      b.box(
        slot('steering'),
        offset + 68,
        45,
        28,
        28,
        deck: deck,
        shape: 'ellipse',
        fill: '#00000000',
        strokeWidth: 3,
      );
      b.line(
        slot('dashboard'),
        [
          [offset + 22, 34],
          [offset + 104, 34],
          [offset + 118, 65],
        ],
        deck: deck,
        strokeWidth: 2,
      );
      b.text(
        slot('driver-label'),
        offset + 64,
        126,
        96,
        20,
        'Driver',
        deck: deck,
      );
      b.line(
        slot('cab-partition'),
        [
          [offset + 18, 146],
          [aisleLeft - 10, 146],
        ],
        deck: deck,
        strokeWidth: 2,
      );
      for (var door = 0; door < 2; door++) {
        final y = door == 0
            ? 94.0
            : min(height - 126, front + max(1, count ~/ 2) * 64);
        b.box(
          slot('door-$door'),
          offset + width - 14,
          y,
          24,
          64,
          deck: deck,
          radius: 2,
          fill: '#E9EFF4FF',
        );
        for (var step = 0; step < 3; step++) {
          b.line(
            slot('door-$door-step-$step'),
            [
              [offset + width - 26, y - 20 + step * 20],
              [offset + width - 3, y - 20 + step * 20],
            ],
            deck: deck,
            stroke: '#7C8C9CFF',
          );
        }
      }
    }
    if (decks == 2) {
      b.box(
        slot('stairs'),
        offset + width - 67,
        62,
        74,
        82,
        deck: deck,
        radius: 4,
        fill: '#EEF2F6FF',
      );
      for (var step = 0; step < 6; step++) {
        b.line(
          slot('stair-$step'),
          [
            [offset + width - 100, 28 + step * 12],
            [offset + width - 34, 28 + step * 12],
          ],
          deck: deck,
          stroke: '#7C8C9CFF',
        );
      }
      b.text(
        slot('stairs-label'),
        offset + width - 68,
        113,
        100,
        20,
        'Stairs',
        deck: deck,
      );
    }
    // A compact arrow points toward the front without covering seat labels.
    final arrowX = (aisleLeft + aisleRight) / 2;
    b.line(
      slot('travel-direction'),
      [
        [arrowX, 132],
        [arrowX, 58],
        [arrowX - 10, 70],
        [arrowX, 58],
        [arrowX + 10, 70],
      ],
      deck: deck,
      strokeWidth: 2,
    );
    for (var row = 0; row < count; row++) {
      final y = front + 20 + row * 64;
      for (var i = 0; i < left; i++) {
        b.seat(
          'deck:$deck:row:$row:left:$i',
          aisleLeft - 26 - (left - 1 - i) * 52,
          y,
          '${number++}',
          deck: deck,
        );
      }
      for (var i = 0; i < right; i++) {
        b.seat(
          'deck:$deck:row:$row:right:$i',
          aisleRight + 26 + i * 52,
          y,
          '${number++}',
          deck: deck,
        );
      }
      b.line(
        slot('window-left-$row'),
        [
          [offset + 8, y - 20],
          [offset + 8, y + 20],
        ],
        deck: deck,
        stroke: '#7896ACFF',
        strokeWidth: 3,
      );
      b.line(
        slot('window-right-$row'),
        [
          [offset + width - 8, y - 20],
          [offset + width - 8, y + 20],
        ],
        deck: deck,
        stroke: '#7896ACFF',
        strokeWidth: 3,
      );
    }
    for (var i = 0; i < back; i++) {
      b.seat(
        'deck:$deck:rear:$i',
        offset + width / 2 + (i - (back - 1) / 2) * 52,
        height - 48,
        '${number++}',
        deck: deck,
      );
    }
    final last = front + 20 + max(0, count - 1) * 64, gap = height - 48 - last;
    if (deck == 0 && decks == 2 && gap >= 130) {
      b.text(
        slot('service-label'),
        offset + width / 2,
        last + gap / 2,
        width - 48,
        22,
        'Service area',
        deck: deck,
      );
    }
  }
  return _checked(
    _transportSeating(
      VenueLayoutDocument(
        schemaVersion: 2,
        nodes: b.nodes,
        seatingDefaults: seating.record,
        attachments: [
          for (final seat in b.nodes.where((node) => node.kind == 'seat'))
            {
              'id': newLayoutId(),
              'seatId': seat.id,
              'targetId': root.id,
              'placement': {'mode': 'automatic'},
              'rotationMode': 'auto',
            },
        ],
      ),
      seating,
    ),
  );
}

VenueLayoutDocument compartmentLayout({
  int compartments = 4,
  int seats = 6,
  double x = 100,
  double y = 100,
  String? id,
  TableSeating seating = const TableSeating(),
}) {
  if (compartments < 1 ||
      seats < 2 ||
      seats > 12 ||
      compartments * seats > layoutMaxSeats) {
    throw RangeError('Invalid compartment or seat count');
  }
  final front = (seats + 1) ~/ 2,
      back = seats ~/ 2,
      cell = 224.0,
      depth = max(224.0, front * 52.0 + 48),
      height = depth + 96,
      width = compartments * cell + 220;
  final root = LayoutNode(
    id: id ?? newLayoutId(),
    kind: 'group',
    x: x,
    y: y,
    width: width,
    height: height,
    label: 'Carriage',
    seating: seating.record,
    assembly: {
      'kind': 'compartments',
      'compartments': compartments,
      'seats': seats,
    },
    properties: const {},
  );
  final b = _Vehicle(root);
  var number = 1;
  b.box(
    'decor:body',
    width / 2,
    height / 2,
    width,
    height,
    radius: 20,
    fill: '#F8FAFCFF',
    strokeWidth: 2,
    z: -20,
  );
  b.box(
    'decor:interior',
    width / 2,
    height / 2,
    width - 16,
    height - 16,
    radius: 14,
    fill: '#00000000',
    stroke: '#B3C0CCFF',
    z: -19,
  );
  b.text('decor:label', width / 2, -24, width, 24, 'Carriage', size: 14);
  b.text(
    'decor:corridor-label',
    width / 2,
    depth + 48,
    width - 300,
    20,
    'Corridor',
  );
  b.line('decor:travel-direction', [
    [width - 210, depth + 48],
    [width - 150, depth + 48],
    [width - 162, depth + 38],
    [width - 150, depth + 48],
    [width - 162, depth + 58],
  ], strokeWidth: 2);
  for (var c = 0; c < compartments; c++) {
    final start = 110 + c * cell, center = start + cell / 2;
    b.text(
      'decor:comp:$c:label',
      center,
      depth / 2,
      cell - 100,
      22,
      'Compartment ${c + 1}',
    );
    b.line(
      'decor:comp:$c:left',
      [
        [start, 16],
        [start, depth + 8],
      ],
      stroke: '#7C8C9CFF',
      strokeWidth: 2,
    );
    if (c == compartments - 1) {
      b.line(
        'decor:comp:$c:right',
        [
          [start + cell, 16],
          [start + cell, depth + 8],
        ],
        stroke: '#7C8C9CFF',
        strokeWidth: 2,
      );
    }
    b.line('decor:comp:$c:door-left', [
      [start, depth + 8],
      [center - 36, depth + 8],
    ], strokeWidth: 2);
    b.line('decor:comp:$c:door-right', [
      [center + 36, depth + 8],
      [start + cell, depth + 8],
    ], strokeWidth: 2);
    b.line(
      'decor:comp:$c:door-slide',
      [
        [center - 36, depth + 2],
        [center + 36, depth + 2],
      ],
      stroke: '#96A6B6FF',
      strokeWidth: 3,
    );
    b.line(
      'decor:comp:$c:window',
      [
        [start + 22, 8],
        [start + cell - 22, 8],
      ],
      stroke: '#7896ACFF',
      strokeWidth: 4,
    );
    b.line(
      'decor:comp:$c:corridor-window',
      [
        [start + 22, height - 8],
        [start + cell - 22, height - 8],
      ],
      stroke: '#7896ACFF',
      strokeWidth: 3,
    );
    // With a horizontal carriage, opposing triples sit against the left/right
    // compartment partitions, along the transverse axis toward the side corridor.
    for (var row = 0; row < 2; row++) {
      final count = row == 0 ? front : back;
      for (var i = 0; i < count; i++) {
        b.seat(
          'comp:$c:row:$row:seat:$i',
          row == 0 ? start + 34 : start + cell - 34,
          24 + (i + .5) * (depth - 48) / count,
          '${number++}',
          rotation: row == 0 ? 90 : 270,
        );
      }
    }
  }
  for (var side = 0; side < 2; side++) {
    final center = side == 0 ? 55.0 : width - 55;
    b.box('decor:wc-$side', center, 66, 78, 94, radius: 5, fill: '#E9EFF4FF');
    b.text('decor:wc-$side:label', center, 66, 60, 20, 'WC');
    b.box(
      'decor:vestibule-$side',
      center,
      depth - 35,
      78,
      80,
      radius: 4,
      fill: '#00000000',
    );
    b.text(
      'decor:vestibule-$side:label',
      center,
      depth - 35,
      82,
      28,
      'Vestibule',
      size: 10,
    );
    b.line(
      'decor:door-$side',
      [
        [center - 24, height - 7],
        [center + 24, height - 7],
      ],
      stroke: '#7896ACFF',
      strokeWidth: 5,
    );
    b.line('decor:gangway-$side', [
      [side == 0 ? 0.0 : width, depth + 20],
      [side == 0 ? 0.0 : width, depth + 70],
    ], strokeWidth: 4);
  }
  return _checked(
    _transportSeating(
      VenueLayoutDocument(
        schemaVersion: 2,
        nodes: b.nodes,
        seatingDefaults: seating.record,
        attachments: [
          for (final seat in b.nodes.where((node) => node.kind == 'seat'))
            {
              'id': newLayoutId(),
              'seatId': seat.id,
              'targetId': root.id,
              'placement': {'mode': 'automatic'},
              'rotationMode': 'auto',
            },
        ],
      ),
      seating,
    ),
  );
}

Map<String, int> busLayoutParameters(VenueLayoutDocument document, String id) {
  final root = _root(document, id, 'bus'), p = root.assembly!;
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
  throw StateError('Missing canonical bus parameters');
}

Map<String, int> compartmentLayoutParameters(
  VenueLayoutDocument document,
  String id,
) {
  final root = _root(document, id, 'compartments'), p = root.assembly!;
  if (p['compartments'] is int && p['seats'] is int) {
    return {
      'compartments': p['compartments'] as int,
      'seats': p['seats'] as int,
    };
  }
  throw StateError('Missing canonical compartment parameters');
}

VenueLayoutDocument updateBusLayout(
  VenueLayoutDocument document,
  String id, {
  int? rows,
  int? left,
  int? right,
  int? rear,
  int? decks,
  int? upperRows,
  int? upperRear,
  Set<String> protectedSeatIds = const {},
}) {
  final root = _root(document, id, 'bus'),
      p = busLayoutParameters(document, id);
  final generated = busLayout(
    seating: TableSeating.fromDocument(document, root),
    id: id,
    x: root.x,
    y: root.y,
    rows: rows ?? p['rows']!,
    left: left ?? p['left']!,
    right: right ?? p['right']!,
    rear: rear ?? p['rear']!,
    decks: decks ?? p['decks']!,
    upperRows: upperRows ?? p['upperRows']!,
    upperRear: upperRear ?? p['upperRear']!,
  );
  return _reconcile(
    document,
    root,
    generated,
    protectedSeatIds,
    (slot) => _busSlot(slot, p['left']!),
  );
}

VenueLayoutDocument updateCompartmentLayout(
  VenueLayoutDocument document,
  String id, {
  int? compartments,
  int? seats,
  Set<String> protectedSeatIds = const {},
}) {
  final root = _root(document, id, 'compartments'),
      p = compartmentLayoutParameters(document, id);
  final generated = compartmentLayout(
    seating: TableSeating.fromDocument(document, root),
    id: id,
    x: root.x,
    y: root.y,
    compartments: compartments ?? p['compartments']!,
    seats: seats ?? p['seats']!,
  );
  return _reconcile(
    document,
    root,
    generated,
    protectedSeatIds,
    (slot) => _coupeSlot(slot, p['seats']!),
  );
}

class TransportLayoutRejected implements Exception {
  final String message;
  final Set<String> seatIds;
  TransportLayoutRejected(this.message, Iterable<String> seatIds)
    : seatIds = Set.unmodifiable(seatIds);
  @override
  String toString() => message;
}

VenueLayoutDocument _reconcile(
  VenueLayoutDocument d,
  LayoutNode root,
  VenueLayoutDocument generated,
  Set<String> protected,
  String Function(String) canonical,
) {
  final index = {for (final n in d.nodes) n.id: n};
  final children = d.nodes.where((n) => n.parentId == root.id).toList();
  final ancestors = <String>{};
  LayoutNode? ancestor = root;
  while (ancestor != null && ancestors.add(ancestor.id)) {
    if (ancestor.locked) throw StateError('Locked transport layout');
    ancestor = index[ancestor.parentId];
  }
  if (children.any((n) => n.locked)) {
    throw StateError('Locked transport layout');
  }
  final oldBySlot = <String, LayoutNode>{};
  for (final node in children) {
    if (node.properties['slot'] != null) {
      final slot = canonical('${node.properties['slot']}');
      if (oldBySlot.containsKey(slot)) {
        throw StateError('Duplicate transport slot');
      }
      oldBySlot[slot] = node;
    }
  }
  final candidates = generated.nodes.skip(1).toList(),
      wanted = candidates.map((n) => '${n.properties['slot']}').toSet();
  final removed = oldBySlot.entries
      .where((e) => !wanted.contains(e.key))
      .map((e) => e.value.id)
      .toSet();
  final protectedAll = {...protected};
  for (final unit in d.selectionUnits) {
    final ids = (unit['nodeIds'] as List).cast<String>().toSet();
    if (ids.any(protected.contains)) protectedAll.addAll(ids);
    if (ids.any(removed.contains) && !removed.containsAll(ids)) {
      throw TransportLayoutRejected(
        'Atomic seat groups prevent changing this transport layout.',
        ids,
      );
    }
  }
  final unsafe = children
      .where(
        (n) =>
            n.kind == 'seat' &&
            removed.contains(n.id) &&
            (protectedAll.contains(n.id) || seatPlacementFree(d, n)),
      )
      .map((n) => n.id)
      .toSet();
  if (unsafe.isNotEmpty) {
    throw TransportLayoutRejected(
      'Manual or protected seats prevent changing this transport layout.',
      unsafe,
    );
  }
  final labels = d.nodes
      .where((n) => n.kind == 'seat')
      .map((n) => n.label)
      .toSet();
  var nextNumber = 1;
  for (final label in labels) {
    final number = int.tryParse(label);
    if (number != null) nextNumber = max(nextNumber, number + 1);
  }
  final replacement = <LayoutNode>[];
  for (final candidate in candidates) {
    final slot = '${candidate.properties['slot']}', old = oldBySlot[slot];
    if (old == null) {
      var added = candidate;
      if (candidate.kind == 'seat') {
        while (labels.contains('$nextNumber')) {
          nextNumber++;
        }
        added = candidate.copyWith(label: '${nextNumber++}');
        labels.add(added.label);
      }
      replacement.add(added);
      continue;
    }
    final manual = old.kind == 'seat' && seatPlacementFree(d, old),
        manualRotation = old.kind == 'seat' && seatRotationManual(d, old);
    replacement.add(
      old.copyWith(
        x: manual ? old.x : candidate.x,
        y: manual ? old.y : candidate.y,
        rotation: manualRotation ? old.rotation : candidate.rotation,
        width: old.kind == 'seat' ? old.width : candidate.width,
        height: old.kind == 'seat' ? old.height : candidate.height,
        properties: {
          ...candidate.properties,
          ...old.properties,
          'slot': slot,
          if (candidate.properties['deck'] != null)
            'deck': candidate.properties['deck'],
          if (candidate.properties['points'] != null && !manual)
            'points': candidate.properties['points'],
          if (candidate.kind == 'text') 'text': candidate.properties['text'],
        },
      ),
    );
  }
  final managed = oldBySlot.values.map((n) => n.id).toSet();
  final updatedRoot = root.copyWith(
    width: generated.nodes.first.width,
    height: generated.nodes.first.height,
    properties: {...root.properties, ...generated.nodes.first.properties},
    assembly: generated.nodes.first.assembly,
  );
  return _checked(
    d.copyWith(
      nodes: [
        for (final n in d.nodes)
          if (n.id == root.id) updatedRoot else if (!managed.contains(n.id)) n,
        ...replacement,
      ],
      selectionUnits: d.selectionUnits
          .where((u) => !(u['nodeIds'] as List).any(removed.contains))
          .toList(),
      attachments: [
        ...d.attachments.where(
          (a) =>
              !removed.contains(a['seatId']) &&
              !removed.contains(a['targetId']),
        ),
        for (final seat in replacement.where((node) => node.kind == 'seat'))
          if (!d.attachments.any((a) => a['seatId'] == seat.id))
            {
              'id': newLayoutId(),
              'seatId': seat.id,
              'targetId': root.id,
              'placement': {'mode': 'automatic'},
              'rotationMode': 'auto',
            },
      ],
    ),
  );
}

String _busSlot(String slot, int left) {
  final old = RegExp(r'^(\d+):(\d+)$').firstMatch(slot);
  if (old != null) {
    final s = int.parse(old[2]!);
    return 'deck:0:row:${old[1]}:${s < left ? 'left' : 'right'}:${s < left ? s : s - left}';
  }
  final rear = RegExp(r'^rear:(\d+)$').firstMatch(slot);
  return rear == null ? slot : 'deck:0:rear:${rear[1]}';
}

String _coupeSlot(String slot, int seats) {
  final old = RegExp(r'^(\d+):(\d+)$').firstMatch(slot);
  if (old == null) return slot;
  final s = int.parse(old[2]!), front = (seats + 1) ~/ 2;
  return 'comp:${old[1]}:row:${s < front ? 0 : 1}:seat:${s < front ? s : s - front}';
}

LayoutNode _root(VenueLayoutDocument d, String id, String assembly) {
  final node = d.nodes.firstWhere((n) => n.id == id);
  if (node.kind != 'group' || ((node.assembly?['kind'])) != assembly) {
    throw ArgumentError('Expected $assembly transport assembly');
  }
  return node;
}

void _busCounts(
  int rows,
  int left,
  int right,
  int rear,
  int decks,
  int upperRows,
  int upperRear,
) {
  if (rows < 0 ||
      upperRows < 0 ||
      rows > layoutMaxSeats ||
      upperRows > layoutMaxSeats ||
      left < 0 ||
      right < 0 ||
      left > 3 ||
      right > 3 ||
      left + right == 0 ||
      rear < 0 ||
      rear > 6 ||
      upperRear < 0 ||
      upperRear > 6 ||
      decks < 1 ||
      decks > 2) {
    throw RangeError('Invalid bus row, deck or seat-block count');
  }
}

VenueLayoutDocument _checked(VenueLayoutDocument d) {
  final issues = validateDocument(d);
  if (issues.isNotEmpty) {
    throw InvalidLayoutDocument(issues, {
      'operation': 'transport',
      'nodes': d.nodes.length,
    });
  }
  return d;
}

class _Vehicle {
  final LayoutNode root;
  final List<LayoutNode> nodes;
  _Vehicle(this.root) : nodes = [root];
  void box(
    String slot,
    double x,
    double y,
    double width,
    double height, {
    int? deck,
    double radius = 4,
    String shape = 'roundedRect',
    String fill = '#FFFFFFFF',
    String stroke = '#4B6072FF',
    double strokeWidth = 1,
    int z = 0,
  }) {
    nodes.add(
      LayoutNode(
        id: newLayoutId(),
        kind: 'shape',
        parentId: root.id,
        x: x,
        y: y,
        width: width,
        height: height,
        z: z,
        style: {
          'fill': fill,
          'stroke': stroke,
          'strokeWidth': strokeWidth,
          'cornerRadius': radius,
          'material': 'simple',
        },
        properties: {
          'shape': shape,

          'role': 'decoration',
          'slot': slot,
          'deck': ?deck,
        },
      ),
    );
  }

  void line(
    String slot,
    List<List<double>> points, {
    int? deck,
    String stroke = '#4B6072FF',
    double strokeWidth = 1,
    List<double>? dash,
  }) {
    final node = shapeFromPoints(
      'polyline',
      points,
      style: {
        'fill': '#00000000',
        'stroke': stroke,
        'strokeWidth': strokeWidth,
        if (dash != null) 'strokePattern': {'type': 'custom', 'lengths': dash},
      },
      properties: {
        'role': 'decoration',
        'slot': slot,
        'deck': ?deck,
      },
    );
    nodes.add(node.copyWith(parentId: root.id));
  }

  void text(
    String slot,
    double x,
    double y,
    double width,
    double height,
    String text, {
    int? deck,
    double size = 12,
  }) {
    nodes.add(
      LayoutNode(
        id: newLayoutId(),
        kind: 'text',
        parentId: root.id,
        x: x,
        y: y,
        width: width,
        height: height,
        style: {
          'label': {'size': size, 'align': 'center', 'color': '#46596BFF'},
        },
        properties: {
          'text': text,

          'role': 'decoration',
          'slot': slot,
          'deck': ?deck,
        },
      ),
    );
  }

  void seat(
    String slot,
    double x,
    double y,
    String label, {
    int? deck,
    double rotation = 0,
  }) {
    nodes.add(
      LayoutNode(
        id: newLayoutId(),
        kind: 'seat',
        parentId: root.id,
        x: x,
        y: y,
        rotation: rotation,
        label: label,
        style: {
          'label': {'size': 12, 'align': 'center'},
        },
        properties: {
          'slot': slot,
          'deck': ?deck,
          'symbol': 'chair',
        },
      ),
    );
  }
}

// Scale the complete vehicle schematic around its root so seats, aisles,
// partitions and labels remain in proportion. Counts and slot identities stay
// independent of these physical dimensions and can be regenerated later.
VenueLayoutDocument _transportSeating(
  VenueLayoutDocument document,
  TableSeating seating,
) {
  final scale = max(seating.width, seating.height) / 40;
  return document.copyWith(
    nodes: [
      for (final node in document.nodes)
        node.copyWith(
          x: node.parentId == null ? node.x : node.x * scale,
          y: node.parentId == null ? node.y : node.y * scale,
          width: node.kind == 'seat' ? seating.width : node.width * scale,
          height: node.kind == 'seat' ? seating.height : node.height * scale,
          style: {
            ...node.style,
            for (final key in ['cornerRadius', 'strokeWidth'])
              if (node.style[key] is num) key: (node.style[key] as num) * scale,
            if (node.style['label'] is Map)
              'label': {
                ...node.style['label'] as Map,
                if (node.style['label']['size'] is num)
                  'size': (node.style['label']['size'] as num) * scale,
              },
            if (node.style['strokePattern']?['type'] == 'custom')
              'strokePattern': {
                'type': 'custom',
                'lengths': [
                  for (final value
                      in node.style['strokePattern']['lengths'] as List)
                    (value as num) * scale,
                ],
              },
          },
          properties: {
            ...node.properties,
            for (final key in ['cornerRadius', 'size', 'strokeWidth'])
              if (node.properties[key] is num)
                key: (node.properties[key] as num) * scale,
            if (node.properties['points'] is List)
              'points': [
                for (final point in node.properties['points'] as List)
                  [(point[0] as num) * scale, (point[1] as num) * scale],
              ],
            if (node.properties['dash'] is List)
              'dash': [
                for (final value in node.properties['dash'] as List)
                  (value as num) * scale,
              ],
          },
        ),
    ],
  );
}
