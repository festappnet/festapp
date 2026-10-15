import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:festapp_core/sync.dart';
import 'package:http/http.dart' as http;

class PublicHeadResult {
  const PublicHeadResult({required this.notModified, this.head});
  final bool notModified;
  final PublicSyncHead? head;
}

abstract interface class PublicSyncHeadRemote {
  Future<PublicHeadResult> getHead(SyncContext context);
}

abstract interface class PublicComponentRemote {
  Future<List<int>> download(
    ArtifactDescriptor descriptor, {
    required int maxBytes,
  });
}

abstract interface class PrivateSyncRemote {
  Future<PrivateSyncResponse> getChanges(
    SyncContext context,
    Map<ClientSyncComponent, int> knownVector,
  );
}

typedef ArtifactRequestUriResolver = Uri Function(Uri artifactUri);

Uri resolvePublicArtifactRequestUriForPage(Uri artifactUri, Uri pageUri) {
  const localHosts = {'localhost', '127.0.0.1', '::1'};
  if (!localHosts.contains(pageUri.host) ||
      artifactUri.scheme != 'https' ||
      artifactUri.host != 'assets.festapp.net') {
    return artifactUri;
  }
  return pageUri.replace(
    path: '/__festapp_sync_asset__${artifactUri.path}',
    query: artifactUri.hasQuery ? artifactUri.query : null,
    fragment: null,
  );
}

class HttpPublicSyncRemote
    implements PublicSyncHeadRemote, PublicComponentRemote {
  HttpPublicSyncRemote({
    required this.headOrigin,
    required this.artifactOrigin,
    this.artifactRequestUriResolver,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final Uri headOrigin;
  final Uri artifactOrigin;
  final ArtifactRequestUriResolver? artifactRequestUriResolver;
  final http.Client _client;
  final Map<String, String> _etags = {};
  int _headPollSequence = 0;

  @override
  Future<PublicHeadResult> getHead(SyncContext context) async {
    final baseUri = headOrigin.resolve(
      '/v1/public-sync/${context.organizationId}/${context.occasionId}/head',
    );
    // The head is mutable. A unique query keeps browser/URLSession caches from
    // serving an hours-old 200 response even if an intermediary accidentally
    // broadens Cache-Control. The worker canonicalizes this query for its
    // five-second edge cache, while If-None-Match still makes unchanged polls
    // bodyless.
    final uri = baseUri.replace(
      queryParameters: {
        ...baseUri.queryParameters,
        'poll':
            '${DateTime.now().toUtc().microsecondsSinceEpoch}-${_headPollSequence++}',
      },
    );
    final response = await _client.get(
      uri,
      headers: {
        'Accept': 'application/json',
        if (_etags[context.publicScope] case final etag?) 'If-None-Match': etag,
      },
    );
    if (response.statusCode == 304) {
      return const PublicHeadResult(notModified: true);
    }
    if (response.statusCode != 200) {
      throw http.ClientException(
        'Public sync head returned ${response.statusCode}',
        uri,
      );
    }
    if (response.bodyBytes.length > 16 * 1024) {
      throw const FormatException('Public sync head exceeds 16 KiB');
    }
    final etag = response.headers['etag'];
    if (etag != null) _etags[context.publicScope] = etag;
    return PublicHeadResult(
      notModified: false,
      head: PublicSyncHead.fromJson(
        (jsonDecode(utf8.decode(response.bodyBytes)) as Map)
            .cast<String, dynamic>(),
      ),
    );
  }

  @override
  Future<List<int>> download(
    ArtifactDescriptor descriptor, {
    required int maxBytes,
  }) async {
    if (artifactOrigin.scheme != 'https' ||
        descriptor.url.scheme != artifactOrigin.scheme ||
        descriptor.url.host != artifactOrigin.host ||
        descriptor.url.port != artifactOrigin.port) {
      throw const FormatException('Public sync artifact origin is not allowed');
    }
    if (descriptor.bytes < 0 || descriptor.bytes > maxBytes) {
      throw FormatException('Artifact size is outside the component budget');
    }
    final requestUri =
        artifactRequestUriResolver?.call(descriptor.url) ?? descriptor.url;
    final response = await _client.get(
      requestUri,
      headers: {'Accept': descriptor.mediaType},
    );
    if (response.statusCode != 200) {
      throw http.ClientException(
        'Artifact returned ${response.statusCode}',
        requestUri,
      );
    }
    final bytes = response.bodyBytes;
    if (bytes.length != descriptor.bytes || bytes.length > maxBytes) {
      throw const FormatException('Artifact byte length mismatch');
    }
    if (sha256.convert(bytes).toString() != descriptor.sha256.toLowerCase()) {
      throw const FormatException('Artifact SHA-256 mismatch');
    }
    return bytes;
  }
}
