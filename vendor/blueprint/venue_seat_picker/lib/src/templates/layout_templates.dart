import 'dart:math' as math;
import 'package:venue_layout_core/venue_layout_core.dart';
import 'scout_hall.dart';
import 'cinema_hall.dart';
import 'scout_balcony_hall.dart';

/// A synthetic, editable layout. Every creation allocates fresh identities.
class LayoutTemplate {
  const LayoutTemplate(
    this.id,
    this.title,
    this.description,
    this.seatCount,
    this.standingCapacity,
    this._build,
  );
  final String id, title, description;
  final int seatCount, standingCapacity;
  final VenueLayoutDocument Function() _build;
  VenueLayoutDocument create({String Function(String)? localize}) {
    final document = _build();
    return localizeLayoutDefaultLabels(document, localize ?? (text) => text);
  }
}

/// Translates stock labels while preserving arbitrary user-authored text.
VenueLayoutDocument localizeLayoutDefaultLabels(
  VenueLayoutDocument document,
  String Function(String) localize,
) {
  String label(String value, {bool decorative = false}) {
    if (decorative &&
        const {'Column', 'Side table', 'Bus outline'}.contains(value)) {
      return '';
    }
    final numbered = RegExp(
      r'^(Table|Couch|Bar|Carriage|Compartment) (\d+)$',
    ).firstMatch(value);
    if (numbered != null) {
      return '${localize(numbered.group(1)!)} ${numbered.group(2)}';
    }
    if (value.startsWith('Standing area - ')) {
      return '${localize('Standing area')} - ${value.substring('Standing area - '.length)}';
    }
    const defaults = {
      'Bar',
      'Stage',
      'Dance floor',
      'Entrance',
      'Ground floor',
      'Balcony',
      'Stairs',
      'Standing area',
      'Driver',
      'Carriage',
      'Corridor',
      'Service area',
      'Door',
      'Bus',
      'Double-decker bus',
      'Lower deck',
      'Upper deck',
      'Your text',
      'Cross aisle',
      'Premium seats',
      'Orchestra pit',
      'Boxes',
      'Vestibule',
      'Baggage',
      'Reception',
      'Screen',
      'Exit',
      'Backstage',
      'Stalls',
      'Conference',
      'Meeting area',
      'Lounge',
      'Standing',
    };
    return defaults.contains(value) ? localize(value) : value;
  }

  return document.copyWith(
    nodes: document.nodes
        .map(
          (n) => n.copyWith(
            label: label(
              n.label,
              decorative: n.kind == 'shape' || n.kind == 'furniture',
            ),
            properties: {
              ...n.properties,
              if (n.kind == 'text' && n.properties['text'] is String)
                'text': label(n.properties['text'] as String),
            },
          ),
        )
        .toList(),
    sections: document.sections
        .map(
          (section) => <String, dynamic>{
            ...section,
            if (section['title'] is String)
              'title': label(section['title'] as String),
          },
        )
        .toList(),
    selectionUnits: document.selectionUnits
        .map(
          (unit) => <String, dynamic>{
            ...unit,
            if (unit['label'] is String)
              'label': label(unit['label'] as String),
          },
        )
        .toList(),
  );
}

