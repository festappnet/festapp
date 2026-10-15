import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/images/image_control_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
      'upload uses the control origin and stable projectId without credentials',
      () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(
          jsonEncode({'url': 'https://a.img.festapp.net/images/1/x.jpg'}), 200);
    });
    final api = ImageControlClient(
        endpoint: 'https://image-api.festapp.net',
        projectId: 'a',
        httpClient: client);
    final result = await api.upload(
        bytes: Uint8List.fromList([0xff, 0xd8, 0xff, 0xe0]),
        filename: 'x.jpg',
        accessToken: 'jwt',
        occasionId: 1);
    expect(captured.url.toString(), 'https://image-api.festapp.net/upload');
    expect(captured.headers['Authorization'], 'Bearer jwt');
    final body = latin1.decode(captured.bodyBytes);
    expect(body, contains('name="projectId"'));
    expect(body, contains('\r\na\r\n'));
    expect(body, isNot(contains('anonKey')));
    expect(body, isNot(contains('supabaseUrl')));
    expect(result, 'https://a.img.festapp.net/images/1/x.jpg');
  });

  test('single and cleanup deletes use the same bounded URL batch contract',
      () async {
    final bodies = <Map<String, dynamic>>[];
    final client = MockClient((request) async {
      bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
      return http.Response(jsonEncode({'complete': true}), 200);
    });
    final api = ImageControlClient(
        endpoint: 'https://image-api.festapp.net',
        projectId: 'default',
        httpClient: client);
    await api.deleteLinks(['https://img.festapp.net/images/1/a.jpg'], 'jwt');
    await api.deleteLinks([
      'https://img.festapp.net/images/1/a.jpg',
      'https://img.festapp.net/images/1/b.jpg',
    ], 'jwt');
    expect(bodies[0], {
      'projectId': 'default',
      'links': ['https://img.festapp.net/images/1/a.jpg']
    });
    expect((bodies[1]['links'] as List).length, 2);
  });

  test('copy download preserves bytes for the subsequent upload', () async {
    final api = ImageControlClient(
        endpoint: 'https://image-api.festapp.net',
        projectId: 'default',
        httpClient:
            MockClient((_) async => http.Response.bytes([1, 2, 3], 200)));
    expect(await api.download('https://img.festapp.net/images/1/a.jpg'),
        Uint8List.fromList([1, 2, 3]));
  });
  for (final format in <(List<int>, String, String)>[
    ([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a], 'png', 'image/png'),
    ([0xff, 0xd8, 0xff], 'jpg', 'image/jpeg'),
    ([0x47, 0x49, 0x46, 0x38, 0x39, 0x61], 'gif', 'image/gif'),
    (
      [0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x45, 0x42, 0x50],
      'webp',
      'image/webp'
    )
  ]) {
    test('${format.$2} byte signature controls filename and MIME', () async {
      final api = ImageControlClient(
          endpoint: 'https://image-api.test',
          projectId: 'test',
          httpClient: MockClient((request) async {
            final body = latin1.decode(request.bodyBytes);
            expect(body, contains('filename="wrong.${format.$2}"'));
            expect(body, contains('content-type: ${format.$3}'));
            expect(body, contains('name="unitId"'));
            expect(body, isNot(contains('name="occasionId"')));
            return http.Response(
                jsonEncode({'url': 'https://assets.test/image'}), 200);
          }));
      await api.upload(
          bytes: Uint8List.fromList(format.$1),
          filename: 'wrong.jpg',
          accessToken: 'test-jwt',
          unitId: 3);
    });
  }
  test('5xx and invalid success responses have an unknown upload outcome',
      () async {
    for (final response in [
      http.Response('failed', 500),
      http.Response('{}', 200),
      http.Response('{"url":"javascript:unsafe"}', 200)
    ]) {
      final api = ImageControlClient(
          endpoint: 'https://image-api.test',
          projectId: 'test',
          httpClient: MockClient((_) async => response));
      await expectLater(
          api.upload(
              bytes: Uint8List.fromList([0xff, 0xd8, 0xff]),
              filename: 'a.jpg',
              accessToken: 'jwt',
              occasionId: 1),
          throwsA(isA<ImageUploadOutcomeUnknown>()));
    }
  });
}
