import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/images/image_control_client.dart';
import 'package:fstapp/components/images/image_file_format.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('background upload preserves verified processed manifest and SVG source MIME', () async {
    final hash = List.filled(64, 'a').join();
    final asset = {'assetRef': 'image:$hash', 'hash': hash,
      'url': 'https://img.festapp.net/assets/background.png',
      'width': 2, 'height': 3, 'byteLength': 80, 'mimeType': 'image/png', 'state': 'ready'};
    final svg = Uint8List.fromList(utf8.encode('<svg xmlns="http://www.w3.org/2000/svg"/>'));
    expect(() => ImageFileFormat.detect(svg), throwsFormatException);
    final client = ImageControlClient(endpoint: 'https://image-api.festapp.net', projectId: 'fixture',
      httpClient: MockClient((request) async {
        expect(latin1.decode(request.bodyBytes), contains('image/svg+xml'));
        return http.Response(jsonEncode({'url': asset['url'], 'asset': asset}), 200);
      }));
    final result = await client.uploadWithResult(bytes: svg, filename: 'background.svg',
      accessToken: 'fixture', occasionId: 1, profile: ImageUploadProfile.blueprintBackground);
    expect(result.asset, asset);
    expect(result.url, asset['url']);
  });
  test('background upload rejects URL-only responses as uncertain, not ready', () async {
    final client = ImageControlClient(endpoint: 'https://image-api.festapp.net', projectId: 'fixture',
      httpClient: MockClient((_) async => http.Response('{"url":"https://img.festapp.net/background.png"}', 200)));
    await expectLater(client.uploadWithResult(bytes: Uint8List.fromList([137,80,78,71,13,10,26,10]),
      filename: 'background.png', accessToken: 'fixture', occasionId: 1,
      profile: ImageUploadProfile.blueprintBackground), throwsA(isA<ImageUploadOutcomeUnknown>()));
  });
}