/// Version 1 of the package-owned geometric template library.
abstract final class VenueLayoutTemplates {
  static const version = 8;
  static const defaultId = 'ball-classic';
  static final List<LayoutTemplate> all = List.unmodifiable([
    LayoutTemplate(
      'scout-ball-182',
      'Scout ball - original hall',
      'Original 182 seats, 31 tables, stage, dance floor and columns',
      182,
      0,
      scoutHall,
    ),
    LayoutTemplate(
      'scout-ball-balcony-249',
      'Scout ball - hall with balcony',
      'Original 249 seats, side tables, balcony, stage and stairs',
      249,
      0,
      scoutBalconyHall,
    ),
    LayoutTemplate(
      'cinema-galaxy',
      'Galaxy cinema',
      'Dark cinema with seven rows, 84 seats and four two-seat sofas',
      84,
      0,
      galaxyCinemaHall,
    ),
    LayoutTemplate(
      'ball-classic',
      'Classic ball',
      'Timber banquet, central dance floor, stage and bar',
      72,
      0,
      () => _ball(12, 0),
    ),
    LayoutTemplate(
      'ball-round',
      'Gala ball',
      'Lounge round tables, reception and dance floor',
      80,
      0,
      () => _ball(0, 10),
    ),
    LayoutTemplate(
      'ball-mixed',
      'Contemporary ball',
      'Mixed seating, generous aisles and a central dance floor',
      68,
      0,
      () => _ball(6, 4),
    ),
    LayoutTemplate(
      'ball-balcony',
      'Hall with balcony',
      'Ground floor and balcony in one plan',
      64,
      0,
      _balcony,
    ),
    LayoutTemplate(
      'lounge',
      'Lounge and standing',
      'Six two-seat couches and a standing area',
      12,
      20,
      () => withLayoutMaterialFamily(_lounge(), 'lounge'),
    ),
    LayoutTemplate(
      'auditorium',
      'Cinema',
      'Continuous rows, side access and a cross aisle',
      198,
      0,
      _auditorium,
    ),
    LayoutTemplate(
      'theatre',
      'Theatre',
      'Continuous curved stalls, side boxes and balcony',
      188,
      0,
      _theatre,
    ),
    LayoutTemplate(
      'conference',
      'Conference and reception',
      'Stage, audience, meeting tables and lounge with a U-shaped bar',
      102,
      40,
      _conference,
    ),
    LayoutTemplate(
      'bus',
      'Bus',
      'Ten 2+2 rows and five rear seats',
      45,
      0,
      () => withLayoutMaterialFamily(_bus(), 'transit'),
    ),
    LayoutTemplate(
      'double-decker',
      'Double-decker bus',
      'Two decks, stairs, service area and separate seating',
      98,
      0,
      () => withLayoutMaterialFamily(
        _transportFrame(busLayout(decks: 2, x: 0, y: 0)),
        'transit',
      ),
    ),
    LayoutTemplate(
      'train',
      'Two train carriages',
      'Two carriages, nine six-seat compartments each',
      108,
      0,
      () => withLayoutMaterialFamily(_train(), 'transit'),
    ),
    LayoutTemplate(
      'blank',
      'Blank layout',
      'Start with an empty canvas',
      0,
      0,
      () => _Seed().finish(),
    ),
  ]);
  static LayoutTemplate byId(String id) => all.firstWhere(
    (t) => t.id == id,
    orElse: () =>
        throw ArgumentError.value(id, 'id', 'Unknown layout template'),
  );
  static VenueLayoutDocument create(
    String id, {
    String Function(String)? localize,
  }) => byId(id).create(localize: localize);
}

class _Seed {
  final nodes = <LayoutNode>[];
  final units = <Map<String, dynamic>>[];
  final sections = <Map<String, dynamic>>[];
  final attachments = <Map<String, dynamic>>[];
  void add(VenueLayoutDocument fragment) {
    nodes.addAll(fragment.nodes);
    attachments.addAll(fragment.attachments);
    units.addAll(fragment.selectionUnits);
    sections.addAll(fragment.sections);
  }

  void line(
    List<List<double>> points, {
    double weight = 2,
    String color = '#CBD5E1FF',
  }) {
    nodes.add(
      shapeFromPoints(
        'polyline',
        points,
        properties: {'role': 'decoration'},
        style: {'fill': '#00000000', 'stroke': color, 'strokeWidth': weight},
      ),
    );
  }

  void room(double width, double height) {
    line([
      [50, height - 50],
      [50, 50],
      [width - 50, 50],
      [width - 50, height - 50],
    ], weight: 5);
    line([
      [50, height - 50],
      [width / 2 - 100, height - 50],
    ], weight: 5);
    line([
      [width / 2 + 100, height - 50],
      [width - 50, height - 50],
    ], weight: 5);
    text(width / 2, height - 55, 'Entrance', width: 180);
  }

  void section(String label, List<LayoutNode> members) {
    final root = object('group', 0, 0, 1, 1, label);
    final ids = members.map((n) => n.id).toSet();
    for (var i = 0; i < nodes.length; i++) {
      if (ids.contains(nodes[i].id) && nodes[i].parentId == null) {
        nodes[i] = nodes[i].copyWith(parentId: root);
      }
    }
    sections.add({
      'id': newLayoutId(),
      'title': label,
      'levelId': label,
      'rootId': root,
    });
  }

