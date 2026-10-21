import 'model.dart';
export 'minimal_appearance.dart';

/// One material definition shared by templates, previews and authoring UI.
const layoutMaterialFamilies = <String, Map<String, dynamic>>{
  'minimal': {
    'construction': 'simple',
    'seatStyle': 'plain',
    'floorStyle': 'plain',
    'radius': 3.0,
    'seatRadius': 8.0,
    'strokeWidth': 1.0,
    'seatStrokeWidth': 0.0,
  },
  'round': {
    'construction': 'simple',
    'seatStyle': 'round',
    'floorStyle': 'plain',
    'radius': 6.0,
    'strokeWidth': 1.0,
    'seatStrokeWidth': 1.0,
  },
  'simple': {
    'seatStyle': 'plain',
    'floorStyle': 'tile',
    'radius': 6.0,
    'strokeWidth': 1.0,
  },
  'wood': {
    'seatStyle': 'wood',
    'floorStyle': 'wood',
    'radius': 4.0,
    'strokeWidth': 1.2,
  },
  'lounge': {
    'seatStyle': 'upholstered',
    'floorStyle': 'carpet',
    'radius': 18.0,
    'strokeWidth': 1.2,
  },
  'hall': {
    'construction': 'wood',
    'seatStyle': 'wood',
    'floorStyle': 'plain',
    'radius': 14.0,
    'strokeWidth': 2.2,
  },
  'banquet': {
    'construction': 'wood',
    'seatStyle': 'banquet',
    'floorStyle': 'plain',
    'radius': 10.0,
    'strokeWidth': 1.8,
  },
  'transit': {
    'seatStyle': 'transit',
    'floorStyle': 'plain',
    'radius': 8.0,
    'strokeWidth': 1.2,
  },
};

/// Canonical family presets contain presentation only and never move seats.
Map<String, Map<String, dynamic>> layoutMaterialStyles(String family) {
  final values = layoutMaterialFamilies[family];
  if (values == null) throw ArgumentError('Unknown material family');
  return {
    for (final kind in [
      'table',
      'seat',
      'furniture',
      'shape',
      'capacityArea',
      'text',
    ])
      kind: {
        'opacity': 1,
        if (kind != 'text') ...{
          'material': family,
          'strokeWidth': kind == 'seat'
              ? values['seatStrokeWidth'] ?? values['strokeWidth']
              : values['strokeWidth'],
          'cornerRadius': kind == 'seat'
              ? values['seatRadius'] ?? values['radius']
              : values['radius'],
        },
        if (kind == 'seat') 'seatStyle': values['seatStyle'],
      },
  };
}

VenueLayoutDocument withLayoutMaterialFamily(
  VenueLayoutDocument document,
  String family,
) {
  final preset =
      layoutMaterialFamilies[family] ??
      (throw ArgumentError('Unknown material family'));
  return document.copyWith(
    canvas: {...document.canvas, 'floorStyle': preset['floorStyle']},
    styles: {
      ...document.styles,
      'kinds': {
        ...document.styles['kinds'] as Map? ?? {},
        for (final entry in layoutMaterialStyles(family).entries)
          entry.key: {
            ...document.styles['kinds']?[entry.key] as Map? ?? {},
            ...entry.value,
          },
      },
    },
  );
}

VenueLayoutDocument withLayoutMinimalStyle(VenueLayoutDocument document) {
  {
    final styled = withLayoutMaterialFamily(document, 'minimal'),
        kinds = Map<String, dynamic>.from(styled.styles['kinds'] as Map);
    for (final kind in ['table', 'furniture'])
      kinds[kind] = {
        ...kinds[kind] as Map,
        'fill': '#FFFFFFFF',
        'stroke': '#000000FF',
        'strokeWidth': 1,
        'cornerRadius': 3.0,
      };
    kinds['table'] = {
      ...kinds['table'] as Map,
      'label': {...kinds['table']['label'] as Map? ?? {}, 'color': '#000000FF'},
    };
    kinds['seat'] = {
      ...kinds['seat'] as Map,
      'fill': '#267329FF',
      'stroke': '#00000000',
      'strokeWidth': 0,
      'cornerRadius': 8,
    };
    kinds['text'] = {
      ...kinds['text'] as Map,
      'label': {...kinds['text']['label'] as Map? ?? {}, 'color': '#000000FF'},
    };
    return styled.copyWith(
      canvas: {...styled.canvas, 'fill': '#FFFFFFFF'},
      styles: {...styled.styles, 'kinds': kinds},
    );
  }
}
