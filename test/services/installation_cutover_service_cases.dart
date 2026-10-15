import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/services/installation_cutover_service.dart';

void main() {
  const testGeneration = 'test_installation_v1';

  test(
    'clears JM caches and sync generations before recording marker',
    () async {
      final stores = <String, Map<String, String>>{
        'default': {
          'events': '[{"title":"JM"}]',
          'user_info': '{"email":"old@example.test"}',
          'locale': 'cs',
        },
        InstallationCutoverService.clientSyncDatabase: {
          'pointer/jm/live': 'old',
          'generation/jm/live/old': '{}',
          'blob/kept': 'bytes',
        },
      };
      final order = <String>[];
      final service = InstallationCutoverService(
        generation: testGeneration,
        read: (key, [database]) async => stores[database ?? 'default']?[key],
        removePrefixes: (prefixes, [database]) async {
          order.add('sync');
          stores[database]!.removeWhere(
            (key, _) => prefixes.any((prefix) => key.startsWith(prefix)),
          );
        },
        writeAtomic: (values, [database]) async {
          order.add('marker');
          final store = stores[database ?? 'default']!;
          for (final entry in values.entries) {
            entry.value == null
                ? store.remove(entry.key)
                : store[entry.key] = entry.value!;
          }
        },
      );

      expect(await service.run(), isTrue);
      expect(order, ['sync', 'marker']);
      expect(stores['default']!['events'], isNull);
      expect(stores['default']!['user_info'], isNull);
      expect(stores['default']!['locale'], 'cs');
      expect(
        stores['default']![InstallationCutoverService.markerKey],
        testGeneration,
      );
      expect(
        stores[InstallationCutoverService.clientSyncDatabase]!['blob/kept'],
        'bytes',
      );
      expect(await service.run(), isFalse);
    },
  );

  test('does not record marker when cleanup fails', () async {
    final values = <String, String>{};
    final service = InstallationCutoverService(
      generation: testGeneration,
      read: (key, [database]) async => values[key],
      removePrefixes: (prefixes, [database]) async => throw StateError('disk'),
      writeAtomic: (changes, [database]) async {
        for (final entry in changes.entries) {
          if (entry.value != null) values[entry.key] = entry.value!;
        }
      },
    );

    await expectLater(service.run(), throwsStateError);
    expect(values[InstallationCutoverService.markerKey], isNull);
  });

  test('does nothing when the tenant has no installation cutover', () async {
    final service = InstallationCutoverService(
      generation: '',
      read: (key, [database]) async => throw StateError('must not read'),
      removePrefixes: (prefixes, [database]) async =>
          throw StateError('must not remove'),
      writeAtomic: (changes, [database]) async =>
          throw StateError('must not write'),
    );

    expect(await service.run(), isFalse);
  });
}