  void table(
    double x,
    double y,
    int count, {
    bool round = false,
    String? section,
  }) {
    final fragment = tableLayout(
      shape: round ? 'ellipse' : 'roundedRect',
      count: count,
      x: x,
      y: y,
      width: round ? 180 : 190,
      height: round ? 180 : 110,
    );
    final title =
        'Table ${nodes.where((n) => n.kind == 'table' && !isBarNode(n)).length + 1}';
    nodes.addAll(
      fragment.nodes.map(
        (n) => n.kind == 'table'
            ? n.copyWith(
                label: title,
                properties: {...n.properties},
                style: {
                  ...n.style,
                  'label': {'align': 'center', 'size': 16},
                },
              )
            : n,
      ),
    );
    attachments.addAll(fragment.attachments);
  }

  String object(
    String kind,
    double x,
    double y,
    double w,
    double h,
    String label, {
    String? parent,
    Map<String, dynamic> extra = const {},
    Map<String, dynamic> style = const {},
  }) {
    final id = newLayoutId();
    nodes.add(
      LayoutNode(
        id: id,
        kind: kind,
        parentId: parent,
        x: x,
        y: y,
        width: w,
        height: h,
        label: label,
        properties: extra,
        style: style,
      ),
    );
    return id;
  }

  void text(double x, double y, String value, {double width = 300}) => object(
    'text',
    x,
    y,
    width,
    40,
    value,
    extra: {'text': value},
    style: {
      'label': {'align': 'center', 'size': 24, 'color': '#243247FF'},
    },
  );
  void decor(
    double x,
    double y,
    double w,
    double h,
    String label, {
    String shape = 'rect',
    String fill = '#E3EAF2FF',
    bool obstacle = true,
  }) => object(
    'shape',
    x,
    y,
    w,
    h,
    label,
    extra: {
      'shape': shape,
      'role': obstacle ? 'obstacle' : 'decoration',
      'obstacle': obstacle,
    },
    style: {
      'fill': fill,
      'label': {'size': 12, 'align': 'center'},
    },
  );
  void seat(double x, double y, {String? parent, String label = ''}) => object(
    'seat',
    x,
    y,
    38,
    38,
    label,
    parent: parent,
    extra: {'symbol': 'chair'},
    style: {
      'label': {'size': 12, 'align': 'center'},
    },
  );
  VenueLayoutDocument finish({double width = 1600, double height = 1200}) =>
      VenueLayoutDocument.fromJson({
        'schemaVersion': 2,
        'seatingDefaults': {},
        'symbolSetVersion': 1,
        'canvas': {
          'x': 0,
          'y': 0,
          'width': width,
          'height': height,
          'fill': '#FFFFFFFF',
        },
        'styles': {
          'label': {'size': 24, 'color': '#243247FF'},
        },
        'textPolicy': {'language': 'und', 'direction': 'auto'},
        'nodes': nodes.map((n) => n.toJson()).toList(),
        'attachments': attachments,
        'sections': sections,
        'selectionUnits': units,
        'presets': [],
        'background': null,
      });
}

VenueLayoutDocument _ball(int rectangular, int round) {
  final s = _Seed();
  s.room(2000, 1600);
  final positions = <List<double>>[
    for (final y in [490.0, 850.0, 1210.0])
      for (final x in [250.0, 560.0, 1440.0, 1750.0]) [x, y],
  ];
  if (rectangular + round == 10) {
    positions.removeRange(8, positions.length);
    positions.addAll([
      [560, 1210],
      [1440, 1210],
    ]);
  }
  for (var i = 0; i < rectangular + round; i++) {
    s.table(
      positions[i][0],
      positions[i][1],
      i < rectangular ? 6 : 8,
      round: i >= rectangular,
    );
  }
  s.decor(1000, 170, 620, 170, '', fill: '#D8DEE9FF');
  s.text(1000, 170, 'Stage');
  s.decor(1000, 820, 470, 700, '', obstacle: false, fill: '#F6EEDCFF');
  s.text(1000, 820, 'Dance floor');
  final counter = sketchSurface(
    [
      [190, 260],
      [190, 135],
      [590, 135],
    ],
    breadth: 64,
    bar: true,
  ).copyWith(label: 'Bar');
  s.add(VenueLayoutDocument(schemaVersion: 2, nodes: [counter]));
  s.decor(1600, 170, 360, 130, '', obstacle: false, fill: '#F1F5F9FF');
  s.text(1600, 170, 'Reception');
  s.line([
    [700, 360],
    [1300, 360],
  ], color: '#CBD5E180');
  return _templateStyle(
    s.finish(width: 2000, height: 1600),
    rectangular == 0
        ? 'lounge'
        : round == 0
        ? 'minimal'
        : 'simple',
  );
}

