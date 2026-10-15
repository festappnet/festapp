import 'package:test/test.dart';
import 'package:festapp_core/sync.dart';
import '../support/sync_fixtures.dart';

void main() {
  const context = SyncContext(
    organizationId: 1,
    occasionId: 2,
    occasionLink: 'test',
    identityEpoch: 0,
  );

  test(
    'a complete valid public release activates one catalog generation',
    () async {
      final fixture = PublicFixture(validMapClosure: true);
      final store = MemoryStore();
      final service = ClientSyncService(
        publicHeadRemote: fixture,
        publicComponentRemote: fixture,
        privateRemote: NoPrivateRemote(),
        store: store,
        clock: () => DateTime.utc(2026, 8, 3),
      );

      await service.open(context).first;
      await service.refresh(reason: SyncReason.bootstrap);

      expect(store.activations, hasLength(1));
      expect(store.activations.single.type, SyncFreshnessClass.catalog);
      expect(
        store.activations.single.payloads.keys,
        containsAll(ReleaseManifest.requiredComponents),
      );
      await service.dispose();
    },
  );

  test(
    'catalog activation schedules every occasion media URL for caching',
    () async {
      final fixture = PublicFixture(
        validMapClosure: true,
        mediaUrls: const [
          'https://img.festapp.net/description-a.webp',
          'https://img.festapp.net/header-b.jpg',
        ],
      );
      final cached = <Uri>[];
      final service = ClientSyncService(
        publicHeadRemote: fixture,
        publicComponentRemote: fixture,
        privateRemote: NoPrivateRemote(),
        store: MemoryStore(),
        cacheOccasionMedia: (_, urls, {required refreshExisting}) async {
          expect(refreshExisting, isTrue);
          cached.addAll(urls);
        },
        clock: () => DateTime.utc(2026, 8, 3),
      );

      await service.open(context).first;
      await service.refresh(reason: SyncReason.bootstrap);

      expect(cached, [
        Uri.parse('https://img.festapp.net/description-a.webp'),
        Uri.parse('https://img.festapp.net/header-b.jpg'),
      ]);
      await service.dispose();
    },
  );

  test(
    'a dangling map icon keeps the previous public generation active',
    () async {
      final fixture = PublicFixture(validMapClosure: false);
      final store = MemoryStore();
      final service = ClientSyncService(
        publicHeadRemote: fixture,
        publicComponentRemote: fixture,
        privateRemote: NoPrivateRemote(),
        store: store,
        clock: () => DateTime.utc(2026, 8, 3),
      );

      await service.open(context).first;
      await service.refresh(reason: SyncReason.bootstrap);

      expect(store.activations, isEmpty);
      await service.dispose();
    },
  );

  test(
    'reconnect refreshes immediately and resumes periodic synchronization',
    () async {
      final fixture = PublicFixture(validMapClosure: true);
      final service = ClientSyncService(
        publicHeadRemote: fixture,
        publicComponentRemote: fixture,
        privateRemote: NoPrivateRemote(),
        store: MemoryStore(),
        clock: () => DateTime.utc(2026, 8, 3),
      );

      await service.open(context).first;
      await service.reconnect();

      expect(fixture.headCalls, 1);
      await service.dispose();
    },
  );

  test(
    'failed public activations do not advance the private-tick cadence',
    () async {
      final fixture = PublicFixture(validMapClosure: false);
      final private = CountingPrivateRemote();
      var now = DateTime.utc(2026, 8, 3);
      final service = ClientSyncService(
        publicHeadRemote: fixture,
        publicComponentRemote: fixture,
        privateRemote: private,
        store: MemoryStore(),
        clock: () => now,
      );
      const authenticated = SyncContext(
        organizationId: 1,
        occasionId: 2,
        occasionLink: 'test',
        userId: 'user-a',
        identityEpoch: 1,
      );

      await service.open(authenticated).first;
      for (var i = 0; i < 5; i++) {
        await service.refresh(reason: SyncReason.timer, privateConsumer: true);
        now = now.add(const Duration(minutes: 5));
      }

      expect(private.calls, 0);
      await service.dispose();
    },
  );

  test('a component artifact from another scope is never activated', () async {
    final fixture = PublicFixture(
      validMapClosure: true,
      componentScope: '1/999',
    );
    final store = MemoryStore();
    final service = ClientSyncService(
      publicHeadRemote: fixture,
      publicComponentRemote: fixture,
      privateRemote: NoPrivateRemote(),
      store: store,
      clock: () => DateTime.utc(2026, 8, 3),
    );

    await service.open(context).first;
    await service.refresh(reason: SyncReason.bootstrap);

    expect(store.activations, isEmpty);
    await service.dispose();
  });

  test(
    'a catalog that regresses an active component is never activated',
    () async {
      final fixture = PublicFixture(validMapClosure: true);
      final store = MemoryStore(
        initialCatalog: StoredSyncGeneration(
          pointer: 'newer-generation',
          revisions: {
            for (final component in ReleaseManifest.requiredComponents)
              component: 2,
          },
          updatedAt: DateTime.utc(2026, 8, 3),
        ),
      );
      final service = ClientSyncService(
        publicHeadRemote: fixture,
        publicComponentRemote: fixture,
        privateRemote: NoPrivateRemote(),
        store: store,
        clock: () => DateTime.utc(2026, 8, 3),
      );

      await service.open(context).first;
      await service.refresh(reason: SyncReason.bootstrap);

      expect(store.activations, isEmpty);
      await service.dispose();
    },
  );

  test(
    'a matching catalog pointer repairs missing component payloads',
    () async {
      final fixture = PublicFixture(validMapClosure: true);
      final store = MemoryStore(
        initialCatalog: StoredSyncGeneration(
          pointer: 'f'.padLeft(64, 'f'),
          revisions: {
            for (final component in ReleaseManifest.requiredComponents)
              component: 1,
          },
          updatedAt: DateTime.utc(2026, 8, 3),
        ),
      );
      final service = ClientSyncService(
        publicHeadRemote: fixture,
        publicComponentRemote: fixture,
        privateRemote: NoPrivateRemote(),
        store: store,
        clock: () => DateTime.utc(2026, 8, 3),
      );

      await service.open(context).first;
      await service.refresh(reason: SyncReason.bootstrap);

      expect(store.activations, hasLength(1));
      expect(
        store.activations.single.payloads.keys,
        containsAll(ReleaseManifest.requiredComponents),
      );
      await service.dispose();
    },
  );

  test('private sync does not advertise a missing cached payload', () async {
    final fixture = PublicFixture(validMapClosure: true);
    final private = RepairingPrivateRemote();
    final privateRevisions = {
      for (final component in ClientSyncComponent.values)
        if (component.isPrivate) component: 1,
    };
    final store = MemoryStore(
      initialPrivate: StoredSyncGeneration(
        pointer: 'private',
        revisions: privateRevisions,
        updatedAt: DateTime.utc(2026, 8, 3),
      ),
    );
    const authenticated = SyncContext(
      organizationId: 1,
      occasionId: 2,
      occasionLink: 'test',
      userId: 'user-a',
      identityEpoch: 1,
    );
    final service = ClientSyncService(
      publicHeadRemote: fixture,
      publicComponentRemote: fixture,
      privateRemote: private,
      store: store,
      clock: () => DateTime.utc(2026, 8, 3),
    );

    await service.open(authenticated).first;
    await service.refresh(reason: SyncReason.bootstrap, privateConsumer: true);

    expect(private.receivedKnownVector, isEmpty);
    final activation = store.activations.singleWhere(
      (item) => item.type == SyncFreshnessClass.privateIdentity,
    );
    expect(activation.payloads.keys, containsAll(privateRevisions.keys));
    await service.dispose();
  });
}
