import 'package:test/test.dart';
import 'package:festapp_core/map.dart';

void main() {
  group('offline_map_bundle_manifest', () {
    test('unsafe relative paths and unknown schema versions are rejected', () {
      final base = {
        'artifact_version': 'v2',
        'source_name': 'versatiles-shortbread',
        'base_url': 'https://assets.festapp.net/csmostrava2026/v2/',
        'assets': <Object?>[],
      };

      expect(
        () => OfflineMapBundleManifest.parse({...base, 'schema_version': 99}),
        throwsA(isA<OfflineMapBundleException>()),
      );
      expect(
        () => OfflineMapBundleManifest.parse({
          ...base,
          'schema_version': 2,
          'assets': [
            {
              'role': 'style',
              'path': '../style.json',
              'url': 'https://assets.festapp.net/style.json',
              'bytes': 1,
              'sha256': List.filled(64, 'a').join(),
            },
          ],
        }),
        throwsA(isA<OfflineMapBundleException>()),
      );
    });

    test('schema 3 maplibre-only bundle does not require MBTiles', () {
      final assets = <String, String>{
        'style.json': 'style',
        'map.pmtiles': 'pmtiles',
        'sprites/sprites.json': 'sprite_json_1x',
        'sprites/sprites.png': 'sprite_png_1x',
        'sprites/sprites@2x.json': 'sprite_json_2x',
        'sprites/sprites@2x.png': 'sprite_png_2x',
        'glyphs/noto_sans_regular/0-255.pbf': 'glyph',
        'glyphs/noto_sans_bold/0-255.pbf': 'glyph',
      };
      final manifest = OfflineMapBundleManifest.parse({
        'schema_version': 3,
        'bundle_mode': 'maplibre_only',
        'artifact_version': 'v3',
        'source_name': 'versatiles-shortbread',
        'base_url': 'https://assets.festapp.net/festivalslunovrat/v2/',
        'assets': assets.entries
            .map(
              (entry) => {
                'role': entry.value,
                'path': entry.key,
                'url':
                    'https://assets.festapp.net/festivalslunovrat/v2/${entry.key}',
                'bytes': 1,
                'sha256': List.filled(64, 'a').join(),
              },
            )
            .toList(),
      });

      expect(manifest.bundleMode, OfflineMapBundleMode.mapLibreOnly);
      expect(
        manifest.assets.any(
          (asset) => asset.role == OfflineMapAssetRole.mbtiles,
        ),
        isFalse,
      );
    });

    test('schema 2 still requires MBTiles and schema 3 requires its mode', () {
      final base = {
        'artifact_version': 'v2',
        'source_name': 'versatiles-shortbread',
        'base_url': 'https://assets.festapp.net/test/v2/',
        'assets': <Object?>[],
      };

      expect(
        () => OfflineMapBundleManifest.parse({...base, 'schema_version': 2}),
        throwsA(isA<OfflineMapBundleException>()),
      );
      expect(
        () => OfflineMapBundleManifest.parse({...base, 'schema_version': 3}),
        throwsA(isA<OfflineMapBundleException>()),
      );
      expect(
        () => OfflineMapBundleManifest.parse({
          ...base,
          'schema_version': 3,
          'bundle_mode': 'dual_renderer',
        }),
        throwsA(isA<OfflineMapBundleException>()),
      );
    });
  });
}
