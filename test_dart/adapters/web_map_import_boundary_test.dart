import 'dart:io';

import 'package:test/test.dart';

void main() {
  group('web_map_import_boundary', () {
    test('web map graph excludes native MBTiles implementation', () {
      final surface = File(
        'lib/components/map/legacy_map_surface.dart',
      ).readAsStringSync();
      final boundary = File(
        'lib/components/map/legacy_map_resources.dart',
      ).readAsStringSync();
      final webStub = File(
        'lib/components/map/legacy_map_resources_stub.dart',
      ).readAsStringSync();
      final nativeImplementation = File(
        'lib/components/map/legacy_map_resources_io.dart',
      ).readAsStringSync();

      expect(surface, isNot(contains("package:mbtiles/mbtiles.dart")));
      expect(
        boundary,
        contains(
          "if (dart.library.io) 'legacy_map_resources_io.dart'",
        ),
      );
      expect(webStub, isNot(contains('package:mbtiles/')));
      expect(nativeImplementation, contains('package:mbtiles/mbtiles.dart'));
    });
  });
}
