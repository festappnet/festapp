import 'dart:convert';
import 'package:festapp_core/sync.dart';
import 'memory_sync_storage.dart';

class PublicFixture implements PublicSyncHeadRemote, PublicComponentRemote {
  PublicFixture({
    required bool validMapClosure,
    String componentScope = '1/2',
    List<String> mediaUrls = const [],
  }) {
    final payloads = <ClientSyncComponent, Object?>{
      ClientSyncComponent.occasionConfig: <String, Object?>{
        'media': [
          for (var i = 0; i < mediaUrls.length; i++)
            {'id': i + 1, 'url': mediaUrls[i]},
        ],
      },
      ClientSyncComponent.programCatalog: {'events': <Object?>[]},
      ClientSyncComponent.mapCatalog: {
        'places': [
          {'id': 1, 'icon': validMapClosure ? 10 : 11},
        ],
        'placeTypes': <Object?>[],
        'paths': <Object?>[],
        'icons': [
          {'id': 10, 'svg': '<svg />'},
        ],
      },
      ClientSyncComponent.contentCatalog: <String, Object?>{},
      ClientSyncComponent.unitCatalog: <String, Object?>{},
    };
    final descriptors = <String, Object?>{};
    var digestIndex = 1;
    for (final entry in payloads.entries) {
      final uri = Uri.parse('https://assets.test/${entry.key.wireName}.json');
      final bytes = utf8.encode(
        jsonEncode({
          'protocol': 1,
          'schema': 1,
          'component': entry.key.wireName,
          'scope': componentScope,
          'revision': 1,
          'generatedAt': '2026-08-03T00:00:00Z',
          'payload': entry.value,
        }),
      );
      _bytes[uri] = bytes;
      descriptors[entry.key.wireName] = _descriptor(
        uri,
        bytes.length,
        1,
        digestIndex.toString().padLeft(64, '0'),
      );
      digestIndex++;
    }
    final manifest = utf8.encode(
      jsonEncode({
        'protocol': 1,
        'schema': 1,
        'scope': '1/2',
        'releaseRevision': 1,
        'generatedAt': '2026-08-03T00:00:00Z',
        'components': descriptors,
      }),
    );
    _bytes[_manifestUri] = manifest;
    _head = PublicSyncHead(
      protocol: 1,
      serverTime: DateTime.utc(2026, 8, 3),
      catalog: ArtifactDescriptor.fromJson(
        _descriptor(_manifestUri, manifest.length, 1, 'f'.padLeft(64, 'f')),
      ),
      live: null,
      publicationPending: false,
    );
  }

  static final _manifestUri = Uri.parse('https://assets.test/manifest.json');
  final Map<Uri, List<int>> _bytes = {};
  late final PublicSyncHead _head;
  int headCalls = 0;

  static Map<String, dynamic> _descriptor(
    Uri uri,
    int bytes,
    int revision,
    String digest,
  ) => {
    'revision': revision,
    'mediaType': 'application/json',
    'url': uri.toString(),
    'sha256': digest,
    'bytes': bytes,
  };

  @override
  Future<PublicHeadResult> getHead(SyncContext context) async {
    headCalls++;
    return PublicHeadResult(notModified: false, head: _head);
  }

  @override
  Future<List<int>> download(
    ArtifactDescriptor descriptor, {
    required int maxBytes,
  }) async => _bytes[descriptor.url]!;
}

class NoPrivateRemote implements PrivateSyncRemote {
  @override
  Future<PrivateSyncResponse> getChanges(
    SyncContext context,
    Map<ClientSyncComponent, int> knownVector,
  ) => throw StateError('private sync was not expected');
}

class CountingPrivateRemote implements PrivateSyncRemote {
  int calls = 0;

  @override
  Future<PrivateSyncResponse> getChanges(
    SyncContext context,
    Map<ClientSyncComponent, int> knownVector,
  ) async {
    calls++;
    return PrivateSyncResponse(
      serverTime: DateTime.utc(2026, 8, 3),
      vector: const {},
      replacements: const [],
    );
  }
}

