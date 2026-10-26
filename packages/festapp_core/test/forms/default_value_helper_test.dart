import 'package:festapp_core/forms.dart';
import 'package:test/test.dart';

Map<String, dynamic> _field({dynamic initialDefault}) => {
  if (initialDefault != null) FormMetadata.metaDefaultValue: initialDefault,
};

dynamic _stored(Map<String, dynamic> data) =>
    data[FormMetadata.metaDefaultValue];

void main() {
  group('default_value_helper', registerCases);
}

void registerCases() {
  group('DefaultValueHelper.read*', () {
    test('readString returns String, null for missing/wrong-type', () {
      expect(DefaultValueHelper.readString(_field(initialDefault: 'A')), 'A');
      expect(DefaultValueHelper.readString(_field()), isNull);
      expect(
        DefaultValueHelper.readString(_field(initialDefault: ['A'])),
        isNull,
      );
    });

    test('readList filters non-strings; empty for missing/wrong-type', () {
      expect(
        DefaultValueHelper.readList(
          _field(initialDefault: ['A', 1, null, 'B']),
        ),
        ['A', 'B'],
      );
      expect(DefaultValueHelper.readList(_field()), isEmpty);
      expect(DefaultValueHelper.readList(_field(initialDefault: 'A')), isEmpty);
    });
  });

  group('DefaultValueHelper.write', () {
    test(
      'null and empty list remove the key; non-empty values store as-is',
      () {
        var f = _field(initialDefault: 'A');
        f = DefaultValueHelper.write(f, null);
        expect(_stored(f), isNull);

        f = DefaultValueHelper.write(f, ['X', 'Y']);
        expect(_stored(f), ['X', 'Y']);

        f = DefaultValueHelper.write(f, []);
        expect(_stored(f), isNull);

        f = DefaultValueHelper.write(f, 'Z');
        expect(_stored(f), 'Z');
      },
    );

    test('empty string is stored (only null clears for single)', () {
      var f = _field();
      f = DefaultValueHelper.write(f, '');
      expect(_stored(f), '');
    });
  });

  group('DefaultValueHelper.rename', () {
    test('renames single-string match; no-op otherwise', () {
      var f = _field(initialDefault: 'old');
      f = DefaultValueHelper.rename(f, 'old', 'new') as Map<String, dynamic>;
      expect(_stored(f), 'new');

      f =
          DefaultValueHelper.rename(f, 'missing', 'other')
              as Map<String, dynamic>;
      expect(_stored(f), 'new');
    });

    test('renames every occurrence in a list', () {
      var f = _field(initialDefault: ['a', 'b', 'a']);
      f = DefaultValueHelper.rename(f, 'a', 'x') as Map<String, dynamic>;
      expect(_stored(f), ['x', 'b', 'x']);
    });
  });

  group('DefaultValueHelper.remove', () {
    test('clears single-string match; no-op when value differs', () {
      var f = _field(initialDefault: 'target');
      f = DefaultValueHelper.remove(f, 'other') as Map<String, dynamic>;
      expect(_stored(f), 'target');

      f = DefaultValueHelper.remove(f, 'target') as Map<String, dynamic>;
      expect(_stored(f), isNull);
    });

    test('filters from list; removes key entirely when list empties', () {
      var f = _field(initialDefault: ['a', 'b']);
      f = DefaultValueHelper.remove(f, 'a') as Map<String, dynamic>;
      expect(_stored(f), ['b']);

      f = DefaultValueHelper.remove(f, 'b') as Map<String, dynamic>;
      expect(_stored(f), isNull);
    });
  });

  group('DefaultValueHelper.toggleInList', () {
    test('adds value when not present; idempotent', () {
      var f = _field();
      f = DefaultValueHelper.toggleInList(f, 'a', true);
      expect(_stored(f), ['a']);
      f = DefaultValueHelper.toggleInList(f, 'a', true);
      expect(_stored(f), ['a']);
    });

    test('removes value when present; clears key when list empties', () {
      var f = _field(initialDefault: ['a']);
      f = DefaultValueHelper.toggleInList(f, 'a', false);
      expect(_stored(f), isNull);
    });

    test('converts non-list stored value to a fresh list', () {
      var f = _field(initialDefault: 'a-single-string');
      f = DefaultValueHelper.toggleInList(f, 'new', true);
      expect(_stored(f), ['new']);
    });
  });
}
