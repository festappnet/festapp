import 'dart:io';

import 'package:festapp_core/sync.dart';
import 'package:fstapp/data_services/client_sync/sembast_client_sync_storage.dart';
import 'package:sembast/sembast_io.dart';
import 'package:test/test.dart';

void main() {
  test('native sync storage persists an atomic replacement across reopen',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('festapp-sync-storage-');
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/sync.db';
    var database = await databaseFactoryIo.openDatabase(path);
    addTearDown(() => database.close());
    final adapter = SembastClientSyncStorage(() async => database);
    final store = ClientSyncStore(storage: adapter);
    Future<void> activate(String pointer, int revision) => store.activate(
          scope: '9/643',
          type: SyncFreshnessClass.live,
          pointer: pointer,
          updatedAt: DateTime.utc(2026, 10, 15),
          revisions: {ClientSyncComponent.livePublic: revision},
          payloads: {
            ClientSyncComponent.livePublic: {'revision': revision}
          },
        );
    await adapter.replaceAtomic({'other-scope': 'retained'});
    await activate('old', 1);
    await activate('new', 2);
    await database.close();
    database = await databaseFactoryIo.openDatabase(path);
    expect(
        (await store.activeGeneration('9/643', SyncFreshnessClass.live))!
            .pointer,
        'new');
    expect(
        await store.readComponent(
            '9/643', SyncFreshnessClass.live, ClientSyncComponent.livePublic),
        {'revision': 2});
    expect(await adapter.get('other-scope'), 'retained');
    expect(
        (await adapter.keys()).where((key) => key.contains('/old')), isEmpty);
  });

  test('owned native handles isolate A-B-A and close before directory deletion',
      () async {
    for (final identity in ['A', 'B', 'A']) {
      final directory =
          await Directory.systemTemp.createTemp('festapp-sync-$identity-');
      try {
        final database =
            await databaseFactoryIo.openDatabase('${directory.path}/sync.db');
        try {
          final adapter = SembastClientSyncStorage(() async => database);
          expect(await adapter.keys(), isEmpty);
          await adapter.replaceAtomic({'identity': identity});
          expect(await adapter.get('identity'), identity);
        } finally {
          await database.close();
        }
      } finally {
        await directory.delete(recursive: true);
      }
    }
  });
}
