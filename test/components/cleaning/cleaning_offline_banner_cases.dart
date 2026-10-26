import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/cleaning/models/cleaning_data.dart';

void main() {
  test('client-sync participants use projection but crew loads live reports',
      () {
    expect(
      shouldLoadLiveCleaningData(
        isClientSyncV1: true,
        isCleaningCrew: false,
      ),
      isFalse,
    );
    expect(
      shouldLoadLiveCleaningData(
        isClientSyncV1: true,
        isCleaningCrew: true,
      ),
      isTrue,
    );
    expect(
      shouldLoadLiveCleaningData(
        isClientSyncV1: false,
        isCleaningCrew: false,
      ),
      isTrue,
    );
  });

  test('cached cleaning projection is not presented as offline while online',
      () {
    expect(
      shouldShowCleaningOfflineBanner(
        cacheFetchedAt: DateTime(2026, 8, 3, 11, 57),
        isOffline: false,
      ),
      isFalse,
    );
  });

  test('cached cleaning projection shows its age when actually offline', () {
    expect(
      shouldShowCleaningOfflineBanner(
        cacheFetchedAt: DateTime(2026, 8, 3, 11, 57),
        isOffline: true,
      ),
      isTrue,
    );
  });
}
