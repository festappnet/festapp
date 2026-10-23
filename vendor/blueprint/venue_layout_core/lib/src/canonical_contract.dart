import 'dart:convert';

/// Versioned declaration metadata shared by the model, JSON Schema and SQL.
/// These are the stored leaves, never a second set of resolved style defaults.
const canonicalDocumentVersion = 2;
const canonicalTextResourceProtocol = 2;
const canonicalLabelFields = <String, Map<String, Object>>{
  'fontFamilyId': {'type': 'string', 'minLength': 1},
  'size': {'type': 'number', 'minimum': 1, 'maximum': 4096},
  'weight': {
    'enum': [400, 700],
  },
  'italic': {'type': 'boolean'},
  'color': {'type': 'string', 'pattern': r'^#[0-9a-fA-F]{8}$'},
  'align': {
    'enum': ['left', 'center', 'right'],
  },
  'lineHeight': {'type': 'number', 'minimum': .8, 'maximum': 3},
  'orientation': {
    'enum': ['screen', 'object'],
  },
  'language': {
    'type': 'string',
    'pattern': r'^([A-Za-z]{2,8})(-[A-Za-z0-9]{1,8})*$',
  },
  'direction': {
    'enum': ['auto', 'ltr', 'rtl'],
  },
};
const canonicalVisualFields = <String, Map<String, Object>>{
  'material': {
    'enum': [
      'round',
      'simple',
      'minimal',
      'wood',
      'lounge',
      'transit',
      'hall',
      'banquet',
    ],
  },
  'seatStyle': {
    'enum': [
      'roundUpholstered',
      'round',
      'plain',
      'wood',
      'upholstered',
      'transit',
      'banquet',
    ],
  },
  'fill': {'type': 'string', 'pattern': r'^#[0-9a-fA-F]{8}$'},
  'stroke': {'type': 'string', 'pattern': r'^#[0-9a-fA-F]{8}$'},
  'strokeWidth': {'type': 'number', 'minimum': 0, 'maximum': 1000000000},
  'cornerRadius': {'type': 'number', 'minimum': 0, 'maximum': 1000000000},
  'opacity': {'type': 'number', 'minimum': 0, 'maximum': 1},
};
const canonicalOriginalSourceFields = <String, Map<String, Object>>{
  'format': {
    'enum': ['svg'],
  },
  'text': {'type': 'string', 'minLength': 1},
  'sha256': {'type': 'string', 'pattern': r'^[a-f0-9]{64}$'},
};
const canonicalSeatingFields = <String, Map<String, Object>>{
  'edgeCounts': {
    'type': 'array',
    'minItems': 4,
    'maxItems': 4,
    'items': {'type': 'integer', 'minimum': 0, 'maximum': 20000},
  },
  'width': {'type': 'number', 'minimum': 1, 'maximum': 1000000},
  'height': {'type': 'number', 'minimum': 1, 'maximum': 1000000},
  'gap': {'type': 'number', 'minimum': 0, 'maximum': 1000000},
  'spacing': {'type': 'number', 'minimum': 0, 'maximum': 1000000},
  'edgePadding': {'type': 'number', 'minimum': 0, 'maximum': 1000000},
};
const canonicalStyleKinds = {
  'table',
  'seat',
  'furniture',
  'shape',
  'capacityArea',
  'text',
  'vector',
  'image',
};
const canonicalGeometryKinds = {'group', ...canonicalStyleKinds};
const canonicalPathArities = {'M': 2, 'L': 2, 'Q': 4, 'C': 6, 'Z': 0};

