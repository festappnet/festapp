import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/data_services/client_sync/client_sync_protocol.dart';
import 'package:fstapp/data_services/client_sync/client_sync_store.dart';

void main() {
  test('cache activation rejects a lower component revision', () {
    expect(
      clientSyncRevisionsRegress(
        const {ClientSyncComponent.privateProgram: 8},
        const {ClientSyncComponent.privateProgram: 7},
      ),
      isTrue,
    );
    expect(
      clientSyncRevisionsRegress(
        const {ClientSyncComponent.privateProgram: 8},
        const {ClientSyncComponent.privateProgram: 9},
      ),
      isFalse,
    );
  });

  test('cache activation cannot silently drop an active component revision',
      () {
    expect(
      clientSyncRevisionsRegress(
        const {
          ClientSyncComponent.privateProgram: 8,
          ClientSyncComponent.privateProfile: 3,
        },
        const {ClientSyncComponent.privateProgram: 9},
      ),
      isTrue,
    );
  });

  test('activation atomically replaces the superseded generation', () async {
    final storage = _MemoryStorage();
    final store = ClientSyncStore(storage: storage);
    await store.activate(
      scope: '9/643',
      type: SyncFreshnessClass.live,
      pointer: 'one',
      updatedAt: DateTime.utc(2026, 8, 5),
      revisions: const {ClientSyncComponent.livePublic: 1},
      payloads: const {
        ClientSyncComponent.livePublic: {'revision': 1}
      },
    );
    await store.activate(
      scope: '9/643',
      type: SyncFreshnessClass.live,
      pointer: 'two',
      updatedAt: DateTime.utc(2026, 8, 5, 0, 0, 5),
      revisions: const {ClientSyncComponent.livePublic: 2},
      payloads: const {
        ClientSyncComponent.livePublic: {'revision': 2}
      },
    );
    expect(
        storage.values.keys
            .where((key) => key.startsWith('generation/9/643/live/')),
        hasLength(2));
    expect(
        (await store.activeGeneration('9/643', SyncFreshnessClass.live))
            ?.pointer,
        'two');
    expect(
        await store.readComponent(
            '9/643', SyncFreshnessClass.live, ClientSyncComponent.livePublic),
        {'revision': 2});
  });

  test('generation completeness detects a missing offline payload', () async {
    final storage = _MemoryStorage();
    final store = ClientSyncStore(storage: storage);
    await store.activate(
      scope: '9/643',
      type: SyncFreshnessClass.catalog,
      pointer: 'catalog',
      updatedAt: DateTime.utc(2026, 8, 6),
      revisions: const {ClientSyncComponent.programCatalog: 49},
      payloads: const {
        ClientSyncComponent.programCatalog: {'events': []}
      },
    );
    expect(
      await store.isGenerationComplete(
        '9/643',
        SyncFreshnessClass.catalog,
        const {ClientSyncComponent.programCatalog},
      ),
      isTrue,
    );

    storage.values.remove('generation/9/643/catalog/catalog/program_catalog');

    expect(
      await store.isGenerationComplete(
        '9/643',
        SyncFreshnessClass.catalog,
        const {ClientSyncComponent.programCatalog},
      ),
      isFalse,
    );
  });

  test('blob cache is bounded by item count and encoded byte budget', () async {
    final storage = _MemoryStorage();
    final store = ClientSyncStore(storage: storage);
    for (var index = 0; index < 17; index++) {
      await store.stageBlob('digest-$index', [index]);
    }
    expect(storage.values.keys.where((key) => key.startsWith('blob/digest-')),
        hasLength(16));
    expect(await store.containsBlob('digest-0'), isFalse);
    await store.stageBlob(
        'oversized', List<int>.filled(6 * 1024 * 1024 + 1, 1));
    expect(await store.containsBlob('oversized'), isFalse);
    final encodedBytes = storage.values.entries
        .where((entry) => entry.key.startsWith('blob/digest-'))
        .fold<int>(0, (sum, entry) => sum + entry.value.length);
    expect(
        encodedBytes, lessThanOrEqualTo(ClientSyncStore.maxBlobEncodedBytes));
  });

  test('reading a blob refreshes its LRU position', () async {
    final storage = _MemoryStorage();
    final store = ClientSyncStore(storage: storage);
    await store.stageBlob('old-read', [1]);
    await store.stageBlob('old-unread', [2]);
    expect(await store.readBlob('old-read'), [1]);
    for (var index = 0; index < 15; index++) {
      await store.stageBlob('new-$index', [index]);
    }
    expect(await store.containsBlob('old-read'), isTrue);
    expect(await store.containsBlob('old-unread'), isFalse);
  });

  test('context cleanup retains current public and private identity only',
      () async {
    final storage = _MemoryStorage();
    final store = ClientSyncStore(storage: storage);
    for (final scope in ['9/643', '9/999', '9/643/old/0', '9/643/current/2']) {
      final type = scope.split('/').length > 2
          ? SyncFreshnessClass.privateIdentity
          : SyncFreshnessClass.catalog;
      await store.activate(
        scope: scope,
        type: type,
        pointer: 'one',
        updatedAt: DateTime.utc(2026, 8, 5),
        revisions: {
          type == SyncFreshnessClass.catalog
              ? ClientSyncComponent.programCatalog
              : ClientSyncComponent.privateProgram: 1
        },
        payloads: {
          type == SyncFreshnessClass.catalog
              ? ClientSyncComponent.programCatalog
              : ClientSyncComponent.privateProgram: const {}
        },
      );
    }
    await store.saveLastContext(
      const StoredSyncContext(
          organizationId: 9, occasionId: 643, occasionLink: 'csmostrava2026'),
      privateScope: '9/643/current/2',
    );
    expect(storage.values.keys.any((key) => key.contains('9/999')), isFalse);
    expect(storage.values.keys.any((key) => key.contains('/old/0')), isFalse);
    expect(
        storage.values.keys.any((key) => key.contains('/current/2')), isTrue);
    expect(await store.activeGeneration('9/643', SyncFreshnessClass.catalog),
        isNotNull);
  });
}

class _MemoryStorage implements ClientSyncStorage {
  final values = <String, String>{};

  @override
  Future<String?> get(String key) async => values[key];

  @override
  Future<List<String>> keys() async => values.keys.toList();

  @override
  Future<void> replaceAtomic(Map<String, String?> writes,
      {List<String> removePrefixes = const []}) async {
    for (final key in values.keys
        .where((key) => removePrefixes.any((prefix) => key.startsWith(prefix)))
        .toList()) {
      values.remove(key);
    }
    for (final entry in writes.entries) {
      if (entry.value == null) {
        values.remove(entry.key);
      } else {
        values[entry.key] = entry.value!;
      }
    }
  }
}
