import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/painting.dart';

import '../../fonts/ticket_font_ids.dart';

/// Concrete values persist with the draft; a preset is only an editing shortcut.
class OccasionSetupAppearance {
  static const fonts = {
    'Roboto': 'roboto',
    'Roboto Slab': 'robotoSlab',
    'Russo One': 'russoOne',
  };
  static const presets = [
    {
      'id': 'clean',
      'label': 'Čistý',
      'primary': '4465A6',
      'secondary': '4465A6',
      'gradient': false,
      'fontFamily': 'Roboto',
    },
    {
      'id': 'gala',
      'label': 'Slavnostní',
      'primary': '14284B',
      'secondary': 'A87F28',
      'gradient': true,
      'fontFamily': 'Roboto Slab',
    },
    {
      'id': 'energy',
      'label': 'Energický',
      'primary': 'BB350C',
      'secondary': '8B182E',
      'gradient': true,
      'fontFamily': 'Russo One',
    },
    {
      'id': 'nature',
      'label': 'Přírodní',
      'primary': '216445',
      'secondary': '146475',
      'gradient': true,
      'fontFamily': 'Roboto',
    },
    {
      'id': 'soft',
      'label': 'Jemný',
      'primary': '885268',
      'secondary': '885268',
      'gradient': false,
      'fontFamily': 'Roboto Slab',
    },
    {
      'id': 'contrast',
      'label': 'Kontrastní',
      'primary': '111111',
      'secondary': '111111',
      'gradient': false,
      'fontFamily': 'Roboto',
    },
  ];

  static Map<String, dynamic> read(Map data) {
    if (data['appearance'] is Map)
      return Map<String, dynamic>.from(data['appearance']);
    final design =
        ((data['formDraft'] as Map?)?['data'] as Map?)?['design'] as Map?;
    if (design != null && design.isNotEmpty)
      return {
        'id': 'custom',
        'preserveSource': true,
        'primary': _hex(design['primary_color'], '4465A6'),
        'secondary': _hex(design['secondary_color'], '4465A6'),
        'gradient': design['background_mode'] == 'gradient',
        'fontFamily': design['font_family'] ?? 'Roboto',
      };
    return Map<String, dynamic>.from(presets.first);
  }

  static String _hex(dynamic raw, String fallback) {
    if (raw is num)
      return (raw.toInt() & 0xffffff)
          .toRadixString(16)
          .padLeft(6, '0')
          .toUpperCase();
    final text = raw?.toString().replaceAll('#', '') ?? fallback;
    return text.length == 8 ? text.substring(2) : text;
  }

  static bool valid(Map a) =>
      RegExp(r'^[A-Fa-f0-9]{6}$').hasMatch(a['primary'] as String? ?? '') &&
      RegExp(r'^[A-Fa-f0-9]{6}$').hasMatch(a['secondary'] as String? ?? '') &&
      ((a['preserveSource'] == true && a['id'] == 'custom') ||
          fonts.containsKey(a['fontFamily'])) &&
      a['gradient'] is bool;

  static void apply(
    Map<String, dynamic> data,
    Map<String, dynamic> appearance,
  ) {
    appearance = Map.of(appearance)..remove('preserveSource');
    if (!valid(appearance))
      throw const FormatException('Unsupported appearance');
    data['appearance'] = Map.of(appearance);
    final form = data['formDraft'] as Map;
    final metadata = Map<String, dynamic>.from(form['data'] as Map? ?? {});
    metadata['design'] = {
      ...Map<String, dynamic>.from(metadata['design'] as Map? ?? {}),
      'primary_color': '#${appearance['primary']}',
      'secondary_color': '#${appearance['secondary']}',
      'background_mode': appearance['gradient'] == true ? 'gradient' : 'solid',
      'font_family': appearance['fontFamily'],
    };
    form['data'] = metadata;
    final feature = Map<String, dynamic>.from(
      data['ticketDraft'] as Map? ?? {'code': 'ticket', 'is_enabled': true},
    );
    final layout = feature['layout'] is Map
        ? jsonDecode(jsonEncode(feature['layout'])) as Map
        : {
            'schemaVersion': 3,
            'templates': {'wide': _template()},
          };
    for (final entry in (layout['templates'] as Map).entries.toList()) {
      layout['templates'][entry.key] =
          styledTemplate(entry.value as Map, appearance);
    }
    feature['layout'] = layout;
    data['ticketDraft'] = feature;
  }

  static Map<String, dynamic> styledTemplate(Map raw, Map appearance) {
    final t = Map<String, dynamic>.from(jsonDecode(jsonEncode(raw)));
    final fontId = legacyTicketFontIds[fonts[appearance['fontFamily']]];
    if (fontId == null) return t;
    final colors = [appearance['primary'], appearance['secondary']];
    final luminance = colors
        .take(appearance['gradient'] == true ? 2 : 1)
        .map((hex) => Color(int.parse('ff$hex', radix: 16)).computeLuminance())
        .toList();
    final whiteContrast =
        luminance.map((l) => 1.05 / (l + .05)).reduce(math.min);
    final blackContrast =
        luminance.map((l) => (l + .05) / .05).reduce(math.min);
    final foreground = blackContrast > whiteContrast ? '000000' : 'FFFFFF';
    t['fontId'] = fontId;
    t['canvasColor'] = appearance['primary'];
    t['canvasOpacity'] = 1;
    if (appearance['gradient'] == true) {
      t['canvasGradient'] = colors;
    } else {
      t.remove('canvasGradient');
    }
    t['qrAppearance'] = {'background': 'FFFFFF', 'opacity': 1, 'margin': 4};
    for (final e in (t['elements'] as List).cast<Map>()) {
      final style = e['style'] as Map;
      style.remove('fontId');
      style['color'] = e['binding'] == 'qr' ? '000000' : foreground;
    }
    return t;
  }

  static Map<String, dynamic> _template() {
    Map<String, dynamic> element(
      String binding,
      double x,
      double y,
      double w,
      double h,
      double size, {
      int lines = 1,
    }) =>
        {
          'id': binding,
          'binding': binding,
          'box': {'x': x, 'y': y, 'width': w, 'height': h},
          'visible': true,
          'locked': false,
          'style': {
            'fontSize': size,
            'minFontSize': 6,
            'maxLines': lines,
            'color': binding == 'qr' ? '000000' : 'FFFFFF',
            'align': 'left',
          },
        };
    return {
      'page': {'width': 595.28, 'height': 841.89},
      'ticketArea': {'x': 0, 'y': 0, 'width': 595.28, 'height': 250.0},
      'elements': [
        element('occasionTitle', 24, 28, 390, 58, 24, lines: 2),
        element('occasionDatePlace', 24, 96, 390, 40, 12, lines: 2),
        element('price', 24, 160, 350, 24, 12),
        element('qr', 455, 65, 100, 100, 12),
        element('ticketSymbol', 445, 176, 130, 24, 10),
      ],
    };
  }
}
