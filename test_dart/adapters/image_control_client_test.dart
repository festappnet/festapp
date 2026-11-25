import 'dart:convert';
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:fstapp/components/images/image_control_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as image;
import 'package:fstapp/components/images/image_upload_input.dart';
import 'package:fstapp/components/images/image_upload_limits.dart';
import 'package:fstapp/services/import_file.dart';

void main() {
  final pixels = image.Image(width: 2, height: 3);
  final jpeg = image.encodeJpg(pixels);
  group('image_control_client', () {
    test('oversized raster is rejected before transport', () async {
      final bytes = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAG1gAABtYCAYAAACZm7uPAAAAC0lEQVR4nGNgAAIAAAUAAXpeqz8AAAAASUVORK5CYII=',
      );
      final api = ImageControlClient(
        endpoint: 'https://image-api.test',
        projectId: 'test',
        httpClient: MockClient((_) async => fail('Unexpected request')),
      );
      await expectLater(
        api.upload(
          bytes: bytes,
          filename: 'large.png',
          accessToken: 'test-jwt',
          unitId: 3,
        ),
        throwsA(isA<ImageUploadLimitExceeded>()),
      );
    });

    test('oversized file metadata prevents a byte read', () async {
      final file = ImportFile(
        name: 'large.jpg',
        size: () async => ImageUploadLimits.maxInputBytes + 1,
        readBytes: () async => fail('Unexpected byte read'),
      );
      await expectLater(
        ImageUploadInput.readFile(file),
        throwsA(isA<ImageUploadLimitExceeded>()),
      );
    });
    test(
        'upload uses the control origin and stable projectId without credentials',
        () async {
      late http.Request captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(
            jsonEncode({'url': 'https://a.img.festapp.net/images/1/x.jpg'}),
            200);
      });
      final api = ImageControlClient(
          endpoint: 'https://image-api.festapp.net',
          projectId: 'a',
          httpClient: client);
      final result = await api.upload(
          bytes: jpeg,
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
      expect(result.url, 'https://a.img.festapp.net/images/1/x.jpg');
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
    for (final format in [
      (image.encodePng(pixels), 'png', 'image/png'),
      (jpeg, 'jpg', 'image/jpeg'),
      (image.encodeGif(pixels), 'gif', 'image/gif'),
      (image.encodeWebP(pixels), 'webp', 'image/webp'),
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
            bytes: format.$1,
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
                bytes: jpeg,
                filename: 'a.jpg',
                accessToken: 'jwt',
                occasionId: 1),
            throwsA(isA<ImageUploadOutcomeUnknown>()));
      }
    });
  });
}
