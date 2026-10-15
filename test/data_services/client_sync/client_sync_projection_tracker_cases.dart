import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/data_services/client_sync/client_sync_projection_tracker.dart';

void main() {
  test('acknowledged command replacements do not remount the projection', () {
    final tracker = ClientSyncProjectionTracker();

    expect(
      tracker.observe(
        publicScope: '9/643',
        catalogPointer: 'catalog-1',
        livePointer: 'live-1',
        privateScope: '9/643/user/1',
        privatePointer: 'private-1',
      ),
      isTrue,
    );

    tracker.acknowledgePrivate(
      scope: '9/643/user/1',
      pointer: 'private-2',
    );
    tracker.acknowledgeLive(
      scope: '9/643',
      pointer: 'live-2',
    );
    tracker.acknowledgeCatalog(
      scope: '9/643',
      pointer: 'catalog-2',
    );

    expect(
      tracker.observe(
        publicScope: '9/643',
        catalogPointer: 'catalog-2',
        livePointer: 'live-2',
        privateScope: '9/643/user/1',
        privatePointer: 'private-2',
      ),
      isFalse,
    );
  });

  test('unacknowledged private and public changes still remount projection',
      () {
    final tracker = ClientSyncProjectionTracker();
    tracker.observe(
      publicScope: '9/643',
      catalogPointer: 'catalog-1',
      livePointer: 'live-1',
      privateScope: '9/643/user/1',
      privatePointer: 'private-1',
    );

    expect(
      tracker.observe(
        publicScope: '9/643',
        catalogPointer: 'catalog-1',
        livePointer: 'live-1',
        privateScope: '9/643/user/1',
        privatePointer: 'private-2',
      ),
      isTrue,
    );
    expect(
      tracker.observe(
        publicScope: '9/643',
        catalogPointer: 'catalog-2',
        livePointer: 'live-2',
        privateScope: '9/643/user/1',
        privatePointer: 'private-2',
      ),
      isTrue,
    );
  });
}
