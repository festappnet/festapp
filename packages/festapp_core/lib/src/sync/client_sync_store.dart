import 'dart:convert';
import 'dart:async';

import 'package:festapp_core/sync.dart';

bool clientSyncRevisionsRegress(
  Map<ClientSyncComponent, int> current,
  Map<ClientSyncComponent, int> incoming,
) => current.entries.any(
  (entry) => incoming[entry.key] == null || incoming[entry.key]! < entry.value,
);

class StoredSyncGeneration {
  const StoredSyncGeneration({
    required this.pointer,
    required this.revisions,
    required this.updatedAt,
  });

  final String pointer;
  final Map<ClientSyncComponent, int> revisions;
  final DateTime updatedAt;
}

class StoredSyncContext {
  const StoredSyncContext({
    required this.organizationId,
    required this.occasionId,
    required this.occasionLink,
  });

  final int organizationId;
  final int occasionId;
  final String occasionLink;

  Map<String, dynamic> toJson() => {
    'organizationId': organizationId,
    'occasionId': occasionId,
    'occasionLink': occasionLink,
  };

  static StoredSyncContext? fromJson(Object? value) {
    if (value is! Map) return null;
    final organizationId = (value['organizationId'] as num?)?.toInt();
    final occasionId = (value['occasionId'] as num?)?.toInt();
    final occasionLink = value['occasionLink'] as String?;
    if (organizationId == null ||
        occasionId == null ||
        occasionLink == null ||
        occasionLink.isEmpty) {
      return null;
    }
    return StoredSyncContext(
      organizationId: organizationId,
      occasionId: occasionId,
      occasionLink: occasionLink,
    );
  }
}

/// Content-addressed client cache with scoped, atomically activated pointers.
class ClientSyncStore {
  ClientSyncStore({required ClientSyncStorage storage}) : _storage = storage;
  final ClientSyncStorage _storage;
  Future<void> _mutationTail = Future<void>.value();
  static const _lastContextKey = 'context/last';
  static const _blobIndexKey = 'blob/index';
  static const maxBlobCount = 16;
  static const maxBlobEncodedBytes = 8 * 1024 * 1024;

  String _blobKey(String digest) => 'blob/$digest';
  String _pointerKey(String scope, SyncFreshnessClass type) =>
      'pointer/$scope/${type.name}';
  String _generationKey(
    String scope,
    SyncFreshnessClass type,
    String pointer,
  ) => 'generation/$scope/${type.name}/$pointer';

  Future<bool> containsBlob(String sha256) async =>
      await _storage.get(_blobKey(sha256)) != null;

  Future<void> stageBlob(String sha256, List<int> bytes) =>
      _serializeMutation(() async {
        final encoded = base64Encode(bytes);
        final entries = await _readBlobIndex();
        entries.removeWhere((entry) => entry.sha256 == sha256);
        entries.add(_BlobEntry(sha256, encoded.length));
        final writes = <String, String?>{_blobKey(sha256): encoded};
        var total = entries.fold<int>(
          0,
          (sum, entry) => sum + entry.encodedBytes,
        );
        while (entries.length > maxBlobCount || total > maxBlobEncodedBytes) {
          final removed = entries.removeAt(0);
          total -= removed.encodedBytes;
          writes[_blobKey(removed.sha256)] = null;
        }
        writes[_blobIndexKey] = _encodeBlobIndex(entries);
        await _storage.replaceAtomic(writes);
      });

  Future<List<int>?> readBlob(String sha256) => _serializeMutation(() async {
    final value = await _storage.get(_blobKey(sha256));
    if (value == null) return null;
    final entries = await _readBlobIndex();
    final currentIndex = entries.indexWhere((entry) => entry.sha256 == sha256);
    final current = currentIndex < 0 ? null : entries[currentIndex];
    entries.removeWhere((entry) => entry.sha256 == sha256);
    entries.add(_BlobEntry(sha256, current?.encodedBytes ?? value.length));
    try {
      final bytes = base64Decode(value);
      await _storage.replaceAtomic({_blobIndexKey: _encodeBlobIndex(entries)});
      return bytes;
    } catch (_) {
      entries.removeWhere((entry) => entry.sha256 == sha256);
      await _storage.replaceAtomic({
        _blobKey(sha256): null,
        _blobIndexKey: _encodeBlobIndex(entries),
      });
      return null;
    }
  });

