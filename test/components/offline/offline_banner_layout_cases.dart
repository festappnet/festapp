import 'package:fstapp/widgets/dependency_material_bridge.dart';

import '../../support/fixtures/localization_log_fixture.dart';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/offline/offline_banner.dart';
import 'package:fstapp/services/connectivity_service.dart';

void main() {
  // This suite intentionally uses untranslated key fallback (no catalog).
  setUp(() {
    final logs = LocalizationLogFixture.install(expectedMissingCatalog: true);
    addTearDown(logs.dispose);
  });
  setUp(ConnectivityService.debugReset);
  tearDown(ConnectivityService.debugReset);

  testWidgets('offline strip does not include the system top safe area', (
    tester,
  ) async {
    ConnectivityService.debugSetInterfaceOffline(true);

    await tester.pumpWidget(
      MaterialApp(
        builder: DependencyMaterialBridge.builder,
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(390, 844),
            padding: EdgeInsets.only(top: 47),
          ),
          child: Scaffold(
            body: Column(
              children: [OfflineBanner(loadLastSyncedAt: () async => null)],
            ),
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byType(OfflineBanner)).height, lessThan(40));
  });
}
