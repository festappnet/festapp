import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/_shared/appearance_palettes.dart';
import 'package:fstapp/components/occasion/setup/occasion_setup_appearance.dart';

void main() {
  test('all historical color pairs retain a unique translated identity', () {
    expect(AppearancePalettes.all.length, 34);
    expect(AppearancePalettes.all.map((p) => p.id).toSet().length, 34);
    for (final locale in ['cs', 'en', 'sk', 'de', 'pl', 'uk']) {
      final translations = jsonDecode(
        File('assets/translations/$locale.json').readAsStringSync(),
      );
      final labels = <String>{};
      for (final palette in AppearancePalettes.all) {
        dynamic label = translations;
        for (final part in palette.labelKey.split('.')) {
          label = label[part];
        }
        expect(label, isA<String>(), reason: '$locale ${palette.id}');
        expect((label as String).isNotEmpty, true);
        expect(
          labels.add(label),
          true,
          reason: 'Ambiguous $locale label: $label',
        );
        expect(
          AppearancePalettes.match(palette.primary, palette.secondary, true),
          same(palette),
        );
        expect(
          AppearancePalettes.match(palette.primary, 0xff123456, false),
          same(palette),
        );
      }
    }
    expect(AppearancePalettes.match(null, null, false), isNull);
    expect(AppearancePalettes.match(0xff263238, 0xff123456, true), isNull);
  });

  test('color names leave custom-font source data valid and unchanged', () {
    final data = <String, dynamic>{
      'formDraft': {
        'data': {
          'design': {
            'primary_color': '#14284B',
            'secondary_color': '#A87F28',
            'background_mode': 'gradient',
            'font_family': 'Existing custom font',
          },
        },
      },
    };
    final before = jsonEncode(data);
    final appearance = OccasionSetupAppearance.read(data);
    expect(AppearancePalettes.match(0xff14284b, 0xffa87f28, true)?.id, 'gala');
    expect(appearance['id'], 'custom');
    expect(appearance['preserveSource'], true);
    expect(OccasionSetupAppearance.valid(appearance), true);
    expect(jsonEncode(data), before);
    final selected = OccasionSetupAppearance.selectPreset(data, 'form-night');
    expect(selected['fontFamily'], 'Existing custom font');
    expect(selected['gradient'], true);
    expect(jsonEncode(data), before);
  });

  test(
    'color selection keeps independent supported font and original manifest',
    () {
      expect(
        OccasionSetupAppearance.presets.map((p) => p['fontFamily']).toSet(),
        OccasionSetupAppearance.fonts.keys.toSet(),
      );
      final data = <String, dynamic>{
        'appearance': {
          ...OccasionSetupAppearance.presets.first,
          'fontFamily': 'Inter',
        },
      };
      for (final palette in AppearancePalettes.all) {
        final selected = OccasionSetupAppearance.selectPreset(data, palette.id);
        expect(selected['fontFamily'], 'Inter');
        expect(selected['gradient'], false);
        expect(OccasionSetupAppearance.valid(selected), true);
      }
    },
  );
}