class CompanionPrivateRemote implements PrivateSyncRemote {
  @override
  Future<PrivateSyncResponse> getChanges(
    SyncContext context,
    Map<ClientSyncComponent, int> knownVector,
  ) async {
    final vector = {
      for (final component in ClientSyncComponent.values)
        if (component.isPrivate) component: 1,
    };
    return PrivateSyncResponse(
      serverTime: DateTime.utc(2026, 8, 5),
      vector: vector,
      replacements: [
        for (final component in vector.keys)
          PrivateComponentReplacement(
            component: component,
            revision: 1,
            payload: component == ClientSyncComponent.privateProgram
                ? <String, dynamic>{
                    'signedIn': [42],
                    'saved': <int>[],
                  }
                : <String, dynamic>{},
          ),
      ],
    );
  }
}

class RepairingPrivateRemote implements PrivateSyncRemote {
  Map<ClientSyncComponent, int>? receivedKnownVector;

  @override
  Future<PrivateSyncResponse> getChanges(
    SyncContext context,
    Map<ClientSyncComponent, int> knownVector,
  ) async {
    receivedKnownVector = Map.of(knownVector);
    final vector = {
      for (final component in ClientSyncComponent.values)
        if (component.isPrivate) component: 1,
    };
    return PrivateSyncResponse(
      serverTime: DateTime.utc(2026, 8, 3),
      vector: vector,
      replacements: [
        for (final component in vector.keys)
          if (!knownVector.containsKey(component))
            PrivateComponentReplacement(
              component: component,
              revision: 1,
              payload: <String, dynamic>{},
            ),
      ],
    );
  }
}

class Activation {
  const Activation(this.scope, this.type, this.payloads);
  final String scope;
  final SyncFreshnessClass type;
  final Map<ClientSyncComponent, Object?> payloads;
}

class MemoryStore extends ClientSyncStore {
  factory MemoryStore({
    StoredSyncGeneration? initialCatalog,
    StoredSyncGeneration? initialPrivate,
  }) => MemoryStore._(MemorySyncStorage(), initialCatalog, initialPrivate);
  MemoryStore._(this.storage, this.initialCatalog, this.initialPrivate)
    : super(storage: storage);
  final MemorySyncStorage storage;
  final StoredSyncGeneration? initialCatalog;
  final StoredSyncGeneration? initialPrivate;
  final List<Activation> activations = [];
  final _seeded = <String>{};

  @override
  Future<StoredSyncGeneration?> activeGeneration(
    String scope,
    SyncFreshnessClass type,
  ) async {
    final initial = switch (type) {
      SyncFreshnessClass.catalog => initialCatalog,
      SyncFreshnessClass.privateIdentity => initialPrivate,
      SyncFreshnessClass.live => null,
    };
    if (_seeded.add('$scope/${type.name}') && initial != null) {
      // Deliberately seed an incomplete persisted generation, as in the original
      // regression fixtures. All subsequent reads/activations use the real store.
      storage.values['pointer/$scope/${type.name}'] = initial.pointer;
      storage.values['generation/$scope/${type.name}/${initial.pointer}'] =
          jsonEncode({
            'revisions': initial.revisions.map(
              (k, v) => MapEntry(k.wireName, v),
            ),
            'updatedAt': initial.updatedAt.toIso8601String(),
          });
    }
    return super.activeGeneration(scope, type);
  }

  @override
  Future<bool> activateGuarded({
    required String scope,
    required SyncFreshnessClass type,
    required String pointer,
    required DateTime updatedAt,
    required Map<ClientSyncComponent, int> revisions,
    required Map<ClientSyncComponent, Object?> payloads,
    required bool Function() precondition,
  }) async {
    final applied = await super.activateGuarded(
      scope: scope,
      type: type,
      pointer: pointer,
      updatedAt: updatedAt,
      revisions: revisions,
      payloads: payloads,
      precondition: precondition,
    );
    if (applied) activations.add(Activation(scope, type, payloads));
    return applied;
  }
}
