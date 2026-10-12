import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/html/html_media_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as image;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final uploads = <http.Request>[];
  final client = MockClient((request) async {
    uploads.add(request);
    return http.Response(
        '{"url":"https://img.festapp.net/images/12/photo.jpg"}', 200);
  });
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://fixture.invalid',
      anonKey: 'fixture',
      authOptions: const FlutterAuthClientOptions(
          autoRefreshToken: false, localStorage: EmptyLocalStorage()),
      httpClient: client,
    );
    final expiry = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
    String part(Object data) =>
        base64Url.encode(utf8.encode(jsonEncode(data))).replaceAll('=', '');
    await Supabase.instance.client.auth.setInitialSession(jsonEncode({
      'access_token':
          '${part({'alg': 'HS256'})}.${part({'exp': expiry})}.fixture',
      'refresh_token': 'fixture-refresh',
      'token_type': 'bearer',
      'expires_in': 3600,
      'expires_at': expiry,
      'user': {
        'id': '00000000-0000-0000-0000-000000000012',
        'app_metadata': {},
        'user_metadata': {},
        'aud': 'authenticated',
        'created_at': '2026-01-01T00:00:00Z'
      },
    }));
  });
  tearDownAll(() async => Supabase.instance.dispose());
  setUp(uploads.clear);

  Future<String> save(Uint8List bytes) => http.runWithClient(() async {
        final draft = HtmlMediaDraft();
        try {
          const owner = HtmlMediaOwner.occasion(12);
          final source = await draft.addBytes(bytes, owner);
          expect(draft.previewBytes(source), bytes);
          expect(uploads, isEmpty);
          return await draft.prepareHtml(
              '<p>Program</p><img src="$source">', '', owner);
        } finally {
          draft.dispose();
        }
      }, () => client);

  test('HTML photo save leaves JPEG compression to the server defaults',
      () async {
    final bytes =
        Uint8List.fromList(image.encodeJpg(image.Image(width: 2, height: 2)));
    final html = await save(bytes);
    expect(uploads, hasLength(1));
    expect(uploads.single.url.path, '/upload');
    final multipart = latin1.decode(uploads.single.bodyBytes);
    expect(multipart, contains('name="occasionId"'));
    expect(multipart, isNot(contains('name="maxBytes"')));
    expect(multipart, isNot(contains('name="quality"')));
    expect(html, contains('https://img.festapp.net/images/12/photo.jpg'));
  });

  for (final format in ['png', 'gif']) {
    test('HTML $format save retains the original-format upload contract',
        () async {
      final pixels = image.Image(width: 2, height: 2);
      final bytes = Uint8List.fromList(
          format == 'png' ? image.encodePng(pixels) : image.encodeGif(pixels));
      await save(bytes);
      final multipart = latin1.decode(uploads.single.bodyBytes);
      expect(multipart, contains('name="maxBytes"'));
      expect(multipart, contains('\r\n${HtmlMediaDraft.maxImageBytes}\r\n'));
    });
  }
}
