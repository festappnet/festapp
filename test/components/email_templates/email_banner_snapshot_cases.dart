import 'package:fstapp/widgets/dependency_material_bridge.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/email_templates/db_email_templates.dart';
import 'package:fstapp/components/email_templates/email_templates_strings.dart';
import 'package:fstapp/components/email_templates/views/email_banner_settings_card.dart';
import 'package:fstapp/components/unit/unit_model.dart';

import '../../support/fixtures/localization_log_fixture.dart';

void main() {
  testWidgets(
    'banner card consumes the SQL snapshot instead of rebuilding inheritance from entity data',
    (tester) async {
      final logs = LocalizationLogFixture.install(expectedMissingCatalog: true);
      addTearDown(logs.dispose);
      final response = EmailTemplatesResponse(
        unit: UnitModel(
          id: 8,
          title: 'Unit',
          data: {'email_banner': 'https://stale.invalid/banner.png'},
        ),
        organization: UnitModel(id: 3, title: 'Organization'),
        templates: [],
        bannerState: {
          'overrideUrl': null,
          'inheritedUrl': null,
          'effectiveUrl': null,
          'wrapperHtml': null,
          'revision': 'a' * 64,
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          builder: DependencyMaterialBridge.builder,
          home: Scaffold(body: EmailBannerSettingsCard(response: response)),
        ),
      );
      expect(find.text(EmailTemplatesStrings.statusNoBanner), findsOneWidget);
      expect(find.text(EmailTemplatesStrings.statusUnit), findsNothing);
    },
  );
}
