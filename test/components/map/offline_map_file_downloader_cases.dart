import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/map/offline_map_file_downloader.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('recovers when the connection drops after partial bytes were received',
      () async {
    final directory = await Directory.systemTemp.createTemp('map-stream-drop');
    addTearDown(() => directory.delete(recursive: true));
    final destination = File('${directory.path}/map.pmtiles');
    await destination.writeAsBytes([1, 2, 3]);
    var requests = 0;
    final progress = <double>[];
    final downloader = OfflineMapFileDownloader(
      retryDelay: Duration.zero,
      client: MockClient.streaming((_, __) async {
        requests++;
        if (requests == 1) {
          return http.StreamedResponse(
            (() async* {
              yield [4, 5];
              throw const SocketException('connection reset by peer');
            })(),
            200,
            contentLength: 3,
          );
        }
        return http.StreamedResponse(
          Stream.value([4, 5, 6]),
          200,
          contentLength: 3,
        );
      }),
    );

    await downloader.download(
      uri: Uri.parse('https://maps.test/map.pmtiles'),
      destination: destination,
      onProgress: progress.add,
    );

    expect(requests, 2);
    expect(progress, containsAllInOrder([2 / 3, 0, 1]));
    expect(await destination.readAsBytes(), [4, 5, 6]);
    expect(File('${destination.path}.part').existsSync(), isFalse);
    expect(File('${destination.path}.old').existsSync(), isFalse);
  });

  test('retries a transient failure and atomically replaces the old file',
      () async {
    final directory = await Directory.systemTemp.createTemp('map-file-retry');
    addTearDown(() => directory.delete(recursive: true));
    final destination = File('${directory.path}/map.mbtiles');
    await destination.writeAsBytes([1, 2, 3]);
    var requests = 0;
    final downloader = OfflineMapFileDownloader(
      retryDelay: Duration.zero,
      client: MockClient((_) async {
        requests++;
        return requests == 1
            ? http.Response('temporary outage', 503)
            : http.Response.bytes([4, 5, 6], 200);
      }),
    );

    await downloader.download(
      uri: Uri.parse('https://maps.test/map.mbtiles'),
      destination: destination,
    );

    expect(requests, 2);
    expect(await destination.readAsBytes(), [4, 5, 6]);
    expect(File('${destination.path}.part').existsSync(), isFalse);
    expect(File('${destination.path}.old').existsSync(), isFalse);
  });

  test('exhausted refresh preserves the previous ready file', () async {
    final directory = await Directory.systemTemp.createTemp('map-file-fail');
    addTearDown(() => directory.delete(recursive: true));
    final destination = File('${directory.path}/map.mbtiles');
    await destination.writeAsBytes([1, 2, 3]);
    final downloader = OfflineMapFileDownloader(
      retryDelay: Duration.zero,
      client: MockClient((_) async => http.Response('outage', 503)),
    );

    await expectLater(
      downloader.download(
        uri: Uri.parse('https://maps.test/map.mbtiles'),
        destination: destination,
      ),
      throwsA(isA<HttpException>()),
    );

    expect(await destination.readAsBytes(), [1, 2, 3]);
    expect(File('${destination.path}.part').existsSync(), isFalse);
  });
}
