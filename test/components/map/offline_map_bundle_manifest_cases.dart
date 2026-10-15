import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/map/offline_map_bundle_manifest.dart';

void main() {
  test('a complete bundle is parsed and checksum verified', () async {
    final directory = await Directory.systemTemp.createTemp('map-bundle-test');
    addTearDown(() => directory.delete(recursive: true));

    final assets = <String, List<int>>{
      'style.json': utf8.encode('{}'),
      'map.pmtiles': [1],
      'map.mbtiles': [2],
      'sprites/sprites.json': utf8.encode('{}'),
      'sprites/sprites.png': [3],
      'sprites/sprites@2x.json': utf8.encode('{}'),
      'sprites/sprites@2x.png': [4],
      'glyphs/noto_sans_regular/0-255.pbf': [5],
      'glyphs/noto_sans_bold/0-255.pbf': [6],
    };
    for (final entry in assets.entries) {
      final file = File('${directory.path}/${entry.key}');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(entry.value);
    }

    final roles = <String, String>{
      'style.json': 'style',
      'map.pmtiles': 'pmtiles',
      'map.mbtiles': 'mbtiles',
      'sprites/sprites.json': 'sprite_json_1x',
      'sprites/sprites.png': 'sprite_png_1x',
      'sprites/sprites@2x.json': 'sprite_json_2x',
      'sprites/sprites@2x.png': 'sprite_png_2x',
      'glyphs/noto_sans_regular/0-255.pbf': 'glyph',
      'glyphs/noto_sans_bold/0-255.pbf': 'glyph',
    };
    final manifest = OfflineMapBundleManifest.parse({
      'schema_version': 2,
      'artifact_version': 'v2',
      'source_name': 'versatiles-shortbread',
      'base_url': 'https://assets.festapp.net/csmostrava2026/v2/',
      'assets': assets.entries
          .map((entry) => {
                'role': roles[entry.key],
                'path': entry.key,
                'url':
                    'https://assets.festapp.net/csmostrava2026/v2/${entry.key}',
                'bytes': entry.value.length,
                'sha256': sha256.convert(entry.value).toString(),
              })
          .toList(),
    });

    await manifest.verifyBundle(directory);
    await File('${directory.path}/map.pmtiles').writeAsBytes([9]);

    expect(
      () => manifest.verifyBundle(directory),
      throwsA(isA<OfflineMapBundleException>()),
    );
  });

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
          }
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
          .map((entry) => {
                'role': entry.value,
                'path': entry.key,
                'url':
                    'https://assets.festapp.net/festivalslunovrat/v2/${entry.key}',
                'bytes': 1,
                'sha256': List.filled(64, 'a').join(),
              })
          .toList(),
    });

    expect(manifest.bundleMode, OfflineMapBundleMode.mapLibreOnly);
    expect(
      manifest.assets.any((asset) => asset.role == OfflineMapAssetRole.mbtiles),
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
}
