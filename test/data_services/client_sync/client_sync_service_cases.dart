import 'package:flutter_test/flutter_test.dart';
import 'package:festapp_core/sync.dart';
import 'package:fstapp/data_services/client_sync/client_sync_projection.dart';
import '../../../packages/festapp_core/test/support/sync_fixtures.dart';
import 'package:timezone/data/latest.dart' as timezone_data;
import 'package:timezone/timezone.dart' as timezone;

void main() {
  setUpAll(() {
    timezone_data.initializeTimeZones();
    timezone.setLocalLocation(timezone.getLocation('Europe/Prague'));
  });
  test(
      'a companion self-login caches owner-created attendance for offline projection',
      () async {
    final fixture = PublicFixture(validMapClosure: true);
    final private = CompanionPrivateRemote();
    final store = MemoryStore();
    final service = ClientSyncService(
      publicHeadRemote: fixture,
      publicComponentRemote: fixture,
      privateRemote: private,
      store: store,
      clock: () => DateTime.utc(2026, 8, 5),
    );
    const companionContext = SyncContext(
      organizationId: 1,
      occasionId: 2,
      occasionLink: 'companion-test',
      userId: 'companion-user',
      identityEpoch: 1,
    );

    await service.open(companionContext).first;
    await service.refresh(reason: SyncReason.login, privateConsumer: true);

    final activation = store.activations.singleWhere(
      (item) => item.type == SyncFreshnessClass.privateIdentity,
    );
    expect(activation.scope, '1/2/companion-user/1');
    final privateProgram = activation
        .payloads[ClientSyncComponent.privateProgram] as Map<String, dynamic>;
    expect(privateProgram['signedIn'], [42]);

    final offlineEvents = ClientSyncProjection.projectEvents(
      catalog: const {
        'events': [
          {
            'id': 42,
            'title': 'Owner-created attendance fixture',
            'startTime': '2026-08-12T10:00:00Z',
            'endTime': '2026-08-12T11:00:00Z',
          },
        ],
      },
      map: const {},
      live: const {},
      privateProgram: privateProgram,
    );
    expect(offlineEvents.single.isSignedIn, isTrue);
    await service.dispose();
  });
}
