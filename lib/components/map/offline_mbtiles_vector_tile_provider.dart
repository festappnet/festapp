import 'dart:typed_data';

import 'package:mbtiles/mbtiles.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart' as vmt;

/// Adapts Festapp's offline MBTiles archive to the vector map renderer.
class OfflineMbTilesVectorTileProvider extends vmt.VectorTileProvider {
  final MbTiles mbtiles;

  late final int _minimumZoom = mbtiles.getMetadata().minZoom?.truncate() ?? 0;
  late final int _maximumZoom = mbtiles.getMetadata().maxZoom?.truncate() ?? 16;

  OfflineMbTilesVectorTileProvider({required this.mbtiles});

  @override
  int get minimumZoom => _minimumZoom;

  @override
  int get maximumZoom => _maximumZoom;

  @override
  vmt.TileOffset get tileOffset => vmt.TileOffset.DEFAULT;

  @override
  Future<Uint8List> provide(vmt.TileIdentity tile) async {
    final tmsY = ((1 << tile.z) - 1) - tile.y;
    final bytes = mbtiles.getTile(z: tile.z, x: tile.x, y: tmsY);
    if (bytes == null) {
      throw vmt.ProviderException(
        message: 'Tile not found: $tile',
        retryable: vmt.Retryable.none,
        statusCode: 404,
      );
    }
    return bytes;
  }
}