/// Source-field coverage is explicit so a newly introduced schema-1 field
/// cannot disappear in a conversion just because a normalizer does not know it.
const legacyStyleDestinations = <String, String>{
  'fontId': 'label.fontFamilyId',
  'size': 'label.size',
  'color': 'label.color',
  'align': 'label.align',
  'lineHeight': 'label.lineHeight',
  'labelOrientation': 'label.orientation',
  'bold': 'label.weight',
  'italic': 'label.italic',
  'fontStyle': 'label.italic',
  'fill': 'fill',
  'stroke': 'stroke',
  'strokeWidth': 'strokeWidth',
  'opacity': 'opacity',
  'cornerRadius': 'cornerRadius',
  'objectStyle': 'material',
  'seatStyle': 'seatStyle',
  'dash': 'strokePattern',
  'strokeStyle': 'strokePattern',
};
const legacySeatingDestinations = <String, String>{
  'seatWidth': 'width',
  'seatHeight': 'height',
  'seatGap': 'gap',
  'seatSpacing': 'spacing',
  'seatEdgePadding': 'edgePadding',
};

class CanonicalContractIssue {
  final String reason, path;
  const CanonicalContractIssue(this.reason, this.path);
  Map<String, String> toJson() => {'reason': reason, 'path': path};
  @override
  String toString() => '$path: $reason';
}

/// Count parameters are integral; curvature is signed. These declarations also
/// generate the SQL admission rules and public JSON Schema.
Map<String, Map<String, Object>> canonicalAssemblyParameterFields() => {
  for (final field in canonicalAssemblyFields)
    field: {
      'type':
          {
            'aisle',
            'spacing',
            'rowSpacing',
            'arc',
            'minSeatWidth',
            'minSeatHeight',
          }.contains(field)
          ? 'number'
          : 'integer',
      'minimum': field == 'arc'
          ? -1000000
          : {'minSeatWidth', 'minSeatHeight'}.contains(field)
          ? 1
          : 0,
      'maximum': 1000000,
    },
};

const canonicalAssemblyMaxSeats = 20000;
const canonicalAssemblyMembers = <String, List<String>>{
  'rows': [
    'rows',
    'seatsPerRow',
    'blocks',
    'aisle',
    'spacing',
    'rowSpacing',
    'arc',
  ],
  'bus': ['rows', 'left', 'right', 'rear', 'decks', 'upperRows', 'upperRear'],
  'compartments': ['compartments', 'seats'],
  'couch': ['seats', 'minSeatWidth', 'minSeatHeight'],
};
const canonicalAssemblyNodeKinds = {
  'rows': 'group',
  'bus': 'group',
  'compartments': 'group',
  'couch': 'furniture',
};
Map<String, Map<String, Object>> canonicalAssemblyRules(String kind) {
  final union = canonicalAssemblyParameterFields();
  return {
    for (final field in canonicalAssemblyMembers[kind] ?? const <String>[])
      field: {
        ...union[field]!,
        if (kind == 'rows' &&
                const {'rows', 'seatsPerRow', 'blocks'}.contains(field) ||
            kind == 'compartments' && field == 'compartments' ||
            kind == 'couch' && field == 'seats' ||
            kind == 'bus' && field == 'decks')
          'minimum': 1,
        if (kind == 'rows' && const {'spacing', 'rowSpacing'}.contains(field))
          'exclusiveMinimum': 0,
        if (kind == 'bus' && const {'left', 'right'}.contains(field))
          'maximum': 3,
        if (kind == 'bus' && const {'rear', 'upperRear'}.contains(field))
          'maximum': 6,
        if (kind == 'bus' && field == 'decks') 'maximum': 2,
        if (kind == 'compartments' && field == 'seats') ...{
          'minimum': 2,
          'maximum': 12,
        },
      },
  };
}

