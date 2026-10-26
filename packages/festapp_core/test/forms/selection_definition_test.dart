import 'package:festapp_core/forms.dart';
import 'package:test/test.dart';

void main() {
  for (final type in [
    FormMetadata.fieldTypeSelectOne,
    FormMetadata.fieldTypeSelectMany,
  ]) {
    for (final data in [
      null,
      <String, dynamic>{},
      {'options': null},
      {'options': 'invalid'},
    ]) {
      test('$type loads legacy missing options: $data', () {
        final field = FormFieldDefinition.fromJson({
          'id': 23,
          'type': type,
          'is_required': true,
          'data': data,
        });
        expect(field.options, isEmpty);
      });
    }
    test(
      '$type deleting the final option does not restore stale saved options',
      () {
        final field = FormFieldDefinition.fromJson({
          'id': 23,
          'type': type,
          'data': {
            'options': [
              {'value': 'Morning'},
            ],
          },
        });
        final cleared = field.copyWith(options: <FormOptionDefinition>[]);
        expect(FormFieldDefinition.fromJson(cleared.toJson()).options, isEmpty);
      },
    );
  }
}
