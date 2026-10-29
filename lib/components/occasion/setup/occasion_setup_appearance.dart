import 'package:fstapp/components/_shared/appearance_palettes.dart';
import 'occasion_setup_font_ids.dart';
import 'occasion_setup_strings.dart';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/painting.dart';

import '../../ticket_layout/models/ticket_layout.dart';
import '../../ticket_layout/ticket_theme_color.dart';

/// Concrete values persist with the draft; a preset is only an editing shortcut.
class OccasionSetupAppearance {
  static Map<String, String> get ticketCompositions => {
        'silk_light': OccasionSetupStrings.ui('silk_light'),
        'silk_dark': OccasionSetupStrings.ui('silk_dark'),
      };
  static const themedArtwork = {
    'concert_stub',
    'festival_poster',
    'club_panorama',
    'theatre_program',
    'gallery_square',
    'gala_invitation',
    'boarding_pass',
    'cinema_strip',
    'sports_arena',
    'festival_badge',
    'workshop_card',
  };
  static String? ticketBackground(String key, Map appearance) {
    const root = 'https://img.festapp.net/ticket-presets/v1/';
    if (key == 'silk_light') return '${root}style-silk-v2.png';
    if (key == 'silk_dark') return '${root}style-silk-dark-v2.png';
    if (themedArtwork.contains(key)) {
      final secondary = appearance['gradient'] == true
          ? appearance['secondary']
          : appearance['primary'];
      return '${root}palette-${appearance['primary']}-${secondary}-$key-v2.png';
    }
    return null;
  }

  // Same luminance-preserving palette as ticketThemePalette.js. Recoloring ink
  // and paper together preserves each original design's contrast and structure.
  static String themeColor(String hex, Map appearance) =>
      ticketThemeColor(hex, appearance['primary'],
          appearance['gradient'] == true ? appearance['secondary'] : appearance['primary']);

  static const fonts = occasionSetupFontIds;
  static List<Map<String, dynamic>> get presets => [
        for (final palette in AppearancePalettes.all.where((p) => p.fontFamily != null))
          {
            'id': palette.id,
            'label': palette.label,
            'primary': palette.primaryHex,
            'secondary': palette.secondaryHex,
            'gradient': false,
            'fontFamily': palette.fontFamily,
          },
      ];

  /// Color choices retain the independently selected font and color mode.
  static Map<String, dynamic> selectPreset(Map data, String id) {
    final palette = AppearancePalettes.byId(id);
    return {
      ...read(data),
      'id': id,
      'primary': palette.primaryHex,
      'secondary': palette.secondaryHex,
    };
  }

  static Map<String, dynamic> read(Map data) {
    final current = data['appearance'] as Map?;
    final design =
        ((data['formDraft'] as Map?)?['data'] as Map?)?['design'] as Map?;
    if (design != null && design.isNotEmpty) {
      final resolved = <String, dynamic>{
        'id': 'custom',
        'preserveSource': true,
        'primary': _hex(design['primary_color'], '4465A6'),
        'secondary': _hex(
          design['secondary_color'],
          _hex(design['primary_color'], '4465A6'),
        ),
        'gradient': design['background_mode'] == 'gradient',
        'fontFamily': design['font_family'] ?? 'Roboto',
      };
      if (current != null &&
          const [
            'primary',
            'secondary',
            'gradient',
            'fontFamily',
          ].every((key) => current[key] == resolved[key])) {
        return Map<String, dynamic>.from(current);
      }
      return resolved;
    }
    return Map<String, dynamic>.from(current ?? presets.first);
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
    if (feature['delivery_mode'] == 'inline_qr') return;
    final layout = feature['layout'] is Map
        ? jsonDecode(jsonEncode(feature['layout'])) as Map
        : {
            'schemaVersion': 3,
            'templates': {'wide': _template()},
          };
    for (final entry in (layout['templates'] as Map).entries.toList()) {
      layout['templates'][entry.key] = styledTemplate(
          data['ticketTemplateSource'] is Map
              ? data['ticketTemplateSource'] as Map
              : entry.value as Map,
          appearance,
          decorated: data['ticketTemplateId'] != null,
          composition: data['ticketTemplateId'] as String?);
    }
    final background =
        ticketBackground(data['ticketTemplateId'] as String? ?? '', appearance);
    if (background != null) feature['background'] = background;
    feature['layout'] = layout;
    data['ticketDraft'] = feature;
  }

  static Map<String, dynamic> styledTemplate(Map raw, Map appearance,
      {bool decorated = false, String? composition}) {
    final t = Map<String, dynamic>.from(jsonDecode(jsonEncode(raw)));
    final fontId = fonts[appearance['fontFamily']];
    if (fontId == null) return t;
    final colors = <String>[appearance['primary'], appearance['secondary']];
    if (decorated) {
      String color(String hex) => themeColor(hex, appearance);
      t['fontId'] = fontId;
      if (t['canvasColor'] != null && t['canvasColor'] != 'transparent')
        t['canvasColor'] = color(t['canvasColor']);
      if (t['canvasGradient'] is List)
        t['canvasGradient'] = (t['canvasGradient'] as List)
            .map((v) => color(v as String))
            .toList();
      if (t['qrAppearance'] is Map) t['qrAppearance']['background'] = 'FFFFFF';
      for (final e in (t['elements'] as List).cast<Map>()) {
        (e['style'] as Map).remove('fontId');
        e['style']['color'] = e['binding'] == 'qr'
            ? '000000'
            : themeColor(e['style']['color'],
                {'primary': '222222', 'secondary': '222222'});
        if (['silk_light', 'ball_silk'].contains(composition) &&
            e['binding'] != 'qr') e['style']['color'] = '222222';
        if (composition == 'silk_dark' && e['binding'] != 'qr')
          e['style']['color'] = 'F5F5F5';
      }
      return t;
    }
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
    t['canvasColor'] = colors.first;
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
      if (e['binding'] == 'qr') {
        e['box'] = TicketElement.fromJson(e).toJson()['box'];
      }
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
