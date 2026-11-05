import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';

import '../example/lib/demo/bundle.dart';

void main() {
  testWidgets(
    'public templates export valid version 2 portable browser fixtures',
    (tester) async {
      const output = String.fromEnvironment('QA_BROWSER_FIXTURES');
      expect(output, isNotEmpty);
      final resources = (await tester.runAsync(loadLayoutFixtureResources))!;
      final dir = Directory(output)..createSync(recursive: true);
      for (final id in ['lounge', 'ball-classic']) {
        final document = VenueLayoutTemplates.create(
          id,
          localize: const VenueLayoutLocalizations(Locale('cs')).text,
        );
        final encoded = DemoBundle(document, resources, {
          'template': id,
          'prices': <String, dynamic>{},
          'revision': 0,
        }).encode();
        expect(
          DemoBundle.decode(Uint8List.fromList(utf8.encode(encoded))).document
              .toJson(),
          document.toJson(),
        );
        File('${dir.path}/$id.json').writeAsStringSync(encoded);
      }
    },
  );
}