  Future<StoredSyncGeneration?> activeGeneration(
    String scope,
    SyncFreshnessClass type,
  ) async {
    final pointer = await _storage.get(_pointerKey(scope, type));
    if (pointer == null) return null;
    final raw = await _storage.get(_generationKey(scope, type, pointer));
    if (raw == null) return null;
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return StoredSyncGeneration(
      pointer: pointer,
      revisions: (json['revisions'] as Map<String, dynamic>).map(
        (key, value) =>
            MapEntry(ClientSyncComponentWireName.parse(key), value as int),
      ),
      updatedAt: DateTime.parse(json['updatedAt'] as String).toUtc(),
    );
  }

  Future<Object?> readComponent(
    String scope,
    SyncFreshnessClass type,
    ClientSyncComponent component,
  ) async {
    final generation = await activeGeneration(scope, type);
    if (generation == null) return null;
    final raw = await _storage.get(
      '${_generationKey(scope, type, generation.pointer)}/${component.wireName}',
    );
    return raw == null ? null : jsonDecode(raw);
  }

  /// Verifies the active generation as a usable offline snapshot, not merely
  /// as a pointer. A browser may retain generation metadata after individual
  /// values were evicted or an older write was interrupted.
  Future<bool> isGenerationComplete(
    String scope,
    SyncFreshnessClass type,
    Set<ClientSyncComponent> requiredComponents,
  ) async {
    final generation = await activeGeneration(scope, type);
    if (generation == null ||
        !generation.revisions.keys.toSet().containsAll(requiredComponents)) {
      return false;
    }
    for (final component in requiredComponents) {
      if (await readComponent(scope, type, component) == null) return false;
    }
    return true;
  }

  /// Stages all component references and switches the class pointer in the
  /// same transaction. Each consistency class is intentionally independent.
  Future<void> activate({
    required String scope,
    required SyncFreshnessClass type,
    required String pointer,
    required DateTime updatedAt,
    required Map<ClientSyncComponent, int> revisions,
    required Map<ClientSyncComponent, Object?> payloads,
  }) async {
    await _activate(
      scope: scope,
      type: type,
      pointer: pointer,
      updatedAt: updatedAt,
      revisions: revisions,
      payloads: payloads,
    );
  }

  Future<bool> activateGuarded({
    required String scope,
    required SyncFreshnessClass type,
    required String pointer,
    required DateTime updatedAt,
    required Map<ClientSyncComponent, int> revisions,
    required Map<ClientSyncComponent, Object?> payloads,
    required bool Function() precondition,
  }) => _activate(
    scope: scope,
    type: type,
    pointer: pointer,
    updatedAt: updatedAt,
    revisions: revisions,
    payloads: payloads,
    precondition: precondition,
  );

  Future<bool> _activate({
    required String scope,
    required SyncFreshnessClass type,
    required String pointer,
    required DateTime updatedAt,
    required Map<ClientSyncComponent, int> revisions,
    required Map<ClientSyncComponent, Object?> payloads,
    bool Function()? precondition,
  }) {
    return _serializeMutation(() async {
      if (precondition != null && !precondition()) return false;
      final current = await activeGeneration(scope, type);
      if (current != null &&
          clientSyncRevisionsRegress(current.revisions, revisions)) {
        return false;
      }
      if (precondition != null && !precondition()) return false;
      final prefix = _generationKey(scope, type, pointer);
      final metadata = jsonEncode({
        'revisions': revisions.map(
          (key, value) => MapEntry(key.wireName, value),
        ),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
      });
      await _storage.replaceAtomic(
        {
          prefix: metadata,
          for (final entry in payloads.entries)
            '$prefix/${entry.key.wireName}': jsonEncode(entry.value),
          _pointerKey(scope, type): pointer,
        },
        removePrefixes: ['generation/$scope/${type.name}/'],
      );
      return true;
    });
  }

  Future<void> clearPrivateScope(String scope) => _serializeMutation(() async {
    await _storage.replaceAtomic(
      {_pointerKey(scope, SyncFreshnessClass.privateIdentity): null},
      removePrefixes: [
        'generation/$scope/${SyncFreshnessClass.privateIdentity.name}/',
      ],
    );
  });

