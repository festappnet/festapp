import 'package:festapp_core/forms.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/forms/models/holder_models/field_holder.dart';
import 'package:fstapp/components/forms/widgets_view/check_box_field_builder.dart';
import 'package:fstapp/components/forms/widgets_view/radio_field_builder.dart';

void main() {
  group('RadioFieldBuilder.resolveDefault (select_one)', () {
    final options = [
      FormOptionDefinition('0', 'Yes'),
      FormOptionDefinition('1', 'No'),
      FormOptionDefinition('2', 'Maybe'),
    ];

    OptionsFieldHolder holderWith(dynamic defaultValue) => OptionsFieldHolder(
          id: 1,
          fieldType: FormMetadata.fieldTypeSelectOne,
          isRequired: false,
          options: options,
          value: defaultValue,
          title: 'Q',
        );

    test('returns matching FormOptionModel when default matches option title',
        () {
      final resolved =
          RadioFieldBuilder.resolveDefault(holderWith('No'), options);
      expect(resolved, isNotNull);
      expect(resolved!.title, 'No');
    });

    test('returns null when default points to a deleted option', () {
      final resolved =
          RadioFieldBuilder.resolveDefault(holderWith('Gone'), options);
      expect(resolved, isNull);
    });

    test('returns null when default is empty string', () {
      final resolved =
          RadioFieldBuilder.resolveDefault(holderWith(''), options);
      expect(resolved, isNull);
    });

    test('returns null when default is missing', () {
      final resolved =
          RadioFieldBuilder.resolveDefault(holderWith(null), options);
      expect(resolved, isNull);
    });

    test('returns null when default is wrong type (list instead of string)',
        () {
      final resolved =
          RadioFieldBuilder.resolveDefault(holderWith(['No']), options);
      expect(resolved, isNull);
    });
  });

  group('CheckboxFieldBuilder.resolveDefaults (select_many)', () {
    final options = [
      FormOptionDefinition('0', 'A'),
      FormOptionDefinition('1', 'B'),
      FormOptionDefinition('2', 'C'),
    ];

    OptionsFieldHolder holderWith(dynamic defaultValue) => OptionsFieldHolder(
          id: 2,
          fieldType: FormMetadata.fieldTypeSelectMany,
          isRequired: false,
          options: options,
          value: defaultValue,
          title: 'Q',
        );

    test('returns matching options when all defaults exist', () {
      final resolved =
          CheckboxFieldBuilder.resolveDefaults(holderWith(['A', 'C']), options);
      expect(resolved.map((o) => o.title).toList()..sort(), ['A', 'C']);
    });

    test('silently drops defaults that refer to deleted options', () {
      final resolved = CheckboxFieldBuilder.resolveDefaults(
          holderWith(['A', 'Gone']), options);
      expect(resolved.map((o) => o.title).toList(), ['A']);
    });

    test('returns empty list when default is missing', () {
      final resolved =
          CheckboxFieldBuilder.resolveDefaults(holderWith(null), options);
      expect(resolved, isEmpty);
    });

    test('restores serialized single or multiple saved answers', () {
      final resolved =
          CheckboxFieldBuilder.resolveDefaults(holderWith('A | C'), options);
      expect(resolved.map((o) => o.title), ['A', 'C']);
      expect(CheckboxFieldBuilder.resolveDefaults(holderWith(''), options),
          isEmpty);
    });

    test('returns empty list when default list is empty', () {
      final resolved =
          CheckboxFieldBuilder.resolveDefaults(holderWith([]), options);
      expect(resolved, isEmpty);
    });

    test('ignores non-string entries in default list', () {
      final resolved = CheckboxFieldBuilder.resolveDefaults(
          holderWith(['A', 42, null, 'B']), options);
      expect(resolved.map((o) => o.title).toList()..sort(), ['A', 'B']);
    });
  });
}
