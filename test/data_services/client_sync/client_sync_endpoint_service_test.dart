import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/data_services/client_sync/client_sync_endpoint_service.dart';

void main() {
  const tenant = 'festival';
  const fallbackHead = 'https://sync.festapp.net';
  const fallbackAssets = 'https://assets.festapp.net';

  String document({
    String head = 'https://sync-next.festapp.net',
    String assets = 'https://assets-next.festapp.net',
  }) =>
      jsonEncode({
        'schemaVersion': 1,
        'tenantId': tenant,
        'syncHeadOrigin': head,
        'syncAssetOrigin': assets,
      });

  test('native client accepts and caches a valid tenant runtime document',
      () async {
    String? cached;
    final endpoints = await ClientSyncEndpointService(
      tenantId: tenant,
      configUrl: 'https://festival.example/client-sync-config.json',
      fallbackHeadOrigin: fallbackHead,
      fallbackAssetOrigin: fallbackAssets,
      isWeb: false,
      read: (_) async => cached,
      write: (_, value) async => cached = value,
      fetch: (_) async => utf8.encode(document()),
    ).resolve();

    expect(endpoints.headOrigin, Uri.parse('https://sync-next.festapp.net'));
    expect(endpoints.assetOrigin, Uri.parse('https://assets-next.festapp.net'));
    expect(cached, isNotNull);
  });

  test('native client uses cached valid endpoints when the network fails',
      () async {
    final endpoints = await ClientSyncEndpointService(
      tenantId: tenant,
      configUrl: 'https://festival.example/client-sync-config.json',
      fallbackHeadOrigin: fallbackHead,
      fallbackAssetOrigin: fallbackAssets,
      isWeb: false,
      read: (_) async => document(),
      write: (_, __) async {},
      fetch: (_) async => throw StateError('offline'),
    ).resolve();

    expect(endpoints.headOrigin.host, 'sync-next.festapp.net');
  });

  test('rejects a foreign tenant and unsafe origins, then uses fallback',
      () async {
    for (final invalid in [
      jsonEncode({
        'schemaVersion': 1,
        'tenantId': 'other',
        'syncHeadOrigin': 'https://sync-next.festapp.net',
        'syncAssetOrigin': 'https://assets-next.festapp.net',
      }),
      document(head: 'http://sync-next.festapp.net'),
      document(assets: 'https://assets-next.festapp.net/path'),
    ]) {
      final endpoints = await ClientSyncEndpointService(
        tenantId: tenant,
        configUrl: 'https://festival.example/client-sync-config.json',
        fallbackHeadOrigin: fallbackHead,
        fallbackAssetOrigin: fallbackAssets,
        isWeb: false,
        read: (_) async => null,
        write: (_, __) async {},
        fetch: (_) async => utf8.encode(invalid),
      ).resolve();
      expect(endpoints.headOrigin, Uri.parse(fallbackHead));
      expect(endpoints.assetOrigin, Uri.parse(fallbackAssets));
    }
  });

  test('web client stays bound to its compiled deployment configuration',
      () async {
    var fetched = false;
    final endpoints = await ClientSyncEndpointService(
      tenantId: tenant,
      configUrl: 'https://festival.example/client-sync-config.json',
      fallbackHeadOrigin: fallbackHead,
      fallbackAssetOrigin: fallbackAssets,
      isWeb: true,
      read: (_) async => null,
      write: (_, __) async {},
      fetch: (_) async {
        fetched = true;
        return utf8.encode(document());
      },
    ).resolve();

    expect(fetched, isFalse);
    expect(endpoints.headOrigin, Uri.parse(fallbackHead));
  });
}
