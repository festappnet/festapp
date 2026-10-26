import 'dart:convert';
import 'dart:math' as math;
import 'package:crypto/crypto.dart';
import 'canonical_contract.dart';
import 'model.dart';
import 'furniture.dart' show couchGeometry;

part 'legacy_document_input.dart';

class LayoutImportResult {
  LayoutImportResult({
    required this.document,
    required Map<String, dynamic> receipt,
  }) : receipt = frozenMap(receipt);
  final VenueLayoutDocument? document;
  final Map<String, dynamic> receipt;
  bool get isReady => document != null;
}

/// Explicit schema-1 input boundary. It never changes source bytes, IDs,
/// transforms or commercial data. Ambiguities use deterministic conservative
/// decisions recorded in the receipt; invalid source data still fails closed.
LayoutImportResult importLegacyLayout(
  Map<String, dynamic> source, {
  required Map<String, Map<String, dynamic>> fontFamilies,
  required int sourceRevision,
  Map<String, Map<String, dynamic>> fontFaces = const {},
}) {
  final original = frozenMap(source),
      issues = <Map<String, dynamic>>[],
      decisions = <Map<String, dynamic>>[];
  void report(String reason, String path, {bool blocked = false}) =>
      (blocked ? issues : decisions).add({
        'reason': reason,
        'path': path,
        'blocked': blocked,
      });
  if (source['schemaVersion'] != 1) throw UnsupportedLayoutSchema(original);
  final legacy = _LegacyLayoutInput.fromJson(source);
  final legacyNodes = {for (final node in legacy.nodes) node.id: node};
  final familyByFace = <String, Map<String, dynamic>>{};
  for (final family in fontFamilies.values) {
    final faces = family['faces'];
    if (faces is! Map) {
      throw const FormatException('invalid_font_family_manifest');
    }
    for (final face in faces.entries) {
      // Prefer the original regular face when multiple families share bytes.
      familyByFace.putIfAbsent(face.value as String, () => family);
    }
  }
  Map<String, dynamic> label(Map raw, String path, {Map? inherited}) {
    final result = <String, dynamic>{};
    for (final e in raw.entries) {
      final destination = legacyStyleDestinations[e.key];
      if (destination != null &&
          destination.startsWith('label.') &&
          !const {'fontId', 'bold', 'italic', 'fontStyle'}.contains(e.key)) {
        result[destination.substring(6)] = e.value;
      }
    }
    final hasTypography = raw.keys.any(
      (k) => legacyStyleDestinations[k]?.startsWith('label.') == true,
    );
    if (!hasTypography) return result;
    final merged = <String, dynamic>{
      ...?inherited,
      ...Map<String, dynamic>.from(raw),
    };
    final oldFace = merged['fontId'];
    var family = oldFace is String ? familyByFace[oldFace] : null;
    if (family == null && fontFaces[oldFace]?['family'] is String) {
      final name = fontFaces[oldFace]!['family'];
      family = fontFamilies.values
          .where((f) => f['family'] == name)
          .firstOrNull;
      if (family != null) {
        result['fontFamilyId'] = family['id'];
        report('historical_face_mapped_to_actual_family', path);
      }
    }
    if (family == null) {
      final available =
          fontFamilies.values
              .where((f) => (f['faces'] as Map).isNotEmpty)
              .toList()
            ..sort((a, b) {
              final c = '${a['family'] ?? a['id']}'.compareTo(
                '${b['family'] ?? b['id']}',
              );
              return c == 0 ? '${a['id']}'.compareTo('${b['id']}') : c;
            });
      family =
          available.where((f) => f['family'] == 'Roboto').firstOrNull ??
          available.firstOrNull;
      if (family == null) {
        report('font_registry_empty', path, blocked: true);
        return result;
      }
      result['fontFamilyId'] = family['id'];
      report('registered_font_selected', path);
    } else if (raw.containsKey('fontId')) {
      result['fontFamilyId'] = family['id'];
    }
    final explicitBold = raw.containsKey('bold'),
        explicitItalic =
            raw.containsKey('italic') || raw.containsKey('fontStyle');
    var weight = merged['bold'] == true ? 700 : 400,
        italic = merged['italic'] == true || merged['fontStyle'] == 'italic';
    final intrinsic =
        (family['faces'] as Map).entries
                .where((e) => e.value == oldFace)
                .firstOrNull
                ?.key
            as String?;
    if (intrinsic != null) {
      final parts = intrinsic.split(':');
      if (!explicitBold && merged['bold'] != true) weight = int.parse(parts[0]);
      if (!explicitItalic && !italic && parts[1] == 'italic') italic = true;
    }
    final desired = '$weight:${italic ? 'italic' : 'normal'}';
    if ((family['faces'] as Map)[desired] == null) {
      final combinations = (family['faces'] as Map).keys
          .cast<String>()
          .where((key) => key.startsWith('400:') || key.startsWith('700:'))
          .toList();
      int cost(String key) {
        final p = key.split(':');
        return (p[1] == (italic ? 'italic' : 'normal') ? 0 : 2) +
            (int.parse(p[0]) == weight ? 0 : 1);
      }

      combinations.sort((a, b) {
        final c = cost(a).compareTo(cost(b));
        return c == 0 ? a.compareTo(b) : c;
      });
      if (combinations.isEmpty) {
        report('font_family_has_no_supported_faces', path, blocked: true);
        return result;
      }
      final chosen = combinations.first.split(':');
      weight = int.parse(chosen[0]);
      italic = chosen[1] == 'italic';
      result['weight'] = weight;
      result['italic'] = italic;
      report('closest_actual_face_selected', path);
    }
    if (explicitBold || raw.containsKey('fontId') && weight != 400) {
      result['weight'] = weight;
    }
    if (explicitItalic || raw.containsKey('fontId') && italic) {
      result['italic'] = italic;
    }
    if (merged['bold'] == true ||
        merged['italic'] == true ||
        merged['fontStyle'] == 'italic') {
      report('faux_typography_replaced', path);
    }

    return result;
  }

  Map<String, dynamic> style(Map raw, String path, {Map? inherited}) {
    final result = <String, dynamic>{};
    for (final e in raw.entries) {
      final destination = legacyStyleDestinations[e.key];
      if (destination != null &&
          !destination.startsWith('label.') &&
          destination != 'strokePattern') {
        result[destination] = e.value;
      }
    }
    final l = label(raw, path, inherited: inherited);
    if (l.isNotEmpty) result['label'] = l;
    if (raw['dash'] case final List dash) {
      result['strokePattern'] = dash.isEmpty
          ? {'type': 'solid'}
          : {'type': 'custom', 'lengths': dash};
    } else if (raw['strokeStyle'] != null) {
      result['strokePattern'] = {'type': raw['strokeStyle']};
    }
    return result;
  }

  final styles = <String, dynamic>{
    'label': label(legacy.defaultTextStyle, 'defaultTextStyle'),
  };
  (styles['label'] as Map).putIfAbsent('orientation', () => 'screen');
  if (!legacy.defaultTextStyle.containsKey('labelOrientation')) {
    report('legacy_label_orientation_materialized', 'styles.label.orientation');
  }
  final kindStyles = <String, dynamic>{};
  for (final e in legacy.appearance.entries) {
    final converted = style(
      e.value as Map,
      'appearance.${e.key}',
      inherited: legacy.defaultTextStyle,
    );
    if (converted.isNotEmpty) kindStyles[e.key] = converted;
  }
  // Historical non-text labels were centered regardless of the text alignment.
  for (final kind in ['table', 'furniture', 'shape', 'capacityArea']) {
    final value = Map<String, dynamic>.from(kindStyles[kind] as Map? ?? {}),
        label = Map<String, dynamic>.from(value['label'] as Map? ?? {});
    label['align'] = 'center';
    value['label'] = label;
    kindStyles[kind] = value;
  }
  if (kindStyles.isNotEmpty) styles['kinds'] = kindStyles;
  final physical = <String, dynamic>{};
  final tableDefaults = legacy.appearance['table'] as Map? ?? {};
  for (final e in legacySeatingDestinations.entries) {
    if (tableDefaults.containsKey(e.key)) {
      physical[e.value] = tableDefaults[e.key];
  }
    }
  final nodes = <LayoutNode>[];
  const assemblyFields = {
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
    'compartments',
    'seats',
  };
  for (final node in legacy.nodes) {
    final raw = node.properties,
        global = legacy.appearance[node.kind] as Map? ?? {},
        mask = (raw['appearanceOverrides'] as List? ?? []).toSet();
    final local = <String, dynamic>{};
    for (final e in raw.entries) {
      if (!legacyStyleDestinations.containsKey(e.key)) continue;
      if (!global.containsKey(e.key) || mask.contains(e.key)) {
        local[e.key] = e.value;
      } else if (e.value != global[e.key])
        report('shadowed_style_removed', 'nodes.${node.id}.${e.key}');
    }
    final ownStyle = node.kind == 'group'
        ? <String, dynamic>{}
        : style(
            local,
            'nodes.${node.id}',
            inherited: {...legacy.defaultTextStyle, ...global},
          );
    if (node.kind == 'text') {
      for (final key
          in ownStyle.keys
              .where((key) => key != 'label' && key != 'opacity')
              .toList()) {
        ownStyle.remove(key);
        report(
          'legacy_unused_text_visual_removed',
          'nodes.${node.id}.style.$key',
        );
      }
    }
    if (node.kind != 'text' &&
        ownStyle['label'] is Map &&
        (ownStyle['label'] as Map).containsKey('align') &&
        ownStyle['label']['align'] != 'center') {
      ownStyle['label'] = {...ownStyle['label'] as Map, 'align': 'center'};
      report(
        'legacy_effective_label_alignment_materialized',
        'nodes.${node.id}.style.label.align',
      );
    }
    final props = <String, dynamic>{...raw}
      ..removeWhere(
        (k, v) =>
            legacyStyleDestinations.containsKey(k) ||
            legacySeatingDestinations.containsKey(k) ||
            const {
              'appearanceOverrides',
              'manual',
              'manualRotation',
              'assembly',
            }.contains(k),
      );
    final seating = <String, dynamic>{};
    Map<String, dynamic>? surface, assembly;
    if (node.kind == 'table') {
      for (final e in legacySeatingDestinations.entries) {
        if (raw.containsKey(e.key)) seating[e.value] = raw[e.key];
      }
      final children = legacy.nodes
          .where((n) => n.parentId == node.id && n.kind == 'seat')
          .toList();
      if (children.isNotEmpty) {
        if (!seating.containsKey('width')) {
          final sizes = children.map((n) => n.width).toSet();
          if (sizes.length == 1) {
            seating['width'] = sizes.single;
          } else {
            seating['width'] = sizes.reduce((a, b) => a > b ? a : b);
            report('seating_width_selected', 'nodes.${node.id}');
          }
        }
        if (!seating.containsKey('height')) {
          final sizes = children.map((n) => n.height).toSet();
          if (sizes.length == 1) {
            seating['height'] = sizes.single;
          } else {
            seating['height'] = sizes.reduce((a, b) => a > b ? a : b);
            report('seating_height_selected', 'nodes.${node.id}');
          }
        }
        if (!seating.containsKey('gap')) {
          final gaps = legacy.attachments
              .where((a) => a['targetId'] == node.id && a['gap'] is num)
              .map((a) => a['gap'])
              .toSet();
          if (gaps.length == 1) {
            seating['gap'] = gaps.single;
          } else if (gaps.length > 1) {
            seating['gap'] = gaps.cast<num>().reduce((a, b) => a > b ? a : b);
            report('seating_gap_selected', 'nodes.${node.id}');
          }
        }
      }
      final shape = raw['shape'] ?? 'rect';
      if (const {'rect', 'rectangle', 'roundedRect'}.contains(shape)) {
        surface = {'type': 'rect'};
      } else if (const {'circle', 'round', 'ellipse', 'oval'}.contains(shape)) {
        if ((node.width - node.height).abs() > 1 / 1024) {
          surface = {'type': 'rect'};
          report('non_circular_table_normalized_to_rect', 'nodes.${node.id}');
        } else {
          surface = {'type': 'circle'};
        }
      } else if (shape == 'polygon') {
        final module = raw['furniture'] == 'bar' ? 60.0 : 100.0;
        List<List<int>>? ring(List rawRing) {
          final points = <List<int>>[];
          for (final p in rawRing) {
            final x = ((p[0] as num) + node.width / 2) / module,
                y = ((p[1] as num) + node.height / 2) / module;
            if ((x - x.round()).abs() > 1e-8 || (y - y.round()).abs() > 1e-8) {
              return null;
            }
            points.add([x.round(), y.round()]);
          }
          return points;
        }

        var actualModule = module;
        var outer = ring(raw['points'] as List),
            holes = [
              for (final h in raw['holes'] as List? ?? []) ring(h as List),
            ];
        if (outer == null || holes.any((h) => h == null)) {
          var divisor = 0;
          int gcd(int a, int b) {
            while (b != 0) {
              final r = a % b;
              a = b;
              b = r;
            }
            return a.abs();
          }

          for (final contour in [raw['points'], ...?raw['holes'] as List?])
            for (final point in contour as List) {
              divisor = gcd(
                divisor,
                (((point[0] as num) + node.width / 2) * 1024).round(),
              );
              divisor = gcd(
                divisor,
                (((point[1] as num) + node.height / 2) * 1024).round(),
              );
            }
          divisor = gcd(divisor, (node.width * 1024).round());
          divisor = gcd(divisor, (node.height * 1024).round());
          if (divisor > 0) {
            actualModule = divisor / 1024;
            List<List<int>> rationalRing(List contour) => [
              for (final p in contour)
                [
                  (((p[0] as num) + node.width / 2) / actualModule).round(),
                  (((p[1] as num) + node.height / 2) / actualModule).round(),
                ],
            ];
            if (node.width / actualModule * node.height / actualModule <=
                16384) {
              outer = rationalRing(raw['points'] as List);
              holes = [
                for (final h in raw['holes'] as List? ?? [])
                  rationalRing(h as List),
              ];
              report('exact_grid_module_selected', 'nodes.${node.id}');
            }
          }
        }
        if (outer == null || holes.any((h) => h == null)) {
          surface = {'type': 'rect'};
          report('legacy_surface_normalized_to_rect', 'nodes.${node.id}');
        } else {
          if (polygonRingArea([
                for (final p in outer) [p[0].toDouble(), p[1].toDouble()],
              ]) <
              0) {
            outer.setAll(0, outer.reversed.toList());
          }
          for (final h in holes) {
            if (polygonRingArea([
                  for (final p in h!) [p[0].toDouble(), p[1].toDouble()],
                ]) >
                0) {
              h.setAll(0, h.reversed.toList());
            }
          }
          surface = {
            'type': 'grid',
            'moduleSize': actualModule,
            'outer': outer,
            'holes': holes,
          };
          var orthogonal = true;
          for (var i = 0; i < outer.length; i++) {
            final a = outer[i], b = outer[(i + 1) % outer.length];
            if ((a[0] == b[0]) == (a[1] == b[1])) orthogonal = false;
          }
          if (!orthogonal) {
            surface = {'type': 'rect'};
            report('legacy_surface_normalized_to_rect', 'nodes.${node.id}');
          }
        }
      } else {
        surface = {'type': 'rect'};
        report('legacy_surface_normalized_to_rect', 'nodes.${node.id}');
      }
      props.remove('shape');
      props.remove('points');
      props.remove('holes');
    }
    if (raw['assembly'] is String) {
      final kind = switch (raw['assembly']) {
        'row' || 'arc' => 'rows',
        final value => value,
      };
      if (const {'rows', 'bus', 'compartments', 'couch'}.contains(kind)) {
        assembly = {
          'kind': kind,
          for (final key in assemblyFields)
            if (raw.containsKey(key)) key: raw[key],
        };
      } else {
        report('materialized_assembly_preserved', 'nodes.${node.id}');
      }
      props.removeWhere((k, v) => assemblyFields.contains(k));
    }
    final effectiveRotation = _legacyTableSeatFacingRotation(
      node,
      legacyNodes[node.parentId],
    );
    if (quantize(effectiveRotation) != quantize(node.rotation)) {
      report(
        'legacy_effective_rotation_materialized',
        'nodes.${node.id}.transform.rotation',
      );
    }
    nodes.add(
      node.copyWith(
        rotation: effectiveRotation,
        properties: props,
        style: ownStyle,
        seating: seating,
        surface: surface,
        assembly: assembly,
      ),
    );
  }
  final attachments = <Map<String, dynamic>>[];
  for (final a in legacy.attachments) {
    final seat = legacy.nodes.firstWhere((n) => n.id == a['seatId']);
    final manual = seat.properties['manual'] == true || a['manual'] == true;
    if (manual) {
      report('free_placement_preserved', 'attachments.${a['seatId']}');
    }
    attachments.add({
      if (a['id'] != null) 'id': a['id'],
      'seatId': a['seatId'],
      'targetId': a['targetId'],
      'rotationMode': seat.properties['manualRotation'] == true
          ? 'manual'
          : 'auto',
      'placement': manual ? {'mode': 'free'} : {'mode': 'automatic'},
    });
  }
  for (final g in legacy.generators) {
    final rootId = g['rootId'] ?? g['assemblyId'] ?? g['nodeId'];
    if (rootId == null) {
      report('materialized_generator_preserved', 'generators');
      continue;
    }
    final index = nodes.indexWhere((n) => n.id == rootId);
    if (index < 0) {
      report('orphan_generator_ignored', 'generators');
      continue;
    }
    final kind = switch (g['kind']) {
      'row' || 'arc' => 'rows',
      final value => value,
    };
    if (!const {'rows', 'bus', 'compartments', 'couch'}.contains(kind)) {
      report('materialized_generator_preserved', 'generators.$rootId');
      continue;
    }
    final parameters = <String, dynamic>{
      ...Map<String, dynamic>.from(g['parameters'] as Map? ?? {}),
      ...g,
    };
    final spec = {
      'kind': kind,
      for (final key in assemblyFields)
        if (parameters.containsKey(key)) key: parameters[key],
    };
    if (nodes[index].assembly != null &&
        !sameLayoutValue(nodes[index].assembly, spec)) {
      report('materialized_assembly_spec_selected', 'generators.$rootId');
    } else {
      nodes[index] = nodes[index].copyWith(assembly: spec);
    }
  }
  // Infer missing legacy parameters once at this explicit input boundary.
  // Canonical commands subsequently read only the stored root specification.
  for (var index = 0; index < nodes.length; index++) {
    final root = nodes[index];
    if (root.assembly?['kind'] == 'rows') {
      final old = legacyNodes[root.id]!;
      final input = legacy.copyWith(
        nodes: [
          for (final node in legacy.nodes)
            node.id == root.id
                ? old.copyWith(
                    properties: {
                      ...old.properties,
                      ...({...root.assembly!}..remove('kind')),
                      'assembly': 'rows',
                    },
                  )
                : node,
        ],
      );
      final parameters = _legacyRowParameters(input, root.id);
      final complete = {'kind': 'rows', ...parameters};
      if (!sameLayoutValue(root.assembly, complete)) {
        report(
          'legacy_row_parameters_materialized',
          'nodes.${root.id}.assembly',
        );
      }
      nodes[index] = root.copyWith(assembly: complete);
    } else if (const {'bus', 'compartments'}.contains(root.assembly?['kind'])) {
      final kind = root.assembly!['kind'] as String,
          old = legacyNodes[root.id]!;
      final input = legacy.copyWith(
        nodes: [
          for (final node in legacy.nodes)
            node.id == root.id
                ? old.copyWith(
                    properties: {
                      ...old.properties,
                      ...({...root.assembly!}..remove('kind')),
                      'assembly': kind,
                    },
                  )
                : node,
        ],
      );
      try {
        final parameters = kind == 'bus'
            ? _legacyBusParameters(input, root.id)
            : _legacyCompartmentParameters(input, root.id);
        nodes[index] = root.copyWith(assembly: {'kind': kind, ...parameters});
        report(
          'legacy_transport_parameters_materialized',
          'nodes.${root.id}.assembly',
        );
      } on Object {
        nodes[index] = root.copyWith(clearAssembly: true);
        report(
          'unreconstructable_assembly_kept_materialized_group',
          'nodes.${root.id}.assembly',
        );
      }
    } else if (root.kind == 'furniture' &&
        root.properties['furniture'] == 'couch') {
      final seats = nodes
              .where((node) => node.parentId == root.id && node.kind == 'seat')
              .toList(),
          old = legacyNodes[root.id]!;
      if (seats.isEmpty) {
        nodes[index] = root.copyWith(clearAssembly: true);
        report(
          'empty_couch_kept_as_materialized_furniture',
          'nodes.${root.id}.assembly',
        );
        continue;
      }
      nodes[index] = root.copyWith(
        assembly: {
          'kind': 'couch',
          'seats': seats.length,
          'minSeatWidth':
              old.properties['seatWidth'] ??
              (seats.isEmpty
                  ? couchGeometry['minSeatWidth']!
                  : seats.map((node) => node.width).reduce(math.min)),
          'minSeatHeight':
              old.properties['seatHeight'] ??
              (seats.isEmpty
                  ? couchGeometry['minSeatHeight']!
                  : seats.map((node) => node.height).reduce(math.min)),
        },
      );
      report(
        'legacy_couch_footprint_materialized',
        'nodes.${root.id}.assembly',
      );
    }
  }
  for (var index = 0; index < nodes.length; index++) {
    final root = nodes[index];
    if (!const {'rows', 'bus', 'compartments'}.contains(root.assembly?['kind'])) {
      continue;
    }
    final seats = nodes
        .where((node) => node.parentId == root.id && node.kind == 'seat')
        .toList();
    nodes[index] = root.copyWith(
      seating: {
        ...physical,
        if (seats.isNotEmpty)
          'width': seats.map((seat) => seat.width).reduce(math.max),
        if (seats.isNotEmpty)
          'height': seats.map((seat) => seat.height).reduce(math.max),
      },
    );
    report(
      'legacy_assembly_physical_profile_materialized',
      'nodes.${root.id}.seating',
    );
  }
  final convertedNodes = {for (final node in nodes) node.id: node},
      attachedSeats = attachments
          .map((attachment) => attachment['seatId'])
          .toSet();
  for (final seat in nodes.where((node) => node.kind == 'seat')) {
    final parent = convertedNodes[seat.parentId];
    if (parent == null ||
        (parent.kind != 'table' && parent.assembly == null) ||
        attachedSeats.contains(seat.id)) {
      continue;
    }
    final old = legacyNodes[seat.id]!;
    var free = old.properties['manual'] == true,
        manualRotation =
            old.properties['manualRotation'] == true ||
            (free && parent.kind != 'table');
    if (parent.assembly?['kind'] == 'rows') {
      final spec = parent.assembly!,
          parts = '${seat.properties['slot']}'
              .split(':')
              .map(int.tryParse)
              .toList();
      if (parts.length != 3 ||
          parts.any((value) => value == null || value < 0) ||
          parts[0]! >= (spec['rows'] as num) ||
          parts[1]! >= (spec['blocks'] as num) ||
          parts[2]! >= (spec['seatsPerRow'] as num)) {
        free = true;
        manualRotation = true;
        report('legacy_row_slot_kept_free', 'nodes.${seat.id}');
      } else {
        final spacing = (spec['spacing'] as num).toDouble(),
            half = ((spec['seatsPerRow'] as num) - 1) / 2,
            arc = (spec['arc'] as num).toDouble();
        final x =
            parts[1]! *
                ((spec['seatsPerRow'] as num) * spacing +
                    (spec['aisle'] as num)) +
            parts[2]! * spacing;
        final y =
            parts[0]! * (spec['rowSpacing'] as num) +
            arc * math.pow(parts[2]! - half, 2);
        if ((seat.x - x).abs() > 1 / 1024 || (seat.y - y).abs() > 1 / 1024) {
          free = true;
        }
        final rotation =
            math.atan(2 * arc * (parts[2]! - half) / spacing) * 180 / math.pi;
        if ((seat.rotation - rotation).abs() > 1 / 1024) manualRotation = true;
      }
    }
    if (free) {
      report('materialized_assembly_exception_preserved', 'nodes.${seat.id}');
    }
    attachments.add({
      'seatId': seat.id,
      'targetId': parent.id,
      'rotationMode': manualRotation ? 'manual' : 'auto',
      'placement': {'mode': free ? 'free' : 'automatic'},
    });
  }
  final presets = <Map<String, dynamic>>[];
  for (final p in legacy.presets) {
    final nested = importLegacyLayout(
      Map<String, dynamic>.from(p['document'] as Map),
      fontFamilies: fontFamilies,
      fontFaces: fontFaces,
      sourceRevision: sourceRevision,
    );
    for (final i in nested.receipt['decisions'] as List) {
      decisions.add({
        ...i as Map<String, dynamic>,
        'path': 'presets.${p['id']}.${i['path']}',
      });
    }
    for (final i in nested.receipt['issues'] as List) {
      issues.add({
        ...i as Map<String, dynamic>,
        'path': 'presets.${p['id']}.${i['path']}',
      });
    }
    if (nested.document != null) {
      presets.add({...p, 'document': nested.document!.toJson()});
    }
  }
  VenueLayoutDocument? candidate;
  if (!issues.any((i) => i['blocked'] == true)) {
    candidate = VenueLayoutDocument(
      schemaVersion: 2,
      nodes: nodes,
      canvas: legacy.canvas,
      styles: styles,
      seatingDefaults: physical,
      textPolicy: const {'language': 'und', 'direction': 'auto'},
      sections: legacy.sections,
      selectionUnits: [
        for (final unit in legacy.selectionUnits)
          {...unit, 'kind': unit['kind'] ?? 'atomic'},
      ],
      attachments: attachments,
      presets: presets,
      background: legacy.background,
    );
    final invalid = validateDocument(candidate);
    for (final i in invalid) {
      report(i.reason, i.path, blocked: true);
    }
    if (invalid.isNotEmpty) candidate = null;
  }
  final target = candidate?.toJson();
  return LayoutImportResult(
    document: candidate,
    receipt: {
      'sourceSchema': 1,
      'targetSchema': 2,
      'sourceRevision': sourceRevision,
      'sourceHash': sha256
          .convert(utf8.encode(canonicalContractJson(original)))
          .toString(),
      'source': original,
      'targetHash': target == null
          ? null
          : sha256
                .convert(utf8.encode(canonicalContractJson(target)))
                .toString(),
      'issues': issues,
      'decisions': decisions,
      'resolutionPolicy':
          'preserve-identities-current-products-and-materialized-positions-v1',
      'status': candidate == null ? 'blocked' : 'ready',
    },
  );
}

/// Conversion is automatic but remains guarded against a stale revision or
/// source bytes. Consumers must pass the current source at the commit boundary.
VenueLayoutDocument acceptLegacyLayoutImport(
  LayoutImportResult prepared,
  Map<String, dynamic> currentSource, {
  required int currentRevision,
}) {
  final receipt = prepared.receipt, document = prepared.document;
  final currentHash = sha256
      .convert(utf8.encode(canonicalContractJson(currentSource)))
      .toString();
  if (document == null || receipt['status'] != 'ready') {
    throw StateError('layout_import_not_ready');
  }
  if (receipt['sourceRevision'] != currentRevision ||
      receipt['sourceHash'] != currentHash) {
    throw StateError('layout_import_source_changed');
  }
  if (receipt['targetHash'] !=
          sha256
              .convert(utf8.encode(canonicalContractJson(document.toJson())))
              .toString() ||
      validateDocument(document).isNotEmpty) {
    throw StateError('layout_import_target_changed');
  }
  return document;
}