  Future<T> _serializeMutation<T>(Future<T> Function() mutation) {
    final completer = Completer<T>();
    _mutationTail = _mutationTail.then((_) async {
      try {
        completer.complete(await mutation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<void> saveLastContext(
    StoredSyncContext context, {
    String? privateScope,
  }) => _serializeMutation(() async {
    final publicScope = '${context.organizationId}/${context.occasionId}';
    final keys = await _storage.keys();
    final writes = <String, String?>{
      _lastContextKey: jsonEncode(context.toJson()),
    };
    for (final key in keys) {
      if (!_isGenerationOrPointer(key)) continue;
      if (_isRetainedScopeKey(key, publicScope, privateScope)) continue;
      writes[key] = null;
    }
    await _storage.replaceAtomic(writes);
    await _pruneUnindexedBlobs();
  });

  Future<StoredSyncContext?> readLastContext() async {
    final raw = await _storage.get(_lastContextKey);
    if (raw == null) return null;
    try {
      return StoredSyncContext.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  Future<void> clearLastContext() =>
      _storage.replaceAtomic({_lastContextKey: null});

  bool _isGenerationOrPointer(String key) =>
      key.startsWith('generation/') || key.startsWith('pointer/');

  bool _isRetainedScopeKey(
    String key,
    String publicScope,
    String? privateScope,
  ) {
    final publicCatalog =
        key.startsWith(
          'generation/$publicScope/${SyncFreshnessClass.catalog.name}/',
        ) ||
        key == 'pointer/$publicScope/${SyncFreshnessClass.catalog.name}';
    final publicLive =
        key.startsWith(
          'generation/$publicScope/${SyncFreshnessClass.live.name}/',
        ) ||
        key == 'pointer/$publicScope/${SyncFreshnessClass.live.name}';
    final currentPrivate =
        privateScope != null &&
        (key.startsWith(
              'generation/$privateScope/${SyncFreshnessClass.privateIdentity.name}/',
            ) ||
            key ==
                'pointer/$privateScope/${SyncFreshnessClass.privateIdentity.name}');
    return publicCatalog || publicLive || currentPrivate;
  }

  Future<List<_BlobEntry>> _readBlobIndex() async {
    final raw = await _storage.get(_blobIndexKey);
    if (raw == null) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map(
            (entry) => _BlobEntry(
              entry['sha256'] as String,
              (entry['encodedBytes'] as num).toInt(),
            ),
          )
          .where((entry) => entry.sha256.isNotEmpty && entry.encodedBytes >= 0)
          .toList();
    } catch (_) {
      return [];
    }
  }

  String _encodeBlobIndex(List<_BlobEntry> entries) => jsonEncode([
    for (final entry in entries)
      {'sha256': entry.sha256, 'encodedBytes': entry.encodedBytes},
  ]);

  Future<void> _pruneUnindexedBlobs() async {
    final entries = await _readBlobIndex();
    var total = entries.fold<int>(0, (sum, entry) => sum + entry.encodedBytes);
    final removed = <String>{};
    while (entries.length > maxBlobCount || total > maxBlobEncodedBytes) {
      final entry = entries.removeAt(0);
      total -= entry.encodedBytes;
      removed.add(_blobKey(entry.sha256));
    }
    final retained = entries.map((entry) => _blobKey(entry.sha256)).toSet();
    final writes = <String, String?>{
      _blobIndexKey: _encodeBlobIndex(entries),
      for (final key in removed) key: null,
    };
    for (final key in await _storage.keys()) {
      if (key.startsWith('blob/') &&
          key != _blobIndexKey &&
          !retained.contains(key)) {
        writes[key] = null;
      }
    }
    if (writes.isNotEmpty) await _storage.replaceAtomic(writes);
  }
}

class _BlobEntry {
  const _BlobEntry(this.sha256, this.encodedBytes);
  final String sha256;
  final int encodedBytes;
}

abstract interface class ClientSyncStorage {
  Future<String?> get(String key);
  Future<List<String>> keys();
  Future<void> replaceAtomic(
    Map<String, String?> writes, {
    List<String> removePrefixes = const [],
  });
}
