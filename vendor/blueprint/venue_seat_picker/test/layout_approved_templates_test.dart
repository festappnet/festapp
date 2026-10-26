import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';

void main() {
  test('recommended picker contains only approved plans plus blank', () {
    expect(VenueLayoutTemplates.recommended.map((t) => t.id), [
      'blank',
      'scout-ball-182',
      'scout-ball-balcony-249',
      'bus',
      'double-decker',
      'train',
      'studio-tables',
      'studio-gala',
      'reference-lipoltice',
      'reference-belvedere',
      'auditorium',
      'cinema-galaxy',
      'reference-brandys',
      'studio-arena',
      'reference-lucerna',
    ]);
    expect(VenueLayoutTemplates.all, same(VenueLayoutTemplates.recommended));
    expect(VenueLayoutTemplates.defaultId, 'blank');
    expect(VenueLayoutTemplates.byId('scout-ball-182').seatCount, 182);
    expect(VenueLayoutTemplates.byId('bus').seatCount, 45);
  });
  test('approved plans retain capacities and valid canonical roundtrips', () {
    const counts = {
      'reference-belvedere': 110,
      'reference-lipoltice': 186,
      'reference-brandys': 265,
      'reference-lucerna': 1066,
      'studio-tables': 96,
      'studio-gala': 96,
      'studio-arena': 96,
    };
    for (final entry in counts.entries) {
      final first = VenueLayoutTemplates.create(entry.key);
      expect(
        first.nodes.where((n) => n.kind == 'seat'),
        hasLength(entry.value),
        reason: entry.key,
      );
      expect(validateDocument(first), isEmpty, reason: entry.key);
      final restored = VenueLayoutDocument.fromJson(
        jsonDecode(jsonEncode(first.toJson())),
      );
      expect(sameLayoutDocument(first, restored), isTrue, reason: entry.key);
      final again = VenueLayoutTemplates.create(entry.key);
      expect(
        first.nodes
            .map((n) => n.id)
            .toSet()
            .intersection(again.nodes.map((n) => n.id).toSet()),
        isEmpty,
      );
    }
  });
  test(
    'Lipoltice automatic head chair and Belvedere authored positions remain editable',
    () {
      final lip = VenueLayoutTemplates.create('reference-lipoltice');
      final sixth = lip.nodes.singleWhere(
        (n) => n.kind == 'table' && n.label == '6',
      );
      expect(
        lip.nodes.where((n) => n.parentId == sixth.id && n.kind == 'seat'),
        hasLength(17),
      );
      expect(
        lip.attachments.every((a) => a['placement']['mode'] == 'automatic'),
        isTrue,
      );
      final bel = VenueLayoutTemplates.create('reference-belvedere');
      expect(bel.nodes.where((n) => n.kind == 'table'), hasLength(20));
      expect(
        bel.attachments.every((a) => a['placement']['mode'] == 'free'),
        isTrue,
      );
      expect(bel.nodes.where((n) => n.kind == 'capacityArea'), isEmpty);
    },
  );
}