List<CanonicalContractIssue> validateCanonicalAssembly(
  Map<String, dynamic> spec,
  String nodeKind,
  String path,
) {
  final kind = spec['kind'], members = canonicalAssemblyMembers[kind];
  if (members == null || canonicalAssemblyNodeKinds[kind] != nodeKind) {
    return [CanonicalContractIssue('invalid_assembly', path)];
  }
  final issues = <CanonicalContractIssue>[
    for (final field in members)
      if (!spec.containsKey(field))
        CanonicalContractIssue('missing_assembly_field', '$path.$field'),
    ...validateCanonicalLeaves(
      {...spec}..remove('kind'),
      canonicalAssemblyRules(kind as String),
      path,
    ),
  ];
  if (issues.isNotEmpty) return issues;
  final seats = switch (kind) {
    'rows' =>
      (spec['rows'] as num) *
          (spec['seatsPerRow'] as num) *
          (spec['blocks'] as num),
    'bus' =>
      (spec['rows'] as num) * ((spec['left'] as num) + (spec['right'] as num)) +
          (spec['rear'] as num) +
          ((spec['decks'] as num) == 2
              ? (spec['upperRows'] as num) *
                        ((spec['left'] as num) + (spec['right'] as num)) +
                    (spec['upperRear'] as num)
              : 0),
    'compartments' => (spec['compartments'] as num) * (spec['seats'] as num),
    _ => spec['seats'] as num,
  };
  if (seats > canonicalAssemblyMaxSeats ||
      kind == 'bus' && (spec['left'] as num) + (spec['right'] as num) == 0) {
    issues.add(CanonicalContractIssue('invalid_assembly_capacity', path));
  }
  return issues;
}

List<CanonicalContractIssue> validateCanonicalLeaves(
  Object? value,
  Map<String, Map<String, Object>> fields,
  String path,
) {
  final issues = <CanonicalContractIssue>[];
  if (value is! Map) {
    return [CanonicalContractIssue('invalid_record', path)];
  }
  for (final entry in value.entries) {
    final rule = fields[entry.key], at = '$path.${entry.key}', v = entry.value;
    if (rule == null) {
      issues.add(CanonicalContractIssue('unknown_field', at));
      continue;
    }
    var valid = v != null;
    if (rule['enum'] case final List allowed) {
      valid = valid && allowed.contains(v);
    }
    switch (rule['type']) {
      case 'number':
        valid =
            valid &&
            v is num &&
            v.isFinite &&
            (rule['minimum'] == null || v >= (rule['minimum'] as num)) &&
            (rule['exclusiveMinimum'] == null ||
                v > (rule['exclusiveMinimum'] as num)) &&
            (rule['maximum'] == null || v <= (rule['maximum'] as num));
      case 'string':
        valid =
            valid &&
            v is String &&
            (rule['minLength'] == null ||
                v.length >= (rule['minLength'] as int)) &&
            (rule['pattern'] == null ||
                RegExp(rule['pattern'] as String).hasMatch(v));
      case 'integer':
        valid =
            valid &&
            v is num &&
            v.isFinite &&
            v == v.truncate() &&
            (rule['minimum'] == null || v >= (rule['minimum'] as num)) &&
            (rule['exclusiveMinimum'] == null ||
                v > (rule['exclusiveMinimum'] as num)) &&
            (rule['maximum'] == null || v <= (rule['maximum'] as num));
      case 'array':
        valid =
            valid &&
            v is List &&
            (rule['minItems'] == null ||
                v.length >= (rule['minItems'] as int)) &&
            (rule['maxItems'] == null || v.length <= (rule['maxItems'] as int));
        if (valid && rule['items'] is Map) {
          final itemRule = Map<String, Object>.from(rule['items'] as Map);
          for (final item in v) {
            if (validateCanonicalLeaves(
              {'value': item},
              {'value': itemRule},
              at,
            ).isNotEmpty) {
              valid = false;
            }
          }
        }
      case 'boolean':
        valid = valid && v is bool;
    }
    if (!valid) issues.add(CanonicalContractIssue('invalid_value', at));
  }
  return issues;
}

