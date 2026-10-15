import 'dart:async';

import 'package:festapp_core/sync.dart';
import 'package:test/test.dart';

import '../support/memory_sync_storage.dart';
import '../support/sync_fixtures.dart';

const _context = SyncContext(
  organizationId: 1,
  occasionId: 2,
  occasionLink: 'test',
  identityEpoch: 0,
);

void main() {
  test(
    'failed atomic activation retains pointer, payload and another scope',
    () async {
      final storage = MemorySyncStorage();
      final store = ClientSyncStore(storage: storage);
      Future<void> activate(String scope, String pointer, int revision) =>
          store.activate(
            scope: scope,
            type: SyncFreshnessClass.live,
            pointer: pointer,
            updatedAt: DateTime.utc(2026, 10, 15),
            revisions: {ClientSyncComponent.livePublic: revision},
            payloads: {
              ClientSyncComponent.livePublic: {'revision': revision},
            },
          );
      await activate('1/2', 'old', 1);
      await activate('1/3', 'other', 7);
      final before = Map.of(storage.values);
      storage.failNextCommit = true;
      await expectLater(activate('1/2', 'new', 2), throwsStateError);
      expect(storage.values, before);
      expect(
        (await store.activeGeneration('1/2', SyncFreshnessClass.live))!.pointer,
        'old',
      );
      // A failed operation cannot poison the serialized mutation queue.
      await activate('1/2', 'new', 2);
      expect(
        (await store.activeGeneration('1/3', SyncFreshnessClass.live))!.pointer,
        'other',
      );
    },
  );

  test(
    'a stale in-flight head cannot activate after context changes',
    () async {
      final fixture = PublicFixture(validMapClosure: true);
      final remote = _DelayedHead(fixture);
      final store = MemoryStore();
      final service = ClientSyncService(
        publicHeadRemote: remote,
        publicComponentRemote: fixture,
        privateRemote: NoPrivateRemote(),
        store: store,
      );
      addTearDown(service.dispose);
      await service.open(_context).first;
      final oldRefresh = service.refresh(reason: SyncReason.bootstrap);
      await remote.entered.future;
      await service
          .open(
            const SyncContext(
              organizationId: 1,
              occasionId: 3,
              occasionLink: 'other',
              identityEpoch: 1,
            ),
          )
          .first;
      remote.release.complete();
      await oldRefresh;
      expect(store.activations, isEmpty);
      expect(
        await store.activeGeneration('1/2', SyncFreshnessClass.catalog),
        isNull,
      );
    },
  );

  test(
    'dispose fences in-flight work and does not clear borrowed storage',
    () async {
      final fixture = PublicFixture(validMapClosure: true);
      final remote = _DelayedHead(fixture);
      final store = MemoryStore();
      store.storage.values['borrowed-resource'] = 'retained';
      final service = ClientSyncService(
        publicHeadRemote: remote,
        publicComponentRemote: fixture,
        privateRemote: NoPrivateRemote(),
        store: store,
      );
      await service.open(_context).first;
      final refresh = service.refresh(reason: SyncReason.bootstrap);
      await remote.entered.future;
      await service.dispose();
      remote.release.complete();
      await refresh;
      expect(store.activations, isEmpty);
      expect(store.storage.values['borrowed-resource'], 'retained');
    },
  );
}

class _DelayedHead implements PublicSyncHeadRemote {
  _DelayedHead(this.delegate);
  final PublicSyncHeadRemote delegate;
  final entered = Completer<void>();
  final release = Completer<void>();
  @override
  Future<PublicHeadResult> getHead(SyncContext context) async {
    entered.complete();
    await release.future;
    return delegate.getHead(context);
  }
}
