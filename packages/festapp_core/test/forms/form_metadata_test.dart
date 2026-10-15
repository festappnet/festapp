import 'package:test/test.dart';
import 'package:festapp_core/forms.dart';

void main() {
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