VenueLayoutDocument _templateStyle(
  VenueLayoutDocument document,
  String family,
) {
  if (family == 'minimal') return withLayoutMinimalStyle(document);
  final colors = family == 'wood'
      ? ['#FFFDF8FF', '#ECE0CCFF', '#C5A574FF', '#735B45FF']
      : family == 'lounge'
      ? ['#F8F8FCFF', '#E4E5F0FF', '#AEB9D0FF', '#59627CFF']
      : family == 'transit'
      ? ['#F6F8FAFF', '#E2E8F0FF', '#92B4C8FF', '#415B70FF']
      : ['#FBFCFDFF', '#E4ECF1FF', '#C5DDDAFF', '#48686AFF'];
  final d = withLayoutMaterialFamily(document, family);
  return d.copyWith(
    canvas: {...d.canvas, 'fill': colors[0]},
    styles: {
      ...d.styles,
      'kinds': {
        ...d.styles['kinds'] as Map? ?? {},
        for (final kind in ['table', 'seat', 'furniture'])
          kind: {
            ...d.styles['kinds']?[kind] as Map? ?? {},
            'fill': kind == 'seat' ? colors[2] : colors[1],
            'stroke': colors[3],
          },
      },
    },
  );
}

VenueLayoutDocument _balcony() {
  final s = _Seed();
  for (var i = 0; i < 8; i++) {
    s.table(260 + (i % 4) * 350, 330 + (i ~/ 4) * 300, 6);
  }
  for (var i = 0; i < 4; i++) {
    s.table(240 + i * 350, 1060, 4);
  }
  s.text(800, 100, 'Ground floor');
  s.text(800, 880, 'Balcony');
  s.decor(1500, 870, 80, 160, 'Stairs');
  s.decor(80, 700, 40, 40, '', shape: 'ellipse');
  s.decor(80, 230, 40, 40, '', shape: 'ellipse');
  final ground = s.nodes.take(56).toList();
  final balcony = s.nodes.skip(56).take(20).toList();
  s.section('Ground floor', ground);
  s.sections.last['outline'] = [
    [100, 170],
    [1470, 170],
    [1470, 780],
    [20, 780],
    [20, 500],
    [100, 500],
  ];
  s.sections.last['levelId'] = 'ground';
  s.section('Balcony', balcony);
  s.sections.last['outline'] = [
    [100, 900],
    [1470, 900],
    [1470, 1220],
    [100, 1220],
  ];
  s.sections.last['levelId'] = 'balcony';
  s.nodes.add(
    shapeFromPoints(
      'polygon',
      [
        [100, 170],
        [1470, 170],
        [1470, 780],
        [20, 780],
        [20, 500],
        [100, 500],
      ],
      properties: {},
      style: {'fill': '#FFFFFF00', 'stroke': '#64748BFF', 'strokeWidth': 3},
    ),
  );
  return s.finish(height: 1300);
}

VenueLayoutDocument _lounge() {
  final s = _Seed();
  for (var i = 0; i < 6; i++) {
    final couch = couchLayout(
      x: 240 + (i % 3) * 500.0,
      y: 270 + (i ~/ 3) * 350.0,
    );
    final root = couch.nodes.firstWhere((n) => n.parentId == null);
    var slot = 0;
    s.nodes.addAll(
      couch.nodes.map(
        (n) => n.id == root.id
            ? n.copyWith(label: 'Couch ${i + 1}')
            : n.copyWith(label: '${i * 2 + ++slot}'),
      ),
    );
    s.units.addAll(
      couch.selectionUnits.map((unit) => {...unit, 'label': 'Couch ${i + 1}'}),
    );
  }
  for (var i = 0; i < 4; i++) {
    s.decor(280 + i * 330, 800, 90, 65, 'Side table');
  }
  s.object(
    'capacityArea',
    800,
    1040,
    1100,
    180,
    'Standing area',
    extra: {'capacity': 20},
    style: {'fill': '#D5EBE2FF'},
  );
  s.text(800, 1035, 'Standing area - 20');
  return s.finish();
}