List<CanonicalContractIssue> validateCanonicalStyle(
  Object? value,
  String path, {
  required String kind,
}) {
  if (value is! Map) return [CanonicalContractIssue('invalid_style', path)];
  if (kind == 'group' && value.isNotEmpty) {
    return [CanonicalContractIssue('unsupported_group_style', path)];
  }
  final leaves = <String, dynamic>{...value}
    ..remove('label')
    ..remove('strokePattern');
  final issues = validateCanonicalLeaves(leaves, canonicalVisualFields, path);
  if (value.containsKey('label')) {
    if (kind == 'seat' ||
        kind == 'table' ||
        kind == 'furniture' ||
        kind == 'shape' ||
        kind == 'capacityArea' ||
        kind == 'text') {
      issues.addAll(
        validateCanonicalLeaves(
          value['label'],
          canonicalLabelFields,
          '$path.label',
        ),
      );
    } else {
      issues.add(CanonicalContractIssue('unsupported_label', '$path.label'));
    }
  }
  if (kind == 'text' && leaves.keys.any((k) => k != 'opacity')) {
    issues.add(CanonicalContractIssue('unsupported_visual_style', path));
  }
  if ((kind == 'image' || kind == 'vector') &&
      value.keys.any((k) => k != 'opacity')) {
    issues.add(CanonicalContractIssue('unsupported_media_style', path));
  }
  if (value.containsKey('strokePattern')) {
    if (kind == 'text' || kind == 'image' || kind == 'vector') {
      issues.add(
        CanonicalContractIssue(
          'unsupported_stroke_pattern',
          '$path.strokePattern',
        ),
      );
    }
    final pattern = value['strokePattern'];
    var valid =
        pattern is Map &&
        pattern['type'] is String &&
        ['solid', 'dashed', 'dotted', 'custom'].contains(pattern['type']);
    if (valid) {
      final custom = pattern['type'] == 'custom';
      valid = pattern.keys.every(
        (k) => k == 'type' || (custom && k == 'lengths'),
      );
      if (custom) {
        final lengths = pattern['lengths'];
        valid =
            valid &&
            lengths is List &&
            lengths.isNotEmpty &&
            lengths.length <= 32 &&
            lengths.every(
              (v) => v is num && v.isFinite && v > 0 && v <= 1000000000,
            );
      }
    }
    if (!valid) {
      issues.add(
        CanonicalContractIssue('invalid_stroke_pattern', '$path.strokePattern'),
      );
    }
  }
  return issues;
}

/// Stable JSON for cross-runtime descriptor and metadata digests. Strings are
/// never Unicode-normalized; source text and UTF-8 cluster mappings stay intact.
String canonicalContractJson(Object? value) {
  String encode(Object? v) {
    if (v is Map) {
      final keys = v.keys.cast<String>().toList()..sort();
      return '{${keys.map((key) => '${jsonEncode(key)}:${encode(v[key])}').join(',')}}';
    }
    if (v is List) return '[${v.map(encode).join(',')}]';
    if (v is num) {
      if (!v.isFinite) {
        throw const FormatException('non_finite_contract_number');
      }
      if (v == 0) return '0';
      var text = v.toString().toLowerCase();
      if (!text.contains('e')) {
        return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
      }
      final parts = text.split('e'), exponent = int.parse(parts[1]);
      var mantissa = parts[0], sign = '';
      if (mantissa.startsWith('-')) {
        sign = '-';
        mantissa = mantissa.substring(1);
      }
      final decimal = mantissa.indexOf('.'),
          whole = decimal < 0 ? mantissa.length : decimal,
          digits = mantissa.replaceAll('.', '');
      final at = whole + exponent;
      text = at <= 0
          ? '0.${'0' * (-at)}$digits'
          : at >= digits.length
          ? '$digits${'0' * (at - digits.length)}'
          : '${digits.substring(0, at)}.${digits.substring(at)}';
      if (text.contains('.')) {
        while (text.endsWith('0')) {
          text = text.substring(0, text.length - 1);
        }
        if (text.endsWith('.')) text = text.substring(0, text.length - 1);
      }
      return '$sign$text';
    }
    if (v == null || v is String || v is bool) return jsonEncode(v);
    throw const FormatException('non_json_contract_value');
  }

  return encode(value);
}

