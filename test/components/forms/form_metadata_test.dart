import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/forms/models/form_model.dart';

void main() {
  test('reading design and schedule defaults does not create an unsaved change',
      () {
    final form = FormModel(data: {});
    expect(form.startTime, isNull);
    expect(form.endTime, isNull);
    expect(form.enableCountdown, false);
    expect(form.primaryColor, isNull);
    expect(form.fontFamily, isNull);
    expect(form.data, isEmpty);
    form.primaryColor = 0xff123456;
    form.enableCountdown = true;
    expect(form.primaryColor, 0xff123456);
    expect(form.enableCountdown, true);
  });
  test('festapp2025 metadata loads and saves as an object', () {
    final form = FormModel.fromJson({
      'id': 22,
      'occasion': 59,
      'link': 'festapp2025',
      'data': [
        null,
        {'phone_prefixes': null}
      ],
    });
    expect(form.startTime, isNull);
    expect(form.data!['phone_prefixes'], isNull);
    expect(form.toJson()['data'], isA<Map<String, dynamic>>());
  });

  test('concatenated metadata preserves settings in merge order', () {
    final form = FormModel.fromJson({
      'data': [
        {
          'design': {'primary_color': '#123456'},
          'custom': 'first'
        },
        null,
        {
          'custom': 'last',
          'phone_prefixes': ['+420']
        },
      ],
    });
    expect(form.data!['design'], {'primary_color': '#123456'});
    expect(form.data!['custom'], 'last');
    expect(form.data!['phone_prefixes'], ['+420']);
  });

  test('object and absent metadata keep their existing contract', () {
    expect(
        FormModel.fromJson({
          'data': {'custom': 1}
        }).data,
        {'custom': 1});
    expect(FormModel.fromJson({'data': null}).data, isNull);
  });
}