// Generic arrangements informed by real CineStar and Vinohrady plans; these
// editable examples do not claim the exact inventory of a named auditorium.
VenueLayoutDocument _auditorium() {
  final s = _Seed();
  s.room(1600, 1550);
  s.line(
    [
      for (var i = 0; i <= 16; i++)
        [300 + i * 62.5, 165 + 24 * (1 - ((i - 8) / 8) * ((i - 8) / 8))],
    ],
    weight: 10,
    color: '#66788AFF',
  );
  s.text(800, 115, 'Screen');
  final counts = [12, 14, 14, 16, 16, 18, 18, 18, 18, 18, 18, 18];
  for (var row = 0; row < counts.length; row++) {
    final count = counts[row], y = 330 + row * 74.0 + (row >= 6 ? 120 : 0);
    var fragment = rowLayout(
      rows: 1,
      seatsPerRow: count,
      spacing: 56,
      x: 800 - (count - 1) * 28,
      y: y,
    );
    if (row >= 9) {
      fragment = fragment.copyWith(
        nodes: [
          for (final n in fragment.nodes)
            n.kind == 'seat'
                ? n.copyWith(
                    properties: {...n.properties},
                    style: {...n.style, 'fill': '#9A7780FF'},
                  )
                : n,
        ],
      );
    }
    s.add(fragment);
    s.text(240, y, '${row + 1}', width: 60);
    s.text(1360, y, '${row + 1}', width: 60);
  }
  s.text(800, 790, 'Cross aisle', width: 400);
  for (var i = 0; i < 6; i++) {
    s.line([
      [1410, 430 + i * 48.0],
      [1460, 430 + i * 48.0],
    ], weight: 2);
  }
  s.text(1435, 360, 'Stairs', width: 120);
  s.text(800, 1450, 'Premium seats');
  s.text(150, 1380, 'Exit', width: 120);
  s.text(1450, 1380, 'Exit', width: 120);
  return _templateStyle(s.finish(width: 1600, height: 1550), 'transit');
}

VenueLayoutDocument _theatre() {
  final s = _Seed();
  s.room(1800, 1800);
  s.decor(900, 160, 1000, 160, '', fill: '#E8DFDAFF');
  s.text(900, 160, 'Backstage');
  s.decor(900, 360, 1100, 200, '', fill: '#D6C5B4FF');
  s.text(900, 360, 'Stage');
  s.line(
    [
      for (var i = 0; i <= 16; i++)
        [350 + i * 68.75, 490 + 30 * (1 - ((i - 8) / 8) * ((i - 8) / 8))],
    ],
    weight: 5,
    color: '#9D7680FF',
  );
  s.text(900, 555, 'Orchestra pit');
  final first = s.nodes.length;
  s.add(
    rowLayout(
      rows: 8,
      seatsPerRow: 16,
      blocks: 1,
      spacing: 64,
      rowSpacing: 76,
      arc: -1.3,
      x: 420,
      y: 640 + 1.3 * 7.5 * 7.5,
    ),
  );
  s.section('Stalls', s.nodes.skip(first).toList());
  for (var row = 0; row < 8; row++) {
    s.text(310, 640 + row * 76.0, '${row + 1}', width: 60);
    s.text(1490, 640 + row * 76.0, '${row + 1}', width: 60);
  }
  s.text(170, 560, 'Boxes', width: 180);
  s.text(1630, 560, 'Boxes', width: 180);
  for (final x in [140.0, 1600.0]) {
    for (var box = 0; box < 3; box++) {
      final y = 720 + box * 190.0;
      s.line(
        [
          [x - 35, y - 55],
          [x + 95, y - 55],
          [x + 95, y + 55],
          [x - 35, y + 55],
        ],
        weight: 2,
        color: '#9D7680FF',
      );
      final centerX = x + 30;
      final angle = math.atan2(900 - centerX, y - 360);
      // Rotate the canonical two-seat assembly around its actual midpoint.
      // Keeping the root transform preserves its direction on count edits.
      final boxSeats = rowLayout(
        rows: 1,
        seatsPerRow: 2,
        spacing: 60,
        x: centerX - 30 * math.cos(angle),
        y: y - 30 * math.sin(angle),
      );
      s.add(
        boxSeats.copyWith(
          nodes: [
            for (final node in boxSeats.nodes)
              node.parentId == null
                  ? node.copyWith(rotation: angle * 180 / math.pi)
                  : node,
          ],
        ),
      );
    }
  }
  s.line(
    [
      [200, 1290],
      [1600, 1290],
    ],
    weight: 4,
    color: '#9D7680FF',
  );
  s.text(900, 1340, 'Balcony');
  final start = s.nodes.length;
  s.add(
    rowLayout(
      rows: 4,
      seatsPerRow: 12,
      blocks: 1,
      spacing: 66,
      rowSpacing: 66,
      arc: -1.4,
      x: 537,
      y: 1410 + 1.4 * 5.5 * 5.5,
    ),
  );
  s.section('Balcony', s.nodes.skip(start).toList());
  return _templateStyle(s.finish(width: 1800, height: 1800), 'lounge');
}

