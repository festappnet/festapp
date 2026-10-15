import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/services/pwa_storage/pwa_storage.dart';
import 'package:fstapp/services/pwa_storage/pwa_storage_codec.dart';

void main() {
  test('unsupported adapter returns a typed partial report without mutation',
      () async {
    final port = createPwaStoragePort();
    final report = await port.inspect();
    final prune = await port.pruneUnusedShells();

    expect(report.estimate.usageBytes, isNull);
    expect(report.shells.blocker, 'unsupported-browser');
    expect(prune.blocker, 'unsupported-browser');
    expect(prune.deleted, isEmpty);
  });

  test('web callback payload decodes into bounded typed metadata', () {
    final report = decodePwaStorageReport({
      'estimate': {
        'usage': 2048.9,
        'quota': 4096,
        'usageDetails': {'caches': 1024, 'invalid': 'payload'},
      },
      'shells': {
        'current': '2.0.0+2',
        'live': ['1.0.0+1', 7],
        'unknown': 1,
        'retained': ['festapp-app-shell-2.0.0+2'],
        'deletable': ['festapp-app-shell-0.9.0+9'],
        'deleted': const [],
        'blocker': 'unknown-live-client',
      },
    });

    expect(report.estimate.usageBytes, 2048);
    expect(report.estimate.usageDetails, {'caches': 1024});
    expect(report.shells.live, ['1.0.0+1']);
    expect(report.shells.unknownClients, 1);
    expect(report.shells.blocker, 'unknown-live-client');
  });
}
