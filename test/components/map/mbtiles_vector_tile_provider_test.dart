import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mbtiles/mbtiles.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart' as vmt;
import 'package:vector_map_tiles_mbtiles/vector_map_tiles_mbtiles.dart';

void main() {
  late MbTiles mbtiles;

  setUp(() {
    mbtiles = MbTiles.create(
      path: null,
      gzip: false,
      metadata: const MbTilesMetadata(
        name: 'test',
        format: 'pbf',
        minZoom: 1,
        maxZoom: 14,
      ),
    );
  });

  tearDown(() => mbtiles.close());

  test('reads an XYZ request from the TMS MBTiles row', () async {
    final expected = Uint8List.fromList([1, 2, 3]);
    mbtiles.putTile(z: 2, x: 1, y: 2, bytes: expected);
    final provider = MbTilesVectorTileProvider(mbtiles: mbtiles);

    expect(await provider.provide(vmt.TileIdentity(2, 1, 1)), expected);
    expect(provider.minimumZoom, 1);
    expect(provider.maximumZoom, 14);
    expect(provider.tileOffset, vmt.TileOffset.DEFAULT);
  });

  test('reports a missing tile as a non-retryable provider error', () async {
    final provider = MbTilesVectorTileProvider(mbtiles: mbtiles);

    await expectLater(
      provider.provide(vmt.TileIdentity(2, 1, 1)),
      throwsA(
        isA<vmt.ProviderException>()
            .having((error) => error.statusCode, 'statusCode', 404)
            .having(
                (error) => error.retryable, 'retryable', vmt.Retryable.none),
      ),
    );
  });
}