VenueLayoutDocument _conference() {
  final s = _Seed();
  s.room(2400, 1800);
  s.decor(650, 180, 900, 190, '', fill: '#D6E2ECFF');
  s.text(650, 180, 'Stage');
  s.add(
    rowLayout(
      rows: 4,
      seatsPerRow: 6,
      blocks: 2,
      spacing: 58,
      rowSpacing: 80,
      aisle: 130,
      x: 260,
      y: 430,
    ),
  );
  s.text(650, 340, 'Conference');
  for (var row = 0; row < 3; row++) {
    for (var col = 0; col < 2; col++) {
      s.table(1550 + col * 490.0, 470 + row * 350.0, 8, round: true);
    }
  }
  s.text(1795, 280, 'Meeting area');
  s.line([
    [1220, 300],
    [1220, 1250],
  ], weight: 3);
  for (var i = 0; i < 2; i++) {
    s.add(
      couchLayout(
        x: 380 + i * 420.0,
        y: 1110,
        count: 3,
        width: 270,
        height: 90,
      ),
    );
  }
  s.text(600, 980, 'Lounge');
  final bar = sketchSurface(
    [
      [160, 1590],
      [160, 1370],
      [1020, 1370],
      [1020, 1590],
    ],
    breadth: 80,
    bar: true,
  ).copyWith(label: 'Bar');
  s.add(VenueLayoutDocument(schemaVersion: 2, nodes: [bar]));
  s.object(
    'capacityArea',
    1750,
    1500,
    650,
    270,
    'Standing area',
    extra: {'capacity': 40},
    style: {'fill': '#E4EFEAFF'},
  );
  s.text(1750, 1500, 'Reception');
  return _templateStyle(s.finish(width: 2400, height: 1800), 'wood');
}

// Transport templates reuse the same assembly factories as palette insertion.
// Decorations and seat attachment metadata therefore have one owner.
VenueLayoutDocument _transportFrame(VenueLayoutDocument document) {
  final b = selectionBounds(document, document.nodes.map((n) => n.id).toSet());
  return document.copyWith(
    nodes: [
      for (final n in document.nodes)
        n.parentId == null
            ? n.copyWith(x: n.x + 64 - b['x']!, y: n.y + 64 - b['y']!)
            : n,
    ],
    canvas: {
      ...document.canvas,
      'x': 0.0,
      'y': 0.0,
      'width': b['width']! + 128,
      'height': b['height']! + 128,
    },
  );
}

VenueLayoutDocument _bus() => _transportFrame(busLayout(x: 0, y: 0));

VenueLayoutDocument _train() {
  final first = compartmentLayout(compartments: 9, x: 0, y: 0);
  final bounds = selectionBounds(first, first.nodes.map((n) => n.id).toSet());
  final second = compartmentLayout(
    compartments: 9,
    x: 0,
    y: bounds['height']! + 100,
  );
  return _transportFrame(
    first.copyWith(
      attachments: [...first.attachments, ...second.attachments],
      nodes: [
        ...first.nodes.map(
          (n) => n.parentId == null ? n.copyWith(label: 'Carriage 1') : n,
        ),
        ...second.nodes.map(
          (n) => n.parentId == null ? n.copyWith(label: 'Carriage 2') : n,
        ),
      ],
    ),
  );
}
