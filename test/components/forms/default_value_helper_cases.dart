import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/forms/models/form_field_model.dart';
import 'package:fstapp/components/forms/widgets_editor/default_value_helper.dart';
import 'package:fstapp/components/forms/widgets_view/form_helper.dart';

FormFieldModel _field({dynamic initialDefault}) {
  final field = FormFieldModel(options: []);
  if (initialDefault != null) {
    field.data = {FormHelper.metaDefaultValue: initialDefault};
  }
  return field;
}

dynamic _stored(FormFieldModel f) =>
    (f.data is Map) ? (f.data as Map)[FormHelper.metaDefaultValue] : null;

void main() {
  group('DefaultValueHelper.read*', () {
    test('readString returns String, null for missing/wrong-type', () {
      expect(DefaultValueHelper.readString(_field(initialDefault: 'A')), 'A');
      expect(DefaultValueHelper.readString(_field()), isNull);
      expect(DefaultValueHelper.readString(_field(initialDefault: ['A'])),
          isNull);
    });

    test('readList filters non-strings; empty for missing/wrong-type', () {
      expect(
          DefaultValueHelper.readList(_field(initialDefault: ['A', 1, null, 'B'])),
          ['A', 'B']);
      expect(DefaultValueHelper.readList(_field()), isEmpty);
      expect(DefaultValueHelper.readList(_field(initialDefault: 'A')), isEmpty);
    });
  });

  group('DefaultValueHelper.write', () {
    test('null and empty list remove the key; non-empty values store as-is', () {
      final f = _field(initialDefault: 'A');
      DefaultValueHelper.write(f, null);
      expect(_stored(f), isNull);

      DefaultValueHelper.write(f, ['X', 'Y']);
      expect(_stored(f), ['X', 'Y']);

      DefaultValueHelper.write(f, []);
      expect(_stored(f), isNull);

      DefaultValueHelper.write(f, 'Z');
      expect(_stored(f), 'Z');
    });

    test('empty string is stored (only null clears for single)', () {
      final f = _field();
      DefaultValueHelper.write(f, '');
      expect(_stored(f), '');
    });
  });

  group('DefaultValueHelper.rename', () {
    test('renames single-string match; no-op otherwise', () {
      final f = _field(initialDefault: 'old');
      DefaultValueHelper.rename(f, 'old', 'new');
      expect(_stored(f), 'new');

      DefaultValueHelper.rename(f, 'missing', 'other');
      expect(_stored(f), 'new');
    });

    test('renames every occurrence in a list', () {
      final f = _field(initialDefault: ['a', 'b', 'a']);
      DefaultValueHelper.rename(f, 'a', 'x');
      expect(_stored(f), ['x', 'b', 'x']);
    });
  });

  group('DefaultValueHelper.remove', () {
    test('clears single-string match; no-op when value differs', () {
      final f = _field(initialDefault: 'target');
      DefaultValueHelper.remove(f, 'other');
      expect(_stored(f), 'target');

      DefaultValueHelper.remove(f, 'target');
      expect(_stored(f), isNull);
    });

    test('filters from list; removes key entirely when list empties', () {
      final f = _field(initialDefault: ['a', 'b']);
      DefaultValueHelper.remove(f, 'a');
      expect(_stored(f), ['b']);

      DefaultValueHelper.remove(f, 'b');
      expect(_stored(f), isNull);
    });
  });

  group('DefaultValueHelper.toggleInList', () {
    test('adds value when not present; idempotent', () {
      final f = _field();
      DefaultValueHelper.toggleInList(f, 'a', true);
      expect(_stored(f), ['a']);
      DefaultValueHelper.toggleInList(f, 'a', true);
      expect(_stored(f), ['a']);
    });

    test('removes value when present; clears key when list empties', () {
      final f = _field(initialDefault: ['a']);
      DefaultValueHelper.toggleInList(f, 'a', false);
      expect(_stored(f), isNull);
    });

    test('converts non-list stored value to a fresh list', () {
      final f = _field(initialDefault: 'a-single-string');
      DefaultValueHelper.toggleInList(f, 'new', true);
      expect(_stored(f), ['new']);
    });
  });
}
