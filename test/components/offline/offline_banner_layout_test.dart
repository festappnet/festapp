import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/offline/offline_banner.dart';
import 'package:fstapp/services/connectivity_service.dart';

void main() {
  setUp(ConnectivityService.debugReset);
  tearDown(ConnectivityService.debugReset);

  testWidgets('offline strip does not include the system top safe area',
      (tester) async {
    ConnectivityService.debugSetInterfaceOffline(true);

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(390, 844),
            padding: EdgeInsets.only(top: 47),
          ),
          child: Scaffold(
            body: Column(
                children: [OfflineBanner(loadLastSyncedAt: () async => null)]),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle(const Duration(milliseconds: 1));
    expect(tester.getSize(find.byType(OfflineBanner)).height, lessThan(40));
  });
}
