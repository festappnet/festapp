import 'package:test/test.dart';
import 'package:festapp_core/forms.dart';

void main() {
  test(
    'form appearance defaults to system and survives the authoring snapshot',
    () {
      final original = FormDefinition(data: {});
      expect(original.themeMode, 'system');
      expect(original.data, isEmpty);
      for (final mode in ['system', 'light', 'dark']) {
        final form = original.withThemeMode(mode);
        final settings = FormMetadata.authoringSettingsSnapshot(form.data);
        expect(settings['design']['theme_mode'], mode);
        expect(FormDefinition.fromJson({'data': form.data}).themeMode, mode);
      }
      expect(() => original.withThemeMode('auto'), throwsArgumentError);
      expect(
        FormDefinition(
          data: {
            'design': {'theme_mode': 'unknown'},
          },
        ).themeMode,
        'system',
      );
    },
  );
  test('wizard background survives the form editor settings snapshot', () {
    for (final mode in ['solid', 'gradient']) {
      final data = <String, dynamic>{
        'design': {
          'primary_color': '#14284B',
          'secondary_color': '#A87F28',
          'background_mode': mode,
          'font_family': 'Roboto Slab',
        },
      };
      final saved = FormMetadata.authoringSettingsSnapshot(data);
      expect(saved['design']['background_mode'], mode);
      final form = FormDefinition.fromJson({'data': data});
      expect(form.backgroundMode, mode);
      final cleared = form.withBackgroundMode(null);
      expect(cleared.backgroundMode, isNull);
      expect(cleared.primaryColor, form.primaryColor);
      expect(cleared.secondaryColor, form.secondaryColor);
      expect(cleared.fontFamily, form.fontFamily);
    }
  });
  test('setup forms accept explicitly null schedule dates', () {
    final form = FormDefinition.fromJson({
      'data': {
        'schedule': {
          'start_time': null,
          'end_time': null,
          'sale_preparation': true,
          'enable_countdown': false,
        },
      },
    });
    expect(form.startTimeUtc, isNull);
    expect(form.endTimeUtc, isNull);
    final scheduled = form.withStartTimeUtc(DateTime.utc(2027, 2, 12));
    expect(scheduled.startTimeUtc, DateTime.utc(2027, 2, 12));
    expect(scheduled.endTimeUtc, isNull);
  });

  group('form_metadata', () {
    test(
      'reading design and schedule defaults does not create an unsaved change',
      () {
        var form = FormDefinition(data: {});
        expect(form.startTimeUtc, isNull);
        expect(form.endTimeUtc, isNull);
        expect(form.enableCountdown, false);
        expect(form.primaryColor, isNull);
        expect(form.fontFamily, isNull);
        expect(form.data, isEmpty);
        form = form.withPrimaryColor(0xff123456);
        form = form.withEnableCountdown(true);
        expect(form.primaryColor, 0xff123456);
        expect(form.enableCountdown, true);
      },
    );
    test('festapp2025 metadata loads and saves as an object', () {
      final form = FormDefinition.fromJson({
        'id': 22,
        'occasion': 59,
        'link': 'festapp2025',
        'data': [
          null,
          {'phone_prefixes': null},
        ],
      });
      expect(form.startTimeUtc, isNull);
      expect(form.data!['phone_prefixes'], isNull);
      expect(form.toJson()['data'], isA<Map<String, dynamic>>());
    });

    test('concatenated metadata preserves settings in merge order', () {
      final form = FormDefinition.fromJson({
        'data': [
          {
            'design': {'primary_color': '#123456'},
            'custom': 'first',
          },
          null,
          {
            'custom': 'last',
            'phone_prefixes': ['+420'],
          },
        ],
      });
      expect(form.data!['design'], {'primary_color': '#123456'});
      expect(form.data!['custom'], 'last');
      expect(form.data!['phone_prefixes'], ['+420']);
    });

    test('object and absent metadata keep their existing contract', () {
      expect(
        FormDefinition.fromJson({
          'data': {'custom': 1},
        }).data,
        {'custom': 1},
      );
      expect(FormDefinition.fromJson({'data': null}).data, isNull);
    });
  });
}
