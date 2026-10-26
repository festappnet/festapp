import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/data_services/offline_data_service.dart';

void main() {
  test('offline banner uses the newest successful sync engine timestamp', () {
    final legacy = DateTime.utc(2026, 8, 3, 9);
    final clientSync = DateTime.utc(2026, 8, 3, 11, 57);

    expect(
      resolveOfflineBannerTimestamp(
        legacyTimestamp: legacy,
        clientSyncTimestamp: clientSync,
      ),
      clientSync,
    );
  });
}