Map<String, Object?> canonicalStyleSchema({required String kind}) => {
  'type': 'object',
  'additionalProperties': false,
  'properties': {
    if (kind == 'text')
      'opacity': canonicalVisualFields['opacity']!
    else if (kind == 'vector' || kind == 'image')
      'opacity': canonicalVisualFields['opacity']!
    else
      ...canonicalVisualFields,
    if (kind != 'image' && kind != 'vector')
      'label': {
        'type': 'object',
        'additionalProperties': false,
        'properties': canonicalLabelFields,
      },
    if (kind != 'text' && kind != 'image' && kind != 'vector')
      'strokePattern': {
        'oneOf': [
          {
            'type': 'object',
            'additionalProperties': false,
            'required': ['type'],
            'properties': {
              'type': {
                'enum': ['solid', 'dashed', 'dotted'],
              },
            },
          },
          {
            'type': 'object',
            'additionalProperties': false,
            'required': ['type', 'lengths'],
            'properties': {
              'type': {'const': 'custom'},
              'lengths': {
                'type': 'array',
                'minItems': 1,
                'maxItems': 32,
                'items': {
                  'type': 'number',
                  'exclusiveMinimum': 0,
                  'maximum': 1000000000,
                },
              },
            },
          },
        ],
      },
  },
};

/// Generated into the server's JSON import by tool/export_contract.dart.
/// Consumers draw prepared output; only the service imports the actual engine.
const canonicalLayoutTextPolicy = <String, Object>{
  'revision': 1,
  'identityCodec': 'layout-json-decimal-v1',
  'engine': {
    'shaper': 'harfbuzz',
    'package': 'harfbuzzjs@1.6.3',
    'version': '14.6.0',
    'clusterEncoding': 'utf8',
    'clusterLevel': 'monotone-graphemes',
    'featurePolicy': 'opentype-defaults-v1',
  },
  'bidi': 'bidi-js@1.1.0/unicode-13',
  'lineBreak': 'linebreak@1.1.0/unicode-13',
  'graphemes': 'unicode-segmenter@0.17.3/unicode-17',
  'script': 'unicode-properties@2.0.1/unicode-12',
  'scriptAliases': 'unicode-match-property-value-ecmascript@2.2.1',
  'wrap': 'unicode-opportunities-long-token-clip',
  'baseline': 'font-ascent-with-ink-containment',
};

const canonicalLabelDefaults = <String, Object>{
  // Immutable Roboto manifest from the shared registered font catalog.
  'fontFamilyId':
      'font-family:f7b3a0ebd5b869a2c40433fdc5c003472743d3587c9ff15275ee2eaea54a19c5',
  'size': 24,
  'weight': 400,
  'italic': false,
  'color': '#222222FF',
  'lineHeight': 1.2,
  'orientation': 'object',
};
Map<String, Object> canonicalDeclarationMetadata() => {
  'documentVersion': canonicalDocumentVersion,
  'resourceProtocol': canonicalTextResourceProtocol,
  'label': canonicalLabelFields,
  'visual': canonicalVisualFields,
  'seating': canonicalSeatingFields,
  'styleKinds': canonicalStyleKinds.toList(),
  'pathArities': canonicalPathArities,
  'labelDefaults': canonicalLabelDefaults,
  'textPolicy': canonicalLayoutTextPolicy,
  'originalSource': canonicalOriginalSourceFields,
  'originalSourceBytesMax': 2097152,
  'nodeGeometryKeys': canonicalGeometryPropertyKeys.toList(),
  'assemblyFields': canonicalAssemblyFields.toList(),
  'assemblySeatsMax': canonicalAssemblyMaxSeats,
  'assembly': canonicalAssemblyParameterFields(),
  'assemblyKinds': {
    for (final kind in canonicalAssemblyMembers.keys)
      kind: {
        'nodeKind': canonicalAssemblyNodeKinds[kind]!,
        'required': canonicalAssemblyMembers[kind]!,
        'fields': canonicalAssemblyRules(kind),
      },
  },
  'styleSchemas': {
    for (final kind in canonicalStyleKinds)
      kind: canonicalStyleSchema(kind: kind),
  },
};

const canonicalGeometryPropertyKeys = {
  'shape',
  'arrowHeadLength',
  'points',
  'holes',
  'pathPattern',
  'zigzagTeeth',
  'zigzagAmplitude',
  'text',
  'symbol',
  'role',
  'obstacle',
  'slot',
  'deck',
  'capacity',
  'furniture',
  'guestSide',
};
const canonicalAssemblyFields = {
  'minSeatWidth',
  'minSeatHeight',
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
