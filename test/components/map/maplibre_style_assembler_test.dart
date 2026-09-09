import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/map/maplibre/maplibre_style_assembler.dart';
import 'package:fstapp/components/map/offline_map_bundle_manager.dart';

void main() {
  test('assembles an entirely local MapLibre resource contract', () async {
    final directory = await Directory.systemTemp.createTemp('style-test');
    addTearDown(() => directory.delete(recursive: true));
    final files = <String, List<int>>{
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
    for (final entry in files.entries) {
      final file = File('${directory.path}/${entry.key}');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(entry.value);
    }
    const roles = {
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
    final manifestJson = {
      'schema_version': 2,
      'artifact_version': 'v2',
      'source_name': 'versatiles-shortbread',
      'base_url': 'https://assets.festapp.net/csmostrava2026/v2/',
      'assets': files.entries
          .map((entry) => {
                'role': roles[entry.key],
                'path': entry.key,
                'url': 'https://example.test/${entry.key}',
                'bytes': entry.value.length,
                'sha256': sha256.convert(entry.value).toString(),
              })
          .toList(),
    };
    await File('${directory.path}/manifest.json')
        .writeAsString(jsonEncode(manifestJson));
    final installation = await OfflineMapBundleManager(
      rootDirectory: directory.parent,
    ).verifyExisting(directory);
    final sourceStyle = jsonEncode({
      'version': 8,
      'sources': {
        'versatiles-shortbread': {
          'type': 'vector',
          'tiles': ['https://tiles.example.test/{z}/{x}/{y}.pbf'],
        }
      },
      'sprite': 'https://assets.example.test/sprites/sprites',
      'glyphs': 'https://assets.example.test/glyphs/{fontstack}/{range}.pbf',
      'layers': <Object?>[],
    });

    final assembled = jsonDecode(await MapLibreStyleAssembler.assemble(
      sourceStyleJson: sourceStyle,
      installation: installation,
    )) as Map<String, dynamic>;

    final source =
        (assembled['sources'] as Map<String, dynamic>)['versatiles-shortbread']
            as Map<String, dynamic>;
    expect(source['url'], startsWith('mbtiles:///'));
    expect(source.containsKey('tiles'), isFalse);
    expect(assembled['sprite'], startsWith('file:///'));
    expect(assembled['glyphs'], startsWith('file:///'));
    expect(assembled['glyphs'], contains('{fontstack}/{range}.pbf'));
    expect(assembled['glyphs'], isNot(contains('%7B')));
    expect(
        jsonEncode(assembled), isNot(contains('https://tiles.example.test')));
    expect(
        jsonEncode(assembled), isNot(contains('https://assets.example.test')));

    final mapLibreOnlyManifest = <String, dynamic>{
      ...manifestJson,
      'schema_version': 3,
      'bundle_mode': 'maplibre_only',
      'assets': (manifestJson['assets'] as List<Object?>)
          .where(
              (asset) => (asset as Map<String, dynamic>)['role'] != 'mbtiles')
          .toList(),
    };
    await File('${directory.path}/manifest.json')
        .writeAsString(jsonEncode(mapLibreOnlyManifest));
    final mapLibreOnlyInstallation = await OfflineMapBundleManager(
      rootDirectory: directory.parent,
    ).verifyExisting(directory);
    final mapLibreOnlyStyle = jsonDecode(await MapLibreStyleAssembler.assemble(
      sourceStyleJson: sourceStyle,
      installation: mapLibreOnlyInstallation,
    )) as Map<String, dynamic>;
    final mapLibreOnlySource = (mapLibreOnlyStyle['sources']
            as Map<String, dynamic>)['versatiles-shortbread']
        as Map<String, dynamic>;
    expect(mapLibreOnlySource['url'], startsWith('pmtiles://file:///'));
  });
}
