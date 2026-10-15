import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/data_services/client_sync/client_sync_protocol.dart';
import 'package:fstapp/data_services/client_sync/client_sync_runtime.dart';
import 'package:fstapp/data_services/client_sync/client_sync_store.dart';

void main() {
  test('offline bootstrap context survives serialization', () {
    const original = StoredSyncContext(
      organizationId: 7,
      occasionId: 42,
      occasionLink: 'festival-2026',
    );

    final restored = StoredSyncContext.fromJson(original.toJson());

    expect(restored, isNotNull);
    expect(restored!.organizationId, 7);
    expect(restored.occasionId, 42);
    expect(restored.occasionLink, 'festival-2026');
  });

  test('invalid offline bootstrap context is rejected', () {
    expect(
      StoredSyncContext.fromJson({
        'organizationId': 7,
        'occasionId': 42,
        'occasionLink': '',
      }),
      isNull,
    );
  });

  test('offline bootstrap requires an activated catalog generation', () {
    const context = StoredSyncContext(
      organizationId: 7,
      occasionId: 42,
      occasionLink: 'festival-2026',
    );
    final generation = StoredSyncGeneration(
      pointer: 'catalog-sha',
      revisions: const {ClientSyncComponent.contentCatalog: 3},
      updatedAt: DateTime.utc(2026, 8, 3),
    );

    expect(isRestorableSyncContext(context, null), isFalse);
    expect(isRestorableSyncContext(context, generation), isTrue);
  });
}
