import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/data_services/offline_data_service.dart';

void main() {
  test('V1 my schedule uses the freshly patched private program', () {
    final ids = resolveMyScheduleIds(
      isV1Selected: true,
      hasPrivateIdentity: true,
      privateProgram: const {
        'saved': [42],
      },
      legacyIds: const [7],
    );

    expect(ids, [42],
        reason: 'the legacy cache must not hide a just-saved V1 event');
  });

  test('legacy my schedule remains isolated from private program data', () {
    final ids = resolveMyScheduleIds(
      isV1Selected: false,
      hasPrivateIdentity: false,
      privateProgram: const {
        'saved': [42],
      },
      legacyIds: const [7],
    );

    expect(ids, [7]);
  });

  test('anonymous V1 my schedule stays in local storage', () {
    final ids = resolveMyScheduleIds(
      isV1Selected: true,
      hasPrivateIdentity: false,
      privateProgram: const {
        'saved': [42],
      },
      legacyIds: const [7],
    );

    expect(ids, [7]);
  });

  test('anonymous persistence mutates confirmed IDs, not optimistic IDs', () {
    expect(updateConfirmedScheduleIds(const [], 42, true), [42]);
    expect(updateConfirmedScheduleIds(const [7, 42], 42, false), [7]);
  });
}
