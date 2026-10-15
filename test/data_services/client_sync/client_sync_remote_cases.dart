import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/data_services/client_sync/client_sync_remote.dart';
import 'package:fstapp/data_services/client_sync/client_sync_protocol.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('resolvePublicArtifactRequestUriForPage', () {
    final artifact = Uri.parse(
      'https://assets.festapp.net/client-sync/v1/9/643/live.json?revision=2',
    );

    test('routes public sync artifacts through the localhost proxy', () {
      expect(
        resolvePublicArtifactRequestUriForPage(
          artifact,
          Uri.parse('http://localhost:8080/csmostrava2026/news'),
        ),
        Uri.parse(
          'http://localhost:8080/__festapp_sync_asset__/client-sync/v1/9/643/live.json?revision=2',
        ),
      );
    });

    test('keeps the production artifact URL unchanged', () {
      expect(
        resolvePublicArtifactRequestUriForPage(
          artifact,
          Uri.parse('https://csmostrava.festapp.net/csmostrava2026/news'),
        ),
        artifact,
      );
    });
  });

  test('head polling bypasses a stale HTTP cache while retaining ETags',
      () async {
    final requests = <http.Request>[];
    var revision = 1;
    final client = MockClient((request) async {
      requests.add(request);
      final body = jsonEncode({
        'protocol': 1,
        'serverTime': '2026-08-06T12:00:00Z',
        'live': {
          'revision': revision++,
          'url':
              'https://assets.festapp.net/client-sync/v1/9/643/live_public/test.json',
          'sha256': List.filled(64, 'a').join(),
          'bytes': 2,
          'mediaType': 'application/json',
        },
      });
      return http.Response(
        body,
        200,
        headers: {
          'content-type': 'application/json',
          'etag': '"head-${requests.length}"',
          // This is the broken production response that previously kept a
          // browser on one live revision for four hours.
          'cache-control': 'public, max-age=14400, must-revalidate, s-maxage=5',
        },
      );
    });
    final remote = HttpPublicSyncRemote(
      headOrigin: Uri.parse('https://sync.festapp.net'),
      artifactOrigin: Uri.parse('https://assets.festapp.net'),
      client: client,
    );
    const context = SyncContext(
      organizationId: 9,
      occasionId: 643,
      occasionLink: 'csmostrava2026',
      identityEpoch: 0,
    );

    await remote.getHead(context);
    await remote.getHead(context);

    expect(requests, hasLength(2));
    expect(requests[0].url.path, requests[1].url.path);
    expect(requests[0].url.queryParameters, contains('poll'));
    expect(requests[1].url.queryParameters, contains('poll'));
    expect(requests[0].url, isNot(requests[1].url));
    expect(requests[1].headers['If-None-Match'], '"head-1"');
  });
}
