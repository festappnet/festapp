import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/services/storage_helper.dart';
import 'package:http/http.dart' as http;

typedef ClientSyncEndpointRead = Future<String?> Function(String key);
typedef ClientSyncEndpointWrite = Future<void> Function(
    String key, String value);
typedef ClientSyncEndpointFetch = Future<List<int>> Function(Uri uri);

class ClientSyncEndpoints {
  const ClientSyncEndpoints(
      {required this.headOrigin, required this.assetOrigin});

  final Uri headOrigin;
  final Uri assetOrigin;
}

/// Resolves public sync endpoints from a tenant-owned runtime document.
///
/// Native releases keep their compiled endpoints as an offline fallback, while
/// a valid document on the stable tenant web origin can move both endpoints
/// without another store release. The document contains public origins only.
class ClientSyncEndpointService {
  ClientSyncEndpointService({
    String? tenantId,
    String? configUrl,
    String? fallbackHeadOrigin,
    String? fallbackAssetOrigin,
    bool? isWeb,
    ClientSyncEndpointRead? read,
    ClientSyncEndpointWrite? write,
    ClientSyncEndpointFetch? fetch,
  })  : tenantId = tenantId ?? AppConfig.clientSyncTenantId,
        configUrl = configUrl ??
            '${AppConfig.webLink.replaceFirst(RegExp(r'/+$'), '')}/client-sync-config.json',
        fallbackHeadOrigin = fallbackHeadOrigin ?? AppConfig.syncHeadOrigin,
        fallbackAssetOrigin = fallbackAssetOrigin ?? AppConfig.syncAssetOrigin,
        isWeb = isWeb ?? kIsWeb,
        _read = read ?? ((key) => StorageHelper.get(key)),
        _write = write ?? ((key, value) => StorageHelper.set(key, value)),
        _fetch = fetch ?? _fetchConfig;

  static const int schemaVersion = 1;
  static const String _cachePrefix = 'client_sync_endpoints_v1/';

  final String tenantId;
  final String configUrl;
  final String fallbackHeadOrigin;
  final String fallbackAssetOrigin;
  final bool isWeb;
  final ClientSyncEndpointRead _read;
  final ClientSyncEndpointWrite _write;
  final ClientSyncEndpointFetch _fetch;

  Future<ClientSyncEndpoints> resolve() async {
    final fallback = _parseOrigins(fallbackHeadOrigin, fallbackAssetOrigin);
    if (isWeb || tenantId.isEmpty || configUrl.isEmpty) return fallback;

    final cacheKey = '$_cachePrefix$tenantId';
    try {
      final bytes = await _fetch(Uri.parse(configUrl))
          .timeout(const Duration(seconds: 2));
      final encoded = utf8.decode(bytes);
      final resolved = _parseDocument(encoded);
      await _write(cacheKey, encoded);
      return resolved;
    } catch (_) {
      try {
        final cached = await _read(cacheKey);
        if (cached != null) return _parseDocument(cached);
      } catch (_) {
        // The compiled pair remains the final offline fallback.
      }
      return fallback;
    }
  }

  ClientSyncEndpoints _parseDocument(String source) {
    final value = jsonDecode(source);
    if (value is! Map<String, dynamic> ||
        value.length != 4 ||
        value['schemaVersion'] != schemaVersion ||
        value['tenantId'] != tenantId ||
        value['syncHeadOrigin'] is! String ||
        value['syncAssetOrigin'] is! String) {
      throw const FormatException('Invalid client sync runtime configuration');
    }
    return _parseOrigins(
      value['syncHeadOrigin'] as String,
      value['syncAssetOrigin'] as String,
    );
  }

  static ClientSyncEndpoints _parseOrigins(String head, String asset) =>
      ClientSyncEndpoints(
        headOrigin: _parseHttpsOrigin(head),
        assetOrigin: _parseHttpsOrigin(asset),
      );

  static Uri _parseHttpsOrigin(String value) {
    final uri = Uri.parse(value);
    if (uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.path.isNotEmpty && uri.path != '/' ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const FormatException(
          'Client sync endpoint must be an HTTPS origin');
    }
    return uri.replace(path: '');
  }

  static Future<List<int>> _fetchConfig(Uri uri) async {
    final response =
        await http.get(uri, headers: const {'cache-control': 'no-cache'});
    if (response.statusCode != 200) {
      throw StateError('Client sync config returned ${response.statusCode}');
    }
    return response.bodyBytes;
  }
}
