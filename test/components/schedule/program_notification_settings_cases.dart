import 'package:fstapp/widgets/dependency_material_bridge.dart';
import '../../support/fixtures/localization_log_fixture.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/features/feature.dart';
import 'package:fstapp/components/features/feature_constants.dart';
import 'package:fstapp/components/features/feature_service.dart';
import 'package:fstapp/components/schedule/program_notification_settings.dart';

void main() {
  // This suite intentionally uses untranslated key fallback (no catalog).
  setUp(() {
    final logs = LocalizationLogFixture.install(expectedMissingCatalog: true);
    addTearDown(logs.dispose);
  });
  test('program notification feature cannot currently be enabled', () {
    final parsed = Feature.fromJson({
      FeatureConstants.metaCode: FeatureConstants.programNotifications,
      FeatureConstants.metaIsEnabled: true,
    });

    expect(parsed, isA<ProgramNotificationsFeature>());
    expect(parsed.isEnabled, isFalse);
    expect(parsed.canBeDisabled, isFalse);
    expect(
      FeatureService.isProgramNotificationsEnabled(features: [parsed]),
      isFalse,
    );
  });

  testWidgets('user can enable reminders and select the lead time',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(builder: DependencyMaterialBridge.builder,
        home: Scaffold(body: ProgramNotificationSettingsCard()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ChoiceChip).at(2));
    await tester.pumpAndSettle();

    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isTrue,
    );
    expect(
      tester.widget<ChoiceChip>(find.byType(ChoiceChip).at(2)).selected,
      isTrue,
    );
  });
}
