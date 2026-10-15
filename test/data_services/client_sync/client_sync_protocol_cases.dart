import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/data_services/client_sync/client_sync_protocol.dart';

void main() {
  test('only searchable public catalogs invalidate the search index', () {
    expect(
      ClientSyncComponent.values
          .where((component) => component.affectsSearchIndex)
          .toSet(),
      {
        ClientSyncComponent.occasionConfig,
        ClientSyncComponent.programCatalog,
        ClientSyncComponent.mapCatalog,
        ClientSyncComponent.contentCatalog,
      },
    );
  });

  test('user and live-state changes do not invalidate the search index', () {
    expect(ClientSyncComponent.livePublic.affectsSearchIndex, isFalse);
    expect(ClientSyncComponent.privateProgram.affectsSearchIndex, isFalse);
    expect(ClientSyncComponent.privateProfile.affectsSearchIndex, isFalse);
    expect(ClientSyncComponent.privateNews.affectsSearchIndex, isFalse);
    expect(ClientSyncComponent.privateFeedback.affectsSearchIndex, isFalse);
  });

  test('private and live revisions leave the search signature unchanged', () {
    const searchable = {
      ClientSyncComponent.occasionConfig: 1,
      ClientSyncComponent.programCatalog: 2,
      ClientSyncComponent.mapCatalog: 3,
      ClientSyncComponent.contentCatalog: 4,
    };
    final original = clientSyncSearchProjectionSignature('9/643', searchable);

    expect(
      clientSyncSearchProjectionSignature('9/643', {
        ...searchable,
        ClientSyncComponent.livePublic: 500,
        ClientSyncComponent.privateProgram: 700,
        ClientSyncComponent.privateProfile: 900,
      }),
      original,
    );
    expect(
      clientSyncSearchProjectionSignature('9/643', {
        ...searchable,
        ClientSyncComponent.programCatalog: 5,
      }),
      isNot(original),
    );
  });
}
