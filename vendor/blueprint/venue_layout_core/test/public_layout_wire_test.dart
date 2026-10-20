import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:venue_layout_core/venue_layout_core.dart';

void main() {
  test('public wire geometry preserves numeric types through decode', () {
    final fixture =
        jsonDecode(
              File('test/fixtures/public_layout_wire.json').readAsStringSync(),
            )
            as Map<String, dynamic>;
    final imported = importLegacyLayout(
      fixture,
      fontFamilies: {
        'family:fixture': {
          'id': 'family:fixture',
          'family': 'Fixture',
          'faces': {'400:normal': 'fixture:sans'},
        },
      },
      sourceRevision: 0,
    );
    final document = imported.document!;
    expect(validateDocument(document), isEmpty);
    expect(document.nodes.length, 7);
    expect(
      validateDocument(VenueLayoutDocument.fromJson(document.toJson())),
      isEmpty,
    );
  });
}
