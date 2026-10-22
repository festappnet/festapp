import 'model.dart';

/// Shared by the editor's color picker and template creation. Color only:
/// applying a palette preserves material, geometry and seat identities.
const layoutStudioPalettes = <String, Map<String, String>>{
  'Graphite': {
    'surface': '#EFEFEFFF',
    'ink': '#171717FF',
    'edge': '#414141FF',
    'seat': '#BEBEBEFF',
    'canvas': '#FFFFFFFF',
  },
  'Forest': {
    'surface': '#E3EEE7FF',
    'ink': '#123C2AFF',
    'edge': '#235C3FFF',
    'seat': '#8FBEA2FF',
    'canvas': '#FFFFFFFF',
  },
  'Blueprint blue': {
    'surface': '#E2ECF8FF',
    'ink': '#163957FF',
    'edge': '#315C80FF',
    'seat': '#9DBEE0FF',
    'canvas': '#FFFFFFFF',
  },
  'Sage': {
    'surface': '#E5EBDFFF',
    'ink': '#294C3AFF',
    'edge': '#7E967FFF',
    'seat': '#BCD1B3FF',
    'canvas': '#F6F6EFFF',
  },
  'Champagne': {
    'surface': '#F1E5CDFF',
    'ink': '#4D3D28FF',
    'edge': '#A38A5FFF',
    'seat': '#D8C09AFF',
    'canvas': '#FFFCF5FF',
  },
  'Cinema red': {
    'surface': '#ECE8E5FF',
    'ink': '#342B2AFF',
    'edge': '#6B4945FF',
    'seat': '#B3252CFF',
    'canvas': '#FAF9F6FF',
  },
  'Burgundy': {
    'surface': '#F0E1E3FF',
    'ink': '#602B3BFF',
    'edge': '#A37683FF',
    'seat': '#DDB6C1FF',
    'canvas': '#FCF6F4FF',
  },
  'Midnight': {
    'surface': '#DDE4F0FF',
    'ink': '#243855FF',
    'edge': '#7E91B3FF',
    'seat': '#A8BDDEFF',
    'canvas': '#F3F5FAFF',
  },
};

VenueLayoutDocument withLayoutStudioPalette(
  VenueLayoutDocument document,
  String name,
) {
  final p = layoutStudioPalettes[name];
  if (p == null)
    throw ArgumentError.value(name, 'name', 'Unknown studio palette');
  final kinds = document.styles['kinds'] as Map? ?? {};
  return document.copyWith(
    canvas: {...document.canvas, 'fill': p['canvas']},
    styles: {
      ...document.styles,
      'label': {...?document.styles['label'] as Map?, 'color': p['ink']},
      'kinds': {
        ...kinds,
        for (final kind in [
          'table',
          'seat',
          'shape',
          'furniture',
          'capacityArea',
          'text',
        ])
          kind: {
            ...?kinds[kind] as Map?,
            if (kind != 'text') 'fill': p[kind == 'seat' ? 'seat' : 'surface'],
            if (kind != 'text') 'stroke': p['edge'],
            'label': {
              ...?(kinds[kind] as Map?)?['label'] as Map?,
              'color': p['ink'],
            },
          },
      },
    },
  );
}
