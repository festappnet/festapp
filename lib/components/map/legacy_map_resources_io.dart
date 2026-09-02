import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:fstapp/components/map/offline_map_bundle_manager.dart';
import 'package:fstapp/components/map/offline_map_bundle_manifest.dart';
import 'package:mbtiles/mbtiles.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart' as vmt;
import 'package:vector_map_tiles_mbtiles/vector_map_tiles_mbtiles.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart' as vtr;

/// Native-only owner of the MBTiles database and vector-map style.
class LegacyMapResources {
  final vmt.Style style;
  final MbTiles mbtiles;

  LegacyMapResources._({required this.style, required this.mbtiles});

  static Future<LegacyMapResources> open({
    required String styleUri,
    required String mbtilesPath,
  }) async {
    final style = await vmt.StyleReader(uri: styleUri).read();
    final mbtiles = MbTiles(path: mbtilesPath, gzip: true);
    return LegacyMapResources._(style: style, mbtiles: mbtiles);
  }

  static Future<LegacyMapResources> openBundle(
    OfflineMapBundleInstallation installation,
  ) async {
    final manifest = installation.manifest;
    File assetFile(OfflineMapAssetRole role) {
      final asset = manifest.assetFor(role);
      return File('${installation.directory.path}/${asset.path}');
    }

    final styleJson = Map<String, dynamic>.from(
      jsonDecode(await assetFile(OfflineMapAssetRole.style).readAsString())
          as Map,
    );
    final spriteJson = jsonDecode(
      await assetFile(OfflineMapAssetRole.spriteJson2x).readAsString(),
    );
    final spritePng = assetFile(OfflineMapAssetRole.spritePng2x);
    final style = vmt.Style(
      name: styleJson['name'] as String?,
      theme: vtr.ThemeReader().read(styleJson),
      providers: vmt.TileProviders({}),
      sprites: vmt.SpriteStyle(
        atlasProvider: spritePng.readAsBytes,
        index: vtr.SpriteIndexReader().read(spriteJson),
      ),
    );
    final mbtilesAsset = manifest.assetFor(OfflineMapAssetRole.mbtiles);
    final mbtiles = MbTiles(
      path: '${installation.directory.path}/${mbtilesAsset.path}',
      gzip: true,
    );
    return LegacyMapResources._(style: style, mbtiles: mbtiles);
  }

  Widget buildBaseLayer({
    required String sourceName,
    required double maximumZoom,
  }) =>
      vmt.VectorTileLayer(
        theme: style.theme,
        sprites: style.sprites,
        tileProviders: vmt.TileProviders({
          sourceName: MbTilesVectorTileProvider(mbtiles: mbtiles),
        }),
        maximumZoom: maximumZoom,
      );

  void dispose() => mbtiles.close();
}
