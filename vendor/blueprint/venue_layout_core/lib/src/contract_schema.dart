import 'canonical_contract.dart';
import 'model.dart' show layoutLimits, layoutMaxSeats;

/// Structural machine-readable contract. Identity references, grid topology,
/// resource readiness and authoring-source hashes are checked by the core.
Map<String, dynamic> canonicalDocumentSchema() {
  Map<String, dynamic> object(
    Map<String, dynamic> fields, [
    List<String> required = const [],
  ]) => {
    'type': 'object',
    'additionalProperties': false,
    'properties': fields,
    if (required.isNotEmpty) 'required': required,
  };
  Map<String, dynamic> array(Object items, {int? min, int? max}) => {
    'type': 'array',
    'items': items,
    if (min != null) 'minItems': min,
    if (max != null) 'maxItems': max,
  };
  Map<String, dynamic> number({num? min, num? max, bool integer = false}) => {
    'type': integer ? 'integer' : 'number',
    if (min != null) 'minimum': min,
    if (max != null) 'maximum': max,
  };
  Map<String, dynamic> ref(String name) => {r'$ref': '#/' + r'$defs/' + name};
  const string = {'type': 'string'}, boolean = {'type': 'boolean'};
  final coordinate = number(min: -1000000000, max: 1000000000),
      positive = number(min: 1 / 1024, max: 1000000000),
      count = number(min: 0, max: layoutMaxSeats, integer: true);
  final id = {
        'type': 'string',
        'pattern':
            r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
      },
      color = {'type': 'string', 'pattern': r'^#[0-9a-fA-F]{8}$'};
  Map<String, dynamic> pair(Object value) => {
    'type': 'array',
    'prefixItems': [value, value],
    'items': false,
    'minItems': 2,
    'maxItems': 2,
  };
  final ring = array(
    pair(number(min: -16384, max: 16384, integer: true)),
    min: 4,
    max: 512,
  );
  final path = array({
    'oneOf': [
      for (final entry in canonicalPathArities.entries)
        {
          'type': 'array',
          'prefixItems': [
            {'const': entry.key},
            for (var i = 0; i < entry.value; i++) coordinate,
          ],
          'items': false,
          'minItems': entry.value + 1,
          'maxItems': entry.value + 1,
        },
    ],
  }, max: 200000);
  final gradientCommon = {
    'colors': array(color, min: 2, max: 1024),
    'stops': array(number(min: 0, max: 1), min: 2, max: 1024),
    'spread': {
      'enum': ['pad', 'repeat', 'reflect'],
    },
  };
  final gradient = {
    'oneOf': [
      object(
        {
          ...gradientCommon,
          'type': {'const': 'linear'},
          'from': pair(coordinate),
          'to': pair(coordinate),
        },
        ['type', 'colors', 'stops', 'spread', 'from', 'to'],
      ),
      object(
        {
          ...gradientCommon,
          'type': {'const': 'radial'},
          'center': pair(coordinate),
          'focal': pair(coordinate),
          'radius': positive,
          'matrix': {
            'type': 'array',
            'items': coordinate,
            'minItems': 6,
            'maxItems': 6,
          },
        },
        ['type', 'colors', 'stops', 'spread', 'center', 'radius', 'matrix'],
      ),
    ],
  };
  final pathPaint = {
    'op': {'const': 'path'},
    'path': path,
    'fillRule': {
      'enum': ['nonzero', 'evenodd'],
    },
    'fill': color,
    'stroke': color,
    'strokeWidth': number(min: 0, max: 1000000000),
    'strokeCap': {
      'enum': ['butt', 'round', 'square'],
    },
    'strokeJoin': {
      'enum': ['miter', 'round', 'bevel'],
    },
    'miterLimit': number(min: 1, max: 1000000),
    'fillGradient': gradient,
    'strokeGradient': gradient,
  };
  final vector = object(
    {
      'type': {'const': 'vector'},
      'version': {'const': 1},
      'width': number(min: 1 / 1024, max: 1000000),
      'height': number(min: 1 / 1024, max: 1000000),
      'commands': array({
        'oneOf': [
          object(pathPaint, [
            'op',
            'path',
            'fillRule',
            'strokeWidth',
            'strokeCap',
            'strokeJoin',
            'miterLimit',
          ]),
          object(
            {
              'op': {'const': 'clip'},
              'path': path,
              'fillRule': {
                'enum': ['nonzero', 'evenodd'],
              },
            },
            ['op', 'path', 'fillRule'],
          ),
          object(
            {
              'op': {'const': 'layer'},
              'opacity': number(min: 0, max: 1),
            },
            ['op', 'opacity'],
          ),
          object(
            {
              'op': {'const': 'restore'},
            },
            ['op'],
          ),
        ],
      }, max: 10000),
    },
    ['type', 'version', 'width', 'height', 'commands'],
  );
  final crop = object(
    {
      'x': number(min: 0, max: 1),
      'y': number(min: 0, max: 1),
      'width': {'type': 'number', 'exclusiveMinimum': 0, 'maximum': 1},
      'height': {'type': 'number', 'exclusiveMinimum': 0, 'maximum': 1},
    },
    ['x', 'y', 'width', 'height'],
  );
  final bitmap = object(
    {
      'type': {'const': 'bitmap'},
      'assetRef': {'type': 'string', 'minLength': 1},
      'hash': canonicalOriginalSourceFields['sha256']!,
      'crop': crop,
    },
    ['type', 'assetRef', 'hash', 'crop'],
  );
  final surface = {
    'oneOf': [
      object(
        {
          'type': {
            'enum': ['rect', 'circle'],
          },
        },
        ['type'],
      ),
      object(
        {
          'type': {'const': 'grid'},
          'moduleSize': number(min: 1 / 1024, max: 1000000),
          'outer': ring,
          'holes': array(ring, max: 128),
        },
        ['type', 'moduleSize', 'outer', 'holes'],
      ),
    ],
  };
  final assembly = {
    'oneOf': [
      for (final kind in canonicalAssemblyMembers.keys)
        object(
          {
            'kind': {'const': kind},
            ...canonicalAssemblyRules(kind),
          },
          ['kind', ...canonicalAssemblyMembers[kind]!],
        ),
    ],
  };
  final geometry = <String, dynamic>{
    'shape': {
      'enum': [
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
      ],
    },
    'arrowHeadLength': positive,
    'points': array(pair(coordinate), min: 2, max: 512),
    'holes': array(array(pair(coordinate), min: 3, max: 512), max: 128),
    'pathPattern': {'const': 'zigzag'},
    'zigzagTeeth': count,
    'zigzagAmplitude': positive,
    'text': string,
    'symbol': {
      'enum': ['chair', 'bench', 'sofa', 'wheelchair', 'driver'],
    },
    'role': string,
    'obstacle': boolean,
    'slot': {
      'oneOf': [
        number(min: 0, integer: true),
        {'type': 'string', 'minLength': 1},
      ],
    },
    'deck': number(min: 0, max: 1, integer: true),
    'capacity': number(min: 0, max: 2147483647, integer: true),
    'furniture': string,
    'guestSide': {
      'enum': ['top', 'right', 'bottom', 'left'],
    },
  };
  assert(geometry.keys.toSet().containsAll(canonicalGeometryPropertyKeys));
  final node = object(
    {
      'id': id,
      'kind': {'enum': canonicalGeometryKinds.toList()},
      'parentId': id,
      'transform': object(
        {'x': coordinate, 'y': coordinate, 'rotation': coordinate},
        ['x', 'y', 'rotation'],
      ),
      'width': positive,
      'height': positive,
      'z': number(integer: true),
      'locked': boolean,
      'label': string,
      ...geometry,
      'style': {'type': 'object'},
      'surface': surface,
      'seating': object(canonicalSeatingFields),
      'childStyles': object({'seat': canonicalStyleSchema(kind: 'seat')}),
      'assembly': assembly,
      'graphic': {
        'oneOf': [vector, bitmap],
      },
      'originalSource': object(canonicalOriginalSourceFields, [
        'format',
        'text',
        'sha256',
      ]),
    },
    ['id', 'kind', 'transform', 'width', 'height'],
  );
  node['allOf'] = [
    for (final kind in canonicalGeometryKinds)
      {
        'if': {
          'properties': {
            'kind': {'const': kind},
          },
          'required': ['kind'],
        },
        'then': {
          'properties': {
            'style': kind == 'group'
                ? object({})
                : canonicalStyleSchema(kind: kind),
            if (kind == 'table') ...{
              'shape': false,
              'points': false,
              'holes': false,
            } else ...{
              'surface': false,
              'seating': const {'group', 'furniture'}.contains(kind)
                  ? object(canonicalSeatingFields)
                  : false,
              'childStyles': false,
            },
            if (kind == 'vector')
              'graphic': vector
            else if (kind == 'image')
              'graphic': bitmap
            else
              'graphic': false,
            if (kind != 'vector') 'originalSource': false,
          },
          if (kind == 'table') 'required': ['surface'],
          if (kind == 'text') 'required': ['text'],
          if (kind == 'vector' || kind == 'image') 'required': ['graphic'],
        },
      },
    {
      'if': {
        'properties': {
          'kind': {
            'enum': ['group', 'furniture'],
          },
        },
        'required': ['seating'],
      },
      'then': {
        'required': ['assembly'],
      },
    },
    for (final kind in canonicalAssemblyMembers.keys)
      {
        'if': {
          'properties': {
            'assembly': {
              'properties': {
                'kind': {'const': kind},
              },
              'required': ['kind'],
            },
          },
          'required': ['assembly'],
        },
        'then': {
          'properties': {
            'kind': {'const': canonicalAssemblyNodeKinds[kind]},
          },
        },
      },
  ];
  final label = object(canonicalLabelFields),
      styles = object({
        'label': label,
        'kinds': object({
          for (final kind in canonicalStyleKinds)
            kind: canonicalStyleSchema(kind: kind),
        }),
      });
  final document = object(
    {
      'schemaVersion': {'const': canonicalDocumentVersion},
      'symbolSetVersion': {'const': 1},
      'canvas': object(
        {
          'x': coordinate,
          'y': coordinate,
          'width': number(
            min: layoutLimits['canvasMin'],
            max: layoutLimits['canvasMax'],
          ),
          'height': number(
            min: layoutLimits['canvasMin'],
            max: layoutLimits['canvasMax'],
          ),
          'fill': color,
          'floorStyle': {
            'enum': ['plain', 'wood', 'tile', 'carpet'],
          },
        },
        ['x', 'y', 'width', 'height', 'fill'],
      ),
      'styles': styles,
      'seatingDefaults': object(canonicalSeatingFields),
      'textPolicy': object(
        {
          for (final key in ['language', 'direction'])
            key: canonicalLabelFields[key]!,
        },
        ['language', 'direction'],
      ),
      'nodes': array(ref('node'), max: layoutLimits['maxNodes']!.toInt()),
      'sections': array(
        object(
          {
            'id': id,
            'title': {'type': 'string', 'minLength': 1},
            'rootId': id,
            'levelId': string,
            'outline': array(pair(coordinate), min: 3, max: 512),
            'order': number(integer: true),
          },
          ['id', 'title', 'rootId'],
        ),
      ),
      'selectionUnits': array(
        object(
          {
            'id': id,
            'kind': {'const': 'atomic'},
            'nodeIds': array(id, min: 1, max: layoutMaxSeats),
            'label': string,
          },
          ['id', 'nodeIds'],
        ),
      ),
      'attachments': array(
        object(
          {
            'id': id,
            'seatId': id,
            'targetId': id,
            'rotationMode': {
              'enum': ['auto', 'manual'],
            },
            'placement': {
              'oneOf': [
                object(
                  {
                    'mode': {
                      'enum': ['automatic', 'free'],
                    },
                  },
                  ['mode'],
                ),
                object(
                  {
                    'mode': {'const': 'sidePinned'},
                    'side': {
                      'enum': ['top', 'right', 'bottom', 'left', 'perimeter'],
                    },
                    't': number(min: 0, max: 1),
                  },
                  ['mode', 'side', 't'],
                ),
                object(
                  {
                    'mode': {'const': 'sidePinned'},
                    'cell': pair(number(min: 0, max: 16384, integer: true)),
                    'face': {
                      'enum': ['top', 'right', 'bottom', 'left'],
                    },
                  },
                  ['mode', 'cell', 'face'],
                ),
              ],
            },
          },
          ['seatId', 'targetId', 'rotationMode', 'placement'],
        ),
      ),
      'background': {
        'oneOf': [
          {'type': 'null'},
          object(
            {
              'assetRef': {'type': 'string', 'minLength': 1},
              'hash': canonicalOriginalSourceFields['sha256']!,
              'x': coordinate,
              'y': coordinate,
              'width': positive,
              'height': positive,
              'scale': positive,
              'rotation': coordinate,
              'opacity': number(min: 0, max: 1),
              'crop': crop,
            },
            [
              'assetRef',
              'hash',
              'x',
              'y',
              'width',
              'height',
              'scale',
              'rotation',
              'opacity',
              'crop',
            ],
          ),
        ],
      },
      'presets': array(
        object(
          {
            'id': id,
            'title': {'type': 'string', 'minLength': 1},
            'version': {'const': 1},
            'description': string,
            'document': {r'$ref': '#'},
          },
          ['id', 'title', 'document'],
        ),
        max: layoutLimits['presetsMax']!.toInt(),
      ),
    },
    [
      'schemaVersion',
      'symbolSetVersion',
      'canvas',
      'nodes',
      'styles',
      'seatingDefaults',
      'textPolicy',
    ],
  );
  return {
    r'$schema': 'https://json-schema.org/draft/2020-12/schema',
    r'$id': 'https://festapp.net/contracts/venue-layout-2.schema.json',
    r'$comment':
        'Generated from core declarations. Core validation additionally checks references, topology, limits across nested records and prepared resources.',
    ...document,
    r'$defs': {'node': node},
  };
}
