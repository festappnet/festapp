import 'package:fstapp/widgets/dependency_material_bridge.dart';
import '../../support/fixtures/localization_log_fixture.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/app_management/app_management_strings.dart';
import 'package:fstapp/components/app_management/pwa_storage_advanced_settings.dart';
import 'package:fstapp/services/pwa_storage/pwa_storage_port.dart';

class _FakeStorage implements PwaStoragePort {
  int inspectCalls = 0;
  int pruneCalls = 0;

  @override
  Future<PwaStorageReport> inspect() async {
    inspectCalls++;
    return const PwaStorageReport(
      estimate: PwaStorageEstimate(usageBytes: 1024, quotaBytes: 2048),
      shells: PwaShellReport(retained: ['current'], deletable: ['stale']),
    );
  }

  @override
  Future<PwaShellReport> pruneUnusedShells() async {
    pruneCalls++;
    return const PwaShellReport(retained: ['current'], deleted: ['stale']);
  }
}

void main() {
  // This suite intentionally uses untranslated key fallback (no catalog).
  setUp(() {
    final logs = LocalizationLogFixture.install(expectedMissingCatalog: true);
    addTearDown(logs.dispose);
  });
  testWidgets('storage controls stay collapsed and prune requires confirmation',
      (tester) async {
    final storage = _FakeStorage();
    await tester.pumpWidget(MaterialApp(builder: DependencyMaterialBridge.builder,
      home: Scaffold(
        body: PwaStorageAdvancedSettings(storage: storage),
      ),
    ));

    expect(find.byType(OutlinedButton), findsNothing);
    await tester.tap(find.byType(ExpansionTile));
    await tester.pumpAndSettle();
    expect(find.byType(OutlinedButton), findsNWidgets(2));

    await tester.tap(find.widgetWithText(
      OutlinedButton,
      AppManagementStrings.inspectStorage,
    ));
    await tester.pumpAndSettle();
    expect(storage.inspectCalls, 1);
    expect(storage.pruneCalls, 0,
        reason: 'inspection must never mutate storage');

    await tester.tap(find.widgetWithText(
      OutlinedButton,
      AppManagementStrings.pruneShells,
    ));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(storage.pruneCalls, 0);

    await tester.tap(find.widgetWithText(
      TextButton,
      AppManagementStrings.pruneShells,
    ));
    await tester.pumpAndSettle();
    expect(storage.pruneCalls, 1);
    expect(storage.inspectCalls, 2,
        reason: 'successful prune refreshes the read-only report');
  });
}
